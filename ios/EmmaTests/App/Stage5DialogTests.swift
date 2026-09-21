import XCTest
@testable import Emma

// MARK: - Etap 5: trzy przebiegi z §6 na zdarzeniach deterministycznych
//
// Warunek akceptacji etapu brzmi: „Trzy przebiegi z §6 na deterministycznych
// zdarzeniach. Korekta odbiorcy/terminu/tekstu, doprecyzowanie głosem,
// deduplikacja zdarzeń, zachowanie szkicu przy pytaniu odczytowym.”
// Ten plik sprawdza dokładnie te cztery rzeczy na jednym silniku akcji.

@MainActor
final class Stage5DialogTests: XCTestCase {

    private let clock = DemoClock()
    /// Model widoku trzyma zależności słabo — tak jak w aplikacji, gdzie żyją one
    /// przez cały czas życia procesu. Test musi więc mieć własny mocny uchwyt.
    private var keptDependencies: [AppDependencies] = []

    private func makeStore() async -> (AssistantStore, AppDependencies) {
        let dependencies = AppDependencies.demo()
        keptDependencies.append(dependencies)
        let store = AssistantStore()
        store.attach(dependencies)
        await store.reload()
        dependencies.emmaContext = DemoFixtures.olenaID
        return (store, dependencies)
    }

    /// Transport bez scenariusza: zdarzenia wypuszczamy ręcznie, więc test nie
    /// zależy od czasu ani od kolejności kroków mocka.
    private func makeManualTransport() -> MockVoiceTransport {
        MockVoiceTransport(
            scenario: VoiceScenario(name: "manual", steps: []),
            delayProvider: { _ in }
        )
    }

    private func makeConfiguration(_ session: String) -> VoiceSessionConfiguration {
        VoiceSessionConfiguration(
            sessionID: VoiceSessionID(session),
            context: AssistantContext(scope: .firm),
            assistantLanguage: .ru,
            conversationToken: "token",
            expiresAt: clock.now().addingTimeInterval(600),
            capabilities: .mock
        )
    }

    private func actions(_ store: AssistantStore) -> [AssistantStore.ActionTurn] {
        store.turns.compactMap { turn in
            if case .action(let value) = turn { return value }
            return nil
        }
    }

    private func lastAssistantText(_ store: AssistantStore) -> String {
        for turn in store.turns.reversed() {
            if case .message(let message) = turn, message.role == .assistant { return message.text }
        }
        return ""
    }

    // MARK: Przebieg A — wiadomość do Oleny

    func testRunAPreparesMessageFromOneUtterance() async {
        let (store, _) = await makeStore()
        await store.handleCommand("Wyślij Olenie WhatsApp, że spóźnię się 15 minut")

        guard let action = actions(store).first else {
            XCTFail("brak propozycji | Emma: \(lastAssistantText(store)) | tur: \(store.turns.count)")
            return
        }
        XCTAssertEqual(action.proposal.kind, .reply)
        XCTAssertEqual(action.proposal.text, "spóźnię się 15 minut")
        XCTAssertEqual(action.proposal.clientID, DemoFixtures.olenaID)
        XCTAssertEqual(
            actions(store).count,
            1,
            "Jedna wypowiedź to jedna propozycja | tur: \(store.turns.count) | Emma: \(lastAssistantText(store))"
        )
    }

    /// §6-A krok 5: „Zmień na 20 minut” poprawia **tę samą** propozycję i unieważnia zgodę.
    func testRunACorrectionKeepsOneProposalAndDropsConsent() async throws {
        let (store, dependencies) = await makeStore()
        await store.handleCommand("Wyślij Olenie WhatsApp, że spóźnię się 15 minut")
        let action = try XCTUnwrap(actions(store).first)
        let actionID = action.proposal.id

        // Zgoda przygotowana na pokazaną propozycję.
        XCTAssertTrue(dependencies.voice.armVoiceConfirmation(
            actionID: actionID,
            presentationID: action.proposal.presentationID
        ))

        await store.handleCommand("Zmień na 20 minut")

        let corrected = try XCTUnwrap(actions(store).first)
        XCTAssertEqual(actions(store).count, 1, "Poprawka nie tworzy drugiej karty")
        XCTAssertEqual(corrected.proposal.id, actionID)
        XCTAssertTrue(corrected.proposal.text.contains("20 minut"))
        XCTAssertGreaterThan(corrected.proposal.version, action.proposal.version)

        // Zgoda dotyczyła poprzedniej treści — po poprawce nie działa.
        let execution = await dependencies.voice.confirmAction(
            actionID: actionID,
            presentationID: action.proposal.presentationID,
            origin: .authenticatedVoiceTurn,
            actor: dependencies.currentUser
        )
        XCTAssertNil(execution, "Zgoda na poprzednią treść nie może wykonać poprawionej")
    }

    /// Powtórne „wyślij” nie wykonuje operacji dwa razy (§5, „Wykonanie”).
    func testRunAConfirmationExecutesOnce() async throws {
        let (store, _) = await makeStore()
        await store.handleCommand("Wyślij Olenie WhatsApp, że spóźnię się 15 minut")
        await store.handleCommand("wyślij")

        let executed = try XCTUnwrap(actions(store).first)
        let execution = try XCTUnwrap(executed.execution)
        XCTAssertEqual(execution.proposalVersion, executed.proposal.version)

        await store.handleCommand("wyślij")
        let after = try XCTUnwrap(actions(store).first)
        XCTAssertEqual(after.execution?.outboxID, execution.outboxID, "Jedno wykonanie na akcję")
        XCTAssertEqual(actions(store).count, 1)
    }

    /// Korekta odbiorcy dotyczy innej osoby, więc unieważnia zgodę (F14).
    func testRunARecipientCorrectionChangesOwnerAndDropsConsent() async throws {
        let (store, dependencies) = await makeStore()
        await store.handleCommand("Wyślij Olenie WhatsApp, że spóźnię się 15 minut")
        let original = try XCTUnwrap(actions(store).first)
        XCTAssertTrue(dependencies.voice.armVoiceConfirmation(
            actionID: original.proposal.id,
            presentationID: original.proposal.presentationID
        ))

        let otherID = try XCTUnwrap(
            store.clients.first { $0.id != DemoFixtures.olenaID }?.id
        )
        await store.handleCommand("Nie, do \(store.clientName(for: otherID) ?? "")")

        let changed = try XCTUnwrap(actions(store).first)
        XCTAssertEqual(actions(store).count, 1, "Korekta odbiorcy nie tworzy drugiej karty")
        XCTAssertEqual(changed.proposal.id, original.proposal.id)
        XCTAssertEqual(changed.proposal.clientID, otherID)
        XCTAssertGreaterThan(changed.proposal.version, original.proposal.version)

        let execution = await dependencies.voice.confirmAction(
            actionID: original.proposal.id,
            presentationID: original.proposal.presentationID,
            origin: .authenticatedVoiceTurn,
            actor: dependencies.currentUser
        )
        XCTAssertNil(execution, "Zgoda dotyczyła innej osoby")
    }

    // MARK: Przebieg B — pytanie odczytowe nie kasuje szkicu

    func testRunBScheduleQuestionKeepsPreparedDraft() async throws {
        let (store, _) = await makeStore()
        await store.handleCommand("Wyślij Olenie WhatsApp, że spóźnię się 15 minut")
        let before = try XCTUnwrap(store.pendingAction)

        await store.handleCommand("Jakie mam terminy na dzisiaj?")

        let after = try XCTUnwrap(store.pendingAction, "Pytanie odczytowe nie może skasować szkicu")
        XCTAssertEqual(after.proposal.id, before.proposal.id)
        XCTAssertEqual(after.proposal.version, before.proposal.version, "Odczyt nie zmienia propozycji")
        XCTAssertFalse(lastAssistantText(store).isEmpty)
    }

    func testRunBTomorrowFollowUpChangesDateScope() async {
        let (store, dependencies) = await makeStore()
        await store.handleCommand("Jakie mam terminy na dzisiaj?")
        let today = lastAssistantText(store)

        await store.handleCommand("A jutro?")

        let tomorrow = lastAssistantText(store)
        XCTAssertFalse(tomorrow.isEmpty)
        XCTAssertNotEqual(tomorrow, today, "„A jutro?” musi odpowiadać o innym dniu")
        XCTAssertEqual(dependencies.emmaContext, DemoFixtures.olenaID)
    }

    // MARK: Przebieg C — zadanie z terminem i korekta terminu

    func testRunCCreatesTaskWithRelativeDate() async throws {
        let (store, dependencies) = await makeStore()
        await store.handleCommand("Dodaj zadanie: wyślij dokumenty Olenie jutro do 14")

        let action = try XCTUnwrap(actions(store).first)
        XCTAssertEqual(action.proposal.kind, .task)
        XCTAssertEqual(action.proposal.taskDueDate, dependencies.today.adding(days: 1))
        XCTAssertTrue(
            lastAssistantText(store).contains("14:00"),
            "Godzina z wypowiedzi musi być pokazana, a nie zniknąć"
        )
        XCTAssertTrue(
            lastAssistantText(store).contains(dependencies.today.adding(days: 1).isoString),
            "Termin powtarzamy jako datę bezwzględną (§6-C)"
        )
    }

    /// „Nie, na poniedziałek” zmienia termin tej samej propozycji.
    func testRunCCorrectionMovesTheSameTaskToMonday() async throws {
        let (store, dependencies) = await makeStore()
        await store.handleCommand("Dodaj zadanie: wyślij dokumenty Olenie jutro do 14")
        let original = try XCTUnwrap(actions(store).first)

        await store.handleCommand("Nie, na poniedziałek")

        let corrected = try XCTUnwrap(actions(store).first)
        XCTAssertEqual(actions(store).count, 1)
        XCTAssertEqual(corrected.proposal.id, original.proposal.id)
        XCTAssertEqual(
            corrected.proposal.taskDueDate,
            dependencies.today.adding(days: 3),
            "Najbliższy poniedziałek liczony od dnia referencyjnego (piątek)"
        )
        XCTAssertGreaterThan(corrected.proposal.version, original.proposal.version)
        XCTAssertTrue(lastAssistantText(store).contains("2026-09-14"))
    }

    func testRunCConfirmationCreatesOneExecution() async throws {
        let (store, _) = await makeStore()
        await store.handleCommand("Dodaj zadanie: wyślij dokumenty Olenie jutro do 14")
        await store.handleCommand("Nie, na poniedziałek")
        await store.handleCommand("zapisz")

        let action = try XCTUnwrap(actions(store).first)
        XCTAssertNotNil(action.execution)
        XCTAssertEqual(
            action.execution?.proposalVersion,
            action.proposal.version,
            "Wykonanie dotyczy poprawionej wersji, nie pierwotnej"
        )
    }

    // MARK: Deduplikacja zdarzeń (F04)

    func testRepeatedTranscriptDoesNotDuplicateTurns() async throws {
        let dependencies = AppDependencies.demo()
        let store = AssistantStore()
        store.attach(dependencies)
        await store.reload()

        let transport = makeManualTransport()
        await dependencies.voice.attach(
            transport: transport,
            configuration: makeConfiguration("session-dedup")
        )
        await transport.emitManually(.connectionChanged(.connected))
        try await Task.sleep(nanoseconds: 80_000_000)

        // To samo zdarzenie tury dwa razy: historia ma jedną wypowiedź użytkownika.
        await transport.emitManually(.userTranscriptFinal("Jakie mam terminy na dzisiaj?"), turnID: "turn-a")
        try await Task.sleep(nanoseconds: 120_000_000)
        await transport.emitManually(.userTranscriptFinal("Jakie mam terminy na dzisiaj?"), turnID: "turn-a")
        try await Task.sleep(nanoseconds: 120_000_000)

        let userTurns = store.turns.filter {
            if case .message(let message) = $0 { return message.role == .user }
            return false
        }
        XCTAssertEqual(userTurns.count, 1, "Ta sama tura nie może dopisać się dwa razy")
    }

    /// Druga wypowiedź o tej samej treści to druga tura — dedup jest po turze, nie po tekście.
    func testSameWordsInNewTurnAreTwoTurns() async throws {
        let dependencies = AppDependencies.demo()
        let store = AssistantStore()
        store.attach(dependencies)
        await store.reload()

        let transport = makeManualTransport()
        await dependencies.voice.attach(
            transport: transport,
            configuration: makeConfiguration("session-dedup-2")
        )
        await transport.emitManually(.connectionChanged(.connected))
        try await Task.sleep(nanoseconds: 80_000_000)

        await transport.emitManually(.userTranscriptFinal("Jakie mam terminy na dzisiaj?"), turnID: "turn-1")
        try await Task.sleep(nanoseconds: 120_000_000)
        await transport.emitManually(.userTranscriptFinal("Jakie mam terminy na dzisiaj?"), turnID: "turn-2")
        try await Task.sleep(nanoseconds: 120_000_000)

        let userTurns = store.turns.filter {
            if case .message(let message) = $0 { return message.role == .user }
            return false
        }
        XCTAssertEqual(userTurns.count, 2)
    }

    // MARK: Doprecyzowanie głosem (F14)

    /// Dwie Oleny w danych: Emma pyta, a odpowiedź nazwiskiem kończy to samo polecenie.
    func testAmbiguousRecipientIsResolvedByVoice() async throws {
        var dataset = DemoFixtures.dataset()
        // Druga Olena to przemianowany klient z zestawu demo: sprawdzamy regułę
        // niejednoznacznego imienia (F14), a nie tworzenie nowych danych.
        // Podmieniamy wpis (a nie dopisujemy kopii), żeby identyfikator
        // wskazywał dokładnie jedną osobę.
        let twinIndex = try XCTUnwrap(dataset.clients.firstIndex { $0.id != DemoFixtures.olenaID })
        dataset.clients[twinIndex].displayName = "Olena Nowak"
        let twinID = dataset.clients[twinIndex].id

        let repository = MockRepository(dataset: dataset, clock: clock, artificialLatency: 0)
        let repositoryClients = try await repository.clients(matching: "", stage: nil)
        XCTAssertTrue(
            repositoryClients.contains { $0.displayName == "Olena Nowak" },
            "repozytorium nie widzi zmiany: \(repositoryClients.map(\.displayName))"
        )
        let dependencies = AppDependencies(
            configuration: AppConfiguration(environment: .demo, apiBaseURL: nil, defaultLocale: "pl-PL"),
            clock: clock,
            repository: repository
        )
        let store = AssistantStore()
        store.attach(dependencies)
        await store.reload()
        XCTAssertTrue(
            store.clients.contains { $0.displayName == "Olena Nowak" },
            "lista sklepu: \(store.clients.map(\.displayName))"
        )

        await store.handleCommand("Dodaj zadanie: przygotować dokumenty dla Oleny")

        let question = try XCTUnwrap(store.pendingClarification)
        XCTAssertEqual(question.candidates.count, 2)
        XCTAssertTrue(question.question.contains("Olena Kovalenko"))
        XCTAssertTrue(question.question.contains("Olena Nowak"), "pytanie: \(question.question)")
        XCTAssertTrue(actions(store).isEmpty, "Bez osoby nie tworzymy propozycji")

        await store.handleCommand("Olena Nowak")

        XCTAssertNil(store.pendingClarification, "Odpowiedź kończy doprecyzowanie")
        let action = try XCTUnwrap(actions(store).first)
        XCTAssertEqual(action.proposal.clientID, twinID)
        XCTAssertEqual(action.proposal.text, "przygotować dokumenty dla Oleny")
    }

    /// „Dodaj spotkanie” otwiera formularz terminu, a nie briefing (F14).
    func testAddMeetingOpensPrefilledEventForm() async throws {
        let (store, dependencies) = await makeStore()
        await store.handleCommand("Dodaj spotkanie z Oleną na jutro o 11")

        let seed = try XCTUnwrap(dependencies.pendingEventDraft)
        XCTAssertEqual(seed.day, dependencies.today.adding(days: 1))
        XCTAssertEqual(seed.time, TimeOfDay(hhmm: "11:00"))
        XCTAssertEqual(dependencies.sheet, .eventForm(
            editing: nil,
            clientID: DemoFixtures.olenaID,
            caseID: DemoFixtures.caseOlenaID,
            initialDay: dependencies.today.adding(days: 1)
        ))
        XCTAssertTrue(actions(store).isEmpty, "Spotkanie nie jest akcją silnika akcji")
        XCTAssertTrue(lastAssistantText(store).contains("formularz"))
    }

    // MARK: Jeden właściciel tury (F15)

    /// Polecenie rozpoznane lokalnie nie idzie dodatkowo do dostawcy.
    func testLocallyHandledTurnIsNotForwardedTwice() async throws {
        let dependencies = AppDependencies.demo()
        let store = AssistantStore()
        store.attach(dependencies)
        await store.reload()

        let transport = makeManualTransport()
        await dependencies.voice.attach(
            transport: transport,
            configuration: makeConfiguration("session-owner")
        )
        await transport.emitManually(.connectionChanged(.connected))
        try await Task.sleep(nanoseconds: 80_000_000)

        await store.handleCommand("Jakie mam terminy na dzisiaj?")

        // Lokalny dialog odpowiedział, więc dostawca nie dostał tej tury: mock
        // odpowiada na przekazaną turę tekstem „Przyjęłam polecenie tekstem.”
        let forwarded = transport.recordedEvents.contains { event in
            if case .agentTextFinal(let text) = event.payload {
                return text.contains("Przyjęłam polecenie tekstem")
            }
            return false
        }
        XCTAssertFalse(forwarded, "Ta sama tura nie może iść i lokalnie, i do dostawcy")
    }
}
