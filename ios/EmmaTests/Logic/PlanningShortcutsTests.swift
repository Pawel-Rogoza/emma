import XCTest
@testable import Emma

final class PlanningShortcutsTests: XCTestCase {

    private func day(_ iso: String) -> LocalDate { LocalDate(iso: iso)! }

    // MARK: Skróty dnia

    func testShortcutsOnFridayIncludeNextMonday() {
        // 9.10.2026 to piątek — poniedziałek wypada za 3 dni.
        let days = PlanningShortcuts.days(today: day("2026-10-09"))
        XCTAssertEqual(days.map(\.title), ["Dziś", "Jutro", "Pojutrze", "W poniedziałek", "Za tydzień", "Za 2 tyg."])
        XCTAssertEqual(days[3].date, day("2026-10-12"))
    }

    func testShortcutsSkipMondayWhenItIsAnotherShortcut() {
        // Sobota: poniedziałek to „pojutrze”. Poniedziałek: to „za tydzień”.
        XCTAssertFalse(PlanningShortcuts.days(today: day("2026-10-10")).map(\.title).contains("W poniedziałek"))
        XCTAssertFalse(PlanningShortcuts.days(today: day("2026-10-12")).map(\.title).contains("W poniedziałek"))
        XCTAssertFalse(PlanningShortcuts.days(today: day("2026-10-11")).map(\.title).contains("W poniedziałek"))
    }

    func testShortcutDatesAreUnique() {
        for offset in 0..<7 {
            let today = day("2026-10-05").adding(days: offset)
            let dates = PlanningShortcuts.days(today: today).map(\.date)
            XCTAssertEqual(Set(dates).count, dates.count, "Powtórzona data dla \(today.isoString)")
        }
    }

    // MARK: Opis i ostrzeżenia

    func testRelativeText() {
        let today = day("2026-10-11")
        XCTAssertEqual(PlanningShortcuts.relative(today, today: today), "dziś")
        XCTAssertEqual(PlanningShortcuts.relative(day("2026-10-12"), today: today), "jutro")
        XCTAssertEqual(PlanningShortcuts.relative(day("2026-10-13"), today: today), "pojutrze")
        XCTAssertEqual(PlanningShortcuts.relative(day("2026-10-16"), today: today), "za 5 dni")
        XCTAssertEqual(PlanningShortcuts.relative(day("2026-10-18"), today: today), "za tydzień")
        XCTAssertEqual(PlanningShortcuts.relative(day("2026-10-25"), today: today), "za 2 tygodnie")
        XCTAssertEqual(PlanningShortcuts.relative(day("2026-10-10"), today: today), "wczoraj")
        XCTAssertEqual(PlanningShortcuts.relative(day("2026-10-08"), today: today), "3 dni temu")
    }

    func testWarningForWeekendHolidayAndPast() {
        let today = day("2026-10-09")
        XCTAssertNil(PlanningShortcuts.warning(for: day("2026-10-12"), today: today))
        XCTAssertEqual(PlanningShortcuts.warning(for: day("2026-10-10"), today: today), "To sobota.")
        XCTAssertEqual(PlanningShortcuts.warning(for: day("2026-10-11"), today: today), "To niedziela.")
        XCTAssertEqual(PlanningShortcuts.warning(for: day("2026-11-11"), today: today), "To dzień wolny: Święto Niepodległości.")
        XCTAssertEqual(PlanningShortcuts.warning(for: day("2026-10-08"), today: today), "Ta data już minęła.")
    }
}
