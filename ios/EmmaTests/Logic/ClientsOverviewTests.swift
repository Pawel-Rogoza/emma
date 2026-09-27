import XCTest
@testable import Emma

// MARK: - Ekran „Klienci”: pilność spraw, kartoteka, kolor osoby
//
// Review właściciela z 27.09.2026: sprawy i klienci „zlewali się”. Reguły,
// które je rozróżniają, są w rdzeniu (`ClientsOverview.swift`), więc
// testujemy je tutaj, bez SwiftUI.

final class ClientsOverviewTests: XCTestCase {

    private let today = LocalDate(iso: "2026-09-27")!

    private func legalCase(_ id: String, title: String? = nil, status: CaseStatus = .inProgress) -> LegalCase {
        LegalCase(
            id: CaseID(id),
            number: "KAN/2026/\(id)",
            title: title ?? "Sprawa \(id)",
            clientID: ClientID("c-\(id)"),
            status: status,
            summary: "",
            createdAt: today
        )
    }

    private func event(_ caseID: String, inDays days: Int) -> ScheduledEvent {
        ScheduledEvent(
            id: EventID("e-\(caseID)"),
            clientID: ClientID("c-\(caseID)"),
            caseID: CaseID(caseID),
            title: "Termin",
            day: today.adding(days: days),
            time: TimeOfDay(hhmm: "10:00")!,
            durationMinutes: 60,
            kind: .caseDeadline,
            status: .confirmed,
            place: "",
            isAllDay: false
        )
    }

    private func client(_ id: String, name: String) -> Client {
        Client(
            id: ClientID(id),
            displayName: name,
            initials: String(name.prefix(2)).uppercased(),
            language: .uk,
            topic: "",
            stage: .client,
            source: .manual,
            createdAt: today,
            briefing: ""
        )
    }

    // MARK: Pilność

    func testUrgencyLevelsFollowDaysToNextEvent() {
        XCTAssertEqual(CaseUrgency(nextEvent: today, overdueTasks: 0, today: today).level, .urgent)
        XCTAssertEqual(CaseUrgency(nextEvent: today.adding(days: 3), overdueTasks: 0, today: today).level, .urgent)
        XCTAssertEqual(CaseUrgency(nextEvent: today.adding(days: 4), overdueTasks: 0, today: today).level, .soon)
        XCTAssertEqual(CaseUrgency(nextEvent: today.adding(days: 7), overdueTasks: 0, today: today).level, .soon)
        XCTAssertEqual(CaseUrgency(nextEvent: today.adding(days: 8), overdueTasks: 0, today: today).level, .calm)
        XCTAssertEqual(CaseUrgency(nextEvent: nil, overdueTasks: 0, today: today).level, .calm)
    }

    func testCountdownTextIsPolishAndOnlyWithinAWeek() {
        XCTAssertEqual(CaseUrgency(nextEvent: today, overdueTasks: 0, today: today).countdownText, "dziś")
        XCTAssertEqual(CaseUrgency(nextEvent: today.adding(days: 1), overdueTasks: 0, today: today).countdownText, "jutro")
        XCTAssertEqual(CaseUrgency(nextEvent: today.adding(days: 2), overdueTasks: 0, today: today).countdownText, "za 2 dni")
        XCTAssertEqual(CaseUrgency(nextEvent: today.adding(days: 5), overdueTasks: 0, today: today).countdownText, "za 5 dni")
        XCTAssertNil(CaseUrgency(nextEvent: today.adding(days: 12), overdueTasks: 0, today: today).countdownText)
    }

    func testOverdueTaskAloneNeedsAttention() {
        let urgency = CaseUrgency(nextEvent: nil, overdueTasks: 1, today: today)
        XCTAssertTrue(urgency.needsAttention)
        XCTAssertEqual(urgency.level, .calm)
    }

    // MARK: Grupy spraw

    func testBoardSplitsActiveCasesIntoThreeGroupsAndSkipsClosed() {
        let cases = [
            legalCase("1"),                                  // termin za 10 dni → W toku
            legalCase("2"),                                  // termin jutro → Wymaga uwagi
            legalCase("3", status: .awaitingClient),         // bez terminu → Czekamy na klienta
            legalCase("4", status: .awaitingClient),         // termin za 2 dni → Wymaga uwagi
            legalCase("5", status: .closed),                 // zamknięta → poza tablicą
            legalCase("6")                                   // zaległe zadanie → Wymaga uwagi
        ]
        let events = [
            CaseID("1"): event("1", inDays: 10),
            CaseID("2"): event("2", inDays: 1),
            CaseID("4"): event("4", inDays: 2)
        ]
        let board = CaseBoard.make(cases, nextEvents: events, overdueTasks: [CaseID("6"): 2], today: today)

        XCTAssertEqual(board.attention.map(\.id.rawValue), ["2", "4", "6"])
        XCTAssertEqual(board.inProgress.map(\.id.rawValue), ["1"])
        XCTAssertEqual(board.awaitingClient.map(\.id.rawValue), ["3"])
    }

    func testInProgressCasesWithEventComeBeforeCasesWithout() {
        let cases = [legalCase("a", title: "A"), legalCase("b", title: "B"), legalCase("c", title: "C")]
        let events = [CaseID("c"): event("c", inDays: 20), CaseID("b"): event("b", inDays: 9)]
        let board = CaseBoard.make(cases, nextEvents: events, overdueTasks: [:], today: today)
        XCTAssertEqual(board.inProgress.map(\.id.rawValue), ["b", "c", "a"])
    }

    // MARK: Kartoteka

    func testDirectorySortsPolishNamesIntoLetterSections() {
        let clients = [
            client("1", name: "Łukasz Nowak"),
            client("2", name: "Andrii Melnyk"),
            client("3", name: "Lena Bondar"),
            client("4", name: "anna Kowal")
        ]
        let sections = ClientDirectory.sections(clients)
        XCTAssertEqual(sections.map(\.letter), ["A", "L", "Ł"])
        XCTAssertEqual(sections[0].clients.map(\.displayName), ["Andrii Melnyk", "anna Kowal"])
    }

    func testDirectoryPutsNamesWithoutLetterUnderHash() {
        XCTAssertEqual(ClientDirectory.sectionLetter("  "), "#")
        XCTAssertEqual(ClientDirectory.sectionLetter("123 Sp. z o.o."), "#")
        XCTAssertEqual(ClientDirectory.sectionLetter("ołena"), "O")
    }

    // MARK: Kolor osoby i język

    func testIdentityToneIsStableAndInRange() {
        let id = ClientID("client-42")
        let first = IdentityTone.index(for: id)
        XCTAssertEqual(first, IdentityTone.index(for: ClientID("client-42")))
        XCTAssertTrue((0..<IdentityTone.count).contains(first))

        // Różne osoby nie dostają jednego koloru — przy kilkudziesięciu
        // identyfikatorach pojawiają się wszystkie tony palety.
        let tones = Set((1...60).map { IdentityTone.index(for: ClientID("lead-\($0)")) })
        XCTAssertEqual(tones.count, IdentityTone.count)
    }

    func testLanguageBadgeCodes() {
        XCTAssertEqual(LanguageCode.uk.badgeCode, "UA")
        XCTAssertEqual(LanguageCode.ru.badgeCode, "RU")
        XCTAssertEqual(LanguageCode.pl.badgeCode, "PL")
    }

    // MARK: Ostatnio otwierani

    func testRecentClientsMoveToFrontWithoutDuplicatesAndCap() {
        var recent = RecentClients()
        for index in 1...10 {
            recent.record(ClientID("c\(index)"))
        }
        recent.record(ClientID("c5"))
        XCTAssertEqual(recent.ids.count, RecentClients.limit)
        XCTAssertEqual(recent.ids.first, ClientID("c5"))
        XCTAssertEqual(recent.ids.filter { $0 == ClientID("c5") }.count, 1)
        XCTAssertFalse(recent.ids.contains(ClientID("c1")))
    }
}
