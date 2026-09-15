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

    /// Adres WebSocket Live API. Bez klucza — klucz dokładamy jako parametr
    /// zapytania dopiero przy otwarciu połączenia, i nigdy nie logujemy adresu.
    private static let defaultEndpoint = URL(
        string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
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

        continuation?.finish()
        let stream = AsyncStream<VoiceEvent>.makeStream()
        eventStream = stream.stream
        continuation = stream.continuation

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

        try await openSocket(token: token, resumeHandle: nil)

        emit(.connectionChanged(.connecting))
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
        components.queryItems = [URLQueryItem(name: "key", value: token)]
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
            if let call = outcome.toolCall { executeToolCall(call) }
            for payload in outcome.payloads { emit(payload) }
        }
    }

    /// Zerwanie połączenia: domykamy to, co otwarte, i próbujemy wznowić sesję
    /// z uchwytem. Nie udajemy, że rozmowa trwa dalej bez przerwy.
    private func handleSocketFailure() {
        guard !isClosing else { return }
        for payload in tracker.connectionLost().payloads { emit(payload) }
        stopPlayback()
        guard reconnectsLeft > 0, let session = configuration else {
            emit(.fatalError(.providerUnavailable))
            return
        }
        reconnectsLeft -= 1
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
            } catch {
                self.emit(.fatalError(.providerUnavailable))
            }
        }
    }

    // MARK: Audio

    private func startAudio() throws {
        let engine = AVAudioEngine()
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

        // Domknięcie tapu celowo **nie chwyta `self`**: AVFAudio woła je z wątku
        // tła, a `self` jest `@MainActor`. Chwytamy tylko wartości `Sendable`
        // (konwerter, docelowy format, bramkę mikrofonu, kontynuację strumienia).
        let gate = microphone
        input.installTap(onBus: 0, bufferSize: 1600, format: inputFormat) { buffer, _ in
            guard !gate.isMuted else { return }
            guard let pcm = GeminiLiveTransport.convertToPCM16(
                buffer,
                converter: converter,
                targetFormat: targetFormat
            ) else { return }
            audioContinuation.yield(pcm)
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

    private func stopPlayback() {
        guard let player else { return }
        player.stop()
        // `stop()` zwalnia kolejkę; `play()` przywraca węzeł do pracy, żeby
        // kolejne fragmenty nie trafiały do zatrzymanego odtwarzacza.
        player.play()
    }

    // MARK: Strumień zdarzeń

    public func events() -> AsyncStream<VoiceEvent> {
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

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, statusPointer in
            if supplied {
                statusPointer.pointee = .noDataNow
                return nil
            }
            supplied = true
            statusPointer.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0, let samples = output.int16ChannelData else { return nil }
        return Data(bytes: samples[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
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
