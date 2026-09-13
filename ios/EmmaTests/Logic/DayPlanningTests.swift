import XCTest
@testable import Emma

// MARK: - Etap 3: podział dnia i grupowanie zadań
//
// „Dzisiaj” ma pokazać najbliższy termin osobno, a minione schować do zwijanej
// sekcji; zadania mają być pogrupowane na zaległe i bieżące. Oba zachowania to
// reguły rdzenia, więc sprawdzamy je bez SwiftUI.

// MARK: Najbliższy termin i minione

final class DayAgendaTests: XCTestCase {

    private let day = DemoFixtures.referenceDay

    private func event(_ id: String, _ hhmm: String, minutes: Int = 30, status: EventStatus = .confirmed) -> ScheduledEvent {
        ScheduledEvent(
            id: EventID(id),
            clientID: DemoFixtures.olenaID,
            caseID: nil,
            title: "Termin \(id)",
            day: day,
            time: TimeOfDay(hhmm: hhmm)!,
            durationMinutes: minutes,
            kind: .consultation,
            status: status,
            place: "Kancelaria"
        )
    }

    private func time(_ hhmm: String) -> TimeOfDay { TimeOfDay(hhmm: hhmm)! }

    func testNextIsFirstEventThatHasNotFinished() {
        let split = DayAgenda.split(
            [event("a", "09:00"), event("b", "12:00"), event("c", "15:00")],
            now: time("11:00")
        )
        XCTAssertEqual(split.next?.id, EventID("b"))
        XCTAssertEqual(split.upcoming.map(\.id), [EventID("c")])
        XCTAssertEqual(split.past.map(\.id), [EventID("a")])
    }

    func testOngoingEventIsNextNotEmpty() {
        // Termin trwa (10:00–10:30), a nie minął — musi być najbliższy.
        let split = DayAgenda.split(
            [event("ongoing", "10:00", minutes: 30), event("later", "13:00")],
            now: time("10:15")
        )
        XCTAssertEqual(split.next?.id, EventID("ongoing"))
        XCTAssertEqual(split.past.count, 0)
    }

    func testEventsAreOrderedByTimeEvenWhenInputIsShuffled() {
        let split = DayAgenda.split(
            [event("late", "16:00"), event("early", "09:00"), event("mid", "12:00")],
            now: time("08:00")
        )
        XCTAssertEqual(split.next?.id, EventID("early"))
        XCTAssertEqual(split.upcoming.map(\.id), [EventID("mid"), EventID("late")])
    }

    func testFinishedStatusCountsAsPastRegardlessOfHour() {
        let split = DayAgenda.split(
            [event("finished", "23:00", status: .finished)],
            now: time("08:00")
        )
        XCTAssertNil(split.next)
        XCTAssertEqual(split.past.map(\.id), [EventID("finished")])
    }

    func testEmptyDayHasNoNext() {
        let split = DayAgenda.split([], now: time("12:00"))
        XCTAssertNil(split.next)
        XCTAssertTrue(split.upcoming.isEmpty)
        XCTAssertTrue(split.past.isEmpty)
    }
}

// MARK: Grupowanie zadań

final class TaskGroupingTests: XCTestCase {

    private let today = DemoFixtures.referenceDay

    private func task(_ id: String, offsetDays: Int) -> TaskItem {
        TaskItem(
            id: TaskID(id),
            title: "Zadanie \(id)",
            clientID: nil,
            caseID: nil,
            dueDate: today.adding(days: offsetDays),
            isDone: false,
            priority: .normal
        )
    }

    func testGroupsSplitOverdueTodayAndLaterKeepingOrder() {
        let groups = TaskGrouping.groups(
            [task("overdue-1", offsetDays: -3), task("today-1", offsetDays: 0),
             task("later-1", offsetDays: 4), task("overdue-2", offsetDays: -1),
             task("today-2", offsetDays: 0)],
            today: today
        )

        XCTAssertEqual(groups.map(\.bucket), [.overdue, .today, .later])
        XCTAssertEqual(groups[0].tasks.map(\.id), [TaskID("overdue-1"), TaskID("overdue-2")])
        XCTAssertEqual(groups[1].tasks.map(\.id), [TaskID("today-1"), TaskID("today-2")])
        XCTAssertEqual(groups[2].tasks.map(\.id), [TaskID("later-1")])
    }

    func testEmptyBucketsDisappear() {
        let groups = TaskGrouping.groups([task("today", offsetDays: 0)], today: today)
        XCTAssertEqual(groups.map(\.bucket), [.today])
    }

    func testSummaryCountsOpenAndOverdue() {
        let summary = TaskGrouping.summary(
            [task("a", offsetDays: -2), task("b", offsetDays: 0), task("c", offsetDays: -1)],
            today: today
        )
        XCTAssertEqual(summary.open, 3)
        XCTAssertEqual(summary.overdue, 2)
        XCTAssertTrue(summary.hasOverdue)
    }

    func testSummaryWithoutOverdue() {
        let summary = TaskGrouping.summary([task("a", offsetDays: 0)], today: today)
        XCTAssertEqual(summary.open, 1)
        XCTAssertEqual(summary.overdue, 0)
        XCTAssertFalse(summary.hasOverdue)
    }

    /// Polska liczba mnoga dla zaległych zadań — etykieta trafia do nagłówka sekcji.
    func testOverdueLabelUsesPolishPlural() {
        XCTAssertEqual(EmmaPlural.overdueTasks(1), "1 zaległe zadanie")
        XCTAssertEqual(EmmaPlural.overdueTasks(3), "3 zaległe zadania")
        XCTAssertEqual(EmmaPlural.overdueTasks(5), "5 zaległych zadań")
        XCTAssertEqual(EmmaPlural.overdueTasks(12), "12 zaległych zadań")
    }
}
