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
    /// Nazwa, gdy nie wiemy, o którego klienta chodzi. Referencja zawsze znajduje
    /// osobę, więc to nie reguła wyglądu, a bezpiecznik: lepiej pokazać „Klient”
    /// niż puste miejsce. Wcześniej ten sam literał stał w czterech plikach.
    public static let unknownDisplayName = "Klient"

    /// Nazwa kancelarii, gdy zadanie nie ma klienta. Cała kancelaria to jeden
    /// wspólny właściciel, więc nie ma już nazwiska opiekuna.
    public static let firmDisplayName = "Kancelaria"

    public let id: ClientID
    public var displayName: String
    public var initials: String
    /// Język klienta. Nie mylić z językiem interfejsu adwokata.
    public var language: LanguageCode
    public var topic: String
    public var stage: ClientStage
    public var source: ClientSource
    public var createdAt: LocalDate
    public var briefing: String
    public var incomingMessage: String?
    public var incomingTranslation: String?
    public var incomingTime: TimeOfDay?
    /// `needsReply` to stan pracy backendu/briefingu, **nie** etykieta na liście rozmów (§3.3 pkt 4).
    public var needsReply: Bool
    /// Dokładna chwila przyjęcia zgłoszenia (`received_at`), gdy backend ją podaje.
    /// Sama data (`createdAt`) nie wystarcza do reguły „nowy przez 24 godziny”
    /// — patrz `LeadWorkflow`.
    public var receivedAt: Date?
    /// Telefon kontaktu. Pusty, dopóki backend go nie udostępni — karta nie
    /// proponuje wtedy dzwonienia ani WhatsApp.
    public var phone: String?
    public var email: String?
    public var version: Version

    public init(
        id: ClientID,
        displayName: String,
        initials: String,
        language: LanguageCode,
        topic: String,
        stage: ClientStage,
        source: ClientSource,
        createdAt: LocalDate,
        briefing: String,
        incomingMessage: String? = nil,
        incomingTranslation: String? = nil,
        incomingTime: TimeOfDay? = nil,
        needsReply: Bool = false,
        receivedAt: Date? = nil,
        phone: String? = nil,
        email: String? = nil,
        version: Version = .initial
    ) {
        self.id = id
        self.displayName = displayName
        self.initials = initials
        self.language = language
        self.topic = topic
        self.stage = stage
        self.source = source
        self.createdAt = createdAt
        self.briefing = briefing
        self.incomingMessage = incomingMessage
        self.incomingTranslation = incomingTranslation
        self.incomingTime = incomingTime
        self.needsReply = needsReply
        self.receivedAt = receivedAt
        self.phone = phone
        self.email = email
        self.version = version
    }

    /// Kolor awatara z prezentacji. Zależy od **stabilnej pozycji prezentacji**, nie od ID (§4.3).
    public enum AvatarTone: Int, Codable, Sendable, CaseIterable {
        case none = 0
        case one = 1
        case two = 2
        case three = 3
    }
}

// MARK: - Sprawa

public enum CaseStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case inProgress = "W toku"
    case awaitingClient = "Oczekujemy na klienta"
    case closed = "Zamknięta"

    public var id: String { rawValue }
    public var isActive: Bool { self != .closed }
    /// Nazwa do pokazania. Wartości surowe są zarazem etykietami referencji (tak samo
    /// koduje je model danych), więc nie tworzymy drugiego zestawu napisów.
    public var displayName: String { rawValue }
}

public struct LegalCase: Identifiable, Hashable, Codable, Sendable {
    public let id: CaseID
    public var number: String
    public var title: String
    public var clientID: ClientID
    public var status: CaseStatus
    public var summary: String
    public var createdAt: LocalDate
    public var version: Version

    public init(
        id: CaseID,
        number: String,
        title: String,
        clientID: ClientID,
        status: CaseStatus,
        summary: String,
        createdAt: LocalDate,
        version: Version = .initial
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.clientID = clientID
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
    /// Klient terminu. `nil` to termin kancelarii bez klienta (rozprawa
    /// z kalendarza sądu, spotkanie wewnętrzne) — review 24.09.2026: termin
    /// ma służyć pamiętaniu o nim, a wymóg klienta blokował jego dodanie.
    public var clientID: ClientID?
    public var caseID: CaseID?
    public var title: String
    public var day: LocalDate
    public var time: TimeOfDay
    public var durationMinutes: Int
    public var kind: EventKind
    public var status: EventStatus
    public var place: String
    /// Termin całodniowy (np. upływ terminu na dokumenty). Backend to wie
    /// (`all_day`), a aplikacja nie miała dotąd gdzie tego zapisać — bez tego
    /// pola termin całodniowy musiałby udawać termin o północy.
    public var isAllDay: Bool
    public var version: Version

    public init(
        id: EventID,
        clientID: ClientID?,
        caseID: CaseID?,
        title: String,
        day: LocalDate,
        time: TimeOfDay,
        durationMinutes: Int,
        kind: EventKind,
        status: EventStatus,
        place: String,
        isAllDay: Bool = false,
        version: Version = .initial
    ) {
        self.id = id
        self.clientID = clientID
        self.caseID = caseID
        self.title = title
        self.day = day
        self.time = time
        self.durationMinutes = durationMinutes
        self.kind = kind
        self.status = status
        self.place = place
        self.isAllDay = isAllDay
        self.version = version
    }
}

// MARK: - Zadanie

public enum TaskPriority: String, Codable, Sendable, CaseIterable, Identifiable {
    case normal = "Zwykłe"
    case urgent = "Pilne"

    public var id: String { rawValue }

    /// Nazwa do pokazania. Wartości surowe są zarazem etykietami referencji (tak samo
    /// koduje je model danych), więc nie tworzymy drugiego zestawu napisów.
    public var displayName: String { rawValue }
}

extension TaskItem {
    /// Czy wiersz pokazuje wyróżnienie pilności.
    ///
    /// Referencja uzależnia je od **dwóch** warunków: priorytet „Pilne” **i** zadanie
    /// niewykonane. Wiersz patrzył tylko na priorytet, więc ukończone zadanie pilne
    /// nadal świeciło się na bursztynowo, choć we wzorcu już nie.
    public var showsUrgentBadge: Bool { priority == .urgent && !isDone }

    /// Tekst po prawej stronie wiersza: albo „Pilne”, albo etykieta dnia.
    ///
    /// Ta sama reguła decyduje o treści i o wyróżnieniu, więc nie mogą się rozjechać.
    public func rowDateText(_ formatter: DateTextFormatter) -> String {
        if showsUrgentBadge { return TaskPriority.urgent.rawValue }
        return dueDate.map(formatter.dayLabel) ?? TaskItem.noDueDateText
    }

    /// Opis wiersza zadania: sama nazwa klienta albo „Kancelaria”.
    /// Cała kancelaria jest jednym właścicielem, więc nie ma nazwiska opiekuna.
    public static func taskMeta(clientName: String?) -> String {
        clientName ?? Client.firmDisplayName
    }
}

public struct TaskItem: Identifiable, Hashable, Codable, Sendable {
    public let id: TaskID
    public var title: String
    public var clientID: ClientID?
    public var caseID: CaseID?
    /// Termin zadania. Panel kancelarii dopuszcza zadania bez terminu — to
    /// nadal zadania, więc `nil` znaczy „bez terminu”, a nie „brak danych”.
    public var dueDate: LocalDate?
    public var isDone: Bool
    public var priority: TaskPriority
    public var version: Version

    public static let noDueDateText = "Bez terminu"

    /// Porządek listy: po terminie, zadania bez terminu na końcu, remis po id.
    public static func isOrderedByDueDate(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?) where left != right: return left < right
        case (.some, .none): return true
        case (.none, .some): return false
        default: return lhs.id.rawValue < rhs.id.rawValue
        }
    }

    public init(
        id: TaskID,
        title: String,
        clientID: ClientID?,
        caseID: CaseID?,
        dueDate: LocalDate?,
        isDone: Bool,
        priority: TaskPriority,
        version: Version = .initial
    ) {
        self.id = id
        self.title = title
        self.clientID = clientID
        self.caseID = caseID
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
