import Foundation

// MARK: - Przegląd bazy kancelarii (ekran „Klienci”)
//
// Review 27.09.2026: na liście spraw i klientów „wszystko się zlewało” — każda
// karta wyglądała tak samo, a pilna sprawa nie różniła się od takiej, w której
// nic się nie dzieje. Reguły, które o tym decydują, są tutaj (bez SwiftUI),
// żeby dało się je przetestować na Linuksie:
//
//   • `CaseUrgency` — ile dni do najbliższego terminu, czy termin minął
//     i czy sprawa wymaga uwagi,
//   • `CaseBoard` — podział aktywnych spraw na „Wymaga uwagi”, „W toku”
//     i „Czekamy na klienta”,
//   • `ClientDirectory` — kartoteka klientów kancelarii w sekcjach A–Ż,
//   • `IdentityTone` — stały kolor awatara osoby, liczony z jej identyfikatora,
//   • `ClientsModel.make` — wszystko, co listy liczą z terminów i zadań,
//     policzone raz przy wczytaniu, a nie przy każdym przerysowaniu ekranu.

/// Pilność sprawy wynikająca z terminów i zadań — bez danych, których backend
/// nie zna (rodzaj sprawy, data zmiany statusu).
///
/// Review 28.09.2026: niezakończony **termin w sprawie** z ostatnich dni
/// (upływ terminu na dokumenty, rozprawa) liczył się jak brak terminu, więc
/// sprawa po terminie lądowała w „W toku”. Teraz jest najpilniejsza ze wszystkich.
public struct CaseUrgency: Equatable, Sendable {

    /// Ile dni naprzód termin uznajemy za „wymagający uwagi”.
    public static let attentionDays = 7
    /// Do ilu dni termin jest „pilny” (czerwona plakietka).
    public static let urgentDays = 3
    /// Jak daleko wstecz szukamy przegapionego terminu. Starsze niezamknięte
    /// terminy to raczej zapomniane wpisy niż sprawa do ratowania.
    public static let missedLookbackDays = 30

    public enum Level: Equatable, Sendable {
        /// Termin w sprawie minął, a nikt go nie zamknął.
        case missed
        /// Termin najpóźniej za `urgentDays` dni.
        case urgent
        /// Termin za 4–7 dni.
        case soon
        /// Nic nie goni.
        case calm
    }

    /// Dni do najbliższego terminu (0 = dziś); `nil`, gdy terminu nie ma.
    public let daysToNextEvent: Int?
    /// Ile dni temu minął niezakończony termin w sprawie; `nil`, gdy żaden.
    public let daysSinceMissed: Int?
    /// Otwarte zadania z terminem przed dziś.
    public let overdueTasks: Int

    public init(nextEvent: LocalDate?, missedEvent: LocalDate? = nil, overdueTasks: Int, today: LocalDate) {
        self.daysToNextEvent = nextEvent.map { max(0, today.days(until: $0)) }
        self.daysSinceMissed = missedEvent.map { max(1, $0.days(until: today)) }
        self.overdueTasks = overdueTasks
    }

    public var level: Level {
        if daysSinceMissed != nil { return .missed }
        guard let days = daysToNextEvent else { return .calm }
        if days <= Self.urgentDays { return .urgent }
        if days <= Self.attentionDays { return .soon }
        return .calm
    }

    /// Czerwień: po terminie albo termin najpóźniej za 3 dni.
    public var isCritical: Bool {
        level == .missed || level == .urgent
    }

    /// Sprawa trafia do „Wymaga uwagi”: termin minął, termin w ciągu tygodnia
    /// albo zaległe zadanie.
    public var needsAttention: Bool {
        level != .calm || overdueTasks > 0
    }

    /// „minął wczoraj”, „minął 3 dni temu”, „dziś”, „jutro”, „za 5 dni” —
    /// `nil`, gdy nic nie minęło, a termin jest dalej niż tydzień.
    public var countdownText: String? {
        if let missed = daysSinceMissed {
            return missed == 1 ? "minął wczoraj" : "minął \(EmmaPlural.days(missed)) temu"
        }
        guard let days = daysToNextEvent, days <= Self.attentionDays else { return nil }
        switch days {
        case 0: return "dziś"
        case 1: return "jutro"
        default: return "za \(EmmaPlural.days(days))"
        }
    }

    /// Klucz kolejności w „Wymaga uwagi”: najdawniej przegapione, potem
    /// najbliższe terminy, na końcu same zaległe zadania.
    var attentionRank: Int {
        if let missed = daysSinceMissed { return -missed }
        if let days = daysToNextEvent, days <= Self.attentionDays { return days }
        return Int.max
    }
}

/// Aktywne sprawy w trzech grupach, w kolejności, w jakiej prawnik je przegląda.
public struct CaseBoard: Equatable, Sendable {

    public enum Group: String, CaseIterable, Sendable {
        case attention = "Wymaga uwagi"
        case inProgress = "W toku"
        case awaitingClient = "Czekamy na klienta"
    }

    public let attention: [LegalCase]
    public let inProgress: [LegalCase]
    public let awaitingClient: [LegalCase]

    public static let empty = CaseBoard(attention: [], inProgress: [], awaitingClient: [])

    public var activeCount: Int {
        attention.count + inProgress.count + awaitingClient.count
    }

    public var isEmpty: Bool { activeCount == 0 }

    public func cases(in group: Group) -> [LegalCase] {
        switch group {
        case .attention: return attention
        case .inProgress: return inProgress
        case .awaitingClient: return awaitingClient
        }
    }

    /// Ta sama tablica zawężona np. wyszukiwaniem — kolejność w grupach zostaje.
    public func filtered(_ isIncluded: (LegalCase) -> Bool) -> CaseBoard {
        CaseBoard(
            attention: attention.filter(isIncluded),
            inProgress: inProgress.filter(isIncluded),
            awaitingClient: awaitingClient.filter(isIncluded)
        )
    }

    /// - Parameters:
    ///   - nextEvents: najbliższy przyszły termin każdej sprawy,
    ///   - missedEvents: przegapiony (niezakończony) termin w sprawie,
    ///   - overdueTasks: liczba zaległych zadań w sprawie.
    public static func make(
        _ cases: [LegalCase],
        nextEvents: [CaseID: ScheduledEvent],
        missedEvents: [CaseID: ScheduledEvent] = [:],
        overdueTasks: [CaseID: Int],
        today: LocalDate
    ) -> CaseBoard {
        var attention: [(LegalCase, CaseUrgency)] = []
        var inProgress: [LegalCase] = []
        var awaiting: [LegalCase] = []

        for legalCase in cases where legalCase.status.isActive {
            let urgency = CaseUrgency(
                nextEvent: nextEvents[legalCase.id]?.day,
                missedEvent: missedEvents[legalCase.id]?.day,
                overdueTasks: overdueTasks[legalCase.id] ?? 0,
                today: today
            )
            if urgency.needsAttention {
                attention.append((legalCase, urgency))
            } else if legalCase.status == .awaitingClient {
                awaiting.append(legalCase)
            } else {
                inProgress.append(legalCase)
            }
        }

        // Po terminie najpierw, potem najbliższy termin; same zaległe zadania
        // (bez terminu w tygodniu) na końcu, żeby nie przesłoniły jutrzejszej rozprawy.
        let sortedAttention = attention.sorted { lhs, rhs in
            let left = lhs.1.attentionRank
            let right = rhs.1.attentionRank
            if left != right { return left < right }
            if lhs.1.overdueTasks != rhs.1.overdueTasks { return lhs.1.overdueTasks > rhs.1.overdueTasks }
            return byTitle(lhs.0, rhs.0)
        }.map(\.0)

        let byNextEvent: (LegalCase, LegalCase) -> Bool = { lhs, rhs in
            switch (nextEvents[lhs.id]?.day, nextEvents[rhs.id]?.day) {
            case let (left?, right?) where left != right: return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            default: return byTitle(lhs, rhs)
            }
        }

        return CaseBoard(
            attention: sortedAttention,
            inProgress: inProgress.sorted(by: byNextEvent),
            awaitingClient: awaiting.sorted(by: byNextEvent)
        )
    }

    private static func byTitle(_ lhs: LegalCase, _ rhs: LegalCase) -> Bool {
        let order = lhs.title.localizedCompare(rhs.title)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.id.rawValue < rhs.id.rawValue
    }
}

/// Kartoteka klientów kancelarii (etap `client`) w sekcjach alfabetycznych.
public enum ClientDirectory {

    public struct Section: Equatable, Sendable, Identifiable {
        /// Litera nagłówka („A”, „Ł”, „#” dla nazw bez litery na początku).
        public let letter: String
        public let clients: [Client]
        public var id: String { letter }
    }

    /// Sortowanie po polsku (Ł po L, Ś po S), sekcje według pierwszej litery.
    public static func sections(_ clients: [Client]) -> [Section] {
        let locale = Locale(identifier: "pl_PL")
        let sorted = clients.sorted { lhs, rhs in
            let order = lhs.displayName.compare(
                rhs.displayName,
                options: [.caseInsensitive],
                range: nil,
                locale: locale
            )
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.id.rawValue < rhs.id.rawValue
        }

        var sections: [Section] = []
        for client in sorted {
            let letter = sectionLetter(client.displayName)
            if let last = sections.last, last.letter == letter {
                sections[sections.count - 1] = Section(letter: letter, clients: last.clients + [client])
            } else {
                sections.append(Section(letter: letter, clients: [client]))
            }
        }
        return sections
    }

    static func sectionLetter(_ name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first, first.isLetter else {
            return "#"
        }
        return String(first).uppercased(with: Locale(identifier: "pl_PL"))
    }
}

/// Stały ton awatara osoby. Ta sama osoba ma ten sam kolor na liście leadów,
/// w kartotece, w sprawach i w rozmowach — to on pozwala rozpoznać ją wzrokiem,
/// zanim przeczyta się nazwisko (odstępstwo D-34 od §4.3).
///
/// `hashValue` w Swifcie zmienia się między uruchomieniami, więc liczymy własny,
/// deterministyczny skrót (FNV-1a) z identyfikatora.
public enum IdentityTone {

    /// Liczba tonów w palecie (`EmmaTheme.identityAvatar`).
    public static let count = 6

    public static func index(for id: ClientID) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in id.rawValue.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(count))
    }
}

public extension LanguageCode {
    /// Krótki kod na plakietkę listy: „UA”, „RU”, „PL”. Ukraiński pokazujemy
    /// jako „UA” — tak czyta go prawnik, choć kod języka to `uk`.
    var badgeCode: String {
        switch self {
        case .pl: return "PL"
        case .ru: return "RU"
        case .uk: return "UA"
        }
    }
}

/// Ostatnio otwierane karty klientów — pasek nad kartoteką. Najnowsze najpierw,
/// bez powtórzeń, najwyżej `limit` osób. Zapis w `UserDefaults` robi powłoka
/// aplikacji; tu jest sama reguła.
public struct RecentClients: Equatable, Sendable {

    public static let limit = 8

    public private(set) var ids: [ClientID]

    public init(ids: [ClientID] = []) {
        self.ids = Array(ids.prefix(Self.limit))
    }

    public mutating func record(_ id: ClientID) {
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        if ids.count > Self.limit {
            ids.removeLast(ids.count - Self.limit)
        }
    }
}

// MARK: - Dane ekranu „Klienci”

/// Dane list leadów, klientów i spraw wraz z policzonymi zależnościami.
///
/// Review 28.09.2026: filtry, liczniki chipów i pilność klientów liczyły się
/// w widoku przy każdym przerysowaniu (a `nextCaseEvents` przeszukiwało
/// wszystkie terminy osobno dla każdej sprawy). Teraz wszystko powstaje raz,
/// w `make`, przy wczytaniu listy — i da się to przetestować bez SwiftUI.
public struct ClientsModel: Equatable, Sendable {

    /// Po ilu dniach bez terminu klient z aktywną sprawą jest „bez ruchu”.
    public static let staleDays = 30

    public var clients: [Client]
    public var cases: [LegalCase]
    public var clientsByID: [ClientID: Client]
    /// Sprawy każdego klienta — kartoteka pokazuje, co u niego prowadzimy.
    public var casesByClient: [ClientID: [LegalCase]]
    /// Klienci kancelarii (etap `client`) — kartoteka.
    public var firmClients: [Client]

    /// Liczba otwartych zadań w sprawie — stopka karty sprawy.
    public var openTaskCounts: [CaseID: Int]
    /// Otwarte zadania z terminem przed dziś — sprawa trafia do „Wymaga uwagi”.
    public var overdueTaskCounts: [CaseID: Int]
    /// Zaległe zadania klienta (jego własne i w jego sprawach) — kartoteka.
    public var clientOverdueTaskCounts: [ClientID: Int]

    /// Najbliższy przyszły, niezakończony termin sprawy.
    public var nextCaseEvents: [CaseID: ScheduledEvent]
    /// Najświeższy niezakończony termin w sprawie, który już minął.
    public var missedCaseEvents: [CaseID: ScheduledEvent]
    /// Najbliższy niezakończony termin leada (referencja: pierwszy z posortowanych).
    public var nextLeadEvents: [ClientID: ScheduledEvent]
    /// Najbliższy **przyszły** termin osoby — jej własny albo w jej sprawie
    /// (rozprawa dodana z kalendarza sądu często nie ma wpisanego klienta).
    public var nextClientEvents: [ClientID: ScheduledEvent]
    /// Przegapiony termin w którejś ze spraw klienta.
    public var missedClientEvents: [ClientID: ScheduledEvent]

    /// Klienci z co najmniej jedną aktywną sprawą.
    public var clientsWithActiveCase: Set<ClientID>
    /// Klienci, którzy wymagają uwagi — ta sama miara co przy sprawach.
    public var clientsNeedingAttention: Set<ClientID>
    /// Klienci z aktywną sprawą, w której od `staleDays` dni nic się nie dzieje:
    /// brak terminu przed nimi i za nimi. To sprawy, które cicho umierają.
    public var staleClients: Set<ClientID>

    /// Aktywne sprawy w grupach „Wymaga uwagi → W toku → Czekamy na klienta”.
    public var caseBoard: CaseBoard
    /// Zamknięte sprawy, najnowsze najpierw.
    public var closedCases: [LegalCase]

    public func urgency(for legalCase: LegalCase, today: LocalDate) -> CaseUrgency {
        CaseUrgency(
            nextEvent: nextCaseEvents[legalCase.id]?.day,
            missedEvent: missedCaseEvents[legalCase.id]?.day,
            overdueTasks: overdueTaskCounts[legalCase.id] ?? 0,
            today: today
        )
    }

    /// - Parameter events: terminy z okna `ClientsEventWindow` (od 30 dni wstecz).
    public static func make(
        clients: [Client],
        cases: [LegalCase],
        openTasks: [TaskItem],
        events: [ScheduledEvent],
        today: LocalDate
    ) -> ClientsModel {
        let caseOwners = Dictionary(cases.map { ($0.id, $0.clientID) }, uniquingKeysWith: { first, _ in first })

        var openTaskCounts: [CaseID: Int] = [:]
        var overdueTaskCounts: [CaseID: Int] = [:]
        var clientOverdueTaskCounts: [ClientID: Int] = [:]
        for task in openTasks {
            let isOverdue = task.dueDate.map { $0 < today } ?? false
            if let caseID = task.caseID {
                openTaskCounts[caseID, default: 0] += 1
                if isOverdue { overdueTaskCounts[caseID, default: 0] += 1 }
            }
            if isOverdue, let owner = task.clientID ?? task.caseID.flatMap({ caseOwners[$0] }) {
                clientOverdueTaskCounts[owner, default: 0] += 1
            }
        }

        let missedFrom = today.adding(days: -CaseUrgency.missedLookbackDays)
        let staleFrom = today.adding(days: -staleDays)

        var nextCaseEvents: [CaseID: ScheduledEvent] = [:]
        var missedCaseEvents: [CaseID: ScheduledEvent] = [:]
        var nextLeadEvents: [ClientID: ScheduledEvent] = [:]
        var nextClientEvents: [ClientID: ScheduledEvent] = [:]
        var missedClientEvents: [ClientID: ScheduledEvent] = [:]
        /// Osoby, które miały jakikolwiek termin w ostatnich `staleDays` dniach.
        var recentlySeen: Set<ClientID> = []

        // Jeden przebieg po terminach zamiast filtrowania całej tablicy
        // osobno dla każdej sprawy i każdej osoby.
        for event in events {
            let owner = event.clientID ?? event.caseID.flatMap { caseOwners[$0] }
            if let owner, event.day < today, event.day >= staleFrom {
                recentlySeen.insert(owner)
            }
            guard event.status != .finished else { continue }

            if let ownClient = event.clientID {
                keepEarliest(event, in: &nextLeadEvents, key: ownClient)
            }
            if event.day >= today {
                if let caseID = event.caseID {
                    keepEarliest(event, in: &nextCaseEvents, key: caseID)
                }
                if let owner {
                    keepEarliest(event, in: &nextClientEvents, key: owner)
                }
            } else if event.kind == .caseDeadline, event.day >= missedFrom {
                if let caseID = event.caseID {
                    keepLatest(event, in: &missedCaseEvents, key: caseID)
                }
                if let owner {
                    keepLatest(event, in: &missedClientEvents, key: owner)
                }
            }
        }

        let casesByClient = Dictionary(grouping: cases, by: \.clientID)
        let firmClients = clients.filter { $0.stage == .client }

        var withActiveCase: Set<ClientID> = []
        var needingAttention: Set<ClientID> = []
        var stale: Set<ClientID> = []
        for client in firmClients {
            let active = (casesByClient[client.id] ?? []).filter { $0.status.isActive }
            if !active.isEmpty { withActiveCase.insert(client.id) }

            let urgency = CaseUrgency(
                nextEvent: nextClientEvents[client.id]?.day,
                missedEvent: missedClientEvents[client.id]?.day,
                overdueTasks: clientOverdueTaskCounts[client.id] ?? 0,
                today: today
            )
            if urgency.needsAttention {
                needingAttention.insert(client.id)
            } else if !active.isEmpty,
                      nextClientEvents[client.id] == nil,
                      !recentlySeen.contains(client.id),
                      active.allSatisfy({ $0.createdAt <= staleFrom }) {
                // Świeżo założona sprawa nie jest „bez ruchu” — jeszcze nie zdążyła.
                stale.insert(client.id)
            }
        }

        let board = CaseBoard.make(
            cases,
            nextEvents: nextCaseEvents,
            missedEvents: missedCaseEvents,
            overdueTasks: overdueTaskCounts,
            today: today
        )
        let closed = cases
            .filter { $0.status == .closed }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return rhs.createdAt < lhs.createdAt }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }

        return ClientsModel(
            clients: clients,
            cases: cases,
            clientsByID: Dictionary(clients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            casesByClient: casesByClient,
            firmClients: firmClients,
            openTaskCounts: openTaskCounts,
            overdueTaskCounts: overdueTaskCounts,
            clientOverdueTaskCounts: clientOverdueTaskCounts,
            nextCaseEvents: nextCaseEvents,
            missedCaseEvents: missedCaseEvents,
            nextLeadEvents: nextLeadEvents,
            nextClientEvents: nextClientEvents,
            missedClientEvents: missedClientEvents,
            clientsWithActiveCase: withActiveCase,
            clientsNeedingAttention: needingAttention,
            staleClients: stale,
            caseBoard: board,
            closedCases: closed
        )
    }

    /// Porządek terminów: data, potem godzina, na końcu identyfikator
    /// (deterministyczne rozstrzygnięcie remisu, jak w repozytorium).
    static func isEarlier(_ lhs: ScheduledEvent, _ rhs: ScheduledEvent) -> Bool {
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        if lhs.time != rhs.time { return lhs.time < rhs.time }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private static func keepEarliest<Key: Hashable>(
        _ event: ScheduledEvent,
        in map: inout [Key: ScheduledEvent],
        key: Key
    ) {
        if let current = map[key], !isEarlier(event, current) { return }
        map[key] = event
    }

    private static func keepLatest<Key: Hashable>(
        _ event: ScheduledEvent,
        in map: inout [Key: ScheduledEvent],
        key: Key
    ) {
        if let current = map[key], !isEarlier(current, event) { return }
        map[key] = event
    }
}

// MARK: - Wyszukiwanie po telefonie

public extension SearchText {
    /// Klient często dzwoni, zamiast się przedstawić — numer z ekranu połączenia
    /// ma znaleźć kartę. Porównujemy same cyfry, więc „600 100 200”,
    /// „+48600100200” i „0048 600-100-200” trafiają w ten sam zapis.
    /// Zapytanie z literami albo krótsze niż 3 cyfry nie jest numerem.
    static func matchesPhone(_ query: String, phone: String?) -> Bool {
        guard let phone else { return false }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isLetter }) else { return false }
        var needle = trimmed.filter { ("0"..."9").contains($0) }
        guard needle.count >= 3 else { return false }
        let haystack = phone.filter { ("0"..."9").contains($0) }
        if haystack.contains(needle) { return true }
        // Numer z kierunkowym przy zapisie bez kierunkowego (i odwrotnie).
        if needle.hasPrefix("00") { needle = String(needle.dropFirst(2)) }
        if needle.hasPrefix("48"), needle.count > 9 { needle = String(needle.dropFirst(2)) }
        return needle.count >= 3 && haystack.contains(needle)
    }
}
