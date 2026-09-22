import Foundation

// MARK: - Zredukowany stan do prezentacji
//
// Stan nie jest jednym przypadkowym booleanem (§5.5). UI wylicza spójny nagłówek
// z tych wymiarów.

public struct VoiceUIState: Hashable, Sendable {
    public var connection: ConnectionState
    public var turn: TurnState
    public var microphone: MicrophoneState
    public var action: ActionPresentationState
    public var route: AudioRoute
    public var lastInterruption: InterruptionReason?
    public var mode: VoiceMode
    public var partialTranscript: String
    public var committedUserTranscript: String
    public var agentText: String
    public var toolLabel: String?
    public var activeProposal: ActionProposal?
    public var lastExecution: ActionExecution?
    public var contextVersion: Version?
    public var lastError: String?
    /// Czy odtwarzanie jest raportowane dokładnie, czy przybliżone (§5.4).
    public var playbackIsApproximate: Bool
    public var isPlaybackActive: Bool
    /// Sesja połączona, ale mikrofon wyciszony — to nie jest rozłączenie.
    public var sessionID: VoiceSessionID?
    public var connectionGeneration: ConnectionGeneration
    /// Tożsamość tury, z której pochodzi `committedUserTranscript`.
    ///
    /// Historia rozmowy nie może dopisać tej samej wypowiedzi dwa razy tylko
    /// dlatego, że stan został opublikowany ponownie (F04). Zdarzenie ma
    /// `turnID`, a gdy go nie ma — `eventID`; to jest ten jeden klucz.
    public var committedUserTurnID: String?
    /// Tożsamość tury, z której pochodzi `agentText` (odpowiedź Emmy).
    public var agentTurnID: String?

    public init(
        connection: ConnectionState = .idle,
        turn: TurnState = .waiting,
        microphone: MicrophoneState = .unavailable,
        action: ActionPresentationState = .none,
        route: AudioRoute = .unknown,
        lastInterruption: InterruptionReason? = nil,
        mode: VoiceMode = .idle,
        partialTranscript: String = "",
        committedUserTranscript: String = "",
        agentText: String = "",
        toolLabel: String? = nil,
        activeProposal: ActionProposal? = nil,
        lastExecution: ActionExecution? = nil,
        contextVersion: Version? = nil,
        lastError: String? = nil,
        playbackIsApproximate: Bool = false,
        isPlaybackActive: Bool = false,
        sessionID: VoiceSessionID? = nil,
        connectionGeneration: ConnectionGeneration = ConnectionGeneration(0),
        committedUserTurnID: String? = nil,
        agentTurnID: String? = nil
    ) {
        self.connection = connection
        self.turn = turn
        self.microphone = microphone
        self.action = action
        self.route = route
        self.lastInterruption = lastInterruption
        self.mode = mode
        self.partialTranscript = partialTranscript
        self.committedUserTranscript = committedUserTranscript
        self.agentText = agentText
        self.toolLabel = toolLabel
        self.activeProposal = activeProposal
        self.lastExecution = lastExecution
        self.contextVersion = contextVersion
        self.lastError = lastError
        self.playbackIsApproximate = playbackIsApproximate
        self.isPlaybackActive = isPlaybackActive
        self.sessionID = sessionID
        self.connectionGeneration = connectionGeneration
        self.committedUserTurnID = committedUserTurnID
        self.agentTurnID = agentTurnID
    }

    /// Spójny nagłówek stanu. Kolejność ma znaczenie: wynik akcji i problemy przed stanem tury.
    public var statusHeadline: String {
        // Niepewny wynik wysyłki jest ważniejszy niż stan tury: Emma nie może
        // ogłosić „Wysłałam”, dopóki nie zna rzeczywistego stanu (§8.3).
        if action == .needsReview { return ExecutionState.unknown.displayName }
        if action == .failed { return ExecutionState.failed.displayName }
        if let lastError { return lastError }
        if connection == .failed { return "Rozmowa jest niedostępna. Możesz pisać tekstem." }
        if connection == .reconnecting { return "Odtwarzam połączenie…" }
        if connection == .requestingPermission { return "Uruchamiam mikrofon…" }
        if connection == .connecting { return "Łączę z Emmą…" }
        switch mode {
        case .dictation:
            switch turn {
            case .listening: return "Dyktuję do \(dictationLabel). Dotknij, aby zakończyć."
            case .thinking: return "Przetwarzam wypowiedź…"
            case .speaking: return "Emma mówi…"
            case .interrupted: return "Dyktowanie przerwane."
            case .waiting: return "Gotowe do dyktowania."
            }
        case .playback:
            return isPlaybackActive ? "Odsłuch trwa. Możesz go zatrzymać." : "Odsłuch zakończony."
        case .conversation:
            if microphone == .muted && turn != .speaking {
                return "Mikrofon wyciszony. Emma nadal słyszy tekst, który napiszesz."
            }
            switch turn {
            case .listening: return "Słucham Cię. Możesz przerwać i zabrać głos."
            case .thinking: return "Przygotowuję odpowiedź…"
            case .speaking: return "Emma mówi. Możesz przerwać i zabrać głos."
            case .interrupted: return "Przerwane. Możesz mówić dalej."
            case .waiting: return "Emma czeka na Twoją wypowiedź."
            }
        case .idle:
            return "Możesz mówić albo napisać polecenie."
        }
    }

    private var dictationLabel: String {
        switch mode {
        case .dictation: return "pola tekstowego"
        default: return "pola"
        }
    }

    /// Czy orb ma pulsować. Tylko w aktywnej pracy.
    public var orbIsActive: Bool {
        switch turn {
        case .listening, .thinking, .speaking: return connection == .connected
        case .waiting, .interrupted: return false
        }
    }

    public var canEndSession: Bool {
        sessionID != nil && connection != .ended && connection != .idle
    }

    /// Czy pokazać globalny mini-panel sterowania sesją (etap 4 audytu, F06).
    ///
    /// Panel stoi nad paskiem zakładek na każdej zakładce poza „Emma” i nad
    /// arkuszem modalnym, dopóki sesja istnieje — także gdy mikrofon jest
    /// wyciszony albo połączenie się odtwarza. Bez sesji i po jej zakończeniu
    /// nie ma czego sterować, więc panelu nie ma.
    public var showsGlobalVoicePanel: Bool { canEndSession }

    /// Krótki stan sesji jednym napisem, bez żargonu (etap 4 audytu, F07).
    ///
    /// Wcześniej dock mówił równocześnie „Rozmowa głosowa”, „Połączenie:
    /// Nieaktywna” i „Mikrofon niedostępny”. Kolejność ma znaczenie: problem
    /// połączenia → wyciszenie → tura. Bez sesji mówimy „Gotowa do rozmowy”.
    public var sessionHeadline: String {
        switch connection {
        case .requestingPermission: return "Uruchamiam mikrofon"
        case .connecting: return "Łączę z Emmą"
        case .reconnecting: return "Odtwarzam połączenie"
        case .failed: return "Rozmowa niedostępna"
        case .idle, .ended: return "Gotowa do rozmowy"
        case .connected: break
        }
        if microphone == .muted, turn != .speaking { return "Mikrofon wyciszony" }
        switch turn {
        case .listening: return "Słucham"
        case .thinking: return "Przygotowuję odpowiedź"
        case .speaking: return "Emma mówi"
        case .interrupted: return "Przerwane"
        case .waiting: return "Emma czeka"
        }
    }

    /// Czy przycisk mikrofonu w mini-panelu ma być zaznaczony (mikrofon aktywny).
    public var isCapturingMicrophone: Bool { microphone == .capturing }
}

/// Stan akcji w prezentacji (§5.5).
public enum ActionPresentationState: String, Codable, Sendable {
    case none
    case draft
    case awaitingConfirmation
    case executing
    case completed
    case needsReview
    case failed

    public var displayName: String {
        switch self {
        case .none: return "Brak działania"
        case .draft: return "Szkic działania"
        case .awaitingConfirmation: return "Czeka na potwierdzenie"
        case .executing: return "Wykonywanie"
        case .completed: return "Wykonano"
        case .needsReview: return "Wymaga sprawdzenia statusu"
        case .failed: return "Błąd wykonania"
        }
    }
}

// MARK: - Reduktor

/// Czysta funkcja redukująca zdarzenia do stanu. Bez efektów ubocznych,
/// w pełni testowalna także poza iOS.
public struct VoiceStateReducer: Sendable {

    public struct Rejection: Equatable, Sendable {
        public var eventID: String
        public var reason: Reason

        public enum Reason: String, Equatable, Sendable {
            /// Zdarzenie z innej lub starszej generacji połączenia.
            case staleGeneration
            /// Zdarzenie z zakończonej innej sesji.
            case foreignSession
            /// Zdarzenie dotyczy zakończonej tury, a tura już się zmieniła.
            case staleTurn
            /// Zdarzenie przyszło po zakończeniu sesji.
            case afterSessionEnded
        }
    }

    public init() {}

    /// Odrzucanie spóźnionych zdarzeń (§5.4). Callback starego połączenia nie może
    /// podszyć się pod aktualne.
    public func reject(
        _ event: VoiceEvent,
        state: VoiceUIState
    ) -> Rejection? {
        if let sessionID = state.sessionID, event.sessionID != sessionID {
            return Rejection(eventID: event.eventID, reason: .foreignSession)
        }
        // Zdarzenie zmiany połączenia musi przejść zawsze: domyka stan przy starcie
        // (idle → connecting) i przy zakończeniu (→ ended). Wyjątkiem jest zdarzenie
        // ze starszej generacji, które nie może nadpisać nowszego połączenia (§5.4).
        if case .connectionChanged = event.payload {
            return event.connectionGeneration < state.connectionGeneration
                ? Rejection(eventID: event.eventID, reason: .staleGeneration)
                : nil
        }
        if state.connection == .idle || state.connection == .ended {
            return Rejection(eventID: event.eventID, reason: .afterSessionEnded)
        }
        if event.connectionGeneration != state.connectionGeneration {
            return Rejection(eventID: event.eventID, reason: .staleGeneration)
        }
        return nil
    }

    /// Klucz tożsamości tury: `turnID`, a gdy zdarzenie go nie niesie — `eventID`.
    /// Dzięki temu powtórzona publikacja tego samego stanu nie dopisze drugiej tury.
    private static func turnKey(_ event: VoiceEvent) -> String {
        event.turnID ?? event.eventID
    }

    /// Czy zdarzenie oznacza powrót do stanu użytecznego i może wyczyścić komunikat błędu.
    private func clearsLastError(_ payload: VoiceEventPayload) -> Bool {
        switch payload {
        case .connectionChanged(let connection):
            return connection == .connected
        case .userSpeechStarted,
             .userTranscriptFinal,
             .agentTextDelta,
             .agentTextFinal,
             .playbackStarted,
             .toolProgress,
             .contextAccepted,
             .proposalChanged:
            return true
        default:
            return false
        }
    }

    /// Zastosowanie zdarzenia. Zwraca nowy stan oraz informację, czy zdarzenie zmieniło
    /// historię (finalna transkrypcja commituje się **raz**, §5.4).
    @discardableResult
    public func apply(
        _ event: VoiceEvent,
        to state: inout VoiceUIState
    ) -> Rejection? {
        if let rejection = reject(event, state: state) { return rejection }
        state.connectionGeneration = max(state.connectionGeneration, event.connectionGeneration)
        // Komunikat błędu znika tylko wtedy, gdy przychodzi zdarzenie oznaczające
        // powrót do zdrowia. Wcześniej zdarzenie `.connectionChanged(.failed)`
        // kasowało komunikat o odmowie dostępu do mikrofonu.
        if clearsLastError(event.payload) { state.lastError = nil }

        switch event.payload {
        case .connectionChanged(let connection):
            state.connection = connection
            if connection == .ended {
                state.turn = .waiting
                state.microphone = .unavailable
                state.mode = .idle
                state.partialTranscript = ""
                state.isPlaybackActive = false
                state.action = state.action == .completed ? .completed : .none
            }
            if connection == .connected, state.mode == .idle {
                state.mode = .conversation
            }

        case .microphoneChanged(let microphone):
            state.microphone = microphone

        case .audioRouteChanged(let route):
            state.route = route

        case .userSpeechStarted:
            // Nowa wypowiedź unieważnia poprzednią hipotezę częściową.
            state.partialTranscript = ""
            state.turn = .listening
            state.isPlaybackActive = false
            // Barge-in: wypowiedź użytkownika przerywa odtwarzanie.
            // Lokalne zatrzymanie audio wykonuje koordynator; tutaj tylko stan.

        case .userTranscriptPartial(let text):
            // Częściowa transkrypcja **zastępuje** poprzednią hipotezę tej samej tury.
            state.partialTranscript = text

        case .userTranscriptFinal(let text):
            state.partialTranscript = ""
            state.committedUserTranscript = text
            // Tożsamość tury dla historii: jedno zdarzenie = jedna tura (F04).
            state.committedUserTurnID = Self.turnKey(event)
            state.turn = .thinking

        case .agentTextDelta(let delta):
            state.agentText += delta
            state.agentTurnID = Self.turnKey(event)
            state.turn = .speaking

        case .agentTextFinal(let text):
            // `agentTextFinal` **nie** oznacza końca TTS (§5.4).
            state.agentText = text
            state.agentTurnID = Self.turnKey(event)
            if state.turn != .speaking { state.turn = .thinking }

        case .playbackStarted(let approximate):
            state.isPlaybackActive = true
            state.playbackIsApproximate = approximate
            state.turn = .speaking

        case .playbackStopped(let reason):
            state.isPlaybackActive = false
            if reason == .completed || reason == .sessionEnded {
                if state.turn == .speaking { state.turn = .waiting }
            }
            if reason == .routeChanged || reason == .failed {
                state.turn = .interrupted
            }

        case .toolProgress(let progress):
            state.toolLabel = progress.isFinished ? nil : progress.label

        case .proposalChanged(let snapshot):
            state.activeProposal = snapshot.proposal
            switch snapshot.proposal.state {
            case .proposed:
                state.action = snapshot.proposal.text.isEmpty ? .draft : .awaitingConfirmation
            case .confirmed:
                state.action = .executing
            case .rejected, .superseded, .expired:
                state.action = .none
            }

        case .executionChanged(let snapshot):
            state.lastExecution = snapshot.execution
            switch snapshot.execution.state {
            case .queued, .claimed, .dispatching:
                state.action = .executing
            case .accepted:
                state.action = .completed
            case .failed:
                state.action = .failed
            case .unknown:
                state.action = .needsReview
            }

        case .contextAccepted(let version):
            // Wersja kontekstu tylko rośnie (kontrakt backendu). Potwierdzenie
            // wcześniejszej zmiany, które dotarło po kolejnej, nie cofa wersji.
            state.contextVersion = max(state.contextVersion ?? version, version)

        case .interruption(let reason):
            state.lastInterruption = reason
            state.turn = .interrupted
            state.partialTranscript = ""
            state.isPlaybackActive = false
            state.toolLabel = nil
            // Rozbrojenie prezentacji akcji: przerwanie odczytu unieważnia zgodę (§8.2).
            if let proposal = state.activeProposal, proposal.state == .proposed {
                state.activeProposal = proposal
                state.action = proposal.text.isEmpty ? .draft : .awaitingConfirmation
            }

        case .recoverableError(let kind):
            state.lastError = kind.safeMessage
            if kind == .networkLost { state.connection = .reconnecting }
            if kind == .audioRouteLost { state.turn = .interrupted }

        case .fatalError(let kind):
            state.lastError = kind.safeMessage
            state.connection = .failed
            state.turn = .waiting
            state.partialTranscript = ""
            state.isPlaybackActive = false
            // Odebranie uprawnienia, wylogowanie i przejęcie sesji kończą
            // możliwość wykonania narzędzi (§5.6).
            switch kind {
            case .microphonePermissionDenied, .microphoneUnavailable, .speechRecognitionPermissionDenied:
                state.microphone = .unavailable
            case .authenticationFailed, .sessionRevoked:
                state.sessionID = nil
                state.mode = .idle
            default:
                break
            }
        }
        return nil
    }

    /// Zamiana trybu. Tryby dzielą jeden zasób audio, więc wejście w tryb
    /// używający mikrofonu wymaga oddania zasobu przez inny tryb.
    public func transition(
        to mode: VoiceMode,
        from state: inout VoiceUIState
    ) -> Bool {
        if state.mode == mode { return true }
        if mode.usesMicrophone && state.mode == .playback {
            // Rozmowa/dyktowanie przejmuje zasób; odsłuch musi się zatrzymać.
            state.isPlaybackActive = false
        }
        if mode == .playback && state.mode.usesMicrophone && state.connection == .connected {
            // Odsłuch w aktywnej sesji nie otwiera osobnego mikrofonu.
            // Zezwalamy, ale tylko gdy mikrofon jest wyciszony albo sesja nie mówi.
            if state.turn == .speaking { return false }
        }
        state.mode = mode
        state.turn = .waiting
        state.partialTranscript = ""
        if mode != .playback { state.isPlaybackActive = false }
        return true
    }
}
