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
    /// Co ile sprawdzamy limity czasu, gdy sesja jest aktywna.
    /// Wartość wstrzykiwalna, żeby test mógł sprawdzić **działanie stróża**,
    /// a nie tylko samej metody.
    private let limitCheckInterval: TimeInterval
    private let sessionStatus: (@MainActor (VoiceSessionID) async -> VoiceSessionStatus?)?
    /// Zgoda na mikrofon pytana **przed** założeniem sesji. Warstwa logiki nie zna
    /// `AVFoundation`, więc dostęp do mikrofonu dostaje jako port. `nil` oznacza
    /// brak sprawdzania (Demo, testy, podglądy) — tam mikrofonu nie ma w ogóle.
    ///
    /// To nie jest kosmetyka: SDK dostawcy przy odmowie łączy sesję **bez toru
    /// mikrofonu** i nie zgłasza tego błędem (patrz `WebRTCConnectionManager`
    /// w SDK: `enableMic: permissionGranted`). Skutek to rozmowa, w której
    /// użytkownik mówi w pustkę. Dlatego odmowa kończy start głośno, zanim
    /// powstanie sesja u dostawcy i na backendzie.
    private let microphonePermission: (any MicrophonePermissionProviding)?

    // MARK: Zasoby wewnętrzne

    private var transport: VoiceTransport?
    private var transportTask: Task<Void, Never>?
    private var dictationService: DictationService?
    private var dictationTask: Task<Void, Never>?
    private var playbackService: SpeechPlaybackService?
    private var playbackTask: Task<Void, Never>?

    private var sessionConfiguration: VoiceSessionConfiguration?
    private var actionState = ActionEngine.State()
    private var observers: [UUID: @MainActor (VoiceUIState) -> Void] = [:]
    private var internalReducer = VoiceStateReducer()
    private var eventLog: [VoiceEvent] = []
    private var rejections: [VoiceStateReducer.Rejection] = []
    private var actionIDSequence = 0
    private var startedAt: Date?
    /// Znacznik ostatniej czynności w sesji — podstawa limitu bezczynności.
    /// Bezczynność to brak ruchu w obie strony, nie brak odtwarzania.
    private var lastActivityAt: Date?
    /// Identyfikator bieżącego żądania odsłuchu. Zdarzenia innego żądania są
    /// odrzucane: odsłuch ma jednego właściciela, a spóźnione zdarzenie starego
    /// żądania nie może zmienić stanu sesji (§5.4).
    private var activePlaybackSourceID: String?
    /// Stróż limitów czasu. Żyje tak długo, jak sesja — należy do właściciela sesji,
    /// bo opuszczenie ekranu Emmy **nie** kończy rozmowy (§5.6).
    private var limitsTask: Task<Void, Never>?

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
        sessionLifetime: TimeInterval = 30 * 60,
        limitCheckInterval: TimeInterval = 15,
        /// Sposób zapytania backendu o stan sesji. `nil` oznacza tryb bez backendu
        /// (np. testy i Demo), w którym nie ma czego uzgadniać.
        sessionStatus: (@MainActor (VoiceSessionID) async -> VoiceSessionStatus?)? = nil,
        /// Zgoda na mikrofon. `nil` = nie pytamy (Demo, testy, podglądy).
        microphonePermission: (any MicrophonePermissionProviding)? = nil
    ) {
        self.sessionRepository = sessionRepository
        self.actionRepository = actionRepository
        self.actionEngine = actionEngine
        self.clock = clock
        self.idleTimeout = idleTimeout
        self.sessionLifetime = sessionLifetime
        self.limitCheckInterval = limitCheckInterval
        self.sessionStatus = sessionStatus
        self.microphonePermission = microphonePermission
        self.state = VoiceUIState()
    }

    // MARK: Obserwacja stanu

    /// Obserwator stanu. Izolacja jest jawna: koordynator żyje na głównym aktorze
    /// i tylko stamtąd woła obserwatorów, więc rejestrujący nie musi owijać
    /// swoich zamknięć w `MainActor.assumeIsolated`.
    public func addObserver(_ observer: @escaping @MainActor (VoiceUIState) -> Void) -> UUID {
        let token = UUID()
        observers[token] = observer
        observer(state)
        return token
    }

    public func removeObserver(_ token: UUID) {
        observers.removeValue(forKey: token)
    }

    // `stateStream()` usunięty: był drugim sposobem obserwacji stanu obok
    // `addObserver`, a nikt go nie wołał. Dwa sposoby na to samo to zaproszenie,
    // żeby jedna ścieżka zaczęła się rozjeżdżać z drugą.

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
        // Start już trwa (zgoda na mikrofon albo zakładanie sesji na backendzie).
        // Bez tej bramki szybkie podwójne dotknięcie zakładało dwie sesje, a
        // transport pierwszej zostawał osierocony — z otwartym mikrofonem.
        guard state.connection != .requestingPermission else { return }
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
        // Zgoda na mikrofon przed założeniem sesji. Bez niej SDK i tak połączy
        // rozmowę, ale bez wejścia audio — użytkownik mówi w pustkę, a UI
        // pokazuje „połączono”. Pytamy więc tutaj i przy odmowie nie tworzymy
        // ani sesji u dostawcy, ani po stronie backendu.
        if let microphonePermission, await microphonePermission.requestRecordPermission() == false {
            state.connection = .failed
            state.turn = .waiting
            state.mode = .idle
            state.microphone = .unavailable
            state.lastError = FatalErrorKind.microphonePermissionDenied.safeMessage
            return
        }
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
            startedAt = clock.now()
            lastActivityAt = startedAt
            // Stróż limitów działa też na ścieżce produkcyjnej. Bez tego limity
            // czasu i uzgodnienie statusu z backendem działałyby wyłącznie dla
            // transportu wstrzykniętego przez `attach` (podglądy i testy).
            startLimitWatchdog()
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
            // Nieudany start sprzątamy do końca: transport mógł już przejąć
            // sesję audio i otworzyć gniazdo, a backend ma założoną sesję.
            // Wcześniej zostawały one aktywne aż do wygaśnięcia dzierżawy.
            let failedTransport = transport
            let failedSessionID = sessionConfiguration?.sessionID
            transport = nil
            sessionConfiguration = nil
            startedAt = nil
            lastActivityAt = nil
            limitsTask?.cancel()
            limitsTask = nil
            state.connection = .failed
            state.turn = .waiting
            state.mode = .idle
            state.sessionID = nil
            state.lastError = message
            if let failedTransport {
                await failedTransport.disconnect(reason: .providerError)
            }
            if let failedSessionID {
                await Self.endRemoteSession(
                    sessionID: failedSessionID,
                    repository: sessionRepository,
                    timeout: 3
                )
            }
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
        lastActivityAt = startedAt
        startLimitWatchdog()
        lastActivityAt = startedAt
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

    /// Zdarzenia, które liczą się jako czynność w sesji. Świadomie **nie** ma tu
    /// odtwarzania: mówienie Emmy bez udziału użytkownika nie jest jego aktywnością.
    private static func isActivity(_ payload: VoiceEventPayload) -> Bool {
        switch payload {
        case .userSpeechStarted, .userTranscriptPartial, .userTranscriptFinal,
             .agentTextDelta, .agentTextFinal,
             .proposalChanged, .executionChanged, .contextAccepted:
            return true
        default:
            return false
        }
    }

    /// Przyjęcie pojedynczego zdarzenia z transportu. Ścieżka używana przez adapter
    /// dostawcy oraz przez testy. Spóźnione zdarzenia są odrzucane i zapisywane.
    public func ingest(_ event: VoiceEvent) {
        if Self.isActivity(event.payload) {
            lastActivityAt = event.receivedAt
        }
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
        lastActivityAt = clock.now()
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
            // Wersja potwierdzona przez backend musi trafić do stanu: bez tego
            // każda kolejna zmiana kontekstu wysyłała tę samą wersję (a więc ten
            // sam klucz idempotencji) i kończyła się konfliktem albo powtórką.
            let confirmed = try await sessionRepository.updateContext(
                UpdateVoiceContext(sessionID: sessionID, context: context, expectedContextVersion: expected)
            )
            if state.sessionID == sessionID {
                state.contextVersion = confirmed.version
            }
            try await transport.updateContext(confirmed)
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
            // Nie zgadujemy przyczyny: adapter mówi, czy to brak zgody, brak
            // rozpoznawania, czy niewydana sesja audio. Wcześniej każdy błąd
            // pokazywał się jako „rozpoznawanie niedostępne", czyli kłamał.
            let failure = (error as? any DictationStartFailureMapping)?.dictationFailure ?? .unknown
            handle(
                dictation: .failed(failure),
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
        // Wynik końcowy mógł właśnie trafić do strumienia — chwila na jego odbiór,
        // zanim odetniemy odbiorcę. Wcześniej „Zakończ dyktowanie” gubiło tekst.
        try? await Task.sleep(nanoseconds: 150_000_000)
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
        // Nowe żądanie unieważnia poprzednie — także wtedy, gdy poprzednie
        // jeszcze nie zakończyło odtwarzania.
        activePlaybackSourceID = request.sourceID
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

    /// Czy zdarzenie dotyczy bieżącego żądania odsłuchu.
    /// Spóźnione zdarzenie poprzedniego żądania nie zmienia stanu sesji.
    private func isCurrentPlayback(_ sourceID: String) -> Bool {
        activePlaybackSourceID == sourceID
    }

    private func handle(playback event: PlaybackEvent) {
        switch event {
        case .started(let sourceID, let approximate):
            guard isCurrentPlayback(sourceID) else { return }
            state.isPlaybackActive = true
            state.playbackIsApproximate = approximate
            state.turn = .speaking
        case .progress(let sourceID):
            guard isCurrentPlayback(sourceID) else { return }
        case .finished(let sourceID, let reason):
            // Koniec odsłuchu **nie** jest dowodem dostarczenia ani zgodą na wysyłkę (§5.4).
            guard isCurrentPlayback(sourceID) else { return }
            activePlaybackSourceID = nil
            state.isPlaybackActive = false
            if reason == .interrupted || reason == .routeChanged {
                state.turn = .interrupted
            } else {
                state.turn = .waiting
                state.mode = state.connection == .connected ? .conversation : .idle
            }
        case .failed(let sourceID, let reason):
            guard isCurrentPlayback(sourceID) else { return }
            activePlaybackSourceID = nil
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
            taskDueDate: taskDueDate
        )
        // Auto-rewizja lokalna: nowa propozycja zastępuje poprzednią, nieaktywną.
        _ = actionEngine.prepare(request, into: &actionState)
        do {
            let remote = try await actionRepository.prepare(PrepareAction(request))
            // Backend nadaje własny identyfikator i identyfikator prezentacji.
            // Lokalna kopia pod tymczasowym ID zostałaby „wiszącą” propozycją,
            // której nie da się potwierdzić — zostaje tylko wersja z backendu.
            if remote.id != actionID {
                actionState.proposals.removeValue(forKey: actionID)
            }
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
            // Propozycja, której backend nie przyjął, nie może wyglądać na
            // gotową do zatwierdzenia: „Zatwierdź” skończyłby się 404, bo
            // backend jej nie zna. Pokazujemy powód (np. „zadanie musi wskazywać
            // sprawę”) i nie publikujemy karty.
            actionState.proposals.removeValue(forKey: actionID)
            state.lastError = (error as? DomainError)?.safeMessage
                ?? (error as? BackendRepositoryError)?.safeMessage
                ?? DomainError.transportFailure("propozycja").safeMessage
            return nil
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
            // Nowa propozycja trafia do `actionState`; do stanu ekranu idzie wersja
            // z backendu (`remote`) — lokalna kopia nie jest potrzebna.
            _ = try actionEngine.revise(
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

    /// Korekta terminu zadania („nie, na poniedziałek”, §6-C). Termin jest
    /// osobnym polem propozycji, więc idzie własną drogą, a nie przez treść.
    @discardableResult
    public func rescheduleAction(actionID: ActionID, dueDate: LocalDate?) async -> ActionProposal? {
        let baseVersion = actionState.proposals[actionID]?.version ?? .initial
        do {
            let remote = try await actionRepository.reschedule(
                RescheduleAction(
                    actionID: actionID,
                    expectedVersion: baseVersion,
                    dueDate: dueDate,
                    now: clock.now()
                )
            )
            actionState.proposals[remote.id] = remote
            publishProposalChange(remote)
            return remote
        } catch {
            recordActionFailure(error, fallback: "termin")
            return nil
        }
    }

    /// Korekta odbiorcy albo kontekstu (F14). Zmiana odbiorcy unieważnia zgodę,
    /// bo dotyczyła innej osoby — pilnuje tego silnik akcji.
    @discardableResult
    public func changeActionContext(
        actionID: ActionID,
        clientID: ClientID?,
        caseID: CaseID?,
        threadID: ThreadID?
    ) async -> ActionProposal? {
        let baseVersion = actionState.proposals[actionID]?.version ?? .initial
        do {
            let remote = try await actionRepository.changeContext(
                ChangeActionContext(
                    actionID: actionID,
                    expectedVersion: baseVersion,
                    clientID: clientID,
                    caseID: caseID,
                    threadID: threadID,
                    now: clock.now()
                )
            )
            actionState.proposals[remote.id] = remote
            publishProposalChange(remote)
            return remote
        } catch {
            recordActionFailure(error, fallback: "odbiorca")
            return nil
        }
    }

    /// Publikacja zmienionej propozycji do stanu ekranu. Jedno miejsce, żeby
    /// każda korekta (treść, termin, odbiorca) kończyła się tym samym zdarzeniem.
    private func publishProposalChange(_ proposal: ActionProposal) {
        var mutable = state
        internalReducer.apply(
            VoiceEvent(
                eventID: "local-proposal-\(proposal.id.rawValue)-\(proposal.version.value)",
                sessionID: state.sessionID ?? VoiceSessionID("local"),
                connectionGeneration: state.connectionGeneration,
                receivedAt: clock.now(),
                source: .backendActionEngine,
                payload: .proposalChanged(ProposalSnapshot(proposal: proposal))
            ),
            to: &mutable
        )
        state = mutable
    }

    private func recordActionFailure(_ error: Error, fallback: String) {
        state.lastError = (error as? ActionEngineError)?.safeMessage
            ?? (error as? DomainError)?.safeMessage
            ?? DomainError.transportFailure(fallback).safeMessage
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
            // Wynik lokalny jest tylko przygotowaniem outboxa; stanem rozstrzygającym
            // jest odpowiedź backendu, dlatego nie przypisujemy go do zmiennej.
            _ = try actionEngine.confirm(
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
        // Liczy się samo istnienie sesji, nie stan połączenia: sesja założona
        // u dostawcy (albo jeszcze w trakcie łączenia) też musi zostać zamknięta,
        // inaczej zostaje po stronie backendu jako `active`.
        guard state.sessionID != nil else { return }
        state.lastError = "Rozmowa wstrzymana. Wróć do aplikacji."
        await end(reason: .applicationBackgrounded, preserveDraft: true, revokedCapability: true)
    }

    /// Powrót aplikacji na pierwszy plan. Sesja mogła zostać przejęta przez inne
    /// urządzenie albo zamknięta po stronie backendu, a my wciąż mamy połączenie.
    /// Pytamy więc o faktyczny stan (`GET /voice/sessions/{id}/status`), zamiast
    /// zgadywać go z zegara (§5.6). Zwykle to no-op: przejście w tło kończy u nas
    /// sesję, ale ma znaczenie, gdy tło zostało pominięte (np. przerwanie systemowe).
    public func handleApplicationForegrounded() async {
        guard state.sessionID != nil else { return }
        _ = await reconcileSessionWithBackend()
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

    /// Odrzucenie szkicu i propozycji poprzedniej sesji.
    ///
    /// „Rozmawiaj” otwiera **nową** rozmowę, więc nie może wskrzeszać cudzej
    /// propozycji: `end` domyślnie zachowuje szkic (§5.6) i przy zakończeniu
    /// publikuje ostatnią propozycję, co po czyszczeniu prezentacji wróciłoby
    /// do historii. To jedyne miejsce, które kasuje zachowany stan bez kończenia
    /// sesji — celowo osobne od `handleUserLoggedOut`, które zeruje całość.
    public func discardPreservedPresentation() {
        actionState = ActionEngine.State()
        var mutable = state
        mutable.activeProposal = nil
        mutable.lastExecution = nil
        mutable.action = .none
        state = mutable
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

        // Zasoby sesji odpinamy synchronicznie, **przed** pierwszym `await`.
        // Koordynator żyje na głównym aktorze, ale `await` wpuszcza inne
        // wywołania: nowa rozmowa rozpoczęta w trakcie zamykania nie może
        // zostać rozłączona przez spóźnione sprzątanie poprzedniej.
        let endingSessionID = state.sessionID
        let endingTransport = transport
        self.transport = nil
        self.sessionConfiguration = nil
        self.dictationService = nil
        self.playbackService = nil
        self.startedAt = nil
        self.lastActivityAt = nil
        self.activePlaybackSourceID = nil
        limitsTask?.cancel()
        limitsTask = nil

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
        // Powód zakończenia musi być widoczny: „Zakończona” bez wyjaśnienia wygląda
        // jak awaria, a to była reguła.
        if reason == .idleTimeout || reason == .sessionExpired {
            finalState.lastError = reason.displayName
        }
        state = finalState

        // Najpierw lokalne rozłączenie (mikrofon, gniazdo), dopiero potem
        // backend. Wcześniej kolejność była odwrotna i po „Zakończ” mikrofon
        // wysyłał dźwięk do dostawcy jeszcze przez czas `DELETE` (do 3 s bez
        // sieci) — wbrew zasadzie, że lokalny koniec nie zależy od sieci.
        if let endingTransport {
            await endingTransport.disconnect(reason: reason)
        }
        if let endingSessionID {
            // Backend wygasza sesję także według lease/heartbeat; końcowy request
            // telefonu nie jest jedynym mechanizmem. Czekamy na `DELETE` **ze
            // stałym limitem**: bez sieci `URLSession` trzymałby „Zakończ" przez
            // pełny timeout, a przejście w tło i tak zawiesiłoby proces przed
            // wysłaniem żądania.
            await Self.endRemoteSession(
                sessionID: endingSessionID,
                repository: sessionRepository,
                timeout: 3
            )
        }
    }

    /// Samo opuszczenie widoku Emmy **nie** kończy sesji (§5.6).
    /// Metoda jest celowo pusta: nawigacja nie kończy rozmowy, a sesja żyje dalej,
    /// dopóki nie skończy jej użytkownik albo nie zadziałają limity czasu
    /// (`enforceSessionLimits()`).
    public func viewDidDisappear() {}

    // MARK: - Trasa audio i przerwania systemowe

    /// Reakcja na zmianę trasy audio (§13).
    ///
    /// Reguła: treść poufna nie może nagle zagrać z głośnika. Decyzję podejmuje
    /// `AudioRoutePolicy` — czysta logika z własnymi testami — a to miejsce nadaje
    /// jej skutek. Bez tego wywołania polityka trasy była kodem bez zastosowania.
    public func handleAudioRouteChange(to current: AudioRoute) async {
        let previous = state.route
        state.route = current

        let decision = AudioRoutePolicy.decision(
            previous: previous,
            current: current,
            isSensitivePlaybackActive: state.isPlaybackActive || state.mode == .playback
        )
        guard decision == .pausePlaybackAndAsk else { return }

        // Zatrzymanie jest natychmiastowe i lokalne: nie czekamy na dostawcę.
        await playbackService?.stop()
        state.isPlaybackActive = false
        state.turn = .waiting
        state.lastError = "Odsłuch wstrzymany: zmieniła się trasa audio. Wznów świadomie."
    }

    /// Przerwanie zgłoszone przez system audio (telefon, inna aplikacja).
    public func handleSystemAudioInterruption(_ reason: InterruptionReason) async {
        await interrupt(InterruptionRequest(reason: reason))
    }

    // MARK: - Limity czasu sesji

    /// Uruchomienie stróża limitów. Jedno zadanie na sesję; poprzednie jest anulowane.
    private func startLimitWatchdog() {
        limitsTask?.cancel()
        limitsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.limitCheckInterval else { return }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                if await self.enforceSessionLimits() != nil { continue }
                _ = await self.reconcileSessionWithBackend()
            }
        }
    }

    /// Egzekwowanie limitów czasu sesji (§5.6).
    ///
    /// Limity były dotąd wyłącznie skonfigurowane — nikt ich nie sprawdzał, więc
    /// dwudziestominutowa rozmowa „na wieki” i sesja bez czynności trwały dowolnie
    /// długo. Ta metoda zamienia konfigurację w regułę.
    ///
    /// Wywołanie należy do interfejsu (cykliczny zegar) albo do testów; brak
    /// własnego zegara w koordynatorze jest świadomy: jedno miejsce decyduje o czasie.
    ///
    /// - Returns: powód zakończenia, jeśli sesja została zakończona; inaczej `nil`.
    @discardableResult
    public func enforceSessionLimits() async -> VoiceEndReason? {
        guard state.connection == .connected || state.connection == .connecting else { return nil }
        let now = clock.now()

        if let startedAt, now.timeIntervalSince(startedAt) >= sessionLifetime {
            await end(reason: .sessionExpired)
            return .sessionExpired
        }

        if let reference = lastActivityAt ?? startedAt, now.timeIntervalSince(reference) >= idleTimeout {
            await end(reason: .idleTimeout)
            return .idleTimeout
        }

        return nil
    }

    /// Uzgodnienie stanu sesji z backendem (§5.6, plan linia 342).
    ///
    /// Metoda `handleSessionTakenOverByAnotherDevice()` istniała, ale **nikt jej nie wołał**,
    /// więc przejęcie sesji przez inne urządzenie nie kończyło u nas uprawnienia do zapisu.
    /// Backend wie o przejęciu pierwszy: raportuje sesję jako nieaktywną, choć my wciąż
    /// trzymamy połączenie. Wtedy kończymy lokalnie z powodem „przejęta przez inne
    /// urządzenie” i odbieramy prawo zapisu głosem, zachowując szkic.
    ///
    /// - Returns: powód zakończenia, jeśli sesja została zakończona z powodu backendu.
    @discardableResult
    public func reconcileSessionWithBackend() async -> VoiceEndReason? {
        guard let sessionStatus, let sessionID = state.sessionID else { return nil }
        guard state.connection == .connected || state.connection == .connecting else { return nil }
        guard let status = await sessionStatus(sessionID) else { return nil }
        // Aktywna sesja na backendzie niczego nie zmienia — to stan oczekiwany.
        guard status.isActive == false else { return nil }
        await handleSessionTakenOverByAnotherDevice()
        return .takenOverByAnotherDevice
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

    /// Zamknięcie sesji po stronie backendu z ograniczeniem czasu.
    ///
    /// `sessionRepository.end` to żądanie sieciowe; bez tego limitu pojedynczy
    /// brak sieci blokowałby zakończenie rozmowy na cały timeout klienta.
    /// Lokalny stan i tak jest już rozłączony — wysyłka jest najlepszą próbą.
    private static func endRemoteSession(
        sessionID: VoiceSessionID,
        repository: VoiceSessionRepository,
        timeout: TimeInterval
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await repository.end(sessionID: sessionID) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            }
            await group.next()
            group.cancelAll()
        }
    }
}
