import XCTest
@testable import Emma

final class MorningBriefTests: XCTestCase {

    private let today = LocalDate(iso: "2026-09-11")!

    private func event(_ id: String, day: LocalDate, at hhmm: String, status: EventStatus = .confirmed) -> ScheduledEvent {
        ScheduledEvent(
            id: EventID(id), clientID: nil, caseID: nil, title: "T\(id)", day: day,
            time: TimeOfDay(hhmm: hhmm)!, durationMinutes: 30, kind: .consultation,
            status: status, place: "", isAllDay: false
        )
    }

    private func at(_ day: LocalDate, hour: Int) -> Date {
        MorningBrief.instant(day: day, timeZoneIdentifier: EmmaTime.referenceTimeZone)!
            .addingTimeInterval(TimeInterval((hour - MorningBrief.hour) * 3600))
    }

    func testTodayBriefBeforeEightListsEventsAndMissed() {
        let events = [event("2", day: today, at: "12:00"), event("1", day: today, at: "10:30")]
        let items = MorningBrief.items(events: events, missedDeadlines: 1, today: today, now: at(today, hour: 6))
        XCTAssertEqual(items.first?.day, today)
        XCTAssertEqual(items.first?.title, "Dziś 2 terminy")
        XCTAssertEqual(items.first?.body, "10:30 T1, 12:00 T2 · ⚠︎ 1 termin po terminie")
    }

    func testAfterEightStartsTomorrowAndSkipsEmptyDays() {
        let tomorrow = today.adding(days: 1)
        let events = [
            event("a", day: today, at: "15:00"),
            event("b", day: tomorrow, at: "09:00"),
            event("c", day: today.adding(days: 3), at: "09:00", status: .finished)
        ]
        let items = MorningBrief.items(events: events, missedDeadlines: 0, today: today, now: at(today, hour: 9))
        XCTAssertEqual(items.map(\.day), [tomorrow])
        XCTAssertEqual(items.first?.identifier, "emma.morning.2026-09-12")
    }

    func testMissedAloneStillBriefsAndLongListIsShortened() {
        XCTAssertEqual(MorningBrief.content([], missed: 2)?.title, "Dziś bez terminów")
        XCTAssertNil(MorningBrief.content([], missed: 0))
        let many = (1...5).map { event("\($0)", day: today, at: "1\($0):00") }
        XCTAssertEqual(MorningBrief.content(many, missed: 0)?.body, "11:00 T1, 12:00 T2, 13:00 T3 i 2 więcej")
    }
}
