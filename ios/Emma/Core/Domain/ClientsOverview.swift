import Foundation

// MARK: - Przegląd bazy kancelarii (ekran „Klienci”)
//
// Review 27.09.2026: na liście spraw i klientów „wszystko się zlewało” — każda
// karta wyglądała tak samo, a pilna sprawa nie różniła się od takiej, w której
// nic się nie dzieje. Reguły, które o tym decydują, są tutaj (bez SwiftUI),
// żeby dało się je przetestować na Linuksie:
//
//   • `CaseUrgency` — ile dni do najbliższego terminu i czy sprawa wymaga uwagi,
//   • `CaseBoard` — podział aktywnych spraw na „Wymaga uwagi”, „W toku”
//     i „Czekamy na klienta”,
//   • `ClientDirectory` — kartoteka klientów kancelarii w sekcjach A–Ż,
//   • `IdentityTone` — stały kolor awatara osoby, liczony z jej identyfikatora.

/// Pilność sprawy wynikająca z terminów i zadań — bez danych, których backend
/// nie zna (rodzaj sprawy, data zmiany statusu).
public struct CaseUrgency: Equatable, Sendable {

    /// Ile dni naprzód termin uznajemy za „wymagający uwagi”.
    public static let attentionDays = 7
    /// Do ilu dni termin jest „pilny” (czerwona plakietka).
    public static let urgentDays = 3

    public enum Level: Equatable, Sendable {
        /// Termin najpóźniej za `urgentDays` dni.
        case urgent
        /// Termin za 4–7 dni.
        case soon
        /// Nic nie goni.
        case calm
    }

    /// Dni do najbliższego terminu (0 = dziś); `nil`, gdy terminu nie ma.
    public let daysToNextEvent: Int?
    /// Otwarte zadania z terminem przed dziś.
    public let overdueTasks: Int

    public init(nextEvent: LocalDate?, overdueTasks: Int, today: LocalDate) {
        self.daysToNextEvent = nextEvent.map { max(0, today.days(until: $0)) }
        self.overdueTasks = overdueTasks
    }

    public var level: Level {
        guard let days = daysToNextEvent else { return .calm }
        if days <= Self.urgentDays { return .urgent }
        if days <= Self.attentionDays { return .soon }
        return .calm
    }

    /// Sprawa trafia do „Wymaga uwagi”: termin w ciągu tygodnia albo zaległe zadanie.
    public var needsAttention: Bool {
        level != .calm || overdueTasks > 0
    }

    /// „dziś”, „jutro”, „za 5 dni” — `nil`, gdy termin jest dalej niż tydzień.
    public var countdownText: String? {
        guard let days = daysToNextEvent, days <= Self.attentionDays else { return nil }
        switch days {
        case 0: return "dziś"
        case 1: return "jutro"
        default: return "za \(EmmaPlural.days(days))"
        }
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

    public func cases(in group: Group) -> [LegalCase] {
        switch group {
        case .attention: return attention
        case .inProgress: return inProgress
        case .awaitingClient: return awaitingClient
        }
    }

    /// - Parameters:
    ///   - nextEvents: najbliższy przyszły termin każdej sprawy,
    ///   - overdueTasks: liczba zaległych zadań w sprawie.
    public static func make(
        _ cases: [LegalCase],
        nextEvents: [CaseID: ScheduledEvent],
        overdueTasks: [CaseID: Int],
        today: LocalDate
    ) -> CaseBoard {
        var attention: [(LegalCase, CaseUrgency)] = []
        var inProgress: [LegalCase] = []
        var awaiting: [LegalCase] = []

        for legalCase in cases where legalCase.status.isActive {
            let urgency = CaseUrgency(
                nextEvent: nextEvents[legalCase.id]?.day,
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

        // Najbliższy termin najpierw; same zaległe zadania (bez terminu w tygodniu)
        // na końcu grupy, żeby nie przesłoniły jutrzejszej rozprawy.
        let sortedAttention = attention.sorted { lhs, rhs in
            let left = lhs.1.daysToNextEvent.flatMap { $0 <= CaseUrgency.attentionDays ? $0 : nil } ?? Int.max
            let right = rhs.1.daysToNextEvent.flatMap { $0 <= CaseUrgency.attentionDays ? $0 : nil } ?? Int.max
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
