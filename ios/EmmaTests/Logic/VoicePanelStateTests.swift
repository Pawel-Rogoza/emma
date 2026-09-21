import XCTest
@testable import Emma

// MARK: - Etap 4: globalny mini-panel i jeden uczciwy stan sesji (F06, F07)
//
// Panel sterowania ma być widoczny na każdej zakładce poza „Emma” i nad arkuszem
// modalnym, dopóki sesja istnieje — także wyciszona i w trakcie odtwarzania.
// Nagłówek ma być jeden i bez żargonu: bez sesji „Gotowa do rozmowy”, a nie
// „Połączenie: Nieaktywna · Mikrofon niedostępny”.

final class VoicePanelStateTests: XCTestCase {

    private let reducer = VoiceStateReducer()
    private let sessionID = VoiceSessionID("session-panel")

    private func event(_ payload: VoiceEventPayload, generation: UInt64 = 1) -> VoiceEvent {
        VoiceEvent(
            eventID: "e-panel",
            sessionID: sessionID,
            connectionGeneration: ConnectionGeneration(generation),
            receivedAt: Date(timeIntervalSince1970: 1_789_100_000),
            source: .mockTransport,
            payload: payload
        )
    }

    private func liveSessionState() -> VoiceUIState {
        var state = VoiceUIState()
        reducer.apply(event(.connectionChanged(.connected)), to: &state)
        state.sessionID = sessionID
        return state
    }

    // MARK: Widoczność panelu

    func testPanelIsHiddenWithoutSession() {
        XCTAssertFalse(VoiceUIState().showsGlobalVoicePanel)
    }

    func testPanelIsVisibleForLiveSession() {
        XCTAssertTrue(liveSessionState().showsGlobalVoicePanel)
    }

    /// Wyciszenie nie kończy rozmowy, więc panel zostaje (mikrofon można włączyć).
    func testPanelStaysVisibleWhenMicrophoneIsMuted() {
        var state = liveSessionState()
        reducer.apply(event(.microphoneChanged(.muted)), to: &state)
        XCTAssertTrue(state.showsGlobalVoicePanel)
        XCTAssertEqual(state.sessionHeadline, "Mikrofon wyciszony")
    }

    /// Przerwane połączenie nadal potrzebuje „Zakończ”, więc panel zostaje.
    func testPanelStaysVisibleWhenConnectionFailed() {
        var state = liveSessionState()
        reducer.apply(event(.connectionChanged(.failed), generation: 2), to: &state)
        XCTAssertTrue(state.showsGlobalVoicePanel)
        XCTAssertEqual(state.sessionHeadline, "Rozmowa niedostępna")
    }

    func testPanelDisappearsAfterSessionEnds() {
        var state = liveSessionState()
        reducer.apply(event(.connectionChanged(.ended), generation: 2), to: &state)
        XCTAssertFalse(state.showsGlobalVoicePanel)
        XCTAssertEqual(state.sessionHeadline, "Gotowa do rozmowy")
    }

    // MARK: Jeden nagłówek bez żargonu

    func testHeadlineWalksThroughTurnStates() {
        var state = liveSessionState()
        XCTAssertEqual(state.sessionHeadline, "Emma czeka")

        reducer.apply(event(.userSpeechStarted), to: &state)
        XCTAssertEqual(state.sessionHeadline, "Słucham")

        reducer.apply(event(.userTranscriptFinal("sprawdź termin")), to: &state)
        XCTAssertEqual(state.sessionHeadline, "Przygotowuję odpowiedź")

        reducer.apply(event(.playbackStarted(approximate: false)), to: &state)
        XCTAssertEqual(state.sessionHeadline, "Emma mówi")
    }

    /// Gdy Emma mówi, wyciszony mikrofon nie jest najważniejszą informacją.
    func testSpeakingWinsOverMutedMicrophone() {
        var state = liveSessionState()
        reducer.apply(event(.microphoneChanged(.muted)), to: &state)
        reducer.apply(event(.playbackStarted(approximate: false)), to: &state)
        XCTAssertEqual(state.sessionHeadline, "Emma mówi")
    }

    func testHeadlineShowsConnectionProgressBeforeTurn() {
        var connecting = VoiceUIState()
        reducer.apply(event(.connectionChanged(.connecting)), to: &connecting)
        XCTAssertEqual(connecting.sessionHeadline, "Łączę z Emmą")

        var requesting = VoiceUIState()
        reducer.apply(event(.connectionChanged(.requestingPermission)), to: &requesting)
        XCTAssertEqual(requesting.sessionHeadline, "Uruchamiam mikrofon")

        var reconnecting = liveSessionState()
        reducer.apply(event(.connectionChanged(.reconnecting), generation: 2), to: &reconnecting)
        XCTAssertEqual(reconnecting.sessionHeadline, "Odtwarzam połączenie")
    }

    // MARK: Mikrofon w panelu

    func testCapturingFlagDrivesMuteButton() {
        var state = liveSessionState()
        reducer.apply(event(.microphoneChanged(.capturing)), to: &state)
        XCTAssertTrue(state.isCapturingMicrophone)

        reducer.apply(event(.microphoneChanged(.muted)), to: &state)
        XCTAssertFalse(state.isCapturingMicrophone)
    }
}

// MARK: - Etap 5: tożsamość tury dla historii rozmowy (F04)
//
// Historia nie może dopisać tej samej wypowiedzi dwa razy tylko dlatego, że
// stan został opublikowany ponownie. Kluczem jest `turnID` (a gdy go nie ma —
// `eventID`), nie treść: to samo „tak” wypowiedziane dwa razy to dwie tury.

final class VoiceTurnIdentityTests: XCTestCase {

    private let reducer = VoiceStateReducer()
    private let sessionID = VoiceSessionID("session-history")

    private func event(
        _ payload: VoiceEventPayload,
        eventID: String = "e1",
        turnID: String? = "turn-1"
    ) -> VoiceEvent {
        VoiceEvent(
            eventID: eventID,
            sessionID: sessionID,
            connectionGeneration: ConnectionGeneration(1),
            turnID: turnID,
            receivedAt: Date(timeIntervalSince1970: 1_789_100_000),
            source: .mockTransport,
            payload: payload
        )
    }

    /// Zdarzenia poza połączoną sesją są odrzucane (generacja/połączenie), więc
    /// historię sprawdzamy na sesji, która naprawdę stoi.
    private func connectedState() -> VoiceUIState {
        var state = VoiceUIState()
        reducer.apply(
            VoiceEvent(
                eventID: "connected",
                sessionID: sessionID,
                connectionGeneration: ConnectionGeneration(1),
                receivedAt: Date(timeIntervalSince1970: 1_789_100_000),
                source: .mockTransport,
                payload: .connectionChanged(.connected)
            ),
            to: &state
        )
        state.sessionID = sessionID
        return state
    }

    func testFinalTranscriptCarriesTurnIdentity() {
        var state = connectedState()
        reducer.apply(event(.userTranscriptFinal("wyślij")), to: &state)
        XCTAssertEqual(state.committedUserTurnID, "turn-1")
        XCTAssertEqual(state.committedUserTranscript, "wyślij")
    }

    func testTurnIdentityFallsBackToEventID() {
        var state = connectedState()
        reducer.apply(
            event(.userTranscriptFinal("tak"), eventID: "event-9", turnID: nil),
            to: &state
        )
        XCTAssertEqual(state.committedUserTurnID, "event-9")
    }

    /// Ponowne zastosowanie tego samego zdarzenia nie zmienia tożsamości tury.
    func testReapplyingSameEventKeepsIdentity() {
        var state = connectedState()
        let final = event(.userTranscriptFinal("zapisz"), turnID: "turn-7")
        reducer.apply(final, to: &state)
        let identity = state.committedUserTurnID
        reducer.apply(final, to: &state)
        XCTAssertEqual(state.committedUserTurnID, identity)
        XCTAssertEqual(state.committedUserTurnID, "turn-7")
    }

    func testSecondUtteranceGetsNewIdentity() {
        var state = connectedState()
        reducer.apply(event(.userTranscriptFinal("pierwsza"), turnID: "turn-1"), to: &state)
        reducer.apply(event(.userTranscriptFinal("druga"), eventID: "e2", turnID: "turn-2"), to: &state)
        XCTAssertEqual(state.committedUserTurnID, "turn-2")
        XCTAssertEqual(state.committedUserTranscript, "druga")
    }

    func testAgentTextCarriesItsOwnTurnIdentity() {
        var state = connectedState()
        reducer.apply(event(.agentTextFinal("Gotowe."), turnID: "agent-turn-3"), to: &state)
        XCTAssertEqual(state.agentTurnID, "agent-turn-3")
        XCTAssertEqual(state.agentText, "Gotowe.")
    }

    /// Nowa sesja zaczyna się od czystego stanu, więc klucze tur nie kolidują
    /// z poprzednią rozmową (transport numeruje je od nowa).
    func testNewSessionStartsWithoutTurnIdentity() {
        let fresh = VoiceUIState(connection: .connecting, mode: .conversation)
        XCTAssertNil(fresh.committedUserTurnID)
        XCTAssertNil(fresh.agentTurnID)
    }
}
