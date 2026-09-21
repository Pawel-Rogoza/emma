import Foundation

// MARK: - Zegar
//
// Demo używa stałej daty 2026-09-11. Tryb live **nie** korzysta z tej stałej (§4.3).

public protocol Clock: Sendable {
    func now() -> Date
    func today() -> LocalDate
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
    public func today() -> LocalDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: EmmaTime.referenceTimeZone) ?? .gmt
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        return LocalDate(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }
}

/// Zegar demonstracyjny. Deterministyczny i przesuwalny wyłącznie jawnie,
/// nigdy przez upływ czasu rzeczywistego.
public final class DemoClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var currentInstant: Date
    private let referenceDate: LocalDate

    public init(referenceDate: LocalDate = LocalDate(year: 2026, month: 9, day: 11), hour: Int = 9, minute: Int = 41) {
        self.referenceDate = referenceDate
        var components = DateComponents()
        components.year = referenceDate.year
        components.month = referenceDate.month
        components.day = referenceDate.day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: EmmaTime.referenceTimeZone) ?? .gmt
        self.currentInstant = calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_789_000_000)
    }

    public func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return currentInstant
    }

    public func today() -> LocalDate { referenceDate }

    /// Przesunięcie zegara demo o podany interwał. Używane w testach i w scenariuszach.
    public func advance(by interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        currentInstant = currentInstant.addingTimeInterval(interval)
    }

    public func set(instant: Date) {
        lock.lock(); defer { lock.unlock() }
        currentInstant = instant
    }
}

// MARK: - Formatowanie

public enum EmmaPlural {

    /// Polska reguła liczby mnogiej: 1 / 2–4 / pozostałe, z wyjątkami dla 12–14.
    public static func form(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let absolute = abs(count)
        let lastTwo = absolute % 100
        let last = absolute % 10
        if absolute == 1 { return one }
        if last >= 2 && last <= 4 && !(lastTwo >= 12 && lastTwo <= 14) { return few }
        return many
    }

    /// Pełna etykieta z liczbą, np. „3 konsultacje”.
    public static func label(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(count) \(form(count, one, few, many))"
    }

    public static func consultations(_ count: Int) -> String {
        label(count, "konsultacja", "konsultacje", "konsultacji")
    }

    public static func tasks(_ count: Int) -> String {
        label(count, "zadanie", "zadania", "zadań")
    }

    public static func openTasks(_ count: Int) -> String {
        label(count, "zadanie do wykonania", "zadania do wykonania", "zadań do wykonania")
    }

    public static func overdueTasks(_ count: Int) -> String {
        label(count, "zaległe zadanie", "zaległe zadania", "zaległych zadań")
    }

    public static func cases(_ count: Int) -> String {
        label(count, "prowadzona sprawa", "prowadzone sprawy", "prowadzonych spraw")
    }

    public static func events(_ count: Int) -> String {
        label(count, "wydarzenie", "wydarzenia", "wydarzeń")
    }

    public static func unread(_ count: Int) -> String {
        label(count, "nieprzeczytana wiadomość", "nieprzeczytane wiadomości", "nieprzeczytanych wiadomości")
    }
}

/// Tekst daty w interfejsie. W demo „Dzisiaj”/„Jutro” liczone względem zegara,
/// nie względem stałej w kodzie widoku.
public struct DateTextFormatter: Sendable {
    private let today: LocalDate
    /// Skrócone nazwy miesięcy w języku polskim. Bez zależności od ustawień systemu,
    /// aby prezentacja była deterministyczna w testach.
    private static let shortMonths = [
        "sty", "lut", "mar", "kwi", "maj", "cze", "lip", "sie", "wrz", "paź", "lis", "gru"
    ]
    private static let fullMonths = [
        "stycznia", "lutego", "marca", "kwietnia", "maja", "czerwca",
        "lipca", "sierpnia", "września", "października", "listopada", "grudnia"
    ]
    /// Mianownik — używany w tytule miesiąca, nie w dacie dziennej.
    private static let nominativeMonths = [
        "Styczeń", "Luty", "Marzec", "Kwiecień", "Maj", "Czerwiec",
        "Lipiec", "Sierpień", "Wrzesień", "Październik", "Listopad", "Grudzień"
    ]
    private static let weekdayShort = ["Pn", "Wt", "Śr", "Cz", "Pt", "So", "Nd"]
    private static let weekdayFull = [
        "PONIEDZIAŁEK", "WTOREK", "ŚRODA", "CZWARTEK", "PIĄTEK", "SOBOTA", "NIEDZIELA"
    ]

    public init(today: LocalDate) {
        self.today = today
    }

    /// Godzina `HH:mm` w strefie referencyjnej.
    ///
    /// Jedno miejsce na całą aplikację: wcześniej ten sam formater powstawał
    /// w trzech widokach, więc każda poprawka musiałaby trafić w trzy pliki.
    /// Strefa jest stała świadomie — patrz D-03 w `DESIGN_DEVIATIONS.md`.
    public func clockTime(_ instant: Date) -> String {
        Self.clockFormatter.string(from: instant)
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: EmmaTime.referenceTimeZone)
        return formatter
    }()

    public func dayLabel(_ date: LocalDate) -> String {
        if date == today { return "Dzisiaj" }
        if date == today.adding(days: 1) { return "Jutro" }
        if date == today.adding(days: -1) { return "Wczoraj" }
        return "\(date.day) \(Self.shortMonths[date.month - 1])"
    }

    /// „PIĄTEK, 11 WRZEŚNIA” — nagłówek ekranu Dzisiaj.
    public func headline(for date: LocalDate) -> String {
        let weekday = Self.weekdayFull[date.weekdayIndexMondayFirst]
        return "\(weekday), \(date.day) \(Self.fullMonths[date.month - 1].uppercased())"
    }

    /// „Wrzesień 2026” — nagłówek kalendarza (mianownik, nie „września”).
    public func monthTitle(for date: LocalDate) -> String {
        "\(Self.nominativeMonths[date.month - 1]) \(date.year)"
    }

    public func weekdayShort(for date: LocalDate) -> String {
        Self.weekdayShort[date.weekdayIndexMondayFirst]
    }

    /// Godzina z długością, np. „10:30 · 30 min”.
    public func timeAndDuration(_ time: TimeOfDay, minutes: Int) -> String {
        "\(time.hhmm) · \(minutes) min"
    }
}

// MARK: - Wykrywanie intencji zatwierdzenia i negacji
//
// „Tak, ale po piątej”, „nie wysyłaj” i cytat „tak” są korektą/negacją/danymi,
// nie zgodą (§8.2).

public enum ConfirmationPhrases {

    public enum Classification: Equatable, Sendable {
        /// Pełne, jednoznaczne potwierdzenie wskazanej prezentacji.
        case explicitConfirmation
        /// Negacja: nie wysyłaj, anuluj.
        case negation
        /// Korekta: „tak, ale…”, zmiana treści lub godziny.
        case correction
        /// Cytat cudzej wypowiedzi zawierającej „tak”.
        case quotedData
        /// Krótkie „tak/да” — niewystarczające bez przetestowanego związania z prezentacją.
        case bareAffirmation
        case neither
    }

    /// Pełne formy potwierdzenia wymagane w pierwszym przyroście (§8.2).
    public static let explicitForms = [
        "wyślij tę wiadomość",
        "отправь это сообщение",
        "отправь это сообщение.",
        "zatwierdzam tę wiadomość"
    ]

    public static let bareAffirmations = ["tak", "да", "yes", "ок", "ok", "хорошо", "dobrze"]
    public static let negations = [
        "nie", "нет", "nie wysyłaj", "не отправляй", "anuluj", "otmena", "отмена", "stop"
    ]
    public static let correctionMarkers = ["ale", "но", "popraw", "zmień", "измени", "исправь", "nie tak"]

    public static func classify(_ raw: String) -> Classification {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return .neither }

        // Cytat: treść w cudzysłowie zawierająca formę potwierdzenia to dane, nie zgoda.
        if containsQuotedAffirmation(text) { return .quotedData }

        if explicitForms.contains(where: { text == $0 || text.hasSuffix($0) }) {
            return .explicitConfirmation
        }
        if negations.contains(where: { text == $0 || text.hasPrefix($0 + " ") }) {
            return .negation
        }
        if correctionMarkers.contains(where: { text.contains($0) }) {
            // „tak, ale po piątej” — korekta, nie zgoda.
            return .correction
        }
        if bareAffirmations.contains(text) { return .bareAffirmation }
        return .neither
    }

    private static func containsQuotedAffirmation(_ text: String) -> Bool {
        let pairs: [(Character, Character)] = [("\"", "\""), ("„", "”"), ("«", "»"), ("'", "'")]
        for (open, close) in pairs {
            guard let openIndex = text.firstIndex(of: open) else { continue }
            let after = text.index(after: openIndex)
            guard let closeIndex = text[after...].firstIndex(of: close) else { continue }
            let quoted = String(text[after..<closeIndex])
            if bareAffirmations.contains(where: { quoted.contains($0) })
                || explicitForms.contains(where: { quoted.contains($0) }) {
                return true
            }
        }
        return false
    }
}

// MARK: - Dopasowanie tekstu w wyszukiwaniu

/// Jedno miejsce, w którym decydujemy, co znaczy „pasuje do zapytania”.
///
/// Powód istnienia: każdy ekran robił `lowercased().contains(…)` po swojemu, więc
/// wyszukiwanie nie znajdowało „Żelazna” po wpisaniu „zelazna” ani „Łukasz” po
/// „lukasz” (znana różnica D-09 w `DESIGN_DEVIATIONS.md`). Reguła jest jedna i ma
/// testy, a nie trzy kopie w trzech widokach.
public enum SearchText {

    /// Normalizacja zapytania i treści: małe litery, bez znaków diakrytycznych.
    ///
    /// `ł` jest osobnym znakiem, nie literą z diakrytykiem — składanie Unicode go nie
    /// usuwa, więc mapujemy je jawnie. Bez tego najczęstszy odruch przy wpisywaniu
    /// polskiego nazwiska (bez ogonków) nie znajdowałby niczego.
    public static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
            .replacingOccurrences(of: "ł", with: "l")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Czy zapytanie pasuje do którejkolwiek z podanych części.
    /// Puste zapytanie pasuje do wszystkiego — filtr jest wtedy wyłączony.
    public static func matches(_ query: String, in parts: [String]) -> Bool {
        let needle = normalize(query)
        guard !needle.isEmpty else { return true }
        return parts.contains { normalize($0).contains(needle) }
    }
}

// MARK: - Rozpoznawanie osoby w poleceniu
//
// Uproszczona, deterministyczna reguła przeniesiona z prototypu, ale bez
// „linkedCase(...).first” jako reguły domenowej (§4.3).

public enum PersonResolver {

    public enum Result: Equatable, Sendable {
        case resolved(ClientID)
        case multiple([ClientID])
        case unknown
        case none
    }

    /// Dopasowanie po imieniu lub nazwisku, z rozróżnieniem „jednoznaczne”
    /// i „kilku kandydatów”. Podobne nazwisko **nie** łączy klientów (§9.2).
    public static func resolve(_ text: String, among clients: [Client]) -> Result {
        let haystack = text.lowercased()
        var matches: [ClientID] = []
        for client in clients {
            let tokens = client.displayName
                .lowercased()
                .split(whereSeparator: { $0 == " " || $0 == "-" })
                .map(String.init)
            let hit = tokens.contains { token in
                guard token.count >= 4 else { return false }
                let stem = String(token.prefix(max(4, token.count - 2)))
                return haystack.contains(stem)
            }
            if hit { matches.append(client.id) }
        }
        switch matches.count {
        case 0: return .unknown
        case 1: return .resolved(matches[0])
        default: return .multiple(matches)
        }
    }
}

// MARK: - Trasa audio po odłączeniu słuchawek
//
// Poufny odsłuch wstrzymujemy; nie przenosimy go automatycznie na głośnik (§5.7).

public enum AudioRoutePolicy {
    public enum Decision: Equatable, Sendable {
        case continuePlayback
        case pausePlaybackAndAsk
        case noChange
    }

    public static func decision(
        previous: AudioRoute,
        current: AudioRoute,
        isSensitivePlaybackActive: Bool
    ) -> Decision {
        guard isSensitivePlaybackActive else { return .noChange }
        if previous.isPrivate && !current.isPrivate {
            return .pausePlaybackAndAsk
        }
        return .continuePlayback
    }
}
