import Foundation

// MARK: - Identifiers
//
// ID produkcyjne są nieprzejrzystymi łańcuchami (§4.3). Nigdy nie mapujemy
// użytkownika na 0/1, a nazwiska na klucz rekordu. Typy opakowujące zapobiegają
// pomyleniu identyfikatora klienta z identyfikatorem sprawy w sygnaturach API.

/// Identyfikator użytkownika. W demo: `user-kancelaria` — jedno wspólne konto
/// zespołu. Konto nadal jest potrzebne (sesja, stan odczytu, preferencje), ale
/// **nie opisuje własności danych**: sprawy i zadania należą do kancelarii,
/// a nie do osoby (decyzja właściciela, `DESIGN_DEVIATIONS.md` D-17).
public struct UserID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    public static let kancelaria = UserID("user-kancelaria")
}

public struct ClientID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct CaseID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct TaskID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct EventID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct NoteID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct ActivityID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct ThreadID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// Identyfikator wiadomości. W demo lokalny, w live pochodzi z backendu.
public struct MessageID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible, Comparable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
    public static func < (lhs: MessageID, rhs: MessageID) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ActionID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct VoiceSessionID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// Generacja połączenia. Adapter przypisuje generację z konkretnego połączenia,
/// nie z „bieżącej globalnej zmiennej” podczas odbioru (§5.4).
public struct ConnectionGeneration: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let value: UInt64
    public init(_ value: UInt64) { self.value = value }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
    public var description: String { "gen#\(value)" }
}

/// Wersja mutowalnego zasobu (§4.3, §8.1). Zapis z `expectedVersion`.
public struct Version: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let value: Int
    public init(_ value: Int) { self.value = value }
    public static let initial = Version(1)
    public func next() -> Version { Version(value + 1) }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
    public var description: String { "v\(value)" }
}

// MARK: - Language

/// Kod języka. Kod ukraińskiego to `uk`, **nie** `ua` (§4.3).
public enum LanguageCode: String, Codable, Sendable, CaseIterable, Identifiable {
    case pl
    case ru
    case uk

    public var id: String { rawValue }

    /// Nazwa języka w interfejsie (język polski).
    public var displayName: String {
        switch self {
        case .pl: return "Polski"
        case .ru: return "Rosyjski"
        case .uk: return "Ukraiński"
        }
    }

    /// Nazwa do etykiety odsłuchu / rozpoznawania mowy.
    public var speechLocaleIdentifier: String {
        switch self {
        case .pl: return "pl-PL"
        case .ru: return "ru-RU"
        case .uk: return "uk-UA"
        }
    }

    /// Kod ukraiński bywa mylony z `ua` — odrzucamy go jawnie zamiast cichego podstawienia.
    public init?(lenient raw: String) {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "pl", "pl-pl", "polish", "polski": self = .pl
        case "ru", "ru-ru", "russian", "rosyjski": self = .ru
        case "uk", "uk-ua", "ukrainian", "ukraiński", "ukrainski": self = .uk
        default: return nil
        }
    }

    /// Język, w którym rozpoznajemy pismo. `nil` oznacza brak znaków rozstrzygających.
    public static func detectedScript(of text: String) -> ScriptKind {
        var hasLatin = false
        var hasCyrillic = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0400...0x04FF, 0x0500...0x052F: hasCyrillic = true
            case 0x0041...0x005A, 0x0061...0x007A: hasLatin = true
            default: break
            }
            if hasLatin && hasCyrillic { return .mixed }
        }
        if hasCyrillic { return .cyrillic }
        if hasLatin { return .latin }
        return .unknown
    }
}

public enum ScriptKind: String, Sendable, Equatable {
    case latin
    case cyrillic
    case mixed
    case unknown
}

// MARK: - Time

/// Data bez godziny (§4.3). Własny typ, aby nie zgubić strefy przy porównaniach.
public struct LocalDate: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Tworzy datę z kanonicznego zapisu `YYYY-MM-DD`. Odrzuca wartości niepoprawne.
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), y > 0,
              let m = Int(parts[1]), (1...12).contains(m),
              let d = Int(parts[2]), (1...31).contains(d)
        else { return nil }
        self.init(year: y, month: m, day: d)
        // Walidacja zakresu dnia w miesiącu. Sam format ISO tego nie wychwytuje
        // (2026-02-30 formatuje się identycznie), więc sprawdzamy długość miesiąca.
        guard day <= daysInMonth else { return nil }
    }

    /// Data z komponentów, ale tylko istniejąca w kalendarzu. Wolny tekst
    /// („31 września”, „30.02”) nie może dać daty, której nie ma — dalej szłaby
    /// jako `2026-09-31` do backendu i do porównań terminów.
    public init?(checkedYear year: Int, month: Int, day: Int) {
        guard year > 0, (1...12).contains(month), day >= 1 else { return nil }
        self.init(year: year, month: month, day: day)
        guard day <= daysInMonth else { return nil }
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { isoString }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = LocalDate(iso: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Oczekiwano daty lokalnej w formacie YYYY-MM-DD, otrzymano: \(raw)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }

    // MARK: Arytmetyka kalendarzowa w stałej strefie odniesienia

    /// Dni od 1970-01-01 liczone w UTC na północy. Arytmetyka dat lokalnych jest
    /// niezależna od europejskiej zmiany czasu, bo operujemy na komponentach daty.
    public var daysSinceEpoch: Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        let julian = day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
        return julian - 2440588
    }

    public init(daysSinceEpoch: Int) {
        let julian = daysSinceEpoch + 2440588
        var a = julian + 32044
        let b = (4 * a + 3) / 146097
        let c = a - (146097 * b) / 4
        let d = (4 * c + 3) / 1461
        let e = c - (1461 * d) / 4
        let m = (5 * e + 2) / 153
        let day = e - (153 * m + 2) / 5 + 1
        let month = m + 3 - 12 * (m / 10)
        let year = 100 * b + d - 4800 + m / 10
        a = 0
        self.init(year: year, month: month, day: day)
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(daysSinceEpoch: daysSinceEpoch + days)
    }

    /// 0 = poniedziałek … 6 = niedziela (konwencja interfejsu: tydzień od poniedziałku).
    public var weekdayIndexMondayFirst: Int {
        // 1970-01-01 był czwartkiem (indeks ISO 4).
        let iso = ((daysSinceEpoch + 3) % 7 + 7) % 7 // 0 = poniedziałek
        return iso
    }

    public var isWeekend: Bool { weekdayIndexMondayFirst >= 5 }

    public func days(until other: LocalDate) -> Int { other.daysSinceEpoch - daysSinceEpoch }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        lhs.daysSinceEpoch < rhs.daysSinceEpoch
    }

    /// Poniedziałek tygodnia zawierającego tę datę.
    public var startOfWeekMonday: LocalDate {
        adding(days: -weekdayIndexMondayFirst)
    }

    /// Pierwszy dzień miesiąca tej daty.
    public var firstOfMonth: LocalDate {
        LocalDate(year: year, month: month, day: 1)
    }

    /// Ten sam dzień miesiąca `months` miesięcy dalej (przycięty do końca
    /// krótszego miesiąca: 31 stycznia + 1 → 28/29 lutego).
    public func addingMonths(_ months: Int) -> LocalDate {
        let index = year * 12 + (month - 1) + months
        let newYear = index >= 0 ? index / 12 : (index - 11) / 12
        let newMonth = index - newYear * 12 + 1
        let first = LocalDate(year: newYear, month: newMonth, day: 1)
        return LocalDate(year: newYear, month: newMonth, day: min(day, first.daysInMonth))
    }

    public var daysInMonth: Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        default:
            let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return isLeap ? 29 : 28
        }
    }
}

/// Godzina bez daty, w minutach od północy. Format kanoniczny `HH:mm`.
public struct TimeOfDay: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let minutes: Int

    public init?(minutes: Int) {
        guard (0..<(24 * 60)).contains(minutes) else { return nil }
        self.minutes = minutes
    }

    public init?(hhmm: String) {
        let parts = hhmm.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              let value = TimeOfDay(minutes: h * 60 + m)
        else { return nil }
        self = value
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }

    public var hhmm: String { String(format: "%02d:%02d", hour, minute) }
    public var description: String { hhmm }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.minutes < rhs.minutes }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = TimeOfDay(hhmm: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Oczekiwano godziny HH:mm, otrzymano: \(raw)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hhmm)
    }
}

/// Konkretny moment spotkania: instant UTC + strefa IANA (§4.3).
public struct MeetingInstant: Hashable, Codable, Sendable {
    public let utc: Date
    public let timeZoneIdentifier: String

    public init(utc: Date, timeZoneIdentifier: String = EmmaTime.referenceTimeZone) {
        self.utc = utc
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: EmmaTime.referenceTimeZone)!
    }
}

public enum EmmaTime {
    /// Domyślna strefa kancelarii.
    public static let referenceTimeZone = "Europe/Warsaw"
}
