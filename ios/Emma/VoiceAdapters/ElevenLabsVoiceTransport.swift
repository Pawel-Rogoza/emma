#if canImport(ElevenLabs)
import Combine
import ElevenLabs
import Foundation

// MARK: - Adapter transportu ElevenLabs
//
// Jedyne miejsce, w którym aplikacja rozmawia z dostawcą głosu. Adapter:
//   • używa **oficjalnego** Swift SDK (`ElevenLabs`, wersja przypięta w project.yml),
//   • nie zawiera żadnego klucza API — otrzymuje wyłącznie token rozmowy wydany
//     przez backend (`BackendConversationTokenProvider`),
//   • nie wykonuje akcji biznesowych: narzędzia dostawcy są obsługiwane po stronie
//     backendu przez ten sam action engine, którego używa UI (§8.1). Klient nie ma
//     prawa zatwierdzić ani wykonać zapisu samodzielnie.

@MainActor
public final class ElevenLabsVoiceTransport: VoiceTransport {

    /// Możliwości wynikające z API SDK. Wartości odpowiadają temu, co SDK
    /// faktycznie raportuje; po weryfikacji na koncie można je rozszerzyć (§etap 09).
    public let capabilities = VoiceCapabilities(
        partialTranscripts: true,
        interruptGeneration: true,
        localPlaybackStop: true,
        reportsPlaybackEvents: true,
        routeSelection: true,
        contextUpdate: true,
        textTurn: true,
        reportsInterruptionReason: true
    )

    private let tokenProvider: BackendConversationTokenProvider
    private let accessToken: String?
    private var conversation: Conversation?
    private var continuation: AsyncStream<VoiceEvent>.Continuation?
    private var configuration: VoiceSessionConfiguration?
    /// Generacja połączenia. SDK nie przekazuje jej wprost, a koordynator musi
    /// umieć odrzucić zdarzenia z poprzedniego połączenia — dlatego liczymy ją tutaj.
    private var generation: Int = 0
    private var observedTasks: [Task<Void, Never>] = []

    /// Inicjalizacja jest wewnętrzna, bo dostawca tokenu (`BackendConversationTokenProvider`)
    /// nie jest typem publicznym — transport powstaje wyłącznie przez `VoiceServicesFactory`.
    init(tokenProvider: BackendConversationTokenProvider, accessToken: String?) {
        self.tokenProvider = tokenProvider
        self.accessToken = accessToken
    }

    // MARK: Połączenie

    public func connect(_ session: VoiceSessionConfiguration) async throws {
        self.configuration = session
        generation += 1

        // Token rozmowy pochodzi z backendu; aplikacja nigdy nie wysyła klucza API.
        let token: String
        if !session.conversationToken.isEmpty {
            token = session.conversationToken
        } else {
            let issued = try await tokenProvider.fetchToken(
                sessionID: session.sessionID,
                contextVersion: session.context.version,
                accessToken: accessToken
            )
            token = issued.token
        }

        let stream = AsyncStream<VoiceEvent>.makeStream()
        continuation = stream.continuation

        // Kontekst sprawy jest wysyłany jako dane inicjujące, ale **wiążące**
        // znaczenie ma dopiero weryfikacja po stronie backendu (§5.1).
        let config = ConversationConfig(
            onAgentReady: { [weak self] in
                Task { @MainActor in self?.emit(.connectionChanged(.connected)) }
            },
            onDisconnect: { [weak self] _ in
                Task { @MainActor in
                    self?.emit(.connectionChanged(.ended))
                    self?.continuation?.finish()
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in self?.emit(.fatalError(Self.fatalKind(for: error))) }
            },
            onAgentResponse: { [weak self] text, _ in
                Task { @MainActor in self?.emit(.agentTextFinal(text)) }
            },
            onUserTranscript: { [weak self] text, _ in
                Task { @MainActor in
                    self?.emit(.userTranscriptFinal(text))
                }
            },
            onInterruption: { [weak self] _ in
                Task { @MainActor in self?.emit(.interruption(.agentTurnCancelled)) }
            },
            onUnhandledClientToolCall: { [weak self] call in
                Task { @MainActor in
                    // Zdarzenie narzędzia jest wyłącznie informacją o postępie.
                    // Wykonanie należy do backendu — klient nie ma ścieżki zapisu.
                    self?.emit(.toolProgress(ToolProgress(label: "Emma pracuje nad sprawą", toolName: call.toolName)))
                }
            }
        )

        let started = try await ElevenLabs.startConversation(
            conversationToken: token,
            config: config
        )
        conversation = started
        observe(started)
        emit(.connectionChanged(.connecting))
    }

    /// SDK jest obserwowalny (`ObservableObject`), więc stan połączenia i stan agenta
    /// czytamy z publikowanych wartości zamiast zgadywać go z wywołań zwrotnych.
    ///
    /// Uwaga: `onAgentStateChange` w `ConversationConfig` działa **wyłącznie** w trybie
    /// opartym na zdarzeniach (wymaga `agentStateConfiguration`). Obserwacja
    /// `agentState` działa w obu trybach i nie zmienia zachowania SDK.
    private func observe(_ conversation: Conversation) {
        observedTasks.append(
            Task { [weak self] in
                for await state in conversation.$state.values {
                    guard let self else { return }
                    self.handle(state: state)
                }
            }
        )
        observedTasks.append(
            Task { [weak self] in
                for await agentState in conversation.$agentState.values {
                    guard let self else { return }
                    self.handle(agentState: agentState)
                }
            }
        )
    }

    private func handle(state: ConversationState) {
        switch state {
        case .idle:
            emit(.connectionChanged(.idle))
        case .connecting:
            emit(.connectionChanged(.connecting))
        case .active:
            emit(.connectionChanged(.connected))
        case .ended:
            emit(.connectionChanged(.ended))
        case .error(let error):
            emit(.fatalError(Self.fatalKind(for: error)))
        @unknown default:
            break
        }
    }

    private func handle(agentState: ElevenLabs.AgentState) {
        switch agentState {
        case .listening:
            // SDK nie raportuje osobno końca odtwarzania, dopóki agent nie wróci
            // do słuchania — dopiero ten stan zamyka odtwarzanie w naszym modelu.
            emit(.playbackStopped(reason: .completed))
        case .thinking:
            // „Myśli” nie jest w naszym modelu osobnym zdarzeniem tury; stan tury
            // wynika z transkrypcji i odtwarzania, więc nie zgadujemy go tutaj.
            break
        case .speaking:
            emit(.playbackStarted(approximate: true))
        @unknown default:
            break
        }
    }

    // MARK: Strumień zdarzeń

    public func events() -> AsyncStream<VoiceEvent> {
        let stream = AsyncStream<VoiceEvent>.makeStream()
        // Jedno połączenie = jeden strumień. Koordynator jest jedynym subskrybentem,
        // więc kolejne żądanie zwraca ten sam kanał, a nie drugi.
        if let continuation {
            continuation.finish()
        }
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
        guard let conversation else { return }
        try await conversation.setMicrophoneMuted(muted)
        emit(.microphoneChanged(muted ? .muted : .capturing))
    }

    public func interrupt(_ request: InterruptionRequest) async throws {
        guard let conversation else { return }
        try await conversation.interruptAgent()
        emit(.interruption(request.reason))
    }

    public func updateContext(_ context: AssistantContext) async throws {
        guard let conversation else { return }
        // `updateContext` w SDK 3.3.1 przyjmuje tekst aktualizacji kontekstu, nie
        // słownik. Wysyłamy zwięzły, stabilny zapis tych samych pól; backend i tak
        // waliduje spójność (klient + sprawa) przed wykonaniem jakiegokolwiek zapisu.
        let fields: [String: String] = [
            "scope": context.scope.rawValue,
            "client_id": context.clientID?.rawValue ?? "",
            "case_id": context.caseID?.rawValue ?? "",
            "version": String(context.version.value)
        ]
        let payload = String(decoding: try JSONEncoder().encode(fields), as: UTF8.self)
        try await conversation.updateContext(payload)
        // Potwierdzenie kontekstu przychodzi od backendu; dopóki go nie ma,
        // lokalny stan kontekstu nie jest uznawany za obowiązujący.
    }

    public func sendTextTurn(_ input: AssistantTextInput) async throws {
        guard let conversation else { return }
        try await conversation.sendMessage(input.text)
        emit(.userTranscriptFinal(input.text))
    }

    public func disconnect(reason: VoiceEndReason) async {
        observedTasks.forEach { $0.cancel() }
        observedTasks.removeAll()
        await conversation?.endConversation()
        conversation = nil
        emit(.connectionChanged(.ended))
        continuation?.finish()
        continuation = nil
    }

    // MARK: Mapowanie błędów

    /// Mapowanie błędów SDK 3.3.1 na nasze rodzaje błędów krytycznych.
    ///
    /// SDK nie ma osobnego przypadku „odmowa dostępu do mikrofonu” ani
    /// „połączenie zamknięte” — te stany rozpoznajemy po dostępnych przypadkach,
    /// a wszystko nieznane zostaje `.unknown` (bez twierdzenia, że sesja żyje).
    private static func fatalKind(for error: ConversationError) -> FatalErrorKind {
        switch error {
        case .authenticationFailed:
            return .authenticationFailed
        case .notConnected, .connectionFailed, .agentTimeout,
             .localNetworkPermissionRequired, .serverError:
            return .providerUnavailable
        case .microphoneToggleFailed:
            return .audioSessionFailed
        case .alreadyActive, .noSoftwareMuteHandlerConfigured:
            return .unknown
        }
    }

    private static func fatalKind(for error: any Error) -> FatalErrorKind {
        if let conversationError = error as? ConversationError {
            return fatalKind(for: conversationError)
        }
        return .unknown
    }
}
#endif
