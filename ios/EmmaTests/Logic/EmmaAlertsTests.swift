import XCTest
@testable import Emma

// Emma proaktywna (Etap 3 audytu 11.10.2026): które alerty serwera zamienić
// w powiadomienie.
final class EmmaAlertsTests: XCTestCase {

    private func alert(_ id: String, priority: Int = 2) -> EmmaAlert {
        EmmaAlert(id: id, kind: .leadWaiting, priority: priority, title: "T", body: "B", prompt: "P")
    }

    func testFirstCheckOnlyRemembers() {
        let outcome = EmmaAlertPlan.check(alerts: [alert("a"), alert("b")], known: nil)
        XCTAssertEqual(outcome.notify, [])
        XCTAssertEqual(outcome.known, ["a", "b"])
    }

    func testNotifiesOnlyNewMostUrgentFirstWithLimit() {
        let alerts = [alert("old"), alert("n1", priority: 2), alert("n2", priority: 1), alert("n3", priority: 3), alert("n4", priority: 2)]
        let outcome = EmmaAlertPlan.check(alerts: alerts, known: ["old"], limit: 3)
        XCTAssertEqual(outcome.notify.map(\.id), ["n2", "n1", "n4"])
        XCTAssertEqual(Set(outcome.known), ["old", "n1", "n2", "n3", "n4"])
        // Drugie sprawdzenie z tym samym stanem — cisza.
        XCTAssertEqual(EmmaAlertPlan.check(alerts: alerts, known: outcome.known).notify, [])
    }

    func testMemoryIsBounded() {
        let known = (0..<EmmaAlertPlan.memory).map { "k\($0)" }
        let outcome = EmmaAlertPlan.check(alerts: [alert("fresh")], known: known)
        XCTAssertEqual(outcome.known.count, EmmaAlertPlan.memory)
        XCTAssertEqual(outcome.known.first, "fresh")
    }
}
