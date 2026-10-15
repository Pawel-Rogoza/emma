import XCTest
@testable import Emma

// MARK: - Czas kancelarii w jednym miejscu (audyt 16.10.2026)
//
// Strefa `Europe/Warsaw`, zamiana chwili na dzień i godzinę kancelarii oraz
// odczyt znaczników ISO 8601 mają po jednej implementacji (`EmmaTime`). Testy
// pilnują granic, na których kopie potrafiły się różnić: północ w UTC, zmiana
// czasu i znaczniki z milisekundami i bez nich.

final class FirmTimeTests: XCTestCase {

    func testInstantLateInUTCBelongsToNextWarsawDay() throws {
        // 22:30Z 12 września = 00:30 13 września w Warszawie (CEST, +2).
        let instant = try XCTUnwrap(EmmaTime.parseISO8601("2026-09-12T22:30:00.000Z"))
        XCTAssertEqual(LocalDate(instant: instant), LocalDate(year: 2026, month: 9, day: 13))
        XCTAssertEqual(TimeOfDay.at(instant), TimeOfDay(hhmm: "00:30"))
    }

    func testWallClockHourSurvivesDaylightSavingChange() throws {
        // 25 października 2026 zegary cofają się o godzinę — południe to 11:00Z, nie 10:00Z.
        let day = LocalDate(year: 2026, month: 10, day: 25)
        let noon = try XCTUnwrap(day.instant(hour: 12))
        XCTAssertEqual(noon, EmmaTime.parseISO8601("2026-10-25T11:00:00Z"))
        XCTAssertEqual(LocalDate(instant: noon), day)
        XCTAssertEqual(TimeOfDay.at(noon), TimeOfDay(hhmm: "12:00"))

        // Dzień wcześniej obowiązuje jeszcze czas letni.
        let summerNoon = try XCTUnwrap(day.adding(days: -1).instant(hour: 12, minute: 15))
        XCTAssertEqual(summerNoon, EmmaTime.parseISO8601("2026-10-24T10:15:00Z"))
    }

    func testISO8601AcceptsBackendAndProviderVariants() throws {
        let withMillis = try XCTUnwrap(EmmaTime.parseISO8601("2026-09-14T11:39:09.844Z"))
        let plain = try XCTUnwrap(EmmaTime.parseISO8601("2026-09-14T11:39:09Z"))
        XCTAssertEqual(EmmaTime.parseISO8601("2026-09-14T13:39:09+02:00"), plain)
        XCTAssertEqual(withMillis.timeIntervalSince(plain), 0.844, accuracy: 0.001)
        XCTAssertNil(EmmaTime.parseISO8601("2026-09-14"))
        XCTAssertNil(EmmaTime.parseISO8601("wczoraj"))
    }

    func testUnknownTimeZoneFallsBackToFirmZoneNotPhoneZone() {
        XCTAssertEqual(EmmaTime.calendar(timeZoneIdentifier: "Nie/Istnieje").timeZone, EmmaTime.firmTimeZone)
        XCTAssertEqual(EmmaTime.firmTimeZone.identifier, EmmaTime.referenceTimeZone)
        XCTAssertEqual(EmmaTime.firmCalendar.timeZone, EmmaTime.firmTimeZone)
    }
}
