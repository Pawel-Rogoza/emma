import XCTest
@testable import Emma

// MARK: - Silnik akcji (§8, §12.2)

final class ActionEngineTests: XCTestCase {

    private let engine = ActionEngine()
    private let now = Date(timeIntervalSince1970: 1_789_100_000)

    private func makeRequest(
        id: String = "action-1",
        text: String = "Dzień dobry, potwierdzam konsultację.",
        kind: ActionKind = .reply,
        clientID: ClientID? = DemoFixtures.olenaID,
        presentationID: String = "presentation-1"
    ) -> PrepareActionRequest {
        PrepareActionRequest(
            actionID: ActionID(id),
            kind: kind,
            actorUserID: .tomasz,
            clientID: clientID,
            caseID: DemoFixtures.caseOlenaID,
            threadID: DemoFixtures.olenaThread,
            text: text,
            contextVersion: Version(4),
            threadVersion: Version(3),
            presentationID: presentationID,
            now: now
        )
    }

    func testPrepareReplacesPreviousActiveProposal() {
        var state = ActionEngine.State()
        _ = engine.prepare(makeRequest(id: "action-1"), into: &state)
        let second = engine.prepare(makeRequest(id: "action-2"), into: &state)
        XCTAssertEqual(state.proposals[ActionID("action-1")]?.state, .superseded)
        XCTAssertEqual(second.state, .proposed)
        XCTAssertEqual(state.activeProposal?.id, ActionID("action-2"))
    }

    func testRevisionChangesVersionAndHashAndDisarmsConsent() throws {
        var state = ActionEngine.State()
        let original = engine.prepare(makeRequest(), into: &state)
        try engine.arm(actionID: original.id, presentationID: original.presentationID, into: &state)
        XCTAssertNotNil(state.armedPresentationID)

        let revised = try engine.revise(
            actionID: original.id,
            newText: "Dzień dobry, potwierdzam konsultację o 11:00.",
            now: now.addingTimeInterval(5),
            into: &state
        )
        XCTAssertEqual(revised.version, original.version.next())
        XCTAssertNotEqual(revised.payloadHash, original.payloadHash)
        XCTAssertNotEqual(revised.presentationID, original.presentationID)
        XCTAssertNil(state.armedPresentationID, "Korekta rozbraja zgodę na poprzednią treść")
    }

    func testConsentOnOlderVersionIsRejected() throws {
        var state = ActionEngine.State()
        let original = engine.prepare(makeRequest(), into: &state)
        try engine.arm(actionID: original.id, presentationID: original.presentationID, into: &state)
        _ = try engine.revise(actionID: original.id, newText: "Nowa treść", now: now, into: &state)

        XCTAssertThrowsError(
            try engine.confirm(
                ActionEngine.Confirmation(
                    actionID: original.id,
                    expectedVersion: original.version,
                    presentationID: original.presentationID,
                    origin: .directUIButton,
                    now: now
                ),
                outboxID: "outbox-1",
                into: &state
            )
        ) { error in
            XCTAssertEqual(error as? ActionEngineError, .versionConflict(expected: original.version, current: Version(2)))
        }
    }

    func testLanguageModelArgumentIsNotProofOfConsent() {
        var state = ActionEngine.State()
        let proposal = engine.prepare(makeRequest(), into: &state)
        XCTAssertThrowsError(
            try engine.confirm(
                ActionEngine.Confirmation(
                    actionID: proposal.id,
                    expectedVersion: proposal.version,
                    presentationID: proposal.presentationID,
                    origin: .languageModelArgument,
                    now: now
                ),
                outboxID: "outbox-1",
                into: &state
            )
        ) { error in
            XCTAssertEqual(error as? ActionEngineError, .confirmationNotBoundToCurrentPresentation)
        }
        XCTAssertTrue(state.executions.isEmpty, "Argument LLM nie może utworzyć wykonania")
    }

    func testVoiceConsentRequiresArmedPresentation() {
        var state = ActionEngine.State()
        let proposal = engine.prepare(makeRequest(), into: &state)
        // Nie uzbrojono prezentacji — sama wypowiedź nie wystarcza.
        XCTAssertThrowsError(
            try engine.confirm(
                ActionEngine.Confirmation(
                    actionID: proposal.id,
                    expectedVersion: proposal.version,
                    presentationID: proposal.presentationID,
                    origin: .authenticatedVoiceTurn,
                    now: now
                ),
                outboxID: "outbox-1",
                into: &state
            )
        )
        // Po uzbrojeniu i wypowiedzi użytkownika przechodzi.
        XCTAssertNoThrow(try engine.arm(actionID: proposal.id, presentationID: proposal.presentationID, into: &state))
        XCTAssertNoThrow(
            try engine.confirm(
                ActionEngine.Confirmation(
                    actionID: proposal.id,
                    expectedVersion: proposal.version,
                    presentationID: proposal.presentationID,
                    origin: .authenticatedVoiceTurn,
                    now: now
                ),
                outboxID: "outbox-1",
                into: &state
            )
        )
    }

    func testUIConfirmAndVoiceConfirmProduceSingleExecution() throws {
        var state = ActionEngine.State()
        let proposal = engine.prepare(makeRequest(), into: &state)
        let first = try engine.confirm(
            ActionEngine.Confirmation(
                actionID: proposal.id,
                expectedVersion: proposal.version,
                presentationID: proposal.presentationID,
                origin: .directUIButton,
                now: now
            ),
            outboxID: "outbox-ui",
            into: &state
        )
        // Drugie potwierdzenie (np. z voice) nie tworzy drugiego wykonania ani wpisu outboxa.
        // Propozycja nie jest już `proposed`, więc silnik zwraca **istniejące** wykonanie.
        let second = try engine.confirm(
            ActionEngine.Confirmation(
                actionID: proposal.id,
                expectedVersion: proposal.version,
                presentationID: proposal.presentationID,
                origin: .authenticatedVoiceTurn,
                now: now
            ),
            outboxID: "outbox-voice",
            into: &state
        )
        XCTAssertEqual(second.outboxID, first.outboxID, "Ten sam wynik akcji dla UI i voice")
        XCTAssertEqual(state.executions.count, 1)
        XCTAssertEqual(state.executions[proposal.id]?.outboxID, first.outboxID)
    }

    func testDoubleConfirmWithSameVersionIsIdempotent() throws {
        var state = ActionEngine.State()
        let proposal = engine.prepare(makeRequest(), into: &state)
        let confirmation = ActionEngine.Confirmation(
            actionID: proposal.id,
            expectedVersion: proposal.version,
            presentationID: proposal.presentationID,
            origin: .directUIButton,
            now: now
        )
        let first = try engine.confirm(confirmation, outboxID: "outbox-same", into: &state)
        let second = try engine.confirm(confirmation, outboxID: "outbox-same", into: &state)
        XCTAssertEqual(first.outboxID, second.outboxID)
        XCTAssertEqual(state.executions.count, 1)
    }

    func testExpiredProposalCannotBeConfirmed() {
        var state = ActionEngine.State()
        let proposal = engine.prepare(makeRequest(), into: &state)
        let late = now.addingTimeInterval(engine.confirmationWindow + 1)
        XCTAssertThrowsError(
            try engine.confirm(
                ActionEngine.Confirmation(
                    actionID: proposal.id,
                    expectedVersion: proposal.version,
                    presentationID: proposal.presentationID,
                    origin: .directUIButton,
                    now: late
                ),
                outboxID: "outbox-late",
                into: &state
            )
        ) { error in
            XCTAssertEqual(error as? ActionEngineError, .proposalExpired)
        }
        XCTAssertEqual(state.proposals[proposal.id]?.state, .expired)
    }

    func testStalePresentationIsRejected() {
        var state = ActionEngine.State()
        let proposal = engine.prepare(makeRequest(), into: &state)
        XCTAssertThrowsError(
            try engine.arm(actionID: proposal.id, presentationID: "inne-pokazanie", into: &state)
        ) { error in
            XCTAssertEqual(
                error as? ActionEngineError,
                .stalePresentation(expected: proposal.presentationID, received: "inne-pokazanie")
            )
        }
    }

    func testMissingRecipientBlocksReply() {
        var state = ActionEngine.State()
        let proposal = engine.prepare(
            makeRequest(clientID: nil, presentationID: "p-no-client"),
            into: &state
        )
        XCTAssertThrowsError(
            try engine.confirm(
                ActionEngine.Confirmation(
                    actionID: proposal.id,
                    expectedVersion: proposal.version,
                    presentationID: proposal.presentationID,
                    origin: .directUIButton,
                    now: now
                ),
                outboxID: "outbox-1",
                into: &state
            )
        ) { error in
            XCTAssertEqual(error as? ActionEngineError, .missingRecipient)
        }
    }

    func testEmptyTextIsRejected() {
        var state = ActionEngine.State()
        let proposal = engine.prepare(makeRequest(text: "   "), into: &state)
        XCTAssertThrowsError(
            try engine.confirm(
                ActionEngine.Confirmation(
                    actionID: proposal.id,
                    expectedVersion: proposal.version,
                    presentationID: proposal.presentationID,
                    origin: .directUIButton,
                    now: now
                ),
                outboxID: "outbox-1",
                into: &state
            )
        ) { error in
            XCTAssertEqual(error as? ActionEngineError, .emptyText)
        }
    }

    func testContextChangeInvalidatesConsent() throws {
        var state = ActionEngine.State()
        let proposal = engine.prepare(makeRequest(), into: &state)
        try engine.arm(actionID: proposal.id, presentationID: proposal.presentationID, into: &state)
        let changed = try engine.changeContext(
            actionID: proposal.id,
            clientID: DemoFixtures.dmytroID,
            caseID: DemoFixtures.caseDmytroID,
            threadID: DemoFixtures.dmytroThread,
            now: now,
            into: &state
        )
        XCTAssertNil(state.armedPresentationID, "Zmiana adresata rozbraja zgodę")
        XCTAssertEqual(changed.version, Version(2))
        XCTAssertEqual(changed.clientID, DemoFixtures.dmytroID)
    }

    func testDisarmKeepsProposal() throws {
        var state = ActionEngine.State()
        let proposal = engine.prepare(makeRequest(), into: &state)
        try engine.arm(actionID: proposal.id, presentationID: proposal.presentationID, into: &state)
        engine.disarm(into: &state)
        XCTAssertNil(state.armedPresentationID)
        XCTAssertEqual(state.proposals[proposal.id]?.state, .proposed, "Rozbrojenie nie usuwa propozycji")
    }

    func testUnknownOutcomeIsNotRetried() {
        var state = ActionEngine.State()
        let proposal = engine.prepare(makeRequest(), into: &state)
        _ = try? engine.confirm(
            ActionEngine.Confirmation(
                actionID: proposal.id,
                expectedVersion: proposal.version,
                presentationID: proposal.presentationID,
                origin: .directUIButton,
                now: now
            ),
            outboxID: "outbox-1",
            into: &state
        )
        let unknown = engine.applyExecutionState(
            actionID: proposal.id,
            state: .unknown,
            now: now,
            into: &state
        )
        XCTAssertEqual(unknown?.state, .unknown)
        XCTAssertFalse(ActionEngine.mayRetry(unknown!), "Niepewny wynik nie zezwala na automatyczne ponowienie")
        XCTAssertTrue(ActionEngine.requiresReconciliation(unknown!))
    }

    func testFailedExecutionMayBeRetriedExplicitly() {
        var state = ActionEngine.State()
        let proposal = engine.prepare(makeRequest(), into: &state)
        _ = try? engine.confirm(
            ActionEngine.Confirmation(
                actionID: proposal.id,
                expectedVersion: proposal.version,
                presentationID: proposal.presentationID,
                origin: .directUIButton,
                now: now
            ),
            outboxID: "outbox-1",
            into: &state
        )
        let failed = engine.applyExecutionState(actionID: proposal.id, state: .failed, now: now, into: &state)
        XCTAssertTrue(ActionEngine.mayRetry(failed!))
    }

    func testCancelledProposalCannotBeConfirmed() throws {
        var state = ActionEngine.State()
        let proposal = engine.prepare(makeRequest(), into: &state)
        let cancelled = try engine.cancel(actionID: proposal.id, now: now, into: &state)
        XCTAssertEqual(cancelled.state, .rejected)
        XCTAssertThrowsError(
            try engine.confirm(
                ActionEngine.Confirmation(
                    actionID: proposal.id,
                    expectedVersion: proposal.version,
                    presentationID: proposal.presentationID,
                    origin: .directUIButton,
                    now: now
                ),
                outboxID: "outbox-1",
                into: &state
            )
        )
    }
}

// MARK: - Reduktor stanu voice (§5.4, §5.5, §12.2)

final class VoiceStateReducerTests: XCTestCase {

    private let reducer = VoiceStateReducer()
    private let sessionID = VoiceSessionID("session-1")

    private func event(
        _ payload: VoiceEventPayload,
        generation: UInt64 = 1,
        eventID: String = "e1",
        turnID: String? = nil
    ) -> VoiceEvent {
        VoiceEvent(
            eventID: eventID,
            sessionID: sessionID,
            connectionGeneration: ConnectionGeneration(generation),
            turnID: turnID,
            receivedAt: Date(timeIntervalSince1970: 1_789_100_000),
            source: .mockTransport,
            payload: payload
        )
    }

    private func connectedState() -> VoiceUIState {
        var state = VoiceUIState()
        reducer.apply(event(.connectionChanged(.connected)), to: &state)
        state.sessionID = sessionID
        return state
    }

    func testPartialTranscriptReplacesHypothesis() {
        var state = connectedState()
        reducer.apply(event(.userTranscriptPartial("Przygotuj odpo")), to: &state)
        XCTAssertEqual(state.partialTranscript, "Przygotuj odpo")
        reducer.apply(event(.userTranscriptPartial("Przygotuj odpowiedź do Oleny")), to: &state)
        XCTAssertEqual(state.partialTranscript, "Przygotuj odpowiedź do Oleny")
    }

    func testUserSpeechStartClearsPartial() {
        var state = connectedState()
        reducer.apply(event(.userTranscriptPartial("stara hipoteza")), to: &state)
        reducer.apply(event(.userSpeechStarted), to: &state)
        XCTAssertEqual(state.partialTranscript, "")
        XCTAssertEqual(state.turn, .listening)
    }

    func testFinalTranscriptCommitsAndClearsPartial() {
        var state = connectedState()
        reducer.apply(event(.userTranscriptPartial("Przygotuj odpo")), to: &state)
        reducer.apply(event(.userTranscriptFinal("Przygotuj odpowiedź do Oleny")), to: &state)
        XCTAssertEqual(state.partialTranscript, "")
        XCTAssertEqual(state.committedUserTranscript, "Przygotuj odpowiedź do Oleny")
        XCTAssertEqual(state.turn, .thinking)
    }

    func testAgentTextFinalIsNotEndOfSpeech() {
        var state = connectedState()
        reducer.apply(event(.agentTextDelta("Wiadomość ")), to: &state)
        reducer.apply(event(.agentTextFinal("Wiadomość gotowa.")), to: &state)
        XCTAssertEqual(state.agentText, "Wiadomość gotowa.")
        // `agentTextFinal` nie kończy odtwarzania i nie zwraca tury do „waiting”.
        XCTAssertNotEqual(state.turn, .waiting)
        reducer.apply(event(.playbackStarted(approximate: false)), to: &state)
        XCTAssertTrue(state.isPlaybackActive)
        reducer.apply(event(.playbackStopped(reason: .completed)), to: &state)
        XCTAssertFalse(state.isPlaybackActive)
        XCTAssertEqual(state.turn, .waiting)
    }

    func testMutedMicrophoneIsNotDisconnection() {
        var state = connectedState()
        reducer.apply(event(.microphoneChanged(.muted)), to: &state)
        XCTAssertEqual(state.microphone, .muted)
        XCTAssertEqual(state.connection, .connected, "Wyciszenie nie jest rozłączeniem")
        XCTAssertTrue(state.canEndSession)
    }

    func testStaleGenerationIsRejected() {
        var state = connectedState()
        // Nowe połączenie: generacja 2.
        reducer.apply(event(.connectionChanged(.reconnecting), generation: 2, eventID: "e2"), to: &state)
        reducer.apply(event(.connectionChanged(.connected), generation: 2, eventID: "e3"), to: &state)
        let before = state.agentText

        var mutable = state
        let rejection = reducer.apply(
            event(.agentTextDelta("SPÓŹNIONA ODPOWIEDŹ"), generation: 1, eventID: "e4"),
            to: &mutable
        )
        XCTAssertNotNil(rejection)
        XCTAssertEqual(rejection?.reason, .staleGeneration)
        XCTAssertEqual(mutable.agentText, before, "Spóźnione zdarzenie nie zmienia stanu")
        state = mutable
        XCTAssertFalse(state.agentText.contains("SPÓŹNIONA"))
    }

    func testForeignSessionIsRejected() {
        var state = connectedState()
        let foreign = VoiceEvent(
            eventID: "x1",
            sessionID: VoiceSessionID("inna-sesja"),
            connectionGeneration: ConnectionGeneration(9),
            receivedAt: Date(),
            source: .providerTransport,
            payload: .agentTextDelta("obca sesja")
        )
        var mutable = state
        let rejection = reducer.apply(foreign, to: &mutable)
        XCTAssertEqual(rejection?.reason, .foreignSession)
    }

    func testEventsAfterEndAreRejected() {
        var state = connectedState()
        reducer.apply(event(.connectionChanged(.ended), eventID: "end"), to: &state)
        var mutable = state
        let rejection = reducer.apply(event(.agentTextDelta("po końcu"), eventID: "late"), to: &mutable)
        XCTAssertEqual(rejection?.reason, .afterSessionEnded)
    }

    func testInterruptionStopsPlaybackAndClearsPartial() {
        var state = connectedState()
        reducer.apply(event(.userTranscriptPartial("Przygotuj")), to: &state)
        reducer.apply(event(.playbackStarted(approximate: false)), to: &state)
        reducer.apply(event(.interruption(.userBargeIn)), to: &state)
        XCTAssertEqual(state.turn, .interrupted)
        XCTAssertFalse(state.isPlaybackActive)
        XCTAssertEqual(state.partialTranscript, "")
        XCTAssertEqual(state.lastInterruption, .userBargeIn)
    }

    func testToolProgressIsClearedWhenFinished() {
        var state = connectedState()
        reducer.apply(event(.toolProgress(ToolProgress(label: "Czytam sprawę", toolName: "get_case"))), to: &state)
        XCTAssertEqual(state.toolLabel, "Czytam sprawę")
        reducer.apply(
            event(.toolProgress(ToolProgress(label: "Czytam sprawę", toolName: "get_case", isFinished: true))),
            to: &state
        )
        XCTAssertNil(state.toolLabel)
    }

    func testExecutionUnknownMapsToNeedsReview() {
        var state = connectedState()
        var execution = DemoFixtures.queuedExecution
        execution.state = .unknown
        reducer.apply(event(.executionChanged(ExecutionSnapshot(execution: execution))), to: &state)
        XCTAssertEqual(state.action, .needsReview)
        XCTAssertEqual(state.statusHeadline, ExecutionState.unknown.displayName,
                       "Nagłówek nie może ogłaszać wysłania przy niepewnym wyniku")
    }

    func testPermissionDeniedKeepsTextPath() {
        var state = VoiceUIState()
        reducer.apply(event(.connectionChanged(.connected)), to: &state)
        reducer.apply(event(.fatalError(.microphonePermissionDenied)), to: &state)
        XCTAssertEqual(state.microphone, .unavailable)
        XCTAssertEqual(state.connection, .failed)
        XCTAssertEqual(state.lastError, FatalErrorKind.microphonePermissionDenied.safeMessage)
        XCTAssertFalse(state.orbIsActive)
    }

    func testSessionRevokedClearsSession() {
        var state = connectedState()
        state.sessionID = sessionID
        reducer.apply(event(.fatalError(.sessionRevoked)), to: &state)
        XCTAssertNil(state.sessionID)
        XCTAssertEqual(state.mode, .idle)
    }

    func testStatusHeadlinePriority() {
        var state = connectedState()
        reducer.apply(event(.recoverableError(.networkLost)), to: &state)
        XCTAssertEqual(state.statusHeadline, RecoverableErrorKind.networkLost.safeMessage)
        XCTAssertEqual(state.connection, .reconnecting)
    }

    func testModeTransitionFromPlaybackToDictation() {
        var state = VoiceUIState()
        _ = reducer.transition(to: .playback, from: &state)
        state.isPlaybackActive = true
        let ok = reducer.transition(to: .dictation, from: &state)
        XCTAssertTrue(ok, "Dyktowanie przejmuje zasób audio")
        XCTAssertFalse(state.isPlaybackActive)
    }

    func testPlaybackCannotStartWhileEmmaSpeaks() {
        var state = connectedState()
        state.mode = .conversation
        state.turn = .speaking
        let ok = reducer.transition(to: .playback, from: &state)
        XCTAssertFalse(ok, "Odsłuch nie przerywa wypowiedzi w trakcie tury")
    }

    func testOdsłuchNeverUsesMicrophone() {
        XCTAssertFalse(VoiceMode.playback.usesMicrophone)
        XCTAssertTrue(VoiceMode.conversation.usesMicrophone)
        XCTAssertTrue(VoiceMode.dictation.usesMicrophone)
        XCTAssertFalse(VoiceMode.idle.usesMicrophone)
    }
}

// MARK: - Koordynator voice (§5.3, §5.6, §6, §12.2)

@MainActor
final class VoiceSessionCoordinatorTests: XCTestCase {

    private var repository: MockRepository!
    private var coordinator: VoiceSessionCoordinator!
    private let clock = DemoClock()

    override func setUp() async throws {
        repository = MockRepository(clock: clock, artificialLatency: 0)
        coordinator = VoiceSessionCoordinator(
            sessionRepository: repository,
            actionRepository: repository,
            clock: clock
        )
    }

    private func configuration() -> VoiceSessionConfiguration {
        VoiceSessionConfiguration(
            sessionID: VoiceSessionID("session-test"),
            context: AssistantContext(scope: .firm),
            assistantLanguage: .ru,
            conversationToken: "test-token",
            expiresAt: clock.now().addingTimeInterval(600),
            capabilities: .mock
        )
    }

    private func attachMock(_ scenario: VoiceScenario) async -> MockVoiceTransport {
        let transport = MockVoiceTransport(scenario: scenario, delayProvider: { _ in })
        await coordinator.attach(transport: transport, configuration: configuration())
        return transport
    }

    private func scenarioWithoutScript() -> VoiceScenario {
        VoiceScenario(name: "manual", steps: [])
    }

    /// Zdarzenia mocka płyną przez strumień asynchronicznie. `settle` i `waitUntil`
    /// pozwalają testom czekać na stan bez używania stałych opóźnień w logice.
    private func settle(_ milliseconds: Int = 80) async {
        try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    private func waitUntil(
        _ message: String,
        timeout: TimeInterval = 3,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 3_000_000)
        }
        XCTAssertTrue(condition(), message)
    }

    func testThereIsExactlyOneSessionPerCoordinator() async throws {
        let transport = await attachMock(scenarioWithoutScript())
        await transport.emitManually(.connectionChanged(.connected))
        await settle()
        XCTAssertEqual(coordinator.state.connection, .connected)

        // Ponowne „wejście” do Emmy nie tworzy drugiego połączenia.
        let second = MockVoiceTransport(scenario: scenarioWithoutScript(), delayProvider: { _ in })
        await coordinator.attach(transport: second, configuration: configuration())
        XCTAssertEqual(coordinator.state.connection, .connecting)
        // Poprzedni transport nie jest już podłączony do strumienia koordynatora.
        await transport.emitManually(.agentTextDelta("stare połączenie"))
        await settle()
        XCTAssertFalse(coordinator.state.agentText.contains("stare połączenie"))
    }

    func testStaleEventFromOldConnectionIsRejectedAndRecorded() async throws {
        let transport = await attachMock(.staleEvent())
        // Scenariusz sam przechodzi przez generacje 1 → 2 i wysyła spóźnione zdarzenie.
        for _ in 0..<50 {
            if !coordinator.recordedRejections.isEmpty { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertFalse(coordinator.recordedRejections.isEmpty, "Spóźnione zdarzenie musi być odrzucone")
        XCTAssertEqual(coordinator.recordedRejections.first?.reason, .staleGeneration)
        XCTAssertFalse(coordinator.state.agentText.contains("SPÓŹNIONA"))
        _ = transport
    }

    func testPermissionDeniedScenarioKeepsAppUsable() async throws {
        _ = await attachMock(.permissionDenied())
        for _ in 0..<50 {
            if coordinator.state.connection == .failed { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(coordinator.state.connection, .failed)
        XCTAssertEqual(coordinator.state.lastError, FatalErrorKind.microphonePermissionDenied.safeMessage)
        XCTAssertEqual(coordinator.state.microphone, .unavailable)
    }

    func testDictationResultGoesToFrozenTargetAndExecutesNothing() async throws {
        let transport = await attachMock(scenarioWithoutScript())
        await transport.emitManually(.connectionChanged(.connected))
        await settle()

        let service = MockDictationService()
        var received: (DictationTarget, String)?
        coordinator.onDictationResult = { target, text in received = (target, text) }

        let target = DictationTarget.threadDraft(threadID: DemoFixtures.olenaThread, draftVersion: Version(2))
        await coordinator.startDictation(target: target, language: .pl, service: service)

        for _ in 0..<50 {
            if received != nil { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(received?.0, target)
        // Dyktowany tekst brzmi jak polecenie („Wyślij to jutro”), ale nie wykonuje akcji.
        XCTAssertEqual(received?.1, "Wyślij to jutro")
        XCTAssertFalse(target.executesCommands)
        XCTAssertNil(coordinator.currentProposal, "Dyktowanie nie tworzy propozycji działania")
        XCTAssertNil(coordinator.currentExecution)
    }

    func testDictationTargetSurvivesThreadSwitch() async throws {
        let transport = await attachMock(scenarioWithoutScript())
        await transport.emitManually(.connectionChanged(.connected))
        await settle()
        let service = MockDictationService()
        var receivedTarget: DictationTarget?
        coordinator.onDictationResult = { target, _ in receivedTarget = target }

        let original = DictationTarget.threadDraft(threadID: DemoFixtures.olenaThread, draftVersion: Version(1))
        await coordinator.startDictation(target: original, language: .pl, service: service)
        // Użytkownik przechodzi do innego wątku w trakcie dyktowania.
        await coordinator.updateContext(AssistantContext.client(DemoFixtures.dmytroID))
        for _ in 0..<50 {
            if receivedTarget != nil { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(receivedTarget, original, "Wynik dyktowania nie trafia do nowego odbiorcy")
    }

    func testDictationFailureSurfacesMessage() async throws {
        let transport = await attachMock(scenarioWithoutScript())
        await transport.emitManually(.connectionChanged(.connected))
        await settle()
        let service = MockDictationService(failure: .noSpeechDetected)
        var failure: DictationFailure?
        coordinator.onDictationFailure = { failure = $0 }
        await coordinator.startDictation(
            target: .caseNote(clientID: DemoFixtures.olenaID, caseID: DemoFixtures.caseOlenaID),
            language: .pl,
            service: service
        )
        for _ in 0..<50 {
            if failure != nil { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(failure, .noSpeechDetected)
        XCTAssertEqual(coordinator.state.lastError, DictationFailure.noSpeechDetected.safeMessage)
    }

    func testPlaybackDoesNotOpenMicrophone() async throws {
        let playback = MockSpeechPlaybackService()
        await coordinator.startPlayback(
            SpeechPlaybackRequest(text: "Treść wiadomości", language: .pl, sourceID: "msg-1"),
            service: playback
        )
        XCTAssertNotEqual(coordinator.state.microphone, .capturing)
        XCTAssertEqual(coordinator.state.mode, .playback)
    }

    func testPlaybackProducesNoBusinessMutation() async throws {
        let before = await repository.snapshot()
        let playback = MockSpeechPlaybackService()
        await coordinator.startPlayback(
            SpeechPlaybackRequest(text: "Odsłuch szkicu", language: .ru, sourceID: "draft-1"),
            service: playback
        )
        let after = await repository.snapshot()
        XCTAssertEqual(before.messages.count, after.messages.count)
        XCTAssertEqual(before.tasks.count, after.tasks.count)
        XCTAssertNil(coordinator.currentProposal)
        XCTAssertNil(coordinator.currentExecution)
    }

    func testEndOfSessionDisarmsVoiceConsentAndKeepsDraft() async throws {
        let transport = await attachMock(scenarioWithoutScript())
        await transport.emitManually(.connectionChanged(.connected))
        await settle()
        let proposal = await coordinator.prepareAction(
            kind: .reply,
            clientID: DemoFixtures.olenaID,
            caseID: DemoFixtures.caseOlenaID,
            threadID: DemoFixtures.olenaThread,
            text: "Treść szkicu",
            actor: DemoFixtures.tomasz,
            presentationID: "presentation-1"
        )
        XCTAssertNotNil(proposal)
        XCTAssertTrue(coordinator.armVoiceConfirmation(actionID: proposal!.id, presentationID: proposal!.presentationID))

        await coordinator.end(reason: .userRequested, preserveDraft: true)
        XCTAssertNil(coordinator.armedPresentationID, "Zgoda głosowa nie przeżywa końca sesji")
        XCTAssertEqual(coordinator.state.connection, .ended)
        XCTAssertEqual(coordinator.lastEndReason, .userRequested)
        XCTAssertNotNil(coordinator.currentProposal, "Szkic zostaje po zakończeniu rozmowy")
    }

    func testLeavingTheViewDoesNotEndTheSession() async throws {
        let transport = await attachMock(scenarioWithoutScript())
        await transport.emitManually(.connectionChanged(.connected))
        await settle()
        coordinator.viewDidDisappear()
        XCTAssertEqual(coordinator.state.connection, .connected, "Nawigacja nie kończy rozmowy")
    }

    func testLogoutClearsEverything() async throws {
        let transport = await attachMock(scenarioWithoutScript())
        await transport.emitManually(.connectionChanged(.connected))
        await settle()
        _ = await coordinator.prepareAction(
            kind: .reply,
            clientID: DemoFixtures.olenaID,
            caseID: DemoFixtures.caseOlenaID,
            threadID: DemoFixtures.olenaThread,
            text: "Treść",
            actor: DemoFixtures.tomasz,
            presentationID: "presentation-1"
        )
        await coordinator.handleUserLoggedOut()
        XCTAssertNil(coordinator.state.sessionID)
        XCTAssertNil(coordinator.currentProposal)
        XCTAssertEqual(coordinator.state.connection, .idle)
    }

    func testPermissionRevokedRemovesWriteCapability() async throws {
        let transport = await attachMock(scenarioWithoutScript())
        await transport.emitManually(.connectionChanged(.connected))
        await settle()
        let proposal = await coordinator.prepareAction(
            kind: .reply,
            clientID: DemoFixtures.olenaID,
            caseID: DemoFixtures.caseOlenaID,
            threadID: DemoFixtures.olenaThread,
            text: "Treść",
            actor: DemoFixtures.tomasz,
            presentationID: "presentation-1"
        )
        await coordinator.handleMicrophonePermissionRevoked()
        XCTAssertEqual(coordinator.state.microphone, .unavailable)
        XCTAssertTrue(coordinator.voiceWritesRevoked)
        // Propozycja pozostaje widoczna do potwierdzenia z UI.
        XCTAssertEqual(coordinator.currentProposal?.id, proposal?.id)
        // Głos nie może wykonać zapisu.
        let viaVoice = await coordinator.confirmAction(
            actionID: proposal!.id,
            presentationID: proposal!.presentationID,
            origin: .authenticatedVoiceTurn,
            actor: DemoFixtures.tomasz
        )
        XCTAssertNil(viaVoice)
        // Przycisk w UI nadal działa.
        let viaButton = await coordinator.confirmAction(
            actionID: proposal!.id,
            presentationID: proposal!.presentationID,
            origin: .directUIButton,
            actor: DemoFixtures.tomasz
        )
        XCTAssertEqual(viaButton?.state, .queued)
    }

    func testReconnectDoesNotResendLastCommand() async throws {
        let transport = await attachMock(scenarioWithoutScript())
        await transport.emitManually(.connectionChanged(.connected))
        await settle()
        await coordinator.sendTextTurn(text: "Sprawdź plan na dziś", language: .pl, inputID: "turn-1")
        XCTAssertEqual(coordinator.lastUserUtterance, "Sprawdź plan na dziś")
        await coordinator.handleReconnected()
        // Licznik zdarzeń transportu nie zawiera drugiego wysłania tego samego polecenia.
        let sends = transport.recordedEvents.filter {
            if case .userTranscriptFinal = $0.payload { return true }
            return false
        }
        XCTAssertEqual(sends.count, 1, "Reconnect nie ponawia ostatniego polecenia")
    }

    func testCoordinatorUsesSingleBackendActionEngineAsUI() async throws {
        let transport = await attachMock(scenarioWithoutScript())
        await transport.emitManually(.connectionChanged(.connected))
        await settle()
        let proposal = await coordinator.prepareAction(
            kind: .reply,
            clientID: DemoFixtures.olenaID,
            caseID: DemoFixtures.caseOlenaID,
            threadID: DemoFixtures.olenaThread,
            text: "Wiadomość przez voice",
            actor: DemoFixtures.tomasz,
            presentationID: "presentation-1"
        )
        guard let proposal else { return XCTFail("brak propozycji") }

        // Wykonanie przez repozytorium (ta sama ścieżka co UI).
        let execution = await coordinator.confirmAction(
            actionID: proposal.id,
            presentationID: proposal.presentationID,
            origin: .directUIButton,
            actor: DemoFixtures.tomasz
        )
        XCTAssertEqual(execution?.state, .queued)
        // Powtórne potwierdzenie (np. głosem) nie tworzy drugiego wykonania:
        // zwraca to samo ID wyniku i ten sam wpis outboxa.
        let second = await coordinator.confirmAction(
            actionID: proposal.id,
            presentationID: proposal.presentationID,
            origin: .authenticatedVoiceTurn,
            actor: DemoFixtures.tomasz
        )
        XCTAssertEqual(second?.outboxID, execution?.outboxID)
        let status = try await repository.status(actionID: proposal.id)
        XCTAssertEqual(status.outboxID, execution?.outboxID)
        XCTAssertEqual(status.state, .queued)
    }

    func testRevisionThroughCoordinatorInvalidatesConsent() async throws {
        let transport = await attachMock(scenarioWithoutScript())
        await transport.emitManually(.connectionChanged(.connected))
        await settle()
        let proposal = await coordinator.prepareAction(
            kind: .reply,
            clientID: DemoFixtures.olenaID,
            caseID: DemoFixtures.caseOlenaID,
            threadID: DemoFixtures.olenaThread,
            text: "Treść pierwsza",
            actor: DemoFixtures.tomasz,
            presentationID: "presentation-1"
        )
        guard let proposal else { return XCTFail("brak propozycji") }
        XCTAssertTrue(coordinator.armVoiceConfirmation(actionID: proposal.id, presentationID: proposal.presentationID))

        let revised = await coordinator.reviseAction(actionID: proposal.id, newText: "Treść druga")
        XCTAssertEqual(revised?.version, Version(2))
        XCTAssertNil(coordinator.armedPresentationID)
        // Potwierdzenie ze starą prezentacją jest odrzucane.
        let stale = await coordinator.confirmAction(
            actionID: proposal.id,
            presentationID: proposal.presentationID,
            origin: .directUIButton,
            actor: DemoFixtures.tomasz
        )
        XCTAssertNil(stale)
    }

    func testMicrophoneMuteDoesNotEndSession() async throws {
        let transport = await attachMock(scenarioWithoutScript())
        await transport.emitManually(.connectionChanged(.connected))
        await settle()
        await coordinator.setMicrophoneMuted(true)
        await waitUntil("mikrofon wyciszony") { [self] in coordinator.state.microphone == .muted }
        XCTAssertEqual(coordinator.state.microphone, .muted)
        XCTAssertEqual(coordinator.state.connection, .connected)
        XCTAssertNotNil(coordinator.state.sessionID)
    }
}

// MARK: - Repozytorium demo (§etap 03–05, §12.2)

final class MockRepositoryTests: XCTestCase {

    private func makeRepository() -> MockRepository {
        MockRepository(clock: DemoClock(), artificialLatency: 0)
    }

    func testSeedDataMatchesPrototype() async throws {
        let repository = makeRepository()
        let clients = try await repository.clients(matching: "", stage: nil)
        XCTAssertEqual(clients.count, 4)
        XCTAssertEqual(clients.first?.displayName, "Olena Kovalenko")

        let todayEvents = try await repository.events(
            in: .day(DemoFixtures.referenceDay),
            ownerID: nil
        )
        XCTAssertEqual(todayEvents.count, 3)
        XCTAssertEqual(todayEvents.first?.time.hhmm, "10:30")

        let urgent = try await repository.tasks(filter: TaskFilter(scope: .open, dueOnOrBefore: DemoFixtures.referenceDay))
        XCTAssertEqual(urgent.count, 3)
        XCTAssertEqual(urgent.first?.priority, .urgent)
    }

    func testClientStageFilterSeparatesLeadsFromClients() async throws {
        let repository = makeRepository()
        let leads = try await repository.clients(matching: "", stage: .new)
        XCTAssertEqual(Set(leads.map(\.displayName)), ["Andrii Melnyk", "Maria Sokołowa"])
    }

    func testCaseConversionDoesNotCreateDuplicate() async throws {
        let repository = makeRepository()
        let first = try await repository.createCase(
            NewCaseDraft(
                clientID: DemoFixtures.andriiID,
                title: "Pomoc w sprawie zatrzymania",
                summary: "Zakres do ustalenia po pierwszej konsultacji.",
                ownerID: .tomasz,
                createdAt: DemoFixtures.referenceDay
            )
        )
        let second = try await repository.createCase(
            NewCaseDraft(
                clientID: DemoFixtures.andriiID,
                title: "Pomoc w sprawie zatrzymania",
                summary: "Zakres do ustalenia po pierwszej konsultacji.",
                ownerID: .tomasz,
                createdAt: DemoFixtures.referenceDay
            )
        )
        XCTAssertEqual(first.id, second.id)
        let all = try await repository.cases(status: nil)
        XCTAssertEqual(all.filter { $0.clientID == DemoFixtures.andriiID }.count, 1)
    }

    func testCaseConversionPromotesStageAndLinksLooseItems() async throws {
        let repository = makeRepository()
        let legalCase = try await repository.createCase(
            NewCaseDraft(
                clientID: DemoFixtures.andriiID,
                title: "Pomoc w sprawie zatrzymania",
                summary: "Zakres po konsultacji.",
                ownerID: .tomasz,
                createdAt: DemoFixtures.referenceDay
            )
        )
        let client = try await repository.client(id: DemoFixtures.andriiID)
        XCTAssertEqual(client?.stage, .client)
        XCTAssertEqual(client?.ownerID, .tomasz)

        let tasks = try await repository.tasks(filter: TaskFilter(scope: .all, clientID: DemoFixtures.andriiID))
        XCTAssertTrue(tasks.allSatisfy { $0.caseID == legalCase.id }, "Luźne zadania zostają powiązane ze sprawą")
    }

    func testChangingClientOwnerDoesNotMoveEventAssignment() async throws {
        let repository = makeRepository()
        let before = try await repository.events(in: .day(DemoFixtures.referenceDay), ownerID: nil)
        let olenaEvent = before.first { $0.clientID == DemoFixtures.olenaID }
        let client = try await repository.client(id: DemoFixtures.olenaID)
        _ = try await repository.assignOwner(
            clientID: DemoFixtures.olenaID,
            ownerID: .pawel,
            expectedVersion: client!.version
        )
        let after = try await repository.events(in: .day(DemoFixtures.referenceDay), ownerID: nil)
        XCTAssertEqual(
            after.first { $0.id == olenaEvent?.id }?.ownerID,
            .tomasz,
            "Zmiana opiekuna klienta nie przepisuje prowadzącego terminu"
        )
        XCTAssertEqual(after.first { $0.id == olenaEvent?.id }?.version, olenaEvent?.version)
    }

    func testOptimisticLockingRejectsStaleUpdate() async throws {
        let repository = makeRepository()
        var client = try await repository.client(id: DemoFixtures.olenaID)!
        client.briefing = "Pierwsza zmiana"
        let updated = try await repository.updateClient(client, expectedVersion: client.version)
        XCTAssertEqual(updated.version, client.version.next())
        // Druga kopia z tym samym numerem wersji nie przechodzi.
        do {
            _ = try await repository.updateClient(client, expectedVersion: client.version)
            XCTFail("Oczekiwano konfliktu wersji")
        } catch let error as DomainError {
            guard case .versionConflict = error else { return XCTFail("Zły błąd: \(error)") }
        }
    }

    func testEventOverlapIsRejectedForSameOwner() async throws {
        let repository = makeRepository()
        do {
            _ = try await repository.createEvent(
                NewEventDraft(
                    clientID: DemoFixtures.mariaID,
                    caseID: nil,
                    title: "Konsultacja kolidująca",
                    day: DemoFixtures.referenceDay,
                    time: TimeOfDay(hhmm: "10:45")!,
                    durationMinutes: 30,
                    ownerID: .tomasz,
                    kind: .consultation,
                    status: .toConfirm,
                    place: "Online"
                )
            )
            XCTFail("Oczekiwano kolizji prowadzącego")
        } catch let error as DomainError {
            guard case .validationFailed(let reason) = error else { return XCTFail("Zły błąd") }
            XCTAssertTrue(reason.contains("10:30"), "Komunikat wskazuje kolidujące wydarzenie")
        }
    }

    func testBackToBackEventsDoNotOverlap() async throws {
        let repository = makeRepository()
        // 10:30–11:00 i 11:00–11:30 nie kolidują.
        let event = try await repository.createEvent(
            NewEventDraft(
                clientID: DemoFixtures.mariaID,
                caseID: nil,
                title: "Konsultacja stykowa",
                day: DemoFixtures.referenceDay,
                time: TimeOfDay(hhmm: "11:00")!,
                durationMinutes: 30,
                ownerID: .tomasz,
                kind: .consultation,
                status: .confirmed,
                place: "Online"
            )
        )
        XCTAssertEqual(event.time.hhmm, "11:00")
    }

    func testConfirmedEventRequiresOwner() async throws {
        let repository = makeRepository()
        var event = try await repository.event(id: DemoFixtures.eventAndriiID)!
        XCTAssertEqual(event.status, .toConfirm)
        XCTAssertNil(event.ownerID)
        event.status = .confirmed
        do {
            _ = try await repository.updateEvent(event, expectedVersion: event.version)
            XCTFail("Potwierdzenie bez prowadzącego nie może przejść")
        } catch let error as DomainError {
            guard case .validationFailed(let reason) = error else { return XCTFail("Zły błąd") }
            XCTAssertTrue(reason.contains("prowadzącego"))
        }
    }

    func testOutgoingMessageStartsAsPendingWithIdempotencyKey() async throws {
        let repository = makeRepository()
        let draft = OutgoingMessageDraft(
            threadID: DemoFixtures.olenaThread,
            text: "Дякую, до зустрічі о 10:30.",
            authorID: .tomasz,
            language: .uk,
            sentAt: Date(timeIntervalSince1970: 1_789_100_000),
            idempotencyKey: "key-1"
        )
        let first = try await repository.appendOutgoing(draft)
        let second = try await repository.appendOutgoing(draft)
        XCTAssertEqual(first.id, second.id, "Ten sam klucz idempotencji zwraca tę samą wiadomość")
        XCTAssertEqual(first.transport, .pending, "Ręczna wysyłka oczekuje, nie jest od razu wysłana")
        XCTAssertEqual(first.source, .app)
    }

    func testProviderStatusLadderMonotonicViaRepository() async throws {
        let repository = makeRepository()
        let first = try await repository.applyProviderStatus(
            providerMessageID: "wamid.demo.dmytro.2",
            status: .read,
            at: Date()
        )
        XCTAssertEqual(first?.transport, .read)
        // Późniejsze zdarzenie „sent” nie cofa stanu.
        let second = try await repository.applyProviderStatus(
            providerMessageID: "wamid.demo.dmytro.2",
            status: .sent,
            at: Date()
        )
        XCTAssertEqual(second?.transport, .read)
    }

    func testUnknownProviderMessageReturnsNilWithoutCreatingAnything() async throws {
        let repository = makeRepository()
        let before = await repository.snapshot()
        let result = try await repository.applyProviderStatus(
            providerMessageID: "wamid.nieznany",
            status: .delivered,
            at: Date()
        )
        XCTAssertNil(result, "Status bez znanej wysyłki nie tworzy wiadomości")
        let after = await repository.snapshot()
        XCTAssertEqual(before.messages.count, after.messages.count)
    }

    func testPaginationBeforeSequenceReturnsOlderHistory() async throws {
        let longThread = DemoFixtures.longThreadMessageCount(80)
        var dataset = DemoFixtures.dataset()
        dataset.messages = longThread.filter { $0.threadID == DemoFixtures.olenaThread }
        dataset.threads = [
            ConversationThread(
                id: DemoFixtures.olenaThread,
                clientID: DemoFixtures.olenaID,
                sequenceHighWatermark: 80
            )
        ]
        let repository = MockRepository(dataset: dataset, clock: DemoClock(), artificialLatency: 0)

        let latest = try await repository.latestMessages(threadID: DemoFixtures.olenaThread, limit: 30)
        XCTAssertEqual(latest.count, 30)
        XCTAssertEqual(latest.last?.sequence, 80)

        let older = try await repository.messages(
            threadID: DemoFixtures.olenaThread,
            before: latest.first!.sequence,
            limit: 30
        )
        XCTAssertEqual(older.count, 30)
        XCTAssertTrue(older.allSatisfy { $0.sequence < latest.first!.sequence })
        XCTAssertEqual(older.last?.sequence, 50)
    }

    func testReadStateIsPerUserAndOnlyMovesForward() async throws {
        let repository = makeRepository()
        // Kursor Pawła czytamy z **tego samego** repozytorium, przed operacją Tomasza:
        // tylko wtedy porównanie „przed/po” cokolwiek dowodzi.
        let pawelCursorBefore = try await repository.readStates(userID: .pawel)
            .first { $0.threadID == DemoFixtures.andriiThread }?
            .readCursorSequence

        var states = try await repository.readStates(userID: .tomasz)
        guard let state = states.first(where: { $0.threadID == DemoFixtures.andriiThread }) else {
            return XCTFail("brak stanu wątku")
        }
        var opened = state
        opened.readCursorSequence = ReadStatePolicy.cursorAfterOpeningThread(
            current: state.readCursorSequence,
            snapshotSequenceAtOpen: 2
        )
        _ = try await repository.saveReadState(opened)

        // Próba cofnięcia kursora nie przechodzi.
        var backwards = opened
        backwards.readCursorSequence = 0
        _ = try await repository.saveReadState(backwards)

        states = try await repository.readStates(userID: .tomasz)
        let tomasz = states.first { $0.threadID == DemoFixtures.andriiThread }
        XCTAssertEqual(tomasz?.readCursorSequence, 2)

        // Kursor drugiego prawnika pozostaje nietknięty. Porównujemy stan sprzed
        // operacji ze stanem po niej — obaj prawnicy mają w demo różne kursory,
        // więc porównywanie z wartością Tomasza nie mówiłoby nic o niezależności.
        let pawelStates = try await repository.readStates(userID: .pawel)
        let pawelCursor = pawelStates.first { $0.threadID == DemoFixtures.andriiThread }?.readCursorSequence
        XCTAssertEqual(
            pawelCursor,
            pawelCursorBefore,
            "Odczyt Tomasza nie może zmienić kursora Pawła"
        )
    }

    func testUnreadCountFromRepositoryMatchesPolicy() async throws {
        let repository = makeRepository()
        let states = try await repository.readStates(userID: .tomasz)
        var total = 0
        for thread in try await repository.threads() {
            let messages = try await repository.latestMessages(threadID: thread.id, limit: 100)
            let state = states.first { $0.threadID == thread.id }
                ?? ThreadUserState(userID: .tomasz, threadID: thread.id)
            total += ReadStatePolicy.unreadCount(in: messages, state: state)
        }
        XCTAssertEqual(total, 3, "Andrii 2 + Maria 1, reszta przeczytana")
    }

    func testDraftIsScopedToThreadAndClearedAfterSending() async throws {
        let repository = makeRepository()
        let draft = Draft(
            threadID: DemoFixtures.olenaThread,
            text: "Szkic odpowiedzi",
            language: .uk,
            quote: QuotedReference(
                messageID: MessageID("msg-olena-1"),
                authorLabel: "Olena Kovalenko",
                text: "Дякую, надішлю документи до зустрічі."
            )
        )
        try await repository.saveDraft(draft)
        var states = try await repository.readStates(userID: .tomasz)
        XCTAssertEqual(states.first { $0.threadID == DemoFixtures.olenaThread }?.draft?.text, "Szkic odpowiedzi")
        XCTAssertEqual(
            states.first { $0.threadID == DemoFixtures.olenaThread }?.draft?.quote?.authorLabel,
            "Olena Kovalenko"
        )

        _ = try await repository.appendOutgoing(
            OutgoingMessageDraft(
                threadID: DemoFixtures.olenaThread,
                text: "Szkic odpowiedzi",
                authorID: .tomasz,
                language: .uk,
                sentAt: Date(),
                idempotencyKey: "key-draft"
            )
        )
        states = try await repository.readStates(userID: .tomasz)
        XCTAssertNil(states.first { $0.threadID == DemoFixtures.olenaThread }?.draft, "Wysłanie czyści szkic")
    }

    func testVoiceSessionContextUpdateIsVersioned() async throws {
        let repository = makeRepository()
        let configuration = try await repository.create(
            CreateVoiceSession(
                userID: .tomasz,
                context: AssistantContext(scope: .firm),
                assistantLanguage: .ru,
                installationID: "device-1"
            )
        )
        let newContext = AssistantContext.client(DemoFixtures.olenaID)
        let updated = try await repository.updateContext(
            UpdateVoiceContext(
                sessionID: configuration.sessionID,
                context: newContext,
                expectedContextVersion: configuration.context.version
            )
        )
        XCTAssertEqual(updated.version, Version(2))
        XCTAssertEqual(updated.clientID, DemoFixtures.olenaID)

        // Powtórzenie ze starą wersją jest konfliktem.
        do {
            _ = try await repository.updateContext(
                UpdateVoiceContext(
                    sessionID: configuration.sessionID,
                    context: newContext,
                    expectedContextVersion: configuration.context.version
                )
            )
            XCTFail("Oczekiwano konfliktu wersji kontekstu")
        } catch let error as DomainError {
            guard case .versionConflict = error else { return XCTFail("Zły błąd: \(error)") }
        }
    }

    func testInconsistentVoiceContextIsRejected() async throws {
        let repository = makeRepository()
        let configuration = try await repository.create(
            CreateVoiceSession(
                userID: .tomasz,
                context: AssistantContext(scope: .firm),
                assistantLanguage: .ru,
                installationID: "device-1"
            )
        )
        let bad = AssistantContext(scope: .legalCase, clientID: DemoFixtures.dmytroID, caseID: DemoFixtures.caseOlenaID)
        do {
            _ = try await repository.updateContext(
                UpdateVoiceContext(
                    sessionID: configuration.sessionID,
                    context: bad,
                    expectedContextVersion: configuration.context.version
                )
            )
            XCTFail("Niespójny kontekst musi być odrzucony")
        } catch let error as DomainError {
            guard case .validationFailed = error else { return XCTFail("Zły błąd: \(error)") }
        }
    }

    func testTaskWithMismatchedCaseIsRejected() async throws {
        let repository = makeRepository()
        do {
            _ = try await repository.createTask(
                NewTaskDraft(
                    title: "Zadanie z cudzą sprawą",
                    clientID: DemoFixtures.olenaID,
                    caseID: DemoFixtures.caseDmytroID,
                    ownerID: .tomasz,
                    dueDate: DemoFixtures.referenceDay
                )
            )
            XCTFail("Sprawa innego klienta musi być odrzucona")
        } catch let error as DomainError {
            guard case .validationFailed = error else { return XCTFail("Zły błąd: \(error)") }
        }
    }

    func testTaskAutoLinksActiveCaseOfClient() async throws {
        let repository = makeRepository()
        let task = try await repository.createTask(
            NewTaskDraft(
                title: "Zadanie bez wskazanej sprawy",
                clientID: DemoFixtures.olenaID,
                caseID: nil,
                ownerID: .tomasz,
                dueDate: DemoFixtures.referenceDay
            )
        )
        XCTAssertEqual(task.caseID, DemoFixtures.caseOlenaID)
    }

    func testSwitchingUserKeepsSeparateReadStates() async throws {
        let repository = makeRepository()
        let pawel = try await repository.switchUser(to: .pawel)
        XCTAssertEqual(pawel.id, .pawel)
        let current = try await repository.currentUser()
        XCTAssertEqual(current.id, .pawel)
    }
}
