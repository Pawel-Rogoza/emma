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
