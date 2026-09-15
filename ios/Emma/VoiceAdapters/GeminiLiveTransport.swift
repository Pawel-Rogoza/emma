#if canImport(UIKit)
import AVFoundation
import Foundation

// MARK: - Adapter transportu Gemini Live API (speech-to-speech)
//
// Drugi dostawca głosu, obok ElevenLabs. Ten plik jest **jedynym** miejscem,
// w którym aplikacja rozmawia z Live API:
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
// Czego Live API nie daje w porównaniu z ElevenLabs Agents:
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
    private let accessToken: String?
    private let installationID: String
    private let audioSession: AudioSessionController?
    private let model: String
    private let endpoint: URL
    private let urlSession: URLSession

    private var configuration: VoiceSessionConfiguration?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var audioSendTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var tracker = GeminiLiveTurnTracker()
    private var continuation: AsyncStream<VoiceEvent>.Continuation?
    private var eventStream: AsyncStream<VoiceEvent>?
    private var generation: Int = 0
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var playerFormat: AVAudioFormat?
    private let microphone = MicrophoneGate()
    private var isClosing = false
    /// Jedna próba wznowienia na zerwanie. Więcej byłoby udawaniem, że sieć
    /// wróciła, a użytkownik nie widzi różnicy między „wracam” i „próbuję w kółko”.
    private var reconnectsLeft = 1

    init(
        tokenProvider: BackendConversationTokenProvider,
        toolExecutor: any VoiceToolExecuting,
        accessToken: String?,
        installationID: String,
        model: String,
        audioSession: AudioSessionController? = nil,
        endpoint: URL = GeminiLiveTransport.defaultEndpoint,
        urlSession: URLSession = .shared
    ) {
        self.tokenProvider = tokenProvider
        self.toolExecutor = toolExecutor
        self.accessToken = accessToken
        self.installationID = installationID
        self.model = model
        self.audioSession = audioSession
        self.endpoint = endpoint
        self.urlSession = urlSession
    }

    // MARK: Połączenie

    public func connect(_ session: VoiceSessionConfiguration) async throws {
        self.configuration = session
        generation += 1
        isClosing = false
        reconnectsLeft = 1
        tracker = GeminiLiveTurnTracker()
        microphone.setMuted(false)

        // Sesję audio dla rozmowy ustawiamy tutaj, dokładnie jak w transporcie
        // ElevenLabs: dostawcy jej nie ustawiają, a bez `.playAndRecord` wejście
        // audio nie istnieje. Awarię meldujemy po otwarciu kanału zdarzeń.
        audioSession?.setProviderOwnsAudioSession(true)
        let audioActivationFailed = audioSession?.activate(.conversation) == false

        // Strumień zdarzeń powstaje raz i żyje całą sesję. Świadomie **nie**
        // kończymy go tutaj: koordynator woła `connect`, a dopiero potem
        // `events()`, ale podglądy i testy robią to w odwrotnej kolejności —
        // zamknięcie kanału w `connect` gubiłoby wtedy cały uścisk dłoni.
        _ = currentStream()

        // Poświadczenie pochodzi z backendu. Normalnie jest już w konfiguracji
        // sesji; poniższa gałąź domyka tylko brak (np. ponowne wejście do sesji).
        let token: String
        if !session.conversationToken.isEmpty {
            token = session.conversationToken
        } else {
            let issued = try await tokenProvider.fetchToken(
                sessionID: session.sessionID,
                contextVersion: session.context.version,
                installationID: installationID,
                accessToken: accessToken
            )
            token = issued.token
        }

        // `connecting` przed otwarciem gniazda: pętla odbioru startuje w środku
        // `openSocket` i `setupComplete` może dotrzeć, zanim wrócimy z `await`.
        emit(.connectionChanged(.connecting))
        try await openSocket(token: token, resumeHandle: nil)

        if audioActivationFailed {
            emit(.fatalError(.audioSessionFailed))
        }
        do {
            try startAudio()
        } catch {
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
                handle(data)
            } catch {
                guard task === socket else { return }
                handleSocketFailure()
                return
            }
        }
    }

    private func handle(_ data: Data) {
        for event in GeminiLiveCodec.decode(data) {
            let outcome = tracker.consume(event)
            if let audio = outcome.audio { enqueuePlayback(audio) }
            // Przerwanie tury po stronie serwera: wycofujemy zbuforowane audio,
            // żeby Emma nie mówiła dalej przez wypowiedź użytkownika.
            if outcome.shouldStopPlayback { stopPlayback() }
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
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        receiveTask?.cancel()
        receiveTask = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let issued = try await self.tokenProvider.fetchToken(
                    sessionID: session.sessionID,
                    contextVersion: session.context.version,
                    installationID: self.installationID,
                    accessToken: self.accessToken
                )
                try await self.openSocket(token: issued.token, resumeHandle: self.tracker.resumptionHandle)
                // Nowe gniazdo = nowy limit prób. Sesja Live API żyje do dwóch
                // godzin, więc jedno zerwanie na całą rozmowę to za mało.
                self.reconnectsLeft = 1
            } catch {
                self.emit(.fatalError(.providerUnavailable))
            }
        }
    }

    // MARK: Audio

    private func startAudio() throws {
        let engine = AVAudioEngine()

        // Kasowanie echa (AEC). Bez tego mikrofon słyszy głośnik, a model
        // odpowiada sam sobie — dokładnie ta pętla, którą zgłoszono po pierwszej
        // udanej rozmowie („Emma słyszy samą siebie i próbuje sobie odpowiadać”).
        // Ścieżka ElevenLabs dostaje AEC od LiveKit/WebRTC; przy własnym silniku
        // trzeba o nie poprosić wprost, i to **przed** startem silnika, bo
        // włączenie przetwarzania głosowego zmienia formaty węzłów wejścia.
        let echoCancellation = enableEchoCancellation(on: engine)
        if !echoCancellation {
            // Nie udajemy, że jest dobrze: bez AEC rozmowa zamienia się w pętlę.
            // Mówimy wprost, co zrobić, i zostawiamy rozmowę działającą.
            emit(.recoverableError(.echoCancellationUnavailable))
        }

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
        let tapBlock = GeminiLiveTransport.makeInputTapBlock(
            converter: converter,
            targetFormat: targetFormat,
            gate: gate,
            continuation: audioContinuation
        )
        input.installTap(onBus: 0, bufferSize: 1600, format: inputFormat, block: tapBlock)

        engine.prepare()
        try engine.start()
        player.play()

        self.engine = engine
        self.player = player
        self.playerFormat = playerFormat

        audioSendTask = Task { [weak self] in
            for await chunk in audioStream {
                guard let self, !Task.isCancelled else { return }
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
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// Ile razy wycofaliśmy lokalne odtwarzanie. `AVAudioPlayerNode` nie mówi,
    /// czy kolejka jest pusta, a twierdzenie „po barge-in audio milknie” musi mieć
    /// dowód — to licznik dla testów, nie element logiki.
    private(set) var localPlaybackStopCount = 0

    private func stopPlayback() {
        localPlaybackStopCount += 1
        guard let player else { return }
        player.stop()
        // `stop()` zwalnia kolejkę; `play()` przywraca węzeł do pracy, żeby
        // kolejne fragmenty nie trafiały do zatrzymanego odtwarzacza.
        player.play()
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
        receiveTask?.cancel()
        receiveTask = nil
        audioSendTask?.cancel()
        audioSendTask = nil
        audioContinuation?.finish()
        audioContinuation = nil

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
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
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.toolExecutor.execute(
                    toolName: call.name,
                    argumentsJSON: call.argumentsJSON
                )
                try await self.send(.toolResponse(id: call.id, name: call.name, resultJSON: result))
                self.emit(
                    .toolProgress(
                        ToolProgress(label: "Sprawdzam dane w kancelarii", toolName: call.name, isFinished: true)
                    )
                )
            } catch {
                let failure = (error as? VoiceToolExecutionError) ?? .failed("Nie udało się sprawdzić danych.")
                // Błąd narzędzia odsyłamy modelowi jako wynik: wtedy Emma powie
                // użytkownikowi, że nie ma danych, zamiast milczeć albo zgadywać.
                let payload = Self.errorJSON(failure.safeMessage)
                try? await self.send(.toolResponse(id: call.id, name: call.name, resultJSON: payload))
                self.emit(.recoverableError(Self.recoverableKind(for: failure)))
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

    /// Włącza systemowe przetwarzanie głosowe na węźle wejścia: to ono daje
    /// kasowanie echa akustycznego (AEC), redukcję szumu i automatyczne
    /// wzmocnienie. Jedna jednostka VoiceProcessingIO obsługuje wtedy **oba**
    /// kierunki, dlatego wołamy to tylko na wejściu — tak każe Apple i tak
    /// wystarcza, żeby system miał sygnał odniesienia do odjęcia od mikrofonu.
    ///
    /// Zwraca `false`, gdy system odmówił (np. symulator bez trasy audio).
    /// Wywołujący musi to pokazać użytkownikowi — z AEC włączonym „za darmo”
    /// nie da się udawać, bo bez niego rozmowa wpada w pętlę.
    private func enableEchoCancellation(on engine: AVAudioEngine) -> Bool {
        do {
            try engine.inputNode.setVoiceProcessingEnabled(true)
            return engine.inputNode.isVoiceProcessingEnabled
        } catch {
            return false
        }
    }

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
final class MicrophoneGate: @unchecked Sendable {
    private let lock = NSLock()
    private var muted = false

    var isMuted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return muted
    }

    func setMuted(_ value: Bool) {
        lock.lock()
        muted = value
        lock.unlock()
    }
}
#endif
