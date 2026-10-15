import Foundation

// MARK: - Czas kancelarii
//
// Audyt 16.10.2026: strefa `Europe/Warsaw` i kalendarz gregoriański w tej strefie
// powstawały od nowa w czternastu miejscach — z trzema różnymi wartościami
// awaryjnymi (`.gmt`, `.current`, UTC) i dwiema różnymi datami zastępczymi
// (1970 i 2026). Każda kopia budowała też nowy `Calendar` przy każdym wywołaniu,
// również w pętlach widoków (dzień każdej wiadomości w rozmowie). Teraz strefa
// i kalendarz powstają raz, a zamiana chwili na dzień i godzinę kancelarii ma
// jedną implementację. Tak samo odczyt znaczników ISO 8601 z backendu.

public enum EmmaTime {
    /// Domyślna strefa kancelarii.
    public static let referenceTimeZone = "Europe/Warsaw"

    /// Strefa kancelarii. `Europe/Warsaw` jest w bazie stref każdego systemu;
    /// UTC zostaje wyłącznie jako wartość awaryjna, żeby nie wymuszać `!`.
    public static let firmTimeZone: TimeZone = TimeZone(identifier: referenceTimeZone) ?? .gmt

    /// Kalendarz gregoriański w strefie kancelarii. `Calendar` jest wartością,
    /// więc jedna instancja służy wszystkim wątkom.
    public static let firmCalendar: Calendar = gregorian(in: firmTimeZone)

    /// Kalendarz w podanej strefie. Strefa kancelarii nie tworzy nowego kalendarza;
    /// nieznany identyfikator daje strefę kancelarii, a nie strefę telefonu.
    public static func calendar(timeZoneIdentifier: String) -> Calendar {
        guard timeZoneIdentifier != referenceTimeZone,
              let zone = TimeZone(identifier: timeZoneIdentifier) else { return firmCalendar }
        return gregorian(in: zone)
    }

    private static func gregorian(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    // MARK: Znaczniki ISO 8601

    /// Znacznik ISO 8601 z backendu: z milisekundami (`2026-09-14T11:39:09.844Z`,
    /// tak pisze backend) albo bez nich (tak piszą niektórzy dostawcy).
    ///
    /// Wcześniej każde wywołanie tworzyło dwa formatery — także przy mapowaniu
    /// każdej wiadomości i każdego podglądu z listy ~1500 rozmów. Formatery są
    /// współdzielone: Apple dokumentuje `ISO8601DateFormatter` jako bezpieczny
    /// wątkowo, a konfiguracja nie zmienia się po utworzeniu.
    public static func parseISO8601(_ raw: String) -> Date? {
        if let date = iso8601WithFraction.date(from: raw) { return date }
        return iso8601Plain.date(from: raw)
    }

    nonisolated(unsafe) private static let iso8601WithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601Plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

public extension LocalDate {

    /// Dzień kalendarzowy chwili `instant` w strefie kancelarii (albo podanej).
    init(instant: Date, timeZoneIdentifier: String = EmmaTime.referenceTimeZone) {
        let parts = EmmaTime.calendar(timeZoneIdentifier: timeZoneIdentifier)
            .dateComponents([.year, .month, .day], from: instant)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Chwila o podanej godzinie ściennej tego dnia w strefie kancelarii (albo
    /// podanej) — tak rozumie godzinę cała aplikacja, niezależnie od strefy telefonu.
    func instant(hour: Int, minute: Int = 0, timeZoneIdentifier: String = EmmaTime.referenceTimeZone) -> Date? {
        EmmaTime.calendar(timeZoneIdentifier: timeZoneIdentifier).date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))
    }
}
