import Foundation

// MARK: - Użytkownik

public struct User: Identifiable, Hashable, Codable, Sendable {
    public let id: UserID
    public var displayName: String
    public var initials: String
    /// Język interfejsu adwokata. **Nie** jest to język klienta (§4.3).
    public var interfaceLanguage: LanguageCode
    /// Język rozmowy z Emmą. Domyślnie rosyjski zgodnie z wcześniejszym planem (§5.1),
    /// ze zmianą na PL i zapisem per użytkownik.
    public var assistantLanguage: LanguageCode

    public init(
        id: UserID,
        displayName: String,
        initials: String,
        interfaceLanguage: LanguageCode = .pl,
        assistantLanguage: LanguageCode = .ru
    ) {
        self.id = id
        self.displayName = displayName
        self.initials = initials
        self.interfaceLanguage = interfaceLanguage
        self.assistantLanguage = assistantLanguage
    }

    /// Imię w wołaczu użyte w powitaniu („Dzień dobry, Tomaszu”).
    public var greetingName: String {
        switch id {
        case .tomasz: return "Tomaszu"
        case .pawel: return "Pawle"
        default: return displayName
        }
    }
}

// MARK: - Klient

/// Etap kontaktu. „Leady” to osoby, które nie są jeszcze klientami.
public enum ClientStage: String, Codable, Sendable, CaseIterable, Identifiable {
    case new = "Nowy"
    case inContact = "W kontakcie"
    case client = "Klient"

    public var id: String { rawValue }
    public var displayName: String { rawValue }
}

public enum ClientSource: String, Codable, Sendable {
    case webForm = "Formularz WWW"
    case referral = "Polecenie"
    case manual = "Dodano ręcznie"
    case whatsApp = "WhatsApp"
}

public struct Client: Identifiable, Hashable, Codable, Sendable {
    public let id: ClientID
    public var displayName: String
    public var initials: String
    /// Język klienta. Nie mylić z językiem interfejsu adwokata.
    public var language: LanguageCode
    public var topic: String
    public var stage: ClientStage
    /// `nil` oznacza „Nieprzypisany”. Nie używamy magicznego użytkownika.
    public var ownerID: UserID?
    public var source: ClientSource
    public var createdAt: LocalDate
    public var briefing: String
    public var incomingMessage: String?
    public var incomingTranslation: String?
    public var incomingTime: TimeOfDay?
    /// `needsReply` to stan pracy backendu/briefingu, **nie** etykieta na liście rozmów (§3.3 pkt 4).
    public var needsReply: Bool
    public var version: Version

    public init(
        id: ClientID,
        displayName: String,
        initials: String,
        language: LanguageCode,
        topic: String,
        stage: ClientStage,
        ownerID: UserID?,
        source: ClientSource,
        createdAt: LocalDate,
        briefing: String,
        incomingMessage: String? = nil,
        incomingTranslation: String? = nil,
        incomingTime: TimeOfDay? = nil,
        needsReply: Bool = false,
        version: Version = .initial
    ) {
        self.id = id
        self.displayName = displayName
        self.initials = initials
        self.language = language
        self.topic = topic
        self.stage = stage
        self.ownerID = ownerID
        self.source = source
        self.createdAt = createdAt
        self.briefing = briefing
        self.incomingMessage = incomingMessage
        self.incomingTranslation = incomingTranslation
        self.incomingTime = incomingTime
        self.needsReply = needsReply
        self.version = version
    }

    public var ownerLabel: String { ownerID.map(OwnerName.of) ?? OwnerName.unassigned }

    /// Kolor awatara z prezentacji. Zależy od **stabilnej pozycji prezentacji**, nie od ID (§4.3).
    public enum AvatarTone: Int, Codable, Sendable, CaseIterable {
        case none = 0
        case one = 1
        case two = 2
        case three = 3
    }
}

public enum OwnerName {
    public static let unassigned = "Nieprzypisany"

    public static func of(_ id: UserID) -> String {
        switch id {
        case .tomasz: return "Tomasz"
        case .pawel: return "Paweł"
        default: return id.rawValue
        }
    }
}

// MARK: - Sprawa

public enum CaseStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case inProgress = "W toku"
    case awaitingClient = "Oczekujemy na klienta"
    case closed = "Zamknięta"

    public var id: String { rawValue }
    public var isActive: Bool { self != .closed }
}

public struct LegalCase: Identifiable, Hashable, Codable, Sendable {
    public let id: CaseID
    public var number: String
    public var title: String
    public var clientID: ClientID
    public var ownerID: UserID
    public var status: CaseStatus
    public var summary: String
    public var createdAt: LocalDate
    public var version: Version

    public init(
        id: CaseID,
        number: String,
        title: String,
        clientID: ClientID,
        ownerID: UserID,
        status: CaseStatus,
        summary: String,
        createdAt: LocalDate,
        version: Version = .initial
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.clientID = clientID
        self.ownerID = ownerID
        self.status = status
        self.summary = summary
        self.createdAt = createdAt
        self.version = version
    }
}

// MARK: - Termin / konsultacja

public enum EventKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case consultation = "Konsultacja"
    case caseDeadline = "Termin w sprawie"

    public var id: String { rawValue }
}

public enum EventStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case toConfirm = "Do potwierdzenia"
    case confirmed = "Potwierdzona"
    case finished = "Zakończona"

    public var id: String { rawValue }
}

public struct ScheduledEvent: Identifiable, Hashable, Codable, Sendable {
    public let id: EventID
    public var clientID: ClientID
    public var caseID: CaseID?
    public var title: String
    public var day: LocalDate
    public var time: TimeOfDay
    public var durationMinutes: Int
    /// `nil` oznacza „Nieprzypisany”; potwierdzenie wymaga wybrania prowadzącego (§etap 04).
    public var ownerID: UserID?
    public var kind: EventKind
    public var status: EventStatus
    public var place: String
    public var version: Version

    public init(
        id: EventID,
        clientID: ClientID,
        caseID: CaseID?,
        title: String,
        day: LocalDate,
        time: TimeOfDay,
        durationMinutes: Int,
        ownerID: UserID?,
        kind: EventKind,
        status: EventStatus,
        place: String,
        version: Version = .initial
    ) {
        self.id = id
        self.clientID = clientID
        self.caseID = caseID
        self.title = title
        self.day = day
        self.time = time
        self.durationMinutes = durationMinutes
        self.ownerID = ownerID
        self.kind = kind
        self.status = status
        self.place = place
        self.version = version
    }

    public var ownerLabel: String { ownerID.map(OwnerName.of) ?? OwnerName.unassigned }

    /// Chwila rozpoczęcia w UTC. Używana tylko do prezentacji i porządkowania;
    /// kolizje liczymy w minutach lokalnych, aby uniknąć wpływu zmiany czasu.
    public func startInstant(referenceDate: Date = Date()) -> MeetingInstant? {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: EmmaTime.referenceTimeZone) else { return nil }
        calendar.timeZone = zone
        guard let date = calendar.date(from: components) else { return nil }
        return MeetingInstant(utc: date)
    }

    /// Kolizja prowadzącego (§etap 04). Zakończone wydarzenia nie kolidują.
    public func overlaps(with other: ScheduledEvent) -> Bool {
        guard id != other.id,
              day == other.day,
              ownerID != nil,
              ownerID == other.ownerID,
              status != .finished,
              other.status != .finished
        else { return false }
        let selfStart = time.minutes
        let selfEnd = selfStart + durationMinutes
        let otherStart = other.time.minutes
        let otherEnd = otherStart + other.durationMinutes
        return otherStart < selfEnd && selfStart < otherEnd
    }
}

// MARK: - Zadanie

public enum TaskPriority: String, Codable, Sendable, CaseIterable, Identifiable {
    case normal = "Zwykłe"
    case urgent = "Pilne"

    public var id: String { rawValue }
}

public struct TaskItem: Identifiable, Hashable, Codable, Sendable {
    public let id: TaskID
    public var title: String
    public var clientID: ClientID?
    public var caseID: CaseID?
    public var ownerID: UserID
    public var dueDate: LocalDate
    public var isDone: Bool
    public var priority: TaskPriority
    public var version: Version

    public init(
        id: TaskID,
        title: String,
        clientID: ClientID?,
        caseID: CaseID?,
        ownerID: UserID,
        dueDate: LocalDate,
        isDone: Bool,
        priority: TaskPriority,
        version: Version = .initial
    ) {
        self.id = id
        self.title = title
        self.clientID = clientID
        self.caseID = caseID
        self.ownerID = ownerID
        self.dueDate = dueDate
        self.isDone = isDone
        self.priority = priority
        self.version = version
    }
}

// MARK: - Notatka i historia

public struct CaseNote: Identifiable, Hashable, Codable, Sendable {
    public let id: NoteID
    public var clientID: ClientID
    public var caseID: CaseID?
    public var text: String
    public var authorID: UserID
    public var createdAt: LocalDate
    public var version: Version

    public init(
        id: NoteID,
        clientID: ClientID,
        caseID: CaseID?,
        text: String,
        authorID: UserID,
        createdAt: LocalDate,
        version: Version = .initial
    ) {
        self.id = id
        self.clientID = clientID
        self.caseID = caseID
        self.text = text
        self.authorID = authorID
        self.createdAt = createdAt
        self.version = version
    }
}

public struct ActivityEvent: Identifiable, Hashable, Codable, Sendable {
    public let id: ActivityID
    public var text: String
    public var clientID: ClientID?
    public var caseID: CaseID?
    public var createdAt: LocalDate
    public var authorID: UserID

    public init(
        id: ActivityID,
        text: String,
        clientID: ClientID?,
        caseID: CaseID?,
        createdAt: LocalDate,
        authorID: UserID
    ) {
        self.id = id
        self.text = text
        self.clientID = clientID
        self.caseID = caseID
        self.createdAt = createdAt
        self.authorID = authorID
    }
}
