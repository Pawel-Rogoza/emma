import Foundation

// MARK: - Scenariusze deterministyczne
//
// Mock działa bez kont API, bez mikrofonu i bez sieci. Każde zdarzenie pochodzi
// ze skryptu, więc scenariusz jest powtarzalny w testach (§etap 06).

public struct VoiceScenarioStep: Hashable, Sendable {
    public var payload: VoiceEventPayload
    /// Opóźnienie przed emisją. W testach 0, w podglądzie UI niewielkie.
    public var delay: TimeInterval
    /// Nadpisanie generacji połączenia — do testów zdarzeń spóźnionych.
    public var generationOverride: UInt64?
    public var turnID: String?

    public init(
        _ payload: VoiceEventPayload,
        delay: TimeInterval = 0,
        generationOverride: UInt64? = nil,
        turnID: String? = nil
    ) {
        self.payload = payload
        self.delay = delay
        self.generationOverride = generationOverride
        self.turnID = turnID
    }
}

public struct VoiceScenario: Hashable, Sendable {
    public var name: String
    public var steps: [VoiceScenarioStep]
    public var capabilities: VoiceCapabilities
    /// Zdolność odpowiedzi na turę tekstową w trakcie sesji.
    public var respondsToTextTurns: Bool

    public init(
        name: String,
        steps: [VoiceScenarioStep],
        capabilities: VoiceCapabilities = .mock,
        respondsToTextTurns: Bool = true
    ) {
        self.name = name
        self.steps = steps
        self.capabilities = capabilities
        self.respondsToTextTurns = respondsToTextTurns
    }
}

public extension VoiceScenario {

    /// Scenariusz podstawowy z §etap 06:
    /// start → listening → partial/final → thinking → speaking → barge-in →
    /// korekta → nowa propozycja → potwierdzenie → wykonanie.
    static func standardProposalFlow(
        proposal: ActionProposal,
        execution: ActionExecution
    ) -> VoiceScenario {
        VoiceScenario(
            name: "standard-proposal-flow",
            steps: [
                .init(.connectionChanged(.connecting), delay: 0.10),
                .init(.microphoneChanged(.capturing), delay: 0.05),
                .init(.connectionChanged(.connected), delay: 0.15),
                .init(.userSpeechStarted, delay: 0.30),
                .init(.userTranscriptPartial("Przygotuj odpo"), delay: 0.20),
                .init(.userTranscriptPartial("Przygotuj odpowiedź do Oleny"), delay: 0.20),
                .init(.userTranscriptFinal("Przygotuj odpowiedź do Oleny"), delay: 0.15, turnID: "turn-1"),
                .init(.toolProgress(ToolProgress(label: "Czytam ustalenia sprawy", toolName: "get_case_summary")), delay: 0.25),
                .init(.toolProgress(ToolProgress(label: "Czytam ustalenia sprawy", toolName: "get_case_summary", isFinished: true)), delay: 0.20),
                .init(.agentTextFinal("Przygotowałam wiadomość do Oleny Kowalenko."), delay: 0.20, turnID: "turn-1"),
                .init(.playbackStarted(approximate: false), delay: 0.05),
                .init(.agentTextFinal("Przygotowałam wiadomość do Oleny Kowalenko. Sprawdź treść przed zatwierdzeniem."), delay: 0.60, turnID: "turn-1"),
                .init(.playbackStopped(reason: .completed), delay: 0.20),
                .init(.proposalChanged(ProposalSnapshot(proposal: proposal)), delay: 0.10, turnID: "turn-1")
            ]
        )
    }

    /// Barge-in w trakcie wypowiedzi Emmy oraz korekta treści.
    static func bargeInAndCorrection(
        revised: ActionProposal
    ) -> VoiceScenario {
        VoiceScenario(
            name: "barge-in-and-correction",
            steps: [
                .init(.connectionChanged(.connected)),
                .init(.microphoneChanged(.capturing)),
                .init(.agentTextDelta("Wiadomość do klienta: ")),
                .init(.agentTextDelta("Dzień dobry, widzę naszą ")),
                .init(.playbackStarted(approximate: false)),
                .init(.userSpeechStarted),
                .init(.interruption(InterruptionReason.userBargeIn)),
                .init(.playbackStopped(reason: .interrupted)),
                .init(.userTranscriptFinal("Nie, spotkanie jest o jedenastej"), turnID: "turn-2"),
                .init(.proposalChanged(ProposalSnapshot(proposal: revised)))
            ]
        )
    }

    /// Odmowa dostępu do mikrofonu. Aplikacja pozostaje użyteczna tekstem (§5.7).
    static func permissionDenied() -> VoiceScenario {
        VoiceScenario(
            name: "permission-denied",
            steps: [
                .init(.connectionChanged(.requestingPermission), delay: 0.10),
                .init(.microphoneChanged(.unavailable), delay: 0.10),
                .init(.fatalError(FatalErrorKind.microphonePermissionDenied), delay: 0.05),
                .init(.connectionChanged(.failed), delay: 0.05)
            ]
        )
    }

    /// Utrata sieci i wznowienie połączenia. Ostatnie polecenie **nie** jest ponawiane (§5.6).
    static func reconnect() -> VoiceScenario {
        VoiceScenario(
            name: "reconnect",
            steps: [
                .init(.connectionChanged(.connected)),
                .init(.microphoneChanged(.capturing)),
                .init(.userTranscriptFinal("Sprawdź plan na dziś"), turnID: "turn-1"),
                .init(.agentTextDelta("Dzisiaj w zespole: ")),
                .init(.recoverableError(RecoverableErrorKind.networkLost)),
                .init(.connectionChanged(.reconnecting)),
                .init(.interruption(InterruptionReason.systemAudioInterruption)),
                .init(.connectionChanged(.connected)),
                .init(.microphoneChanged(.capturing)),
                .init(.contextAccepted(Version(3)))
            ]
        )
    }

    /// Spóźnione zdarzenie ze starej generacji połączenia. Musi zostać odrzucone (§5.4).
    static func staleEvent() -> VoiceScenario {
        VoiceScenario(
            name: "stale-event",
            steps: [
                .init(.connectionChanged(.connected), generationOverride: 1),
                .init(.microphoneChanged(.capturing), generationOverride: 1),
                .init(.userTranscriptFinal("Stare polecenie"), generationOverride: 1, turnID: "old-turn"),
                .init(.connectionChanged(.reconnecting), generationOverride: 2),
                .init(.connectionChanged(.connected), generationOverride: 2),
                // To zdarzenie pochodzi z generacji 1 i nie może zmienić stanu generacji 2.
                .init(.agentTextDelta("SPÓŹNIONA ODPOWIEDŹ"), generationOverride: 1, turnID: "old-turn")
            ]
        )
    }

    /// Sesja z klientem rosyjskojęzycznym: dyktowanie PL, propozycja RU.
    static func mixedLanguages(proposal: ActionProposal) -> VoiceScenario {
        VoiceScenario(
            name: "mixed-languages",
            steps: [
                .init(.connectionChanged(.connected)),
                .init(.microphoneChanged(.capturing)),
                .init(.userTranscriptFinal("Напиши ему, что встреча подтверждена"), turnID: "turn-1"),
                .init(.agentTextFinal("Черновик готов. Проверьте текст перед отправкой."), turnID: "turn-1"),
                .init(.playbackStarted(approximate: false)),
                .init(.playbackStopped(reason: .completed)),
                .init(.proposalChanged(ProposalSnapshot(proposal: proposal)))
            ]
        )
    }
}

// MARK: - MockVoiceTransport

@MainActor
public final class MockVoiceTransport: VoiceTransport {

    public private(set) var capabilities: VoiceCapabilities

    private let scenario: VoiceScenario
    private let delayProvider: @Sendable (TimeInterval) async throws -> Void
    private var continuation: AsyncStream<VoiceEvent>.Continuation?
    private var runTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var sessionID = VoiceSessionID("mock-session")
    private var eventCounter = 0
    private var emittedEvents: [VoiceEvent] = []
    private var isMuted = false
    private var isRunning = false

    /// Wszystkie zdarzenia wyemitowane przez transport. Używane przez testy
    /// i przez ekran diagnostyczny w trybie debug.
    public var recordedEvents: [VoiceEvent] { emittedEvents }

    public init(
        scenario: VoiceScenario,
        delayProvider: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            guard seconds > 0 else { return }
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.scenario = scenario
        self.capabilities = scenario.capabilities
        self.delayProvider = delayProvider
    }

    public convenience init(scenarioName: String = "standard-proposal-flow") {
        self.init(scenario: MockVoiceScenarios.named(scenarioName))
    }

    public func connect(_ session: VoiceSessionConfiguration) async throws {
        generation += 1
        sessionID = session.sessionID
        capabilities = session.capabilities
        emittedEvents.removeAll()
        eventCounter = 0
        isRunning = true
        startScript()
    }

    public func events() -> AsyncStream<VoiceEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { _ in }
        }
    }

    public func setMicrophoneMuted(_ muted: Bool) async throws {
        isMuted = muted
        emit(.microphoneChanged(muted ? .muted : .capturing))
    }

    public func interrupt(_ request: InterruptionRequest) async throws {
        emit(.interruption(request.reason))
        emit(.playbackStopped(reason: .interrupted))
        // Przerwanie zatrzymuje dalszy skrypt wypowiedzi Emmy.
        runTask?.cancel()
        runTask = nil
    }

    public func updateContext(_ context: AssistantContext) async throws {
        emit(.contextAccepted(context.version))
    }

    public func sendTextTurn(_ input: AssistantTextInput) async throws {
        emit(.userTranscriptFinal(input.text), turnID: input.inputID)
        emit(.agentTextDelta("Przyjęłam polecenie tekstem."), turnID: input.inputID)
        emit(.agentTextFinal("Przyjęłam polecenie tekstem."), turnID: input.inputID)
    }

    public func disconnect(reason: VoiceEndReason) async {
        isRunning = false
        runTask?.cancel()
        runTask = nil
        emit(.playbackStopped(reason: .sessionEnded))
        emit(.connectionChanged(.ended))
        continuation?.finish()
        continuation = nil
    }

    /// Ręczne wypuszczenie pojedynczego kroku scenariusza. Używane przez testy,
    /// aby nie zależeć od czasu.
    public func emitManually(_ payload: VoiceEventPayload, generationOverride: UInt64? = nil, turnID: String? = nil) {
        emit(payload, generationOverride: generationOverride, turnID: turnID)
    }

    // MARK: Wewnętrzne

    private func startScript() {
        runTask?.cancel()
        let steps = scenario.steps
        let scriptedGeneration = generation
        runTask = Task { [weak self] in
            for step in steps {
                guard let self else { return }
                if Task.isCancelled { return }
                if step.delay > 0 {
                    do { try await self.delayProvider(step.delay) }
                    catch { return }
                }
                if Task.isCancelled { return }
                self.emit(step.payload, generationOverride: step.generationOverride, turnID: step.turnID, fallbackGeneration: scriptedGeneration)
            }
        }
    }

    private func emit(
        _ payload: VoiceEventPayload,
        generationOverride: UInt64? = nil,
        turnID: String? = nil,
        fallbackGeneration: UInt64? = nil
    ) {
        eventCounter += 1
        let generationValue = generationOverride ?? fallbackGeneration ?? generation
        var contextVersion: Version?
        if case .proposalChanged(let snapshot) = payload {
            contextVersion = snapshot.proposal.contextVersion
        }
        let event = VoiceEvent(
            eventID: "mock-event-\(eventCounter)",
            sessionID: sessionID,
            connectionGeneration: ConnectionGeneration(generationValue),
            turnID: turnID,
            contextVersion: contextVersion,
            sourceSequence: eventCounter,
            receivedAt: Date(),
            source: .mockTransport,
            payload: payload
        )
        emittedEvents.append(event)
        continuation?.yield(event)
    }
}

// MARK: - Biblioteka scenariuszy mocka

public enum MockVoiceScenarios {

    /// Argument `--fixture=voice-…` albo nazwa scenariusza z kodu.
    public static func named(_ name: String) -> VoiceScenario {
        switch name {
        case "permission-denied":
            return .permissionDenied()
        case "reconnect":
            return .reconnect()
        case "stale-event":
            return .staleEvent()
        case "barge-in":
            return .bargeInAndCorrection(revised: DemoFixtures.revisedReplyProposal)
        case "mixed-languages":
            return .mixedLanguages(proposal: DemoFixtures.replyProposalRussian)
        default:
            return .standardProposalFlow(
                proposal: DemoFixtures.replyProposal,
                execution: DemoFixtures.queuedExecution
            )
        }
    }

    public static let allNames = [
        "standard-proposal-flow",
        "barge-in",
        "permission-denied",
        "reconnect",
        "stale-event",
        "mixed-languages"
    ]
}

// MARK: - MockDictationService

@MainActor
public final class MockDictationService: DictationService {

    /// Deterministyczna transkrypcja per język. Ostatni element to wynik finalny.
    public static let scriptedTranscripts: [LanguageCode: [String]] = [
        .pl: ["Wyślij to", "Wyślij to jutro"],
        .ru: ["Отправь это", "Отправь это завтра"],
        .uk: ["Надішли це", "Надішли це завтра"]
    ]

    private var continuation: AsyncStream<DictationEvent>.Continuation?
    private var request: DictationRequest?
    private var stepIndex = 0
    private let failure: DictationFailure?
    private let delayProvider: @Sendable (TimeInterval) async throws -> Void

    public init(
        failure: DictationFailure? = nil,
        delayProvider: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            guard seconds > 0 else { return }
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.failure = failure
        self.delayProvider = delayProvider
    }

    public func start(_ request: DictationRequest) async throws {
        self.request = request
        stepIndex = 0
        guard let continuation else { return }
        continuation.yield(.started(request.target))
        if let failure {
            continuation.yield(.failed(failure))
            return
        }
        let script = Self.scriptedTranscripts[request.language] ?? Self.scriptedTranscripts[.pl]!
        for index in script.indices {
            let isLast = index == script.count - 1
            if !isLast {
                continuation.yield(.partialText(script[index]))
            } else {
                continuation.yield(.finalText(script[index]))
            }
        }
    }

    public func events() -> AsyncStream<DictationEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    public func finish() async {
        continuation?.yield(.cancelled)
    }

    public func cancel() async {
        continuation?.yield(.cancelled)
    }
}

// MARK: - MockSpeechPlaybackService

@MainActor
public final class MockSpeechPlaybackService: SpeechPlaybackService {

    private var continuation: AsyncStream<PlaybackEvent>.Continuation?
    private var current: SpeechPlaybackRequest?
    /// Mock raportuje dokładne zdarzenia odtwarzania, więc informacja nie jest przybliżona.
    public let reportsExactPlayback = true

    public init() {}

    public func play(_ request: SpeechPlaybackRequest) async throws {
        current = request
        continuation?.yield(.started(sourceID: request.sourceID, approximate: false))
        continuation?.yield(.progress(sourceID: request.sourceID))
        continuation?.yield(.finished(sourceID: request.sourceID, reason: .completed))
    }

    public func events() -> AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    public func stop() async {
        guard let current else { return }
        continuation?.yield(.finished(sourceID: current.sourceID, reason: .interrupted))
        self.current = nil
    }
}
