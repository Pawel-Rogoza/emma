import XCTest
@testable import Emma

// MARK: - Terminy dnia: „minęło”, „trwa” i usuwanie
//
// Ekran „Dzisiaj” wygasza to, co już minęło, i pozwala usunąć termin z menu.
// Oba zachowania mają jedną regułę w rdzeniu, więc testujemy je tutaj, bez
// SwiftUI — a nie przez porównywanie zrzutów ekranu.

final class AgendaTimelineTests: XCTestCase {

    private let day = DemoFixtures.referenceDay

    private func makeEvent(
        hhmm: String,
        durationMinutes: Int,
        status: EventStatus = .confirmed
    ) -> ScheduledEvent {
        ScheduledEvent(
            id: EventID("event-test"),
            clientID: DemoFixtures.olenaID,
            caseID: nil,
            title: "Konsultacja",
            day: day,
            time: TimeOfDay(hhmm: hhmm)!,
            durationMinutes: durationMinutes,
            kind: .consultation,
            status: status,
            place: "Kancelaria"
        )
    }

    private func time(_ hhmm: String) -> TimeOfDay { TimeOfDay(hhmm: hhmm)! }

    // MARK: Odczyt godziny z zegara

    func testTimeOfDayFromInstantUsesWarsawClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: EmmaTime.referenceTimeZone))
        let instant = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 9, minute: 41))
        )
        XCTAssertEqual(TimeOfDay.at(instant).hhmm, "09:41")
    }

    // MARK: „Minęło”

    func testFinishedStatusCountsAsPassedWhateverTheHour() {
        let finished = makeEvent(hhmm: "23:00", durationMinutes: 30, status: .finished)
        XCTAssertTrue(finished.hasPassed(at: time("08:00")), "Status „Zakończona” rozstrzyga sam")
    }

    func testEventPassesOnlyAfterItsEnd() {
        let event = makeEvent(hhmm: "10:00", durationMinutes: 45)
        XCTAssertFalse(event.hasPassed(at: time("09:59")))
        XCTAssertFalse(event.hasPassed(at: time("10:44")), "Trwający termin jeszcze nie minął")
        XCTAssertTrue(event.hasPassed(at: time("10:45")), "Koniec terminu to już „minęło”")
    }

    func testZeroDurationEventPassesAtItsStart() {
        let event = makeEvent(hhmm: "10:00", durationMinutes: 0)
        XCTAssertTrue(event.hasPassed(at: time("10:00")))
    }

    // MARK: „Trwa”

    func testHappeningCoversStartInclusiveAndEndExclusive() {
        let event = makeEvent(hhmm: "10:00", durationMinutes: 45)
        XCTAssertTrue(event.isHappening(at: time("10:00")))
        XCTAssertTrue(event.isHappening(at: time("10:44")))
        XCTAssertFalse(event.isHappening(at: time("10:45")))
        XCTAssertFalse(event.isHappening(at: time("09:59")))
    }

    func testFinishedEventIsNeverHappening() {
        let event = makeEvent(hhmm: "10:00", durationMinutes: 45, status: .finished)
        XCTAssertFalse(event.isHappening(at: time("10:10")))
    }

    // MARK: Usuwanie terminu

    func testDeletingEventRemovesItFromTheDay() async throws {
        let repository = MockRepository(clock: DemoClock(), artificialLatency: 0)
        let before = try await repository.events(in: .day(day))
        let victim = try XCTUnwrap(before.first, "Dane demo powinny mieć termin tego dnia")

        try await repository.deleteEvent(id: victim.id, expectedVersion: victim.version)

        let after = try await repository.events(in: .day(day))
        XCTAssertEqual(after.count, before.count - 1)
        XCTAssertFalse(after.contains { $0.id == victim.id })
    }

    func testDeletingEventWithStaleVersionKeepsItInCalendar() async throws {
        let repository = MockRepository(clock: DemoClock(), artificialLatency: 0)
        let before = try await repository.events(in: .day(day))
        let victim = try XCTUnwrap(before.first)

        do {
            try await repository.deleteEvent(id: victim.id, expectedVersion: Version(99))
            XCTFail("Oczekiwano konfliktu wersji")
        } catch {
            // Oczekiwane: nie usuwamy terminu, który zmienił się od czasu odczytu.
        }

        let after = try await repository.events(in: .day(day))
        XCTAssertTrue(after.contains { $0.id == victim.id })
    }

    func testDeletingMissingEventReportsNotFound() async {
        let repository = MockRepository(clock: DemoClock(), artificialLatency: 0)
        do {
            try await repository.deleteEvent(
                id: EventID("event-nie-ma-takiego"),
                expectedVersion: .initial
            )
            XCTFail("Oczekiwano błędu „nie znaleziono”")
        } catch {
            // Oczekiwane.
        }
    }
}
