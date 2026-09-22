#if canImport(UIKit)
import AVFoundation
import Foundation

// MARK: - Adapter transportu Gemini Live API (speech-to-speech)
//
// Jedyny transport głosowy Emmy. Ten plik jest **jedynym** miejscem,
// w którym aplikacja rozmawia z Gemini Live API:
//   • nie zawiera klucza API — dostaje wyłącznie krótkotrwałe poświadczenie
//     wydane przez backend (`BackendConversationTokenProvider`),
//   • nie zawiera instrukcji systemowej ani deklaracji narzędzi — są zablokowane
//     w tokenie po stronie backendu, więc aplikacja nie może ich podmienić,
//   • nie wykonuje akcji: wywołanie narzędzia idzie do backendu
//     (`BackendVoiceToolExecutor`), który ma allowlistę, action engine i audyt.
//
// Podział odpowiedzialności jest celowy: logika protokołu i reguły tury siedzą
// w `Core/Voice` (testowalne bez telefonu), a tutaj zostaje sieć i audio.
//
// Ograniczenia Live API, które obsługujemy jawnie:
//   • nie ma identyfikatora rozmowy ani hostowanej pętli agenta,
//   • nie ma potwierdzonego końca odtwarzania — zdarzenia playbacku są lokalne
//     i oznaczone jako przybliżone,
//   • nie ma osobnego zdarzenia „powód przerwania”: barge-in rozpoznajemy po
//     `interrupted`, a przerwanie na polecenie po własnym wywołaniu.

@MainActor
public final class GeminiLiveTransport: VoiceTransport {

    public let capabilities = VoiceCapabilities(
        // Live API wysyła transkrypcję przyrostowo (input/output transcription).
        partialTranscripts: true,
        interruptGeneration: true,
        localPlaybackStop: true,
        // Zdarzenia odtwarzania pochodzą z naszego bufora, nie od dostawcy.
        reportsPlaybackEvents: true,
        routeSelection: true,
        contextUpdate: true,
        textTurn: true,
        reportsInterruptionReason: true
    )

    /// Adres WebSocket Live API dla poświadczenia sesji.
    ///
    /// Uwaga na dwa szczegóły, które łatwo pomylić i które kosztują pierwsze
    /// nieudane połączenie: przy tokenie efemerycznym ścieżka ma końcówkę
    /// **`Constrained`**, a token jedzie w parametrze **`access_token`**, nie
    /// `key` (tym drugim posługuje się klucz API). Źródło: dokumentacja Live API
    /// („Get started using raw WebSockets”) oraz referencyjny przykład Google
    /// `gemini-live-ephemeral-tokens-websocket`.
    ///
    /// Adresu z tokenem nigdy nie logujemy.
    private static let defaultEndpoint = URL(
        string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained"
    )!

    private let tokenProvider: BackendConversationTokenProvider
    private let toolExecutor: any VoiceToolExecuting
    /// Token użytkownika pobierany przy każdym wydaniu poświadczenia — rozmowa
    /// (z wznowieniami po `goAway`) żyje dłużej niż token dostępu.
    private let tokens: VoiceAccessTokenSource
    /// Wykonawca narzędzi `app_*` (nawigacja, propozycje). Rozwiązywany przy
    /// każdym wywołaniu, bo ekran Emmy podpina się dopiero po starcie rozmowy.
    private let appTools: @MainActor () -> (any VoiceAppToolHandling)?
    private let installationID: String
    private let audioSession: AudioSessionController?
    private let model: String
    private let endpoint: URL
    private let urlSession: URLSession

    private var configuration: VoiceSessionConfiguration?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var audioSendTask: Task<Void, Never>?
    private var toolTasks: [String: (token: UUID, name: String, task: Task<Void, Never>)] = [:]
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var tracker = GeminiLiveTurnTracker()
    private var continuation: AsyncStream<VoiceEvent>.Continuation?
    private var eventStream: AsyncStream<VoiceEvent>?
    private var generation: Int = 0
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var playerFormat: AVAudioFormat?
    private let microphone = MicrophoneGate()
    /// Tryb bieżącej rozmowy, ustalany przy `connect` (przełącznik w Profilu).
    private var duplexMode: VoiceDuplexMode = .halfDuplex
    private var sinkNode: AVAudioSinkNode?
    /// Serwer przyjmuje audio dopiero po `setupComplete`. Mikrofon startuje
    /// wcześniej (rozgrzany silnik = krótszy start), więc pierwsze fragmenty
    /// czekają tu zamiast przepaść albo trafić do gniazda przed konfiguracją.
    private var isSetupComplete = false
    private var pendingAudio: [Data] = []
    /// ~3 s mowy przy fragmentach 20–100 ms; starsze fragmenty odrzucamy.
    private static let pendingAudioLimit = 60
    private var isClosing = false
    /// Jedna próba wznowienia na zerwanie. Więcej byłoby udawaniem, że sieć
    /// wróciła, a użytkownik nie widzi różnicy między „wracam” i „próbuję w kółko”.
    private var reconnectsLeft = 1

    init(
        tokenProvider: BackendConversationTokenProvider,
        toolExecutor: any VoiceToolExecuting,
        tokens: VoiceAccessTokenSource,
        appTools: @escaping @MainActor () -> (any VoiceAppToolHandling)? = { nil },
        installationID: String,
        model: String,
        audioSession: AudioSessionController? = nil,
        endpoint: URL = GeminiLiveTransport.defaultEndpoint,
        urlSession: URLSession = .shared
    ) {
        self.tokenProvider = tokenProvider
        self.toolExecutor = toolExecutor
        self.tokens = tokens
        self.appTools = appTools
        self.installationID = installationID
        self.model = model
        self.audioSession = audioSession
        self.endpoint = endpoint
        self.urlSession = urlSession
    }

    /// Stały token — testy i podglądy.
    convenience init(
        tokenProvider: BackendConversationTokenProvider,
        toolExecutor: any VoiceToolExecuting,
        accessToken: String?,
        installationID: String,
        model: String,
        audioSession: AudioSessionController? = nil,
        endpoint: URL = GeminiLiveTransport.defaultEndpoint,
        urlSession: URLSession = .shared
    ) {
        self.init(
            tokenProvider: tokenProvider,
            toolExecutor: toolExecutor,
            tokens: .fixed(accessToken),
            installationID: installationID,
            model: model,
            audioSession: audioSession,
            endpoint: endpoint,
            urlSession: urlSession
        )
    }

    // MARK: Połączenie

    public func connect(_ session: VoiceSessionConfiguration) async throws {
        self.configuration = session
        generation += 1
        isClosing = false
        reconnectsLeft = 1
        tracker = GeminiLiveTurnTracker()
        microphone.setMuted(false)
        duplexMode = VoiceDuplexMode.current
        isSetupComplete = false
        pendingAudio.removeAll()

        // Sesję audio dla rozmowy ustawiamy tutaj. Bez `.playAndRecord` wejście
        // audio nie istnieje. Awarię meldujemy po otwarciu kanału zdarzeń.
        audioSession?.setProviderOwnsAudioSession(true)
        let audioActivationFailed = audioSession?.activate(.conversation) == false

        // Strumień zdarzeń powstaje raz i żyje całą sesję. Świadomie **nie**
        // kończymy go tutaj: koordynator woła `connect`, a dopiero potem
        // `events()`, ale podglądy i testy robią to w odwrotnej kolejności —
        // zamknięcie kanału w `connect` gubiłoby wtedy cały uścisk dłoni.
        _ = currentStream()

        // Silnik audio startuje **równolegle** z wydaniem poświadczenia
        // i otwarciem gniazda, a nie po nich: jego rozruch (50–150 ms) nie
        // dokłada się do czasu „dotknąłem — mogę mówić”. Fragmenty sprzed
        // `setupComplete` czekają w `pendingAudio`.
        var audioStartFailed = false
        do {
            try startAudio()
        } catch {
            audioStartFailed = true
        }

        // Poświadczenie pochodzi z backendu. Normalnie jest już w konfiguracji
        // sesji; poniższa gałąź domyka tylko brak (np. ponowne wejście do sesji).
        let token: String
        if !session.conversationToken.isEmpty {
            token = session.conversationToken
        } else {
            token = try await issueConversationToken(for: session)
        }

        // `connecting` przed otwarciem gniazda: pętla odbioru startuje w środku
        // `openSocket` i `setupComplete` może dotrzeć, zanim wrócimy z `await`.
        emit(.connectionChanged(.connecting))
        try await openSocket(token: token, resumeHandle: nil)

        if audioActivationFailed {
            emit(.fatalError(.audioSessionFailed))
        }
        if audioStartFailed {
            // Bez mikrofonu rozmowa nie ma wejścia; mówimy to wprost, zamiast
            // udawać sesję, w której użytkownik mówi do ciszy (F05).
            microphone.setMuted(true)
            emit(.microphoneChanged(.unavailable))
            emit(.fatalError(.microphoneUnavailable))
        }
    }

    /// Otwarcie gniazda i wysłanie `setup`. `setupComplete` przychodzi w pętli
    /// odbioru i dopiero ono daje `connectionChanged(.connected)`.
    private func openSocket(token: String, resumeHandle: String?) async throws {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw GeminiLiveProtocolError.websocketFailed("Nieprawidłowy adres Live API.")
        }
        // `access_token`, nie `key`: token efemeryczny nie jest kluczem API.
        components.queryItems = [URLQueryItem(name: "access_token", value: token)]
        guard let url = components.url else {
            throw GeminiLiveProtocolError.websocketFailed("Nieprawidłowy adres Live API.")
        }

        let task = urlSession.webSocketTask(with: url)
        task.resume()
        socket = task
        // Nowe gniazdo = nowy `setup`; audio czeka, aż serwer go przyjmie.
        isSetupComplete = false
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task)
        }
        try await send(.setup(model: model, resumeHandle: resumeHandle))
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                // Zdarzenia z poprzedniego połączenia nie mogą wpływać na nowe.
                guard task === socket else { return }
                let data: Data
                switch message {
                case .data(let payload): data = payload
                case .string(let text): data = Data(text.utf8)
                @unknown default: continue
                }
                // JSON z audio w base64 dekodujemy poza głównym wątkiem: ten sam
                // wątek rysuje orb Emmy i interfejs, a opóźnione fragmenty to
                // przerwy w odtwarzaniu.
                let events = await Self.decodeOffMain(data)
                guard task === socket else { return }
                handle(events)
            } catch {
                guard task === socket else { return }
                handleSocketFailure()
                return
            }
        }
    }

    nonisolated private static func decodeOffMain(_ data: Data) async -> [GeminiLiveServerEvent] {
        await Task.detached(priority: .userInitiated) { GeminiLiveCodec.decode(data) }.value
    }

    private func handle(_ events: [GeminiLiveServerEvent]) {
        for event in events {
            if case .setupComplete = event {
                // Bufor sprzed konfiguracji opróżnia pętla wysyłki — jedna
                // kolejka, więc kolejność nagrania zostaje zachowana.
                isSetupComplete = true
            }
            let outcome = tracker.consume(event)
            if let audio = outcome.audio { enqueuePlayback(audio) }
            // Przerwanie tury po stronie serwera: wycofujemy zbuforowane audio,
            // żeby Emma nie mówiła dalej przez wypowiedź użytkownika.
            if outcome.shouldStopPlayback { stopPlayback() }
            cancelToolCalls(outcome.cancelledToolCallIDs)
            if let call = outcome.toolCall { executeToolCall(call) }
            for payload in outcome.payloads { emit(payload) }
            // `goAway` to zapowiedź zamknięcia (limit ~10 minut). Nie czekamy, aż
            // gniazdo padnie: otwieramy nowe połączenie z uchwytem tej samej sesji,
            // więc rozmowa trwa bez przerwy w słuchaniu użytkownika.
            if outcome.goAwayIn != nil {
                reconnect(proactive: true)
            }
        }
    }

    /// Zerwanie połączenia: domykamy to, co otwarte, i próbujemy wznowić sesję
    /// z uchwytem. Nie udajemy, że rozmowa trwa dalej bez przerwy.
    private func handleSocketFailure() {
        guard !isClosing else { return }
        for payload in tracker.connectionLost().payloads { emit(payload) }
        stopPlayback()
        reconnect(proactive: false)
    }

    /// Wznowienie sesji: nowe poświadczenie i nowe gniazdo z uchwytem.
    ///
    /// `proactive` odróżnia zapowiedziane zamknięcie (`goAway`, po którym zdarzenia
    /// już poszły) od zerwania — dzięki temu nie dublujemy komunikatów o błędzie.
    /// Jedna próba: jeśli się nie uda, mówimy wprost, że dostawca jest niedostępny.
    private func reconnect(proactive: Bool) {
        guard !isClosing, reconnectsLeft > 0, let session = configuration else {
            if !proactive, !isClosing { emit(.fatalError(.providerUnavailable)) }
            return
        }
        reconnectsLeft -= 1
        cancelToolCalls(Array(toolTasks.keys))
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        receiveTask?.cancel()
        receiveTask = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await self.issueConversationToken(for: session)
                try await self.openSocket(token: token, resumeHandle: self.tracker.resumptionHandle)
                // Nowe gniazdo = nowy limit prób. Sesja Live API żyje do dwóch
                // godzin, więc jedno zerwanie na całą rozmowę to za mało.
                self.reconnectsLeft = 1
            } catch {
                self.emit(.fatalError(.providerUnavailable))
            }
        }
    }

    /// Nowe poświadczenie Live API z backendu. Po 401 raz odnawiamy token
    /// użytkownika i ponawiamy — wznowienie po `goAway` w drugiej połowie
    /// godziny nie może kończyć rozmowy tylko dlatego, że wygasł token dostępu.
    private func issueConversationToken(for session: VoiceSessionConfiguration) async throws -> String {
        do {
            return try await tokenProvider.fetchToken(
                sessionID: session.sessionID,
                contextVersion: session.context.version,
                installationID: installationID,
                accessToken: await tokens.current()
            ).token
        } catch ConversationTokenError.unauthorized {
            guard let refresh = tokens.refresh, let refreshed = await refresh(), !refreshed.isEmpty else {
                throw ConversationTokenError.unauthorized
            }
            return try await tokenProvider.fetchToken(
                sessionID: session.sessionID,
                contextVersion: session.context.version,
                installationID: installationID,
                accessToken: refreshed
            ).token
        }
    }

    // MARK: Audio

    private func startAudio() throws {
        let engine = AVAudioEngine()

        // Pełny dupleks: kasowanie echa (VoiceProcessingIO). Włączamy je
        // **przed** odczytem formatów — VP zmienia format wejścia, a konwerter
        // zbudowany na starym formacie psuł sygnał (to najpewniej była przyczyna
        // „ucinania mowy” w zgłoszeniu 2026-09-15). Wyciszanie innego audio
        // ustawiamy na minimum, żeby głos Emmy nie był ściszany przez system.
        if duplexMode == .fullDuplex {
            do {
                try engine.inputNode.setVoiceProcessingEnabled(true)
                engine.inputNode.voiceProcessingOtherAudioDuckingConfiguration =
                    AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                        enableAdvancedDucking: false,
                        duckingLevel: .min
                    )
            } catch {
                // Bez AEC pełny dupleks oznaczałby, że Emma przerywa sama siebie.
                duplexMode = .halfDuplex
            }
        }

        // Domyślnie (półdupleks) kasowania echa nie ma: pierwsza próba AEC
        // (zgłoszenie 2026-09-15) ucinała mowę użytkownika i dawała „robotyczny”
        // głos, więc pętlę zamyka `MicrophoneGate` — mikrofon jest zamknięty,
        // gdy Emma mówi. Pełny dupleks powyżej to poprawiona próba AEC za
        // przełącznikiem w Profilu; domyślną ścieżką zostanie po pomiarze.
        let player = AVAudioPlayerNode()
        engine.attach(player)

        guard let playerFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: GeminiLiveDefaults.outputSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw GeminiLiveProtocolError.websocketFailed("Nie udało się utworzyć formatu odtwarzania.")
        }
        engine.connect(player, to: engine.mainMixerNode, format: playerFormat)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        // Symulator bez mikrofonu zwraca format o zerowej częstotliwości; wtedy
        // nie ma czego przechwytywać i musimy to powiedzieć wprost.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: GeminiLiveDefaults.inputSampleRate,
                  channels: 1,
                  interleaved: true
              ),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw GeminiLiveProtocolError.websocketFailed("Brak wejścia audio.")
        }

        let (audioStream, audioContinuation) = AsyncStream<Data>.makeStream()
        self.audioContinuation = audioContinuation

        // Domknięcie tapu biegnie na wątku czasu rzeczywistego audio
        // (`RealtimeMessenger.mServiceQueue`), a nie na głównym aktorze.
        // Samo nietykanie `self` nie wystarcza: bez jawnego `@Sendable`
        // domknięcie **dziedziczy izolację `@MainActor`** z tej metody i Swift 6
        // zatrzymuje proces na sprawdzeniu wykonawcy (`_dispatch_assert_queue_fail`
        // → EXC_BREAKPOINT/SIGTRAP) już przy pierwszym buforze z mikrofonu.
        // To była rzeczywista przyczyna zamknięcia aplikacji przy „rozmawiaj”
        // (raport `Emma-2026-09-15-231936.ips`); identyczna pułapka została
        // wcześniej naprawiona w `AppleSpeechDictationService` przy „dyktuj tekst”.
        // Konwerter i format są klasami bez `Sendable`, więc chwytamy je przez
        // `nonisolated(unsafe)` — dokładnie tak, jak w tamtym miejscu.
        let gate = microphone
        if duplexMode == .fullDuplex {
            // Węzeł-odbiornik dostaje bufory w rytmie wejścia sprzętowego
            // (~20 ms przy `preferredIOBufferDuration`), a nie co ≥100 ms jak tap.
            // To bezpośrednio skraca opóźnienie „mówię → serwer słyszy”.
            let sink = AVAudioSinkNode(receiverBlock: GeminiLiveTransport.makeSinkBlock(
                inputFormat: inputFormat,
                converter: converter,
                targetFormat: targetFormat,
                gate: gate,
                accumulator: PCMChunkAccumulator(minimumBytes: GeminiLiveDefaults.minimumChunkBytes),
                continuation: audioContinuation
            ))
            engine.attach(sink)
            engine.connect(input, to: sink, format: inputFormat)
            sinkNode = sink
        } else {
            let tapBlock = GeminiLiveTransport.makeInputTapBlock(
                converter: converter,
                targetFormat: targetFormat,
                gate: gate,
                continuation: audioContinuation
            )
            input.installTap(onBus: 0, bufferSize: 1600, format: inputFormat, block: tapBlock)
        }

        engine.prepare()
        try engine.start()
        player.play()

        self.engine = engine
        self.player = player
        self.playerFormat = playerFormat

        audioSendTask = Task { [weak self] in
            for await chunk in audioStream {
                guard let self, !Task.isCancelled else { return }
                guard self.isSetupComplete, self.socket != nil else {
                    self.bufferAudio(chunk)
                    continue
                }
                if !self.pendingAudio.isEmpty {
                    let queued = self.pendingAudio
                    self.pendingAudio.removeAll()
                    for earlier in queued {
                        try? await self.send(.audio(earlier))
                    }
                }
                try? await self.send(.audio(chunk))
            }
        }
    }

    /// Odtwarzanie: Live API wysyła PCM 16-bit mono 24 kHz. Buforujemy lokalnie,
    /// a `interrupted`/`interrupt` natychmiast czyści kolejkę — przerwanie ma być
    /// słyszalne od razu, nie po ostatnim zbuforowanym zdaniu.
    private func enqueuePlayback(_ data: Data) {
        guard let player, let format = playerFormat,
              let buffer = Self.floatBuffer(from: data, format: format) else { return }
        // Półdupleks: na czas tej porcji audio (plus ogon na pogłos) zamykamy
        // mikrofon, żeby Emma nie usłyszała siebie z głośnika. To rozwiązanie
        // wybrane **świadomie zamiast** kasowania echa na silniku: AEC
        // (`setVoiceProcessingEnabled`) przepuszcza dźwięk przez tor telefoniczny
        // i na tym urządzeniu wycinało mowę użytkownika oraz degradowało głos
        // modelu (zgłoszenie 2026-09-15: „nie notuje mojego dźwięku”, „robotycznie”).
        // W pełnym dupleksie echo usuwa VoiceProcessingIO, więc mikrofon zostaje
        // otwarty i użytkownik może wejść Emmie w słowo (barge-in).
        if duplexMode == .halfDuplex {
            microphone.schedulePlayback(
                seconds: Double(data.count / MemoryLayout<Int16>.size) / GeminiLiveDefaults.outputSampleRate
            )
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// Ile razy wycofaliśmy lokalne odtwarzanie. `AVAudioPlayerNode` nie mówi,
    /// czy kolejka jest pusta, a twierdzenie „po barge-in audio milknie” musi mieć
    /// dowód — to licznik dla testów, nie element logiki.
    private(set) var localPlaybackStopCount = 0

    private func stopPlayback() {
        localPlaybackStopCount += 1
        // Kolejka jest właśnie czyszczona, więc oddajemy mikrofon użytkownikowi
        // od razu — inaczej zostałby niesłyszalny do końca wyliczonego ogona.
        microphone.releasePlayback()
        guard let player else { return }
        player.stop()
        // `stop()` zwalnia kolejkę; `play()` przywraca węzeł do pracy, żeby
        // kolejne fragmenty nie trafiały do zatrzymanego odtwarzacza.
        player.play()
    }

    private func bufferAudio(_ chunk: Data) {
        pendingAudio.append(chunk)
        if pendingAudio.count > Self.pendingAudioLimit {
            pendingAudio.removeFirst(pendingAudio.count - Self.pendingAudioLimit)
        }
    }

    // MARK: Strumień zdarzeń

    public func events() -> AsyncStream<VoiceEvent> {
        currentStream()
    }

    /// Jedna kolejka na sesję. `AsyncStream` buforuje to, co trafiło przed
    /// pierwszym odczytem, więc zdarzenia z `connect` nie przepadają.
    private func currentStream() -> AsyncStream<VoiceEvent> {
        if let eventStream { return eventStream }
        let stream = AsyncStream<VoiceEvent>.makeStream()
        eventStream = stream.stream
        continuation = stream.continuation
        return stream.stream
    }

    private func emit(_ payload: VoiceEventPayload) {
        guard let configuration else { return }
        let event = VoiceEvent(
            eventID: UUID().uuidString,
            sessionID: configuration.sessionID,
            connectionGeneration: ConnectionGeneration(UInt64(generation)),
            receivedAt: Date(),
            source: .providerTransport,
            payload: payload
        )
        continuation?.yield(event)
    }

    // MARK: Sterowanie

    public func setMicrophoneMuted(_ muted: Bool) async throws {
        // Wyciszenie w Live API robimy po naszej stronie: nie wysyłamy ramek
        // audio. Dzięki temu nie zależy to od tego, czy dostawca zna „mute”.
        microphone.setMuted(muted)
        emit(.microphoneChanged(muted ? .muted : .capturing))
    }

    public func interrupt(_ request: InterruptionRequest) async throws {
        // Live API nie ma klientowego „anuluj turę”: przerwanie realizuje się
        // przez wejście audio użytkownika (VAD). My robimy to, co możemy
        // zrobić natychmiast i uczciwie: zatrzymujemy lokalne odtwarzanie.
        stopPlayback()
        emit(.interruption(request.reason))
        emit(.playbackStopped(reason: .interrupted))
    }

    public func updateContext(_ context: AssistantContext) async throws {
        // Kontekst wstrzykujemy jako treść bez `turnComplete`, więc model nie
        // odpowiada na nią samoistnie — ma ją tylko uwzględnić w kolejnej turze.
        let fields: [String: String] = [
            "scope": context.scope.rawValue,
            "client_id": context.clientID?.rawValue ?? "",
            "case_id": context.caseID?.rawValue ?? "",
            "version": String(context.version.value)
        ]
        let payload = (try? JSONEncoder().encode(fields)).flatMap { String(decoding: $0, as: UTF8.self) } ?? "{}"
        try await send(.clientContent(role: .user, text: "Kontekst bieżącej rozmowy: \(payload)", turnComplete: false))
        // Potwierdzenie kontekstu przychodzi od backendu; lokalny stan nie jest
        // uznawany za obowiązujący, dopóki go nie ma.
    }

    public func sendTextTurn(_ input: AssistantTextInput) async throws {
        try await send(.textTurn(input.text))
        emit(.userTranscriptFinal(input.text))
    }

    public func disconnect(reason: VoiceEndReason) async {
        isClosing = true
        cancelToolCalls(Array(toolTasks.keys))
        microphone.releasePlayback()
        receiveTask?.cancel()
        receiveTask = nil
        audioSendTask?.cancel()
        audioSendTask = nil
        audioContinuation?.finish()
        audioContinuation = nil

        if let engine {
            if let sinkNode {
                engine.disconnectNodeInput(sinkNode)
                engine.detach(sinkNode)
            } else {
                engine.inputNode.removeTap(onBus: 0)
            }
            engine.stop()
        }
        sinkNode = nil
        pendingAudio.removeAll()
        isSetupComplete = false
        engine = nil
        player = nil
        playerFormat = nil

        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil

        emit(.connectionChanged(.ended))
        emit(.microphoneChanged(.unavailable))
        continuation?.finish()
        continuation = nil
        eventStream = nil

        // Sesję audio zwalniamy dopiero tutaj: odsłuch i dyktowanie mogą znowu
        // przejąć kategorię, a mikrofon nie zostaje zarezerwowany po rozmowie.
        audioSession?.setProviderOwnsAudioSession(false)
        audioSession?.deactivate()
    }

    // MARK: Narzędzia

    /// Wywołanie narzędzia przez model. Wykonanie należy do backendu — klient
    /// nie ma ścieżki zapisu i nie interpretuje argumentów.
    private func executeToolCall(_ call: GeminiLiveToolCall) {
        guard toolTasks[call.id] == nil, let callSocket = socket, !isClosing else { return }
        let callGeneration = generation
        let taskToken = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.toolTasks[call.id]?.token == taskToken {
                    self.toolTasks.removeValue(forKey: call.id)
                }
            }
            do {
                let result: String
                if VoiceAppTools.isAppTool(call.name) {
                    // Sterowanie aplikacją wykonuje się lokalnie — bez sieci,
                    // więc model dostaje wynik w milisekundach.
                    guard let handler = self.appTools() else {
                        throw VoiceToolExecutionError.failed("Ekran Emmy nie jest gotowy — spróbuj ponownie za chwilę.")
                    }
                    result = await handler.handleAppTool(name: call.name, argumentsJSON: call.argumentsJSON)
                } else {
                    result = try await self.toolExecutor.execute(
                        toolName: call.name,
                        argumentsJSON: call.argumentsJSON
                    )
                }
                guard !Task.isCancelled, !self.isClosing,
                      self.generation == callGeneration, self.socket === callSocket else { return }
                try await self.send(.toolResponse(id: call.id, name: call.name, resultJSON: result))
                self.emit(
                    .toolProgress(
                        ToolProgress(label: "Sprawdzam dane w kancelarii", toolName: call.name, isFinished: true)
                    )
                )
            } catch {
                guard !Task.isCancelled, !self.isClosing,
                      self.generation == callGeneration, self.socket === callSocket else { return }
                let failure = (error as? VoiceToolExecutionError) ?? .failed("Nie udało się sprawdzić danych.")
                // Błąd narzędzia odsyłamy modelowi jako wynik: wtedy Emma powie
                // użytkownikowi, że nie ma danych, zamiast milczeć albo zgadywać.
                let payload = Self.errorJSON(failure.safeMessage)
                try? await self.send(.toolResponse(id: call.id, name: call.name, resultJSON: payload))
                self.emit(.recoverableError(Self.recoverableKind(for: failure)))
            }
        }
        toolTasks[call.id] = (taskToken, call.name, task)
    }

    private func cancelToolCalls(_ ids: [String]) {
        for id in ids {
            if let pending = toolTasks.removeValue(forKey: id) {
                pending.task.cancel()
                emit(.toolProgress(ToolProgress(label: "", toolName: pending.name, isFinished: true)))
            }
        }
    }

    private static func recoverableKind(for failure: VoiceToolExecutionError) -> RecoverableErrorKind {
        switch failure {
        case .unauthorized: return .unknown
        case .failed: return .unknown
        case .forbidden, .unknownTool: return .unknown
        }
    }

    nonisolated static func errorJSON(_ message: String) -> String {
        let object: [String: String] = ["error": message]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return #"{"error":"Błąd"}"# }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Wysyłka

    private func send(_ message: GeminiLiveClientMessage) async throws {
        guard let socket else {
            throw GeminiLiveProtocolError.websocketFailed("Brak połączenia z Live API.")
        }
        let data = try GeminiLiveCodec.encode(message)
        try await socket.send(.data(data))
    }

    // MARK: Konwersje audio (bez stanu, wywoływane także z wątku tapu)

    /// Buduje domknięcie tapu mikrofonu w kontekście **bez izolacji aktora**.
    ///
    /// Trzymamy je osobno, bo to obiekt, który faktycznie się wywracał: AVFAudio
    /// woła je z `RealtimeMessenger.mServiceQueue`, więc każde domknięcie
    /// odziedziczone z `@MainActor` kończy proces na `_dispatch_assert_queue_fail`
    /// (EXC_BREAKPOINT/SIGTRAP) — patrz `Emma-2026-09-15-231936.ips`. `@Sendable`
    /// jest tu istotą naprawy, a nie ozdobnikiem.
    nonisolated static func makeInputTapBlock(
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        gate: MicrophoneGate,
        continuation: AsyncStream<Data>.Continuation
    ) -> AVAudioNodeTapBlock {
        // Konwerter i format są w tym SDK `Sendable`, więc wchodzą do domknięcia
        // wprost — obejścia z `nonisolated(unsafe)` są tu zbędne (kompilator je
        // zgłasza jako niepotrzebne). W dyktowaniu tekstu były konieczne, bo tam
        // chwytamy `AVAudioRecognitionRequest`.
        return { @Sendable buffer, _ in
            guard !gate.isMuted else { return }
            guard let pcm = convertToPCM16(
                buffer,
                converter: converter,
                targetFormat: targetFormat
            ) else { return }
            continuation.yield(pcm)
        }
    }

    /// Blok węzła-odbiornika mikrofonu (pełny dupleks). Te same zasady co przy
    /// tapie: brak izolacji `@MainActor`, bo AVFAudio woła go z wątku audio.
    nonisolated static func makeSinkBlock(
        inputFormat: AVAudioFormat,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        gate: MicrophoneGate,
        accumulator: PCMChunkAccumulator,
        continuation: AsyncStream<Data>.Continuation
    ) -> AVAudioSinkNodeReceiverBlock {
        return { @Sendable _, frameCount, audioBufferList in
            guard frameCount > 0, !gate.isMuted,
                  let buffer = AVAudioPCMBuffer(
                      pcmFormat: inputFormat,
                      bufferListNoCopy: audioBufferList,
                      deallocator: nil
                  ),
                  let pcm = convertToPCM16(buffer, converter: converter, targetFormat: targetFormat),
                  let chunk = accumulator.append(pcm)
            else { return noErr }
            continuation.yield(chunk)
            return noErr
        }
    }

    /// Int16 PCM mono 24 kHz → bufor Float32 dla węzła odtwarzania.
    nonisolated static func floatBuffer(from data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let bytesPerFrame = MemoryLayout<Int16>.size
        let frames = data.count / bytesPerFrame
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            let source = raw.bindMemory(to: Int16.self)
            for index in 0..<frames {
                channels[0][index] = Float(Int16(littleEndian: source[index])) / 32768
            }
        }
        return buffer
    }

    /// Bufor wejściowy → Int16 PCM mono 16 kHz, gotowy do wysłania w `realtimeInput`.
    nonisolated static func convertToPCM16(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> Data? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }

        // Blok wejściowy konwertera jest `@Sendable`, a AVFAudio może go zawołać
        // spoza wątku, który nas woła. Źródło trzymamy w pudełku z zamkiem,
        // zamiast współdzielić zmienną `var` (to była realna data race).
        let source = ConversionSource(buffer: buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, statusPointer in
            guard let next = source.take() else {
                statusPointer.pointee = .noDataNow
                return nil
            }
            statusPointer.pointee = .haveData
            return next
        }
        guard status != .error, output.frameLength > 0, let samples = output.int16ChannelData else { return nil }
        return Data(bytes: samples[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }
}

/// Skleja krótkie fragmenty z węzła-odbiornika w porcje ~40 ms. Fragment 10–20 ms
/// to 50–100 ramek JSON na sekundę — sam narzut base64 i WebSocketu zjadałby
/// zysk z krótszego bufora.
final class PCMChunkAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let minimumBytes: Int
    private var pending = Data()

    init(minimumBytes: Int) {
        self.minimumBytes = minimumBytes
    }

    /// Zwraca porcję gotową do wysłania albo `nil`, gdy trzeba jeszcze zebrać.
    func append(_ data: Data) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        guard pending.count >= minimumBytes else { return nil }
        let chunk = pending
        pending = Data()
        return chunk
    }
}

/// Jednorazowe źródło dla bloku wejściowego `AVAudioConverter`. Konwerter sam
/// zgłasza, ile buforów zużył, więc oddajemy bufor raz i potem mówimy „brak
/// danych” — inaczej resampling w kółko przetwarzałby ten sam fragment.
final class ConversionSource: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        let next = buffer
        buffer = nil
        return next
    }
}

/// Bramka mikrofonu czytana z wątku tapu AVFAudio, który nie jest `@MainActor`.
/// Bez tego wyciszenie wymagałoby sięgania do stanu aktora z wątku tła — czyli
/// dokładnie tej pułapki, która wcześniej wywracała aplikację (M5, SIGTRAP).
///
/// Trzyma **dwa** powody wyciszenia, bo mają różne źródła:
/// - `muted` — decyzja użytkownika (przycisk mikrofonu),
/// - `playbackEndsAt` — półdupleks: gdy Emma mówi, mikrofon jest zamknięty,
///   żeby nie usłyszała samej siebie przez głośnik.
final class MicrophoneGate: @unchecked Sendable {
    /// Ogon po ostatniej próbce: pogłos w pokoju dochodzi do mikrofonu jeszcze
    /// chwilę po tym, jak głośnik zamilkł.
    static let playbackTail: TimeInterval = PlaybackSuppression.echoTail

    private let lock = NSLock()
    private var muted = false
    private var suppression = PlaybackSuppression()

    var isMuted: Bool {
        lock.lock()
        defer { lock.unlock() }
        if muted { return true }
        return suppression.isSuppressed(at: ProcessInfo.processInfo.systemUptime)
    }

    /// Powód użytkownika (przycisk mikrofonu).
    func setMuted(_ value: Bool) {
        lock.lock()
        muted = value
        lock.unlock()
    }

    /// Dopisuje odcinek odtwarzania do kolejki półdupleksu. Kolejne porcje audio
    /// przychodzą z serwera szybciej niż realne odtwarzanie, więc liczymy koniec
    /// **od końca kolejki**, a nie od „teraz” — inaczej bramka otworzyłaby się
    /// w środku zdania Emmy.
    func schedulePlayback(seconds: TimeInterval) {
        guard seconds > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        suppression.schedule(seconds: seconds, now: ProcessInfo.processInfo.systemUptime)
    }

    /// Przerwanie/`interrupt`: kolejka odtwarzania jest czyszczona, więc bramka
    /// wraca do użytkownika natychmiast — inaczej zostałby niesłyszalny do końca
    /// wyliczonego ogona.
    func releasePlayback() {
        lock.lock()
        suppression.release()
        lock.unlock()
    }
}
#endif
