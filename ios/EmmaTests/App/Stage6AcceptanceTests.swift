import XCTest
@testable import Emma

// MARK: - Etap 6: domknięcie luk z tabeli regresji §8
//
// Audyt wylicza w §8 dwanaście scenariuszy akceptacyjnych. Ten plik zamyka luki,
// które nie miały dowodu: dziedziczenie wybranego dnia przez formularz, wariant
// wiadomości przy edycji i natychmiastowym „wyślij”, przerwanie odczytu a zgoda,
// powrót do szkicu po pytaniu odczytowym, aplikacja w tle oraz uzgodnienie stanu
// po niepewnym wyniku. Wszystkie asercje patrzą na stan, nie na nazwy metod.

@MainActor
final class Stage6AcceptanceTests: XCTestCase {

    private let clock = DemoClock()
    /// Model widoku trzyma zależności słabo — test potrzebuje własnego uchwytu.
    private var keptDependencies: [AppDependencies] = []

    override func tearDown() {
        keptDependencies = []
        super.tearDown()
    }

    private func makeStore() async -> (AssistantStore, AppDependencies) {
        let dependencies = AppDependencies.demo()
        keptDependencies.append(dependencies)
        let store = AssistantStore()
        store.attach(dependencies)
        await store.reload()
        dependencies.emmaContext = DemoFixtures.olenaID
        return (store, dependencies)
    }

    private func actions(_ store: AssistantStore) -> [AssistantStore.ActionTurn] {
        store.turns.compactMap { turn in
            if case .action(let value) = turn { return value }
            return nil
        }
    }

    // MARK: Wiersz 1 — wybór dnia dziedziczony przez formularz

    /// Nagłówek kalendarza i sekcja dnia muszą prowadzić do **wybranego** dnia,
    /// a nie do „dzisiaj”. Wcześniej przycisk w nagłówku przekazywał `initialDay: nil`.
    func testFormInheritsTheSelectedDayFromTheWeekStrip() async {
        let (_, dependencies) = await makeStore()
        let store = CalendarStore()
        await store.load(dependencies)

        let tomorrow = dependencies.today.adding(days: 1)
        await store.select(tomorrow, dependencies: dependencies)

        guard case .eventForm(_, _, _, let initialDay) = store.newEventRoute else {
            return XCTFail("Nowy termin to nie arkusz formularza: \(store.newEventRoute)")
        }
        XCTAssertEqual(initialDay, tomorrow, "Formularz dziedziczy wybrany dzień, nie „dzisiaj”")
        XCTAssertEqual(store.selectedDay, tomorrow, "Wybór dnia przeżywa wczytanie danych")
    }

    // MARK: Wiersz 4 — edycja wiadomości i natychmiastowe „wyślij”

    /// Wysłana ma być wyłącznie najnowsza potwierdzona wersja — na propozycji
    /// **wiadomości**, nie zadania.
    func testEditedReplySendsTheLatestVersionOnly() async throws {
        let (store, _) = await makeStore()
        await store.handleCommand("Wyślij Olenie WhatsApp, że spóźnię się 15 minut")

        let prepared = try XCTUnwrap(actions(store).first)
        XCTAssertEqual(prepared.proposal.kind, .reply)
        let originalVersion = prepared.proposal.version

        await store.edit(actionID: prepared.proposal.id, text: "spóźnię się 25 minut")
        await store.handleCommand("wyślij")

        let executed = try XCTUnwrap(actions(store).first)
        let execution = try XCTUnwrap(executed.execution)
        XCTAssertEqual(executed.proposal.text, "spóźnię się 25 minut")
        XCTAssertEqual(execution.proposalVersion, executed.proposal.version)
        XCTAssertGreaterThan(execution.proposalVersion, originalVersion, "Wykonanie wskazuje nowszą wersję")

        // Powtórzone „wyślij” nie tworzy drugiej operacji ani drugiego outboxa.
        await store.handleCommand("wyślij")
        let after = try XCTUnwrap(actions(store).first)
        XCTAssertEqual(after.execution?.outboxID, execution.outboxID)
        XCTAssertEqual(actions(store).count, 1)
    }

    // MARK: Wiersz 7 — pytanie odczytowe w trakcie szkicu, potem „wyślij”

    /// Odpowiedź odczytowa nie kasuje szkicu, a powrót do niego kończy się
    /// dokładnie jednym wykonaniem tej samej propozycji.
    func testReturnToDraftAfterReadOnlyQuestionSendsOnce() async throws {
        let (store, _) = await makeStore()
        await store.handleCommand("Wyślij Olenie WhatsApp, że spóźnię się 15 minut")
        let before = try XCTUnwrap(actions(store).first)

        await store.handleCommand("A jakie mam jutro terminy?")

        let kept = try XCTUnwrap(actions(store).first)
        XCTAssertEqual(kept.proposal.id, before.proposal.id, "Szkic zachowany po pytaniu odczytowym")
        XCTAssertEqual(kept.execution, nil, "Pytanie odczytowe nic nie wykonuje")

        await store.handleCommand("wyślij")
        let executed = try XCTUnwrap(actions(store).first)
        XCTAssertNotNil(executed.execution, "Powrót do szkicu kończy się wykonaniem")
        XCTAssertEqual(executed.proposal.id, before.proposal.id)
        XCTAssertEqual(actions(store).count, 1, "Jedna karta akcji przez cały przebieg")
    }

    // MARK: Wiersz 12 — dane do układu z długim nazwiskiem w cyrylicy

    /// Zestaw `dlugie-nazwy` musi naprawdę dokładać klientkę (inaczej test układu
    /// sprawdzałby nieistniejący wiersz), mieć **osobny** identyfikator i dać się
    /// znaleźć wyszukiwaniem po cyrylicy.
    func testLongNameFixtureAddsSearchableClientWithDistinctIdentity() async throws {
        let dependencies = AppDependencies.demo(fixtureName: "dlugie-nazwy")
        keptDependencies.append(dependencies)

        let clients = try await dependencies.repository.clients(matching: "", stage: nil)
        let longName = try XCTUnwrap(clients.first { $0.displayName == "Олександра Ковальчук-Шевченко" })
        XCTAssertEqual(longName.initials, "ОК")
        XCTAssertEqual(Set(clients.map(\.id)).count, clients.count, "Brak duplikatów identyfikatorów")

        let found = try await dependencies.repository.clients(matching: "Олександра", stage: nil)
        XCTAssertEqual(found.map(\.id), [longName.id], "Wyszukiwanie po cyrylicy znajduje klientkę")

        // Zwykłe demo zostaje bez zmian — zestaw układu nie przecieka do codziennych danych.
        let regular = AppDependencies.demo()
        keptDependencies.append(regular)
        let regularClients = try await regular.repository.clients(matching: "", stage: nil)
        XCTAssertFalse(regularClients.contains { $0.id == DemoFixtures.oleksandraID })
    }

    // MARK: Wiersze 6, 9, 11 — koordynator: zgoda, tło, uzgodnienie

    private func makeConnectedCoordinator() async throws -> (VoiceSessionCoordinator, MockRepository) {
        let repository = MockRepository(clock: clock, artificialLatency: 0)
        let coordinator = VoiceSessionCoordinator(
            sessionRepository: repository,
            actionRepository: repository,
            clock: clock
        )
        let transport = MockVoiceTransport(
            scenario: VoiceScenario(name: "pusty", steps: []),
            delayProvider: { _ in }
        )
        await coordinator.attach(
            transport: transport,
            configuration: VoiceSessionConfiguration(
                sessionID: VoiceSessionID("session-acceptance"),
                context: AssistantContext(scope: .firm),
                assistantLanguage: .pl,
                conversationToken: "token",
                expiresAt: clock.now().addingTimeInterval(600),
                capabilities: .mock
            )
        )
        await transport.emitManually(.connectionChanged(.connected))
        await waitUntil("połączenie aktywne") { coordinator.state.connection == .connected }
        return (coordinator, repository)
    }

    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Nie doczekano: \(what)")
    }

    /// Propozycja przygotowana tą samą drogą, co w aplikacji (jedno miejsce zgody).
    private func preparedReply(_ coordinator: VoiceSessionCoordinator) async throws -> ActionProposal {
        let proposal = await coordinator.prepareAction(
            kind: .reply,
            clientID: DemoFixtures.olenaID,
            caseID: DemoFixtures.caseOlenaID,
            threadID: DemoFixtures.olenaThread,
            text: "spóźnię się 15 minut",
            actor: DemoFixtures.kancelaria,
            presentationID: "presentation-acceptance"
        )
        return try XCTUnwrap(proposal, "Nie udało się przygotować propozycji")
    }

    /// Wiersz 6: przerwanie odczytu rozbraja zgodę głosową, ale nie kasuje
    /// propozycji ani szkicu — wykonanie zostaje przy przycisku.
    func testInterruptDisarmsVoiceConsentAndKeepsProposal() async throws {
        let (coordinator, _) = try await makeConnectedCoordinator()
        let proposal = try await preparedReply(coordinator)

        XCTAssertTrue(coordinator.armVoiceConfirmation(
            actionID: proposal.id,
            presentationID: proposal.presentationID
        ))
        XCTAssertEqual(coordinator.armedPresentationID, proposal.presentationID)

        await coordinator.interrupt(InterruptionRequest(reason: .userRequested))

        XCTAssertNil(coordinator.armedPresentationID, "Przerwanie odczytu rozbraja zgodę")
        let voiceExecution = await coordinator.confirmAction(
            actionID: proposal.id,
            presentationID: proposal.presentationID,
            origin: .authenticatedVoiceTurn,
            actor: DemoFixtures.kancelaria
        )
        XCTAssertNil(voiceExecution, "Bez uzbrojonej prezentacji „tak” nie wykonuje zapisu")

        // Prezentacja i treść zostają: użytkownik nadal może potwierdzić przyciskiem.
        let uiExecution = await coordinator.confirmAction(
            actionID: proposal.id,
            presentationID: proposal.presentationID,
            origin: .directUIButton,
            actor: DemoFixtures.kancelaria
        )
        XCTAssertNotNil(uiExecution, "Przycisk nadal działa — przerwanie nie blokuje pracy")
        XCTAssertEqual(uiExecution?.proposalVersion, proposal.version)
    }

    /// Wiersz 9 (część wykonalna w symulatorze): przejście w tło kończy zapisy
    /// głosem i zachowuje szkic; nie tworzy żadnego wykonania.
    func testBackgroundingRevokesVoiceWritesAndKeepsDraft() async throws {
        let (coordinator, _) = try await makeConnectedCoordinator()
        let proposal = try await preparedReply(coordinator)
        XCTAssertTrue(coordinator.armVoiceConfirmation(
            actionID: proposal.id,
            presentationID: proposal.presentationID
        ))

        await coordinator.handleApplicationBackgrounded()

        XCTAssertNotEqual(coordinator.state.connection, .connected, "Tło kończy połączenie")
        XCTAssertNil(coordinator.armedPresentationID, "Zgoda głosowa nie przeżywa tła")
        XCTAssertEqual(coordinator.currentProposal?.id, proposal.id, "Szkic zostaje na ekranie")

        let voiceExecution = await coordinator.confirmAction(
            actionID: proposal.id,
            presentationID: proposal.presentationID,
            origin: .authenticatedVoiceTurn,
            actor: DemoFixtures.kancelaria
        )
        XCTAssertNil(voiceExecution, "W tle nie wykonujemy zapisów głosem")
    }

    /// Wiersz 11: niepewny wynik najpierw się sprawdza. Uzgodnienie nie tworzy
    /// drugiego wykonania ani drugiego outboxa i nie ponawia polecenia.
    func testUnknownOutcomeIsReconciledInsteadOfResent() async throws {
        let (coordinator, repository) = try await makeConnectedCoordinator()
        let proposal = try await preparedReply(coordinator)

        let firstConfirmation = await coordinator.confirmAction(
            actionID: proposal.id,
            presentationID: proposal.presentationID,
            origin: .directUIButton,
            actor: DemoFixtures.kancelaria
        )
        let first = try XCTUnwrap(firstConfirmation)

        // Provider nie potwierdził wyniku — stan jest niepewny, nie „wysłano”.
        await repository.simulateProviderUnknown(actionID: proposal.id, at: clock.now())
        await coordinator.refreshExecutionState(actionID: proposal.id)

        XCTAssertEqual(coordinator.state.action, .needsReview, "Niepewny wynik to sprawdzenie, nie sukces")
        let reconciled = try XCTUnwrap(coordinator.currentExecution)
        XCTAssertEqual(reconciled.outboxID, first.outboxID, "To samo wykonanie, nie nowe")
        XCTAssertFalse(ActionEngine.mayRetry(reconciled), "Niepewny wynik nie zezwala na automatyczne ponowienie")

        // Ponowne potwierdzenie nie tworzy drugiej operacji.
        let again = await coordinator.confirmAction(
            actionID: proposal.id,
            presentationID: proposal.presentationID,
            origin: .directUIButton,
            actor: DemoFixtures.kancelaria
        )
        XCTAssertEqual(again?.outboxID, first.outboxID)
        let stored = try await repository.status(actionID: proposal.id)
        XCTAssertEqual(stored.outboxID, first.outboxID)
    }
}
