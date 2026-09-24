import XCTest
@testable import Emma

// MARK: - Etap 1: wiarygodność (F01, F03, F11)
//
// Testy warstwy SwiftUI. Leżą w `EmmaTests/App`, a nie w `EmmaTests/Logic`, bo
// `CalendarStore`, `MessagesStore` i `AssistantStore` należą do targetu aplikacji
// i nie wchodzą do pakietu `swift test` (patrz `Package.swift`).

@MainActor
final class Stage1ReliabilityTests: XCTestCase {

    // MARK: F01 — wybór dnia przetrwa odświeżenie

    func testCalendarKeepsSelectedDayAcrossReload() async {
        let dependencies = AppDependencies.demo()
        let store = CalendarStore()

        await store.load(dependencies)
        XCTAssertTrue(store.phase.hasLoaded, "Pierwsze wczytanie musi się udać na danych demo")

        let saturday = dependencies.today.adding(days: 5)
        await store.select(saturday, dependencies: dependencies)
        XCTAssertEqual(store.selectedDay, saturday)

        // Odświeżenie (np. po zmianie danych) nie może cofnąć wyboru do „dzisiaj”.
        await store.load(dependencies)
        XCTAssertEqual(store.selectedDay, saturday, "Odświeżenie nie może resetować wybranego dnia")
    }

    func testCalendarKeepsMonthOffsetAcrossReload() async {
        let dependencies = AppDependencies.demo()
        let store = CalendarStore()

        await store.load(dependencies)
        await store.shift(by: 1, dependencies: dependencies)
        let shiftedMonth = store.visibleMonth
        let shiftedDay = store.selectedDay
        XCTAssertEqual(shiftedMonth, dependencies.today.firstOfMonth.addingMonths(1))

        await store.load(dependencies)

        XCTAssertEqual(store.visibleMonth, shiftedMonth, "Przesunięcie miesiąca nie może wrócić do bieżącego")
        XCTAssertEqual(store.selectedDay, shiftedDay)
    }

    func testCalendarWeekModeShiftsByWeek() async {
        let dependencies = AppDependencies.demo()
        let store = CalendarStore()

        await store.load(dependencies)
        await store.setMode(.week, dependencies: dependencies)
        await store.shift(by: 1, dependencies: dependencies)
        XCTAssertEqual(store.selectedDay, dependencies.today.adding(days: 7))
        XCTAssertEqual(store.phase.value?.days.first, dependencies.today.adding(days: 7).startOfWeekMonday)
    }

    func testCalendarMonthGridHasSixWeeksStartingMonday() async {
        let dependencies = AppDependencies.demo()
        let store = CalendarStore()

        await store.load(dependencies)
        let days = store.phase.value?.days ?? []
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first?.weekdayIndexMondayFirst, 0)
        XCTAssertTrue(days.contains(dependencies.today))
    }

    func testCalendarBackToTodayResetsSelection() async {
        let dependencies = AppDependencies.demo()
        let store = CalendarStore()

        await store.load(dependencies)
        await store.select(dependencies.today.adding(days: 21), dependencies: dependencies)
        await store.backToToday(dependencies)

        XCTAssertEqual(store.selectedDay, dependencies.today)
        XCTAssertEqual(store.visibleMonth, dependencies.today.firstOfMonth)
    }

    // MARK: F11 — wyczyszczenie wyszukiwania przywraca całą listę

    func testClearingConversationSearchRestoresAllRows() async {
        let dependencies = AppDependencies.demo()
        let store = MessagesStore()

        await store.load(dependencies)
        let allCount = store.phase.value?.rows.count ?? 0
        XCTAssertGreaterThan(allCount, 1, "Dane demo muszą mieć kilka rozmów")

        store.searchText = "zzzz-nie-ma-takiej-osoby"
        await store.applyLocalFilter()
        XCTAssertEqual(store.phase.value?.rows.count, 0)

        store.searchText = ""
        await store.applyLocalFilter()
        XCTAssertEqual(
            store.phase.value?.rows.count,
            allCount,
            "Usunięcie zapytania musi odtworzyć pełny zbiór, a nie filtrować już przefiltrowany"
        )
    }

    func testConversationSearchFiltersByNameWithoutLosingRows() async {
        let dependencies = AppDependencies.demo()
        let store = MessagesStore()

        await store.load(dependencies)
        let allCount = store.phase.value?.rows.count ?? 0
        let sample = store.phase.value?.rows.first?.client.displayName ?? ""
        XCTAssertFalse(sample.isEmpty)

        store.searchText = sample
        await store.applyLocalFilter()
        XCTAssertGreaterThan(store.phase.value?.rows.count ?? 0, 0)

        store.searchText = ""
        await store.applyLocalFilter()
        XCTAssertEqual(store.phase.value?.rows.count, allCount)
    }

    // MARK: F03 — zatwierdzenie tuż po edycji wykonuje widoczną treść

    func testImmediateConfirmAfterEditExecutesVisibleText() async throws {
        let dependencies = AppDependencies.demo()
        let store = AssistantStore()
        store.attach(dependencies)
        await store.reload()

        let created = await store.newAction(kind: .task, clientID: nil, text: "Pierwotna treść")
        let turn = try XCTUnwrap(created)
        let actionID = turn.proposal.id
        let originalVersion = turn.proposal.version

        // Symulacja: użytkownik zmienił tekst w karcie i od razu dotknął „Zapisz”,
        // zanim odroczona rewizja zdążyła dotrzeć do koordynatora.
        await store.confirm(actionID: actionID, text: "Poprawiona treść")

        let action = store.turns.compactMap { turn -> AssistantStore.ActionTurn? in
            if case .action(let value) = turn { return value }
            return nil
        }.first

        // Jedynym powodem, dla którego propozycja ma nową treść, jest rewizja
        // wykonana wewnątrz `confirm` — czyli to ona, a nie stara wersja, poszła dalej.
        XCTAssertEqual(action?.proposal.text, "Poprawiona treść")
        XCTAssertNotNil(action?.execution, "Potwierdzenie po korekcie musi wykonać działanie")

        let version = try XCTUnwrap(action?.proposal.version)
        XCTAssertGreaterThan(version, originalVersion, "Zatwierdzenie musi dotyczyć nowej wersji")
        XCTAssertEqual(action?.execution?.proposalVersion, version, "Wykonanie musi wskazywać poprawioną wersję")
    }

    func testConfirmWithoutEditExecutesProposedText() async throws {
        let dependencies = AppDependencies.demo()
        let store = AssistantStore()
        store.attach(dependencies)
        await store.reload()

        let created = await store.newAction(kind: .task, clientID: nil, text: "Bez zmian")
        let turn = try XCTUnwrap(created)
        await store.confirm(actionID: turn.proposal.id, text: "Bez zmian")

        let action = store.turns.compactMap { turn -> AssistantStore.ActionTurn? in
            if case .action(let value) = turn { return value }
            return nil
        }.first
        XCTAssertEqual(action?.proposal.text, "Bez zmian")
        XCTAssertEqual(action?.proposal.version, turn.proposal.version, "Bez korekty wersja się nie zmienia")
        XCTAssertEqual(action?.execution?.proposalVersion, turn.proposal.version)
    }
}
