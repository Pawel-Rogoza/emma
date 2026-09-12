import Foundation

// MARK: - Protokoły wewnętrznego API Emmy (§5.3)
//
// To projekt wewnętrznego kontraktu, nie cytat z SDK dostawcy. Właścicielem transportu
// i jego **jednego subskrybenta** jest `VoiceSessionCoordinator` (§5.3).

@MainActor
public protocol VoiceTransport: AnyObject {
    var capabilities: VoiceCapabilities { get }
    func connect(_ session: VoiceSessionConfiguration) async throws
    /// Jeden strumień zdarzeń na połączenie. Dwa widoki nie konkurują o ten sam strumień.
    func events() -> AsyncStream<VoiceEvent>
    func setMicrophoneMuted(_ muted: Bool) async throws
    func interrupt(_ request: InterruptionRequest) async throws
    func updateContext(_ context: AssistantContext) async throws
    func sendTextTurn(_ input: AssistantTextInput) async throws
    func disconnect(reason: VoiceEndReason) async
}

@MainActor
public protocol DictationService: AnyObject {
    func start(_ request: DictationRequest) async throws
    func events() -> AsyncStream<DictationEvent>
    func finish() async
    func cancel() async
}

@MainActor
public protocol SpeechPlaybackService: AnyObject {
    func play(_ request: SpeechPlaybackRequest) async throws
    func events() -> AsyncStream<PlaybackEvent>
    func stop() async
}

// MARK: - Repozytoria głosu i akcji

public protocol VoiceSessionRepository: Sendable {
    func create(_ request: CreateVoiceSession) async throws -> VoiceSessionConfiguration
    func updateContext(_ request: UpdateVoiceContext) async throws -> AssistantContext
    func fetchStatus(sessionID: VoiceSessionID) async throws -> VoiceSessionStatus
    func end(sessionID: VoiceSessionID) async throws
}

public protocol AssistantActionRepository: Sendable {
    func prepare(_ request: PrepareAction) async throws -> ActionProposal
    func revise(_ request: ReviseAction) async throws -> ActionProposal
    func confirm(_ request: ConfirmAction) async throws -> ActionExecution
    func cancel(_ request: CancelAction) async throws -> ActionExecution
    func status(actionID: ActionID) async throws -> ActionExecution
}

// MARK: - Repozytoria danych kancelarii
//
// UI nie czyta i nie zapisuje danych w niezależnych lokalnych tablicach (§8.1).
// Etap 03 wprowadza jeden `MockRepository` implementujący wszystkie te protokoły.

public protocol ClientRepository: Sendable {
    func clients(matching query: String, stage: ClientStage?) async throws -> [Client]
    func client(id: ClientID) async throws -> Client?
    func createClient(_ draft: NewClientDraft) async throws -> Client
    func updateClient(_ client: Client, expectedVersion: Version) async throws -> Client
}

public protocol CaseRepository: Sendable {
    func cases(status: CaseStatus?) async throws -> [LegalCase]
    func legalCase(id: CaseID) async throws -> LegalCase?
    func caseForClient(_ clientID: ClientID) async throws -> LegalCase?
    func createCase(_ draft: NewCaseDraft) async throws -> LegalCase
    func updateCase(_ legalCase: LegalCase, expectedVersion: Version) async throws -> LegalCase
}

public protocol TaskRepository: Sendable {
    func tasks(filter: TaskFilter) async throws -> [TaskItem]
    func createTask(_ draft: NewTaskDraft) async throws -> TaskItem
    func updateTask(_ task: TaskItem, expectedVersion: Version) async throws -> TaskItem
    func setDone(taskID: TaskID, isDone: Bool, expectedVersion: Version) async throws -> TaskItem
}

public protocol AgendaRepository: Sendable {
    func events(in range: DateIntervalFilter) async throws -> [ScheduledEvent]
    func event(id: EventID) async throws -> ScheduledEvent?
    func createEvent(_ draft: NewEventDraft) async throws -> ScheduledEvent
    func updateEvent(_ event: ScheduledEvent, expectedVersion: Version) async throws -> ScheduledEvent
    /// Usuwa termin. `expectedVersion` chroni przed usunięciem terminu, który
    /// w międzyczasie ktoś zmienił — tak samo jak przy edycji.
    func deleteEvent(id: EventID, expectedVersion: Version) async throws
}

public protocol NoteRepository: Sendable {
    func notes(clientID: ClientID, caseID: CaseID?) async throws -> [CaseNote]
    func addNote(_ draft: NewNoteDraft) async throws -> CaseNote
}

public protocol ActivityRepository: Sendable {
    func activity(caseID: CaseID) async throws -> [ActivityEvent]
    func activity(clientID: ClientID) async throws -> [ActivityEvent]
}

public protocol MessagingRepository: Sendable {
    func threads() async throws -> [ConversationThread]
    func thread(id: ThreadID) async throws -> ConversationThread?
    /// Paginacja starszej historii zachowuje kotwicę scrolla (§3.3 pkt 7).
    func messages(threadID: ThreadID, before sequence: Int?, limit: Int) async throws -> [Message]
    func latestMessages(threadID: ThreadID, limit: Int) async throws -> [Message]
    /// Zapis ręcznie zatwierdzonej treści z kluczem idempotencji (§7).
    func appendOutgoing(_ draft: OutgoingMessageDraft) async throws -> Message
    /// Zapisuje jawny kursor użytkownika; nie czyści wiadomości po kursorze (§3.3 pkt 1).
    func saveReadState(_ state: ThreadUserState) async throws -> ThreadUserState
    func readStates(userID: UserID) async throws -> [ThreadUserState]
    func saveThreadPreferences(_ state: ThreadUserState) async throws -> ThreadUserState
    func saveDraft(_ draft: Draft?) async throws
    /// Stosuje zdarzenie statusu od dostawcy; wyłącznie „poprawa” statusu (§9.2).
    func applyProviderStatus(
        providerMessageID: String,
        status: MessageTransport,
        at date: Date
    ) async throws -> Message?
}

public protocol UserRepository: Sendable {
    func currentUser() async throws -> User
    func updatePreferences(_ user: User) async throws -> User
}

// MARK: - Filtry i szkice zapisów

public struct TaskFilter: Hashable, Codable, Sendable {
    public enum Scope: String, Codable, Sendable, CaseIterable, Identifiable {
        case open = "Otwarte"
        case done = "Wykonane"
        case all = "Wszystkie"
        public var id: String { rawValue }
    }

    public var scope: Scope
    public var dueOnOrBefore: LocalDate?
    public var clientID: ClientID?
    public var caseID: CaseID?

    public init(
        scope: Scope = .open,
        dueOnOrBefore: LocalDate? = nil,
        clientID: ClientID? = nil,
        caseID: CaseID? = nil
    ) {
        self.scope = scope
        self.dueOnOrBefore = dueOnOrBefore
        self.clientID = clientID
        self.caseID = caseID
    }
}

/// Zakres daty włącznie. Bez godzin — to filtr planu, nie spotkanie.
public struct DateIntervalFilter: Hashable, Codable, Sendable {
    public var from: LocalDate
    public var through: LocalDate

    public init(from: LocalDate, through: LocalDate) {
        self.from = from
        self.through = through
    }

    public static func day(_ date: LocalDate) -> DateIntervalFilter {
        DateIntervalFilter(from: date, through: date)
    }

    public func contains(_ date: LocalDate) -> Bool {
        from <= date && date <= through
    }
}

public struct NewClientDraft: Hashable, Sendable {
    public var displayName: String
    public var topic: String
    public var language: LanguageCode
    public var context: String
    public var source: ClientSource
    public var createdAt: LocalDate

    public init(
        displayName: String,
        topic: String,
        language: LanguageCode,
        context: String,
        source: ClientSource = .manual,
        createdAt: LocalDate
    ) {
        self.displayName = displayName
        self.topic = topic
        self.language = language
        self.context = context
        self.source = source
        self.createdAt = createdAt
    }
}

public struct NewCaseDraft: Hashable, Sendable {
    public var clientID: ClientID
    public var title: String
    public var summary: String
    public var createdAt: LocalDate

    public init(clientID: ClientID, title: String, summary: String, createdAt: LocalDate) {
        self.clientID = clientID
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
    }
}

public struct NewTaskDraft: Hashable, Sendable {
    public var title: String
    public var clientID: ClientID?
    public var caseID: CaseID?
    public var dueDate: LocalDate
    public var priority: TaskPriority

    public init(
        title: String,
        clientID: ClientID?,
        caseID: CaseID?,
        dueDate: LocalDate,
        priority: TaskPriority = .normal
    ) {
        self.title = title
        self.clientID = clientID
        self.caseID = caseID
        self.dueDate = dueDate
        self.priority = priority
    }
}

public struct NewEventDraft: Hashable, Sendable {
    public var clientID: ClientID
    public var caseID: CaseID?
    public var title: String
    public var day: LocalDate
    public var time: TimeOfDay
    public var durationMinutes: Int
    public var kind: EventKind
    public var status: EventStatus
    public var place: String

    public init(
        clientID: ClientID,
        caseID: CaseID?,
        title: String,
        day: LocalDate,
        time: TimeOfDay,
        durationMinutes: Int,
        kind: EventKind,
        status: EventStatus,
        place: String
    ) {
        self.clientID = clientID
        self.caseID = caseID
        self.title = title
        self.day = day
        self.time = time
        self.durationMinutes = durationMinutes
        self.kind = kind
        self.status = status
        self.place = place
    }
}

public struct NewNoteDraft: Hashable, Sendable {
    public var clientID: ClientID
    public var caseID: CaseID?
    public var text: String
    public var authorID: UserID
    public var createdAt: LocalDate

    public init(clientID: ClientID, caseID: CaseID?, text: String, authorID: UserID, createdAt: LocalDate) {
        self.clientID = clientID
        self.caseID = caseID
        self.text = text
        self.authorID = authorID
        self.createdAt = createdAt
    }
}

public struct OutgoingMessageDraft: Hashable, Sendable {
    public var threadID: ThreadID
    public var text: String
    public var quote: QuotedReference?
    public var authorID: UserID
    public var language: LanguageCode
    public var sentAt: Date
    /// Klucz idempotencji dla tworzenia (§7).
    public var idempotencyKey: String
    public var source: MessageSource
    /// Akcja, z której powstała wiadomość (jeśli wysłano ją przez action engine).
    public var actionID: ActionID?

    public init(
        threadID: ThreadID,
        text: String,
        quote: QuotedReference? = nil,
        authorID: UserID,
        language: LanguageCode,
        sentAt: Date,
        idempotencyKey: String,
        source: MessageSource = .app,
        actionID: ActionID? = nil
    ) {
        self.threadID = threadID
        self.text = text
        self.quote = quote
        self.authorID = authorID
        self.language = language
        self.sentAt = sentAt
        self.idempotencyKey = idempotencyKey
        self.source = source
        self.actionID = actionID
    }
}

// MARK: - Błędy domenowe

public enum DomainError: Error, Equatable, Sendable {
    case notFound(resource: String, id: String)
    case versionConflict(expected: Version, current: Version)
    case unauthorized
    case forbidden
    case validationFailed(String)
    case offline
    case notConfigured(String)
    case transportFailure(String)
    case unknownOutcome(String)

    public var safeMessage: String {
        switch self {
        case .notFound: return "Nie znaleziono danych."
        case .versionConflict(let expected, let current):
            return "Ktoś zmienił ten element. Twoja wersja: \(expected), aktualna: \(current)."
        case .unauthorized: return "Sesja wygasła. Zaloguj się ponownie."
        case .forbidden: return "Brak uprawnień do tego elementu."
        case .validationFailed(let reason): return reason
        case .offline: return "Brak połączenia. Zmiany lokalne zostają zapisane."
        case .notConfigured(let what): return "Nie skonfigurowano: \(what)."
        case .transportFailure(let what): return "Błąd komunikacji: \(what)."
        case .unknownOutcome(let what): return "Nieznany wynik operacji: \(what). Bez automatycznego ponowienia."
        }
    }

    /// Czy ponowienie ma sens. Konflikty wersji i brak uprawnień — nie (§4.4, §7).
    public var isRetryable: Bool {
        switch self {
        case .offline, .transportFailure: return true
        default: return false
        }
    }
}
