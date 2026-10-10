import XCTest
@testable import Emma

final class WorkRemindersTests: XCTestCase {

    private func task(
        _ id: String,
        due: String?,
        done: Bool = false,
        priority: TaskPriority = .normal,
        clientID: ClientID? = nil
    ) -> TaskItem {
        TaskItem(
            id: TaskID(id), title: "Zadanie \(id)", clientID: clientID, caseID: nil,
            dueDate: due.flatMap { LocalDate(iso: $0) }, isDone: done, priority: priority
        )
    }

    // MARK: Zadania

    func testTaskReminderFiresAtNineInFirmTimeZone() {
        let items = TaskReminderPlan.items(
            tasks: [task("t1", due: "2026-10-12", priority: .urgent, clientID: ClientID("c1"))],
            clientNames: [ClientID("c1"): "Maria Kowalska"],
            now: ISO8601DateFormatter().date(from: "2026-10-10T12:00:00Z")!
        )
        XCTAssertEqual(items.count, 1)
        // 9:00 w Warszawie (CEST) = 07:00 UTC.
        XCTAssertEqual(items[0].fireAt, ISO8601DateFormatter().date(from: "2026-10-12T07:00:00Z"))
        XCTAssertEqual(items[0].title, "Zadanie t1")
        XCTAssertEqual(items[0].body, "Pilne zadanie na dziś · Maria Kowalska")
        XCTAssertEqual(items[0].identifier, "emma.task.t1")
    }

    func testTaskReminderSkipsDoneUndatedPastAndCapsLimit() {
        let now = ISO8601DateFormatter().date(from: "2026-10-10T08:00:00Z")!
        let items = TaskReminderPlan.items(
            tasks: [
                task("done", due: "2026-10-12", done: true),
                task("undated", due: nil),
                task("today-past", due: "2026-10-10"),   // 9:00 już minęła
                task("later", due: "2026-10-14"),
                task("soon", due: "2026-10-11"),
            ],
            clientNames: [:],
            now: now,
            limit: 1
        )
        XCTAssertEqual(items.map(\.taskID.rawValue), ["soon"])
    }

    // MARK: Leady

    private func lead(_ id: String, topic: String = "Karta pobytu") -> LeadAlertPlan.Lead {
        LeadAlertPlan.Lead(id: id, name: "Osoba \(id)", topic: topic)
    }

    func testFirstLeadCheckOnlyRemembers() {
        let outcome = LeadAlertPlan.check(leads: [lead("a"), lead("b")], known: nil)
        XCTAssertTrue(outcome.alerts.isEmpty)
        XCTAssertEqual(outcome.known, ["a", "b"])
    }

    func testNewLeadAlertsOnceAndKeepsFormerLeads() {
        let outcome = LeadAlertPlan.check(leads: [lead("a"), lead("c", topic: " ")], known: ["a", "b"])
        XCTAssertEqual(outcome.alerts.map(\.identifier), ["emma.lead.c"])
        XCTAssertEqual(outcome.alerts.first?.title, "Nowy lead: Osoba c")
        XCTAssertEqual(outcome.alerts.first?.body, "Nowe zgłoszenie w „Nowych”")
        // „b” wyszedł z „Nowych”, ale zostaje zapamiętany.
        XCTAssertEqual(outcome.known, ["a", "b", "c"])
        XCTAssertTrue(LeadAlertPlan.check(leads: [lead("a"), lead("c")], known: outcome.known).alerts.isEmpty)
    }

    func testManyNewLeadsGiveOneSummary() {
        let outcome = LeadAlertPlan.check(leads: (1...5).map { lead("\($0)") }, known: [])
        XCTAssertEqual(outcome.alerts.count, 1)
        XCTAssertEqual(outcome.alerts[0].title, "Nowe leady: 5")
        XCTAssertTrue(outcome.alerts[0].identifier.hasPrefix("emma.lead.batch."))
    }
}
