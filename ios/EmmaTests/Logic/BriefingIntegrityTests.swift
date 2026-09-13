import XCTest
@testable import Emma

// MARK: - Briefing: „pusto” to nie to samo co „nie udało się sprawdzić” (F02)
//
// Awaria odczytu kalendarza albo listy zadań nie może dać odpowiedzi „nie masz
// terminów”. Test pilnuje rozróżnienia: `nil` znaczy błąd odczytu, `[]` znaczy
// sprawdzone i puste.

final class BriefingIntegrityTests: XCTestCase {

    private let day = DemoFixtures.referenceDay

    private func event(_ hhmm: String, status: EventStatus = .confirmed) -> ScheduledEvent {
        ScheduledEvent(
            id: EventID("event-briefing"),
            clientID: DemoFixtures.olenaID,
            caseID: nil,
            title: "Konsultacja",
            day: day,
            time: TimeOfDay(hhmm: hhmm)!,
            durationMinutes: 30,
            kind: .consultation,
            status: status,
            place: "Kancelaria"
        )
    }

    private func task(_ title: String) -> TaskItem {
        TaskItem(
            id: TaskID("task-briefing"),
            title: title,
            clientID: nil,
            caseID: nil,
            dueDate: day,
            isDone: false,
            priority: .normal
        )
    }

    private func briefing(events: [ScheduledEvent]?, tasks: [TaskItem]?) -> String {
        EmmaBriefing.briefing(
            events: events,
            tasks: tasks,
            waitingForReply: [],
            clientNames: [DemoFixtures.olenaID: "Olena"]
        )
    }

    func testCompleteDataListsEventsAndTasks() {
        let text = briefing(events: [event("10:00")], tasks: [task("Wysłać dokumenty")])
        XCTAssertTrue(text.contains("Dzisiaj w zespole: 1 wydarzenie."))
        XCTAssertTrue(text.contains("10:00: Olena, Konsultacja."))
        XCTAssertTrue(text.contains("Do załatwienia: Wysłać dokumenty."))
        XCTAssertFalse(text.contains("Nie udało się sprawdzić"))
    }

    func testEmptyMonthIsReportedAsEmptyNotAsFailure() {
        let text = briefing(events: [], tasks: [])
        XCTAssertTrue(text.contains("Dzisiaj w zespole: 0 wydarzeń."))
        XCTAssertTrue(text.contains("brak otwartych zadań na dziś"))
        XCTAssertFalse(text.contains("Nie udało się sprawdzić"))
    }

    func testCalendarReadFailureIsNamedExplicitly() {
        let text = briefing(events: nil, tasks: [])
        XCTAssertTrue(text.contains("Nie udało się sprawdzić kalendarza"))
        XCTAssertFalse(text.contains("0 wydarzeń"), "Błąd odczytu nie może wyglądać jak pusty dzień")
    }

    func testTaskReadFailureIsNamedExplicitly() {
        let text = briefing(events: [], tasks: nil)
        XCTAssertTrue(text.contains("Nie udało się sprawdzić listy zadań"))
        XCTAssertFalse(text.contains("brak otwartych zadań"))
    }

    func testBothReadFailuresAreReportedWithoutClaimingFreeDay() {
        let text = briefing(events: nil, tasks: nil)
        XCTAssertTrue(text.contains("Nie udało się sprawdzić kalendarza"))
        XCTAssertTrue(text.contains("Nie udało się sprawdzić listy zadań"))
        XCTAssertFalse(text.contains("Wolny termin"))
    }
}
