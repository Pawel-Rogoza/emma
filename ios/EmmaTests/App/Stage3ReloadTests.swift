import XCTest
@testable import Emma

// MARK: - Etap 3: odświeżenie nie cofa listy
//
// Warunek z §7 etapu 3: „listy zachowują pozycję przy odświeżeniu”. Po zapisie
// (np. odhaczeniu zadania) `dataVersion` rośnie i ekran wczytuje dane ponownie.
// Jeżeli sklep ustawia wtedy `.loading`, zawartość listy jest zdejmowana z ekranu
// i pozycja przewijania przepada.
//
// Testy należą do targetu aplikacji (`EmmaTests/App`), bo `TodayStore`,
// `TasksStore` i `CaseStore` są w `Emma/Features`, a nie w pakiecie `swift test`.
// Wydłużona latencja repozytorium pozwala zajrzeć w **środek** odświeżenia,
// a nie tylko na jego wynik.

@MainActor
final class Stage3ReloadTests: XCTestCase {

    /// Ten sam dzień referencyjny co demo, ale każde żądanie trwa 0,3 s — dzięki
    /// temu stan pośredni jest obserwowalny i test nie zależy od wyścigu.
    private func slowDependencies() -> AppDependencies {
        let clock = DemoClock(
            referenceDate: DemoFixtures.referenceDay,
            hour: 9,
            minute: 41
        )
        let repository = MockRepository(
            dataset: DemoFixtures.dataset(),
            clock: clock,
            artificialLatency: 0.3
        )
        return AppDependencies(clock: clock, repository: repository, fixtureName: "today-default")
    }

    private func assertStaysLoaded<Model>(
        _ phase: LoadPhase<Model>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .loading = phase {
            XCTFail("Odświeżenie cofnęło listę do stanu ładowania", file: file, line: line)
        }
    }

    func testTodayReloadKeepsLoadedContent() async throws {
        let dependencies = slowDependencies()
        let store = TodayStore()

        await store.load(dependencies)
        guard case .loaded = store.phase else {
            return XCTFail("Pierwsze wczytanie dnia nie dało danych")
        }

        let reload = Task { await store.load(dependencies) }
        try await Task.sleep(nanoseconds: 80_000_000)
        assertStaysLoaded(store.phase)
        await reload.value
    }

    func testTasksReloadKeepsLoadedList() async throws {
        let dependencies = slowDependencies()
        let store = TasksStore()

        await store.load(dependencies)
        guard case .loaded = store.phase else {
            return XCTFail("Pierwsze wczytanie listy zadań nie dało danych")
        }

        let reload = Task { await store.load(dependencies) }
        try await Task.sleep(nanoseconds: 80_000_000)
        assertStaysLoaded(store.phase)
        await reload.value
    }

    func testCaseReloadKeepsLoadedContent() async throws {
        let dependencies = slowDependencies()
        let store = CaseStore()

        await store.load(dependencies, caseID: DemoFixtures.caseOlenaID)
        guard case .loaded = store.phase else {
            return XCTFail("Pierwsze wczytanie sprawy nie dało danych")
        }

        let reload = Task { await store.load(dependencies, caseID: DemoFixtures.caseOlenaID) }
        try await Task.sleep(nanoseconds: 80_000_000)
        assertStaysLoaded(store.phase)
        await reload.value
    }
}
