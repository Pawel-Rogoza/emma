import XCTest
@testable import Emma

/// Terminy procesowe: dzień zdarzenia się nie liczy, sobota i dzień ustawowo
/// wolny przesuwają koniec terminu na najbliższy dzień roboczy.
final class ProceduralDeadlinesTests: XCTestCase {

    private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: year, month: month, day: day)
    }

    func testEasterDates() {
        XCTAssertEqual(PolishHolidays.easterSunday(year: 2025), day(2025, 4, 20))
        XCTAssertEqual(PolishHolidays.easterSunday(year: 2026), day(2026, 4, 5))
        XCTAssertEqual(PolishHolidays.easterSunday(year: 2027), day(2027, 3, 28))
    }

    func testMovableHolidays2026() {
        XCTAssertTrue(PolishHolidays.isHoliday(day(2026, 4, 6)), "Poniedziałek Wielkanocny")
        XCTAssertTrue(PolishHolidays.isHoliday(day(2026, 6, 4)), "Boże Ciało")
        XCTAssertEqual(PolishHolidays.name(of: day(2026, 6, 4)), "Boże Ciało")
        XCTAssertFalse(PolishHolidays.isHoliday(day(2026, 6, 5)))
    }

    func testChristmasEveIsHolidayFrom2025() {
        XCTAssertFalse(PolishHolidays.isHoliday(day(2024, 12, 24)))
        XCTAssertTrue(PolishHolidays.isHoliday(day(2025, 12, 24)))
    }

    func testEventDayIsNotCounted() {
        // Doręczenie w poniedziałek 14.09.2026 → 7 dni kończy się w poniedziałek 21.09.
        let result = ProceduralDeadlines.due(from: day(2026, 9, 14), days: 7)
        XCTAssertEqual(result.due, day(2026, 9, 21))
        XCTAssertFalse(result.isShifted)
        XCTAssertNil(result.shiftReason)
    }

    func testSaturdayMovesToMonday() {
        // Doręczenie w sobotę 26.09.2026 + 14 dni = sobota 10.10 → poniedziałek 12.10.
        let result = ProceduralDeadlines.due(from: day(2026, 9, 26), days: 14)
        XCTAssertEqual(result.nominal, day(2026, 10, 10))
        XCTAssertEqual(result.due, day(2026, 10, 12))
        XCTAssertEqual(result.shiftReason, "sobota")
    }

    func testHolidayChainMovesPastAllFreeDays() {
        // 24.12.2026 (czwartek, Wigilia) → 25 i 26 święta, 27 niedziela → poniedziałek 28.12.
        let result = ProceduralDeadlines.due(from: day(2026, 12, 17), days: 7)
        XCTAssertEqual(result.nominal, day(2026, 12, 24))
        XCTAssertEqual(result.due, day(2026, 12, 28))
        XCTAssertEqual(result.shiftReason, "Wigilia")
    }

    func testAllSaintsDay() {
        // 1.11.2026 to niedziela i święto — nazwa święta ważniejsza niż dzień tygodnia.
        let result = ProceduralDeadlines.due(from: day(2026, 10, 18), days: 14)
        XCTAssertEqual(result.due, day(2026, 11, 2))
        XCTAssertEqual(result.shiftReason, "Wszystkich Świętych")
    }

    func testCommonRulesAreDistinctAndPositive() {
        let rules = ProceduralDeadlines.common
        XCTAssertEqual(Set(rules.map(\.id)).count, rules.count)
        XCTAssertTrue(rules.allSatisfy { !$0.legalBasis.isEmpty && !$0.startsFrom.isEmpty })
        XCTAssertEqual(rules.first { $0.id == "kpk-apelacja" }?.span, .days(14))
        XCTAssertEqual(rules.first { $0.id == "kpk-apelacja" }?.spanText, "14 dni")
    }

    func testDetentionRunsByTheHourThroughWeekends() {
        let rule = ProceduralDeadlines.common.first { $0.id == "kpk-zatrzymanie-48" }
        XCTAssertEqual(rule?.span, .hours(48))
        XCTAssertEqual(rule?.isHourly, true)
        XCTAssertEqual(rule?.spanText, "48 h")
        // Zatrzymanie w piątek o 22:30 → niedziela 22:30, bez przesunięcia na poniedziałek.
        let arrest = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(ProceduralDeadlines.due(from: arrest, hours: 48).timeIntervalSince(arrest), 48 * 3600)
        XCTAssertEqual(ProceduralDeadlines.common.first { $0.id == "kpk-zatrzymanie-72" }?.span, .hours(72))
    }
}
