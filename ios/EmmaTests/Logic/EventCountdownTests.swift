import XCTest
@testable import Emma

final class EventCountdownTests: XCTestCase {

    private let today = LocalDate(iso: "2026-09-11")!

    private func event(at hhmm: String, day: LocalDate? = nil, status: EventStatus = .confirmed, allDay: Bool = false) -> ScheduledEvent {
        ScheduledEvent(
            id: EventID("e"),
            clientID: nil,
            caseID: nil,
            title: "Rozprawa",
            day: day ?? today,
            time: TimeOfDay(hhmm: hhmm)!,
            durationMinutes: 60,
            kind: .caseDeadline,
            status: status,
            place: "",
            isAllDay: allDay
        )
    }

    func testCountdownWording() {
        let now = TimeOfDay(hhmm: "09:00")!
        XCTAssertEqual(event(at: "09:45").countdownText(now: now, today: today), "za 45 min")
        XCTAssertEqual(event(at: "11:00").countdownText(now: now, today: today), "za 2 godz.")
        XCTAssertEqual(event(at: "10:15").countdownText(now: now, today: today), "za 1 godz. 15 min")
        XCTAssertEqual(event(at: "12:30").countdownText(now: now, today: today), "za 3 godz.")
        XCTAssertEqual(event(at: "08:30").countdownText(now: now, today: today), "teraz")
    }

    func testNoCountdownWhenFarPastOrOtherDay() {
        let now = TimeOfDay(hhmm: "09:00")!
        XCTAssertNil(event(at: "16:00").countdownText(now: now, today: today))
        XCTAssertNil(event(at: "07:00").countdownText(now: now, today: today))
        XCTAssertNil(event(at: "10:00", day: today.adding(days: 1)).countdownText(now: now, today: today))
        XCTAssertNil(event(at: "10:00", status: .finished).countdownText(now: now, today: today))
        XCTAssertNil(event(at: "10:00", allDay: true).countdownText(now: now, today: today))
    }
}
