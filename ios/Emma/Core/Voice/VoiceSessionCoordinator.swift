import Foundation

// MARK: - VoiceSessionCoordinator
//
// Jeden koordynator voice w procesie aplikacji (§1.9). Jest właścicielem transportu
// i jego **jednego subskrybenta** (§5.3). Widoki nie tworzą własnej rozmowy
// przy każdym `onAppear` — subskrybują stan koordynatora.
//
// Rozmowa, dyktowanie i odsłuch są osobnymi trybami dzielącymi jeden zasób audio (§5.1).

@MainActor
public final class VoiceSessionCoordinator {

    // MARK: Publiczny stan

    public private(set) var state: VoiceUIState {
        didSet {
            guard state != oldValue else { return }
            for observer in observers.values {
                observer(state)
            }
        }
    }

    public var capabilities: VoiceCapabilities { transport?.capabilities ?? .providerUnverified }

    /// Czy zgłoszenia zgody głosowej są uzbrojone dla wskazanej prezentacji.
    public var armedPresentationID: String? { actionState.armedPresentationID }

    /// Czy zapisy głosem są zablokowane (odebrane uprawnienie, tło, wylogowanie).
    /// Nie odbiera to użytkownikowi możliwości zatwierdzenia **przyciskiem w UI** (§5.6).
    public private(set) var voiceWritesRevoked = false

    public private(set) var lastEndReason: VoiceEndReason?
    /// Ostatnie polecenie użytkownika. Służy wyłącznie do diagnostyki —
    /// reconnect **nie** wysyła go ponownie (§5.6).
    public private(set) var lastUserUtterance: String?

    // MARK: Zależności

    private let sessionRepository: VoiceSessionRepository
    private let actionRepository: AssistantActionRepository
    private let actionEngine: ActionEngine
    private let clock: Clock
    private let idleTimeout: TimeInterval
    private let sessionLifetime: TimeInterval

    // MARK: Zasoby wewnętrzne

    private var transport: VoiceTransport?
    private var transportTask: Task<Void, Never>?
    private var dictationService: DictationService?
    private var dictationTask: Task<Void, Never>?
    private var playbackService: SpeechPlaybackService?
    private var playbackTask: Task<Void, Never>?

    private var sessionConfiguration: VoiceSessionConfiguration?
    private var actionState = ActionEngine.State()
    private var observers: [UUID: (VoiceUIState) -> Void] = [:]
    private var internalReducer = VoiceStateReducer()
    private var eventLog: [VoiceEvent] = []
    private var rejections: [VoiceStateReducer.Rejection] = []
    private var actionIDSequence = 0
    private var startedAt: Date?

    /// Pełny ślad zdarzeń sesji. Używany w diagnostyce i w testach kontraktu.
    public var recordedEvents: [VoiceEvent] { eventLog }
    /// Odrzucone zdarzenia spóźnione — dowód działania reguły z §5.4.
    public var recordedRejections: [VoiceStateReducer.Rejection] { rejections }

    public init(
        sessionRepository: VoiceSessionRepository,
        actionRepository: AssistantActionRepository,
        actionEngine: ActionEngine = ActionEngine(),
        clock: Clock = SystemClock(),
        idleTimeout: TimeInterval = 5 * 60,
        sessionLifetime: TimeInterval = 30 * 60
    ) {
        self.sessionRepository = sessionRepository
        self.actionRepository = actionRepository
        self.actionEngine = actionEngine
        self.clock = clock
        self.idleTimeout = idleTimeout
        self.sessionLifetime = sessionLifetime
        self.state = VoiceUIState()
    }

    // MARK: Obserwacja stanu

    public func addObserver(_ observer: @escaping (VoiceUIState) -> Void) -> UUID {
        let token = UUID()
        observers[token] = observer
        observer(state)
        return token
    }

    public func removeObserver(_ token: UUID) {
        observers.removeValue(forKey: token)
    }

    public func stateStream() -> AsyncStream<VoiceUIState> {
        AsyncStream { continuation in
            let token = addObserver { continuation.yield($0) }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.removeObserver(token) }
            }
        }
    }

    // MARK: - Tryb 1: rozmowa z Emmą

    /// Start lub wznowienie istniejącej sesji. Nie tworzy nowego agenta przy każdym tapnięciu.
    public func startConversation(
        context: AssistantContext,
        user: User,
        installationID: String,
        transportFactory: (VoiceSessionConfiguration) -> VoiceTransport
    ) async {
        if state.sessionID != nil, state.connection == .connected || state.connection == .connecting {
            // Wznowienie istniejącej sesji: aktualizujemy tylko kontekst.
            await updateContext(context)
            return
        }
        sessionConfiguration = nil
        voiceWritesRevoked = false
        state = VoiceUIState(
            connection: .requestingPermission,
            turn: .waiting,
            microphone: .unavailable,
            action: state.action,
            route: state.route,
            mode: .conversation
        )
        do {
            let configuration = try await sessionRepository.create(
                CreateVoiceSession(
                    userID: user.id,
                    context: context,
                    assistantLanguage: user.assistantLanguage,
                    installationID: installationID
                )
            )
            sessionConfiguration = configuration
            let transport = transportFactory(configuration)
            self.transport = transport
            state.sessionID = configuration.sessionID
            state.contextVersion = configuration.context.version
            state.connection = .connecting
            try await transport.connect(configuration)
            startTransportSubscription(transport)
        } catch {
            let message = (error as? DomainError)?.safeMessage
                ?? FatalErrorKind.providerUnavailable.safeMessage
            state.connection = .failed
            state.turn = .waiting
            state.mode = .idle
            state.lastError = message
        }
    }

    /// Wstrzyknięcie gotowego transportu (mock albo adapter dostawcy).
    /// Używane przez testy i przez scenariusze demo; nie zmienia logiki koordynatora.
    public func attach(transport: VoiceTransport, configuration: VoiceSessionConfiguration) async {
        self.transport = transport
        self.sessionConfiguration = configuration
        voiceWritesRevoked = false
        state = VoiceUIState(
            connection: .connecting,
            turn: .waiting,
            microphone: .unavailable,
            action: state.action,
            route: state.route,
            mode: .conversation,
            contextVersion: configuration.context.version,
            sessionID: configuration.sessionID
        )
        startedAt = clock.now()
        do {
            try await transport.connect(configuration)
            startTransportSubscription(transport)
        } catch {
            state.connection = .failed
            state.lastError = FatalErrorKind.providerUnavailable.safeMessage
        }
    }

    private func startTransportSubscription(_ transport: VoiceTransport) {
        // Jeden subskrybent na proces. Poprzedni jest zawsze anulowany.
        transportTask?.cancel()
        let stream = transport.events()
        transportTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if Task.isCancelled { return }
                await MainActor.run { self.ingest(event) }
            }
        }
    }

    /// Przyjęcie pojedynczego zdarzenia z transportu. Ścieżka używana przez adapter
    /// dostawcy oraz przez testy. Spóźnione zdarzenia są odrzucane i zapisywane.
    public func ingest(_ event: VoiceEvent) {
        eventLog.append(event)
        if eventLog.count > 500 { eventLog.removeFirst(eventLog.count - 500) }
        var mutable = state
        if let rejection = internalReducer.apply(event, to: &mutable) {
            rejections.append(rejection)
            return
        }
        // Odbicie treści wypowiedzi i propozycji w stanie koordynatora.
        switch event.payload {
        case .userTranscriptFinal(let text):
            lastUserUtterance = text
        case .proposalChanged(let snapshot):
            actionState.proposals[snapshot.proposal.id] = snapshot.proposal
            if snapshot.proposal.state == .proposed {
                actionState.armedPresentationID = nil
            }
        case .executionChanged(let snapshot):
            actionState.executions[snapshot.execution.actionID] = snapshot.execution
        default:
            break
        }
        state = mutable
    }

    /// Wysłanie tury tekstowej w aktywnej sesji.
    public func sendTextTurn(
        text: String,
        language: LanguageCode,
        inputID: String
    ) async {
        guard let transport, let contextVersion = state.contextVersion else { return }
        let input = AssistantTextInput(
            text: text,
            language: language,
            contextVersion: contextVersion,
            inputID: inputID,
            origin: .typedText
        )
        lastUserUtterance = text
        do {
            try await transport.sendTextTurn(input)
        } catch {
            state.lastError = DomainError.transportFailure("polecenie tekstowe").safeMessage
        }
    }

    /// Wyciszenie mikrofonu. Nie kończy sesji i nie zmienia stanu połączenia (§5.5).
    public func setMicrophoneMuted(_ muted: Bool) async {
        guard let transport else { return }
        do {
            try await transport.setMicrophoneMuted(muted)
        } catch {
            state.lastError = DomainError.transportFailure("mikrofon").safeMessage
        }
    }

    /// Przerwanie: natychmiastowe zatrzymanie lokalnego audio, anulowanie tury
    /// i rozbrojenie prezentacji akcji. Nie wycofuje requestu do Meta, który już wyszedł (§5.6).
    public func interrupt(_ request: InterruptionRequest = InterruptionRequest(reason: .userRequested)) async {
        // Lokalne zatrzymanie odtwarzania jest natychmiastowe i niezależne od możliwości transportu.
        await playbackService?.stop()
        actionEngine.disarm(into: &actionState)
        guard let transport else {
            var mutable = state
            internalReducer.apply(
                VoiceEvent(
                    eventID: "local-interrupt",
                    sessionID: state.sessionID ?? VoiceSessionID("local"),
                    connectionGeneration: state.connectionGeneration,
                    receivedAt: clock.now(),
                    source: .localPlaybackController,
                    payload: .interruption(request.reason)
                ),
                to: &mutable
            )
            state = mutable
            return
        }
        do {
            try await transport.interrupt(request)
        } catch {
            state.lastError = DomainError.transportFailure("przerwanie").safeMessage
        }
    }

    /// Aktualizacja kontekstu w trakcie sesji. Wersjonowana, oddzielna czynność (§5.2).
    public func updateContext(_ context: AssistantContext) async {
        guard let transport, let sessionID = state.sessionID else { return }
        let expected = state.contextVersion ?? context.version
        do {
            _ = try await sessionRepository.updateContext(
                UpdateVoiceContext(sessionID: sessionID, context: context, expectedContextVersion: expected)
            )
            try await transport.updateContext(context)
        } catch {
            state.lastError = (error as? DomainError)?.safeMessage
                ?? DomainError.transportFailure("kontekst").safeMessage
        }
    }

    // MARK: - Tryb 2: dyktowanie do pola

    /// Dyktowanie zapisuje tekst do wskazanego szkicu. **Nigdy** nie uruchamia toola (§5.1).
    /// Docelowy identyfikator szkicu jest zamrożony na czas nagrania.
    public func startDictation(
        target: DictationTarget,
        language: LanguageCode,
        service: DictationService
    ) async {
        // Tryb dyktowania wymaga oddania zasobu audio przez rozmowę, jeśli ta mówi.
        if state.mode == .conversation, state.turn == .speaking {
            await interrupt(InterruptionRequest(reason: .userRequested))
        }
        if state.connection == .connected {
            await setMicrophoneMuted(true)
        }
        var mutable = state
        _ = internalReducer.transition(to: .dictation, from: &mutable)
        mutable.mode = .dictation
        mutable.turn = .listening
        state = mutable

        dictationService = service
        dictationTask?.cancel()
        let stream = service.events()
        let frozenTarget = target
        dictationTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if Task.isCancelled { return }
                await MainActor.run { self.handle(dictation: event, frozenTarget: frozenTarget) }
            }
        }
        do {
            try await service.start(DictationRequest(target: target, language: language))
        } catch {
            handle(
                dictation: .failed(.recognizerUnavailable),
                frozenTarget: frozenTarget
            )
        }
    }

    /// Wynik dyktowania. Zdarzenie niesie **zamrożony** cel, więc zmiana wątku
    /// w trakcie nagrania nie przenosi tekstu do nowego odbiorcy (§12.2).
    public var onDictationResult: ((DictationTarget, String) -> Void)?
    public var onDictationFailure: ((DictationFailure) -> Void)?

    private func handle(dictation event: DictationEvent, frozenTarget: DictationTarget) {
        switch event {
        case .started:
            state.turn = .listening
        case .partialText(let text):
            state.partialTranscript = text
        case .finalText(let text):
            state.partialTranscript = ""
            state.turn = .waiting
            state.mode = .idle
            // Tekst trafia do pola. Nie wykonuje żadnego polecenia, nawet jeśli
            // brzmi jak „wyślij to jutro”.
            onDictationResult?(frozenTarget, text)
        case .failed(let failure):
            state.partialTranscript = ""
            state.turn = .waiting
            state.mode = .idle
            state.lastError = failure.safeMessage
            onDictationFailure?(failure)
        case .cancelled:
            state.partialTranscript = ""
            state.turn = .waiting
            state.mode = .idle
        }
    }

    public func finishDictation() async {
        await dictationService?.finish()
        dictationTask?.cancel()
        dictationTask = nil
        dictationService = nil
        state.mode = .idle
        state.partialTranscript = ""
    }

    public func cancelDictation() async {
        await dictationService?.cancel()
        dictationTask?.cancel()
        dictationTask = nil
        dictationService = nil
        state.mode = .idle
        state.partialTranscript = ""
    }

    // MARK: - Tryb 3: odsłuch

    /// Odsłuch **nie** otwiera mikrofonu i nie mutuje danych biznesowych (§5.1).
    /// W trakcie aktywnej sesji korzysta z jednego właściciela audio.
    public func startPlayback(
        _ request: SpeechPlaybackRequest,
        service: SpeechPlaybackService
    ) async {
        playbackService = service
        playbackTask?.cancel()
        let stream = service.events()
        playbackTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if Task.isCancelled { return }
                await MainActor.run { self.handle(playback: event) }
            }
        }
        var mutable = state
        if state.connection == .connected {
            // W aktywnej sesji odsłuch nie tworzy drugiego mikrofonu ani drugiego silnika audio.
            mutable.mode = .playback
        } else {
            _ = internalReducer.transition(to: .playback, from: &mutable)
        }
        state = mutable
        do {
            try await service.play(request)
        } catch {
            state.lastError = DomainError.transportFailure("odsłuch").safeMessage
        }
    }

    private func handle(playback event: PlaybackEvent) {
        switch event {
        case .started(_, let approximate):
            state.isPlaybackActive = true
            state.playbackIsApproximate = approximate
            state.turn = .speaking
        case .progress:
            break
        case .finished(let sourceID, let reason):
            state.isPlaybackActive = false
            if reason == .interrupted || reason == .routeChanged {
                state.turn = .interrupted
            } else {
                state.turn = .waiting
                state.mode = state.connection == .connected ? .conversation : .idle
            }
            // Koniec odsłuchu nie jest dowodem dostarczenia ani zgody na wysyłkę (§5.4).
            _ = sourceID
        case .failed(_, let reason):
            state.isPlaybackActive = false
            state.turn = .interrupted
            state.lastError = reason == .routeChanged
                ? "Odsłuch wstrzymany po zmianie trasy audio."
                : "Odsłuch się nie powiódł. Treść jest dostępna na ekranie."
        }
    }

    public func stopPlayback() async {
        await playbackService?.stop()
        playbackTask?.cancel()
        playbackTask = nil
        playbackService = nil
        state.isPlaybackActive = false
        if state.mode == .playback {
            state.mode = state.connection == .connected ? .conversation : .idle
        }
        state.turn = .waiting
    }

    // MARK: - Akcje (jeden silnik dla UI i głosu)

    /// Przygotowanie propozycji. UI i voice wywołują tę samą metodę (§8.1).
    @discardableResult
    public func prepareAction(
        kind: ActionKind,
        clientID: ClientID?,
        caseID: CaseID?,
        threadID: ThreadID?,
        text: String,
        actor: User,
        presentationID: String,
        taskOwnerID: UserID? = nil,
        taskDueDate: LocalDate? = nil
    ) async -> ActionProposal? {
        actionIDSequence += 1
        let actionID = ActionID("action-\(actionIDSequence)")
        let request = PrepareActionRequest(
            actionID: actionID,
            kind: kind,
            actorUserID: actor.id,
            sessionID: state.sessionID,
            clientID: clientID,
            caseID: caseID,
            threadID: threadID,
            text: text,
            contextVersion: state.contextVersion ?? .initial,
            threadVersion: sessionConfiguration?.context.threadVersion,
            presentationID: presentationID,
            now: clock.now(),
            taskOwnerID: taskOwnerID,
            taskDueDate: taskDueDate
        )
        // Auto-rewizja lokalna: nowa propozycja zastępuje poprzednią, nieaktywną.
        let local = actionEngine.prepare(request, into: &actionState)
        do {
            let remote = try await actionRepository.prepare(PrepareAction(request))
            actionState.proposals[remote.id] = remote
            var mutable = state
            internalReducer.apply(
                VoiceEvent(
                    eventID: "local-proposal-\(actionID)",
                    sessionID: state.sessionID ?? VoiceSessionID("local"),
                    connectionGeneration: state.connectionGeneration,
                    contextVersion: remote.contextVersion,
                    receivedAt: clock.now(),
                    source: .backendActionEngine,
                    payload: .proposalChanged(ProposalSnapshot(proposal: remote))
                ),
                to: &mutable
            )
            state = mutable
            return remote
        } catch {
            state.lastError = (error as? DomainError)?.safeMessage
                ?? DomainError.transportFailure("propozycja").safeMessage
            var mutable = state
            internalReducer.apply(
                VoiceEvent(
                    eventID: "local-proposal-\(actionID)",
                    sessionID: state.sessionID ?? VoiceSessionID("local"),
                    connectionGeneration: state.connectionGeneration,
                    receivedAt: clock.now(),
                    source: .backendActionEngine,
                    payload: .proposalChanged(ProposalSnapshot(proposal: local))
                ),
                to: &mutable
            )
            state = mutable
            return local
        }
    }

    /// Rewizja treści. Unieważnia wcześniejszą zgodę (§1.10).
    @discardableResult
    public func reviseAction(
        actionID: ActionID,
        newText: String
    ) async -> ActionProposal? {
        // Wersja oczekiwana to wersja, **z której** rewidujemy (blokada optymistyczna),
        // a nie wersja wynikowa.
        let baseVersion = actionState.proposals[actionID]?.version ?? .initial
        do {
            let revised = try actionEngine.revise(
                actionID: actionID,
                newText: newText,
                now: clock.now(),
                into: &actionState
            )
            let remote = try await actionRepository.revise(
                ReviseAction(
                    actionID: actionID,
                    expectedVersion: baseVersion,
                    newText: newText,
                    now: clock.now()
                )
            )
            actionState.proposals[remote.id] = remote
            var mutable = state
            internalReducer.apply(
                VoiceEvent(
                    eventID: "local-revision-\(remote.version.value)",
                    sessionID: state.sessionID ?? VoiceSessionID("local"),
                    connectionGeneration: state.connectionGeneration,
                    receivedAt: clock.now(),
                    source: .backendActionEngine,
                    payload: .proposalChanged(ProposalSnapshot(proposal: remote))
                ),
                to: &mutable
            )
            state = mutable
            return remote
        } catch {
            state.lastError = (error as? ActionEngineError)?.safeMessage
                ?? (error as? DomainError)?.safeMessage
                ?? DomainError.transportFailure("rewizja").safeMessage
            return nil
        }
    }

    /// Uzbrojenie potwierdzenia głosowego dla konkretnej prezentacji (§8.2).
    public func armVoiceConfirmation(actionID: ActionID, presentationID: String) -> Bool {
        do {
            try actionEngine.arm(
                actionID: actionID,
                presentationID: presentationID,
                into: &actionState
            )
            return true
        } catch {
            state.lastError = (error as? ActionEngineError)?.safeMessage
                ?? DomainError.validationFailed("Nie można uzbroić potwierdzenia.").safeMessage
            return false
        }
    }

    public func disarmVoiceConfirmation() {
        actionEngine.disarm(into: &actionState)
    }

    /// Potwierdzenie. Tworzy jedno wykonanie i unikalny wpis outboxa dla tej wersji (§8.1).
    @discardableResult
    public func confirmAction(
        actionID: ActionID,
        presentationID: String,
        origin: ActionEngine.Confirmation.Origin,
        actor: User
    ) async -> ActionExecution? {
        guard let proposal = actionState.proposals[actionID] else {
            state.lastError = ActionEngineError.proposalNotFound.safeMessage
            return nil
        }
        // Po odebraniu uprawnienia głos nie może wykonać zapisu. Zostaje przycisk w UI.
        if origin == .authenticatedVoiceTurn && voiceWritesRevoked {
            state.lastError = "Zapisy głosem są zablokowane. Zatwierdź przyciskiem na ekranie."
            return nil
        }
        let confirmation = ActionEngine.Confirmation(
            actionID: actionID,
            expectedVersion: proposal.version,
            presentationID: presentationID,
            origin: origin,
            now: clock.now()
        )
        do {
            let execution = try actionEngine.confirm(
                confirmation,
                outboxID: "outbox-\(actionID.rawValue)-\(proposal.version.value)",
                into: &actionState
            )
            let remote = try await actionRepository.confirm(
                ConfirmAction(
                    confirmation: confirmation,
                    idempotencyKey: "confirm-\(actionID.rawValue)-\(proposal.version.value)"
                )
            )
            actionState.executions[actionID] = remote
            var mutable = state
            internalReducer.apply(
                VoiceEvent(
                    eventID: "local-execution-\(actionID)",
                    sessionID: state.sessionID ?? VoiceSessionID("local"),
                    connectionGeneration: state.connectionGeneration,
                    receivedAt: clock.now(),
                    source: .backendActionEngine,
                    payload: .executionChanged(ExecutionSnapshot(execution: remote))
                ),
                to: &mutable
            )
            state = mutable
            return remote
        } catch {
            state.lastError = (error as? ActionEngineError)?.safeMessage
                ?? (error as? DomainError)?.safeMessage
                ?? DomainError.transportFailure("potwierdzenie").safeMessage
            return nil
        }
    }

    @discardableResult
    public func cancelAction(actionID: ActionID) async -> ActionProposal? {
        do {
            let cancelled = try actionEngine.cancel(
                actionID: actionID,
                now: clock.now(),
                into: &actionState
            )
            _ = try? await actionRepository.cancel(CancelAction(actionID: actionID, now: clock.now()))
            var mutable = state
            internalReducer.apply(
                VoiceEvent(
                    eventID: "local-cancel-\(actionID)",
                    sessionID: state.sessionID ?? VoiceSessionID("local"),
                    connectionGeneration: state.connectionGeneration,
                    receivedAt: clock.now(),
                    source: .backendActionEngine,
                    payload: .proposalChanged(ProposalSnapshot(proposal: cancelled))
                ),
                to: &mutable
            )
            state = mutable
            return cancelled
        } catch {
            state.lastError = (error as? ActionEngineError)?.safeMessage
                ?? DomainError.transportFailure("anulowanie").safeMessage
            return nil
        }
    }

    /// Odświeżenie stanu istniejącego wykonania, np. po reconnectcie.
    /// Nie tworzy nowego wykonania i nie ponawia polecenia (§5.6, §8.3).
    public func refreshExecutionState(actionID: ActionID) async {
        do {
            let execution = try await actionRepository.status(actionID: actionID)
            actionState.executions[actionID] = execution
            state.lastExecution = execution
            switch execution.state {
            case .accepted: state.action = .completed
            case .failed: state.action = .failed
            case .unknown: state.action = .needsReview
            default: state.action = .executing
            }
        } catch {
            state.lastError = (error as? DomainError)?.safeMessage
                ?? DomainError.transportFailure("status akcji").safeMessage
        }
    }

    public var currentProposal: ActionProposal? { state.activeProposal }
    public var currentExecution: ActionExecution? { state.lastExecution }

    // MARK: - Cykl życia aplikacji

    /// Odebranie uprawnienia do mikrofonu w Ustawieniach systemowych.
    public func handleMicrophonePermissionRevoked() async {
        state.lastError = FatalErrorKind.microphonePermissionDenied.safeMessage
        await end(reason: .userRequested, preserveDraft: true, revokedCapability: true)
    }

    /// Aplikacja w tle. Domyślnie kończy możliwość wykonywania zapisów głosem,
    /// zachowując szkic (§5.8). M2b rozszerza to zachowanie osobno.
    public func handleApplicationBackgrounded() async {
        guard state.connection == .connected else { return }
        state.lastError = "Rozmowa wstrzymana. Wróć do aplikacji."
        await end(reason: .applicationBackgrounded, preserveDraft: true, revokedCapability: true)
    }

    public func handleUserLoggedOut() async {
        await end(reason: .userLoggedOut, preserveDraft: false, revokedCapability: true)
        state = VoiceUIState()
        actionState = ActionEngine.State()
        voiceWritesRevoked = false
        eventLog.removeAll()
        rejections.removeAll()
    }

    public func handleAccountSwitched() async {
        await end(reason: .accountSwitched, preserveDraft: false, revokedCapability: true)
        state = VoiceUIState()
        actionState = ActionEngine.State()
    }

    public func handleSessionTakenOverByAnotherDevice() async {
        await end(reason: .takenOverByAnotherDevice, preserveDraft: true, revokedCapability: true)
    }

    // MARK: - Zakończenie

    /// „Zakończ”: odłącza transport, zwalnia mikrofon, zamyka strumienie
    /// i powiadamia backend (§5.6). Przy braku sieci lokalny koniec jest natychmiastowy.
    public func end(
        reason: VoiceEndReason,
        preserveDraft: Bool = true,
        revokedCapability: Bool = false
    ) async {
        transportTask?.cancel()
        transportTask = nil
        dictationTask?.cancel()
        dictationTask = nil
        playbackTask?.cancel()
        playbackTask = nil

        if let sessionID = state.sessionID {
            // Backend wygasza sesję także według lease/heartbeat; końcowy request
            // telefonu nie jest jedynym mechanizmem.
            try? await sessionRepository.end(sessionID: sessionID)
        }
        if let transport {
            await transport.disconnect(reason: reason)
        }
        self.transport = nil
        self.sessionConfiguration = nil
        self.dictationService = nil
        self.playbackService = nil
        self.startedAt = nil

        // Zgoda głosowa nie przeżywa końca sesji.
        actionState.armedPresentationID = nil
        if !preserveDraft {
            actionState = ActionEngine.State()
        }
        // Odebranie uprawnienia blokuje wyłącznie wykonanie **głosem**. Propozycja
        // pozostaje widoczna i zatwierdzalna przyciskiem na ekranie (§5.6, §8.2).
        voiceWritesRevoked = revokedCapability

        var finalState = state
        finalState.connection = .ended
        finalState.turn = .waiting
        finalState.microphone = .unavailable
        finalState.mode = .idle
        finalState.partialTranscript = ""
        finalState.isPlaybackActive = false
        finalState.sessionID = nil
        finalState.activeProposal = actionState.proposals.values.first { $0.state == .proposed }
        if finalState.activeProposal == nil { finalState.action = .none }
        lastEndReason = reason
        state = finalState
    }

    /// Samo opuszczenie widoku Emmy **nie** kończy sesji (§5.6).
    /// Ta metoda istnieje, aby ta reguła była jawna i testowalna.
    public func viewDidDisappear() {
        // Celowo puste: nawigacja nie kończy rozmowy.
        _ = idleTimeout
        _ = sessionLifetime
        _ = startedAt
    }

    // MARK: - Decyzje o ponowieniu

    /// Reconnect odtwarza bezpieczny kontekst i **nie** wysyła ponownie ostatniego polecenia.
    public func handleReconnected() async {
        actionEngine.disarm(into: &actionState)
        await refreshExecutionStatesForOpenActions()
    }

    private func refreshExecutionStatesForOpenActions() async {
        for actionID in actionState.executions.keys {
            await refreshExecutionState(actionID: actionID)
        }
    }
}
