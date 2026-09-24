import Foundation

// MARK: - Przypomnienia o terminach
//
// Review 24.09.2026: „to ma być w celu dodania terminu i później powiadomień /
// pamiętania o nim”. Termin w aplikacji był wpisem do kalendarza bez żadnego
// przypomnienia — telefon o nim nie mówił.
//
// Przypomnienie jest **lokalnym powiadomieniem telefonu**: nie wymaga serwera
// ani APNs i działa także bez sieci. Każdy termin ma przypomnienie (domyślne
// z ustawień albo wybrane w formularzu terminu). Tu mieszka czysta logika —
// co i kiedy przypomnieć; wysyłką do systemu zajmuje się `EventReminderScheduler`.

/// Ile przed terminem przypomnieć.
public enum ReminderOffset: Int, CaseIterable, Identifiable, Sendable, Codable {
    case none = -1
    case atStart = 0
    case minutes15 = 15
    case minutes30 = 30
    case hour1 = 60
    case hours2 = 120
    case day1 = 1_440
    case days2 = 2_880

    public var id: Int { rawValue }

    /// Etykieta w formularzu: „1 godz. przed”.
    public var title: String {
        switch self {
        case .none: return "Bez przypomnienia"
        case .atStart: return "W chwili rozpoczęcia"
        case .minutes15: return "15 min przed"
        case .minutes30: return "30 min przed"
        case .hour1: return "1 godz. przed"
        case .hours2: return "2 godz. przed"
        case .day1: return "Dzień przed"
        case .days2: return "2 dni przed"
        }
    }

    /// Krótka etykieta do wiersza szczegółów terminu.
    public var shortTitle: String {
        switch self {
        case .none: return "Brak"
        default: return title
        }
    }

    /// Domyślne przypomnienie dla nowego terminu.
    public static let standard: ReminderOffset = .hour1
}

/// Plan powiadomień: które terminy, kiedy i z jaką treścią.
public enum EventReminderPlan {

    public struct Item: Equatable, Sendable {
        /// Identyfikator powiadomienia — stały dla terminu, więc ponowne
        /// zaplanowanie zastępuje stare zamiast dublować.
        public let identifier: String
        public let eventID: EventID
        public let fireAt: Date
        public let title: String
        public let body: String
    }

    /// Prefiks identyfikatorów powiadomień terminów (sprzątanie nie rusza innych).
    public static let identifierPrefix = "emma.event."

    /// iOS trzyma najwyżej 64 zaplanowane powiadomienia na aplikację. Zostawiamy
    /// zapas na inne powiadomienia i planujemy tylko najbliższe przypomnienia.
    public static let defaultLimit = 48

    /// Godzina, o której przypominamy o terminie całodniowym (bez godziny).
    public static let allDayHour = 9

    public static func items(
        events: [ScheduledEvent],
        clientNames: [ClientID: String],
        offset: (ScheduledEvent) -> ReminderOffset,
        now: Date,
        timeZoneIdentifier: String = EmmaTime.referenceTimeZone,
        limit: Int = defaultLimit
    ) -> [Item] {
        var items: [Item] = []
        for event in events where event.status != .finished {
            let chosen = offset(event)
            guard chosen != .none else { continue }
            guard let start = startInstant(of: event, timeZoneIdentifier: timeZoneIdentifier) else { continue }
            let fireAt = start.addingTimeInterval(-TimeInterval(chosen.rawValue * 60))
            guard fireAt > now else { continue }
            items.append(
                Item(
                    identifier: identifierPrefix + event.id.rawValue,
                    eventID: event.id,
                    fireAt: fireAt,
                    title: title(for: event, offset: chosen),
                    body: body(for: event, clientNames: clientNames)
                )
            )
        }
        return Array(
            items
                .sorted { lhs, rhs in
                    lhs.fireAt != rhs.fireAt ? lhs.fireAt < rhs.fireAt : lhs.identifier < rhs.identifier
                }
                .prefix(limit)
        )
    }

    /// Początek terminu jako chwila — czas ściany w strefie kancelarii.
    public static func startInstant(
        of event: ScheduledEvent,
        timeZoneIdentifier: String = EmmaTime.referenceTimeZone
    ) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = event.day.year
        components.month = event.day.month
        components.day = event.day.day
        components.hour = event.isAllDay ? allDayHour : event.time.hour
        components.minute = event.isAllDay ? 0 : event.time.minute
        return calendar.date(from: components)
    }

    /// „Za 1 godz.: Konsultacja”, „Jutro: Termin w sprawie”.
    static func title(for event: ScheduledEvent, offset: ReminderOffset) -> String {
        let lead: String
        switch offset {
        case .none, .atStart: lead = "Teraz"
        case .minutes15: lead = "Za 15 min"
        case .minutes30: lead = "Za 30 min"
        case .hour1: lead = "Za godzinę"
        case .hours2: lead = "Za 2 godziny"
        case .day1: lead = "Jutro"
        case .days2: lead = "Pojutrze"
        }
        return "\(lead): \(event.title)"
    }

    /// „10:30 · Maria Kowalska · Kancelaria, pok. 2”.
    static func body(for event: ScheduledEvent, clientNames: [ClientID: String]) -> String {
        var parts: [String] = [event.isAllDay ? "Cały dzień" : event.time.hhmm]
        if let clientID = event.clientID, let name = clientNames[clientID] {
            parts.append(name)
        }
        let place = event.place.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { parts.append(place) }
        return parts.joined(separator: " · ")
    }
}

/// Wybór przypomnienia per termin, trzymany na telefonie.
///
/// CRM nie ma pola „przypomnienie w aplikacji” (jego `reminders` to e-maile
/// dni przed terminem), więc wybór zostaje lokalnie. Brak wpisu znaczy
/// „domyślne z ustawień”.
public struct ReminderPreferences: @unchecked Sendable {
    public static let defaultKey = "emma.reminders.default"
    public static let perEventKey = "emma.reminders.perEvent"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var defaultOffset: ReminderOffset {
        get {
            guard defaults.object(forKey: Self.defaultKey) != nil else { return .standard }
            return ReminderOffset(rawValue: defaults.integer(forKey: Self.defaultKey)) ?? .standard
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.defaultKey) }
    }

    public func offset(for eventID: EventID) -> ReminderOffset {
        let stored = defaults.dictionary(forKey: Self.perEventKey) as? [String: Int] ?? [:]
        guard let raw = stored[eventID.rawValue], let value = ReminderOffset(rawValue: raw) else {
            return defaultOffset
        }
        return value
    }

    public func setOffset(_ offset: ReminderOffset, for eventID: EventID) {
        var stored = defaults.dictionary(forKey: Self.perEventKey) as? [String: Int] ?? [:]
        stored[eventID.rawValue] = offset.rawValue
        defaults.set(stored, forKey: Self.perEventKey)
    }

    public func removeOffset(for eventID: EventID) {
        var stored = defaults.dictionary(forKey: Self.perEventKey) as? [String: Int] ?? [:]
        stored.removeValue(forKey: eventID.rawValue)
        defaults.set(stored, forKey: Self.perEventKey)
    }
}
