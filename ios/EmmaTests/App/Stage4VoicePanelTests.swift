import XCTest
@testable import Emma

// MARK: - Etap 4: powłoka widzi stan sesji (F06)
//
// Mini-panel czyta stan z `AppDependencies.voiceState`, a nie z własnej
// subskrypcji koordynatora. Ten test pilnuje, że lustro faktycznie się
// aktualizuje i że wyciszenie oraz zakończenie przechodzą jedną ścieżką —
// bez tworzenia drugiej sesji.

@MainActor
final class Stage4VoicePanelTests: XCTestCase {

    private let clock = DemoClock()

    private func configuration() -> VoiceSessionConfiguration {
        VoiceSessionConfiguration(
            sessionID: VoiceSessionID("session-mirror"),
            context: AssistantContext(scope: .firm),
            assistantLanguage: .ru,
            conversationToken: "test-token",
            expiresAt: clock.now().addingTimeInterval(600),
            capabilities: .mock
        )
    }

    private func attachManualSession(_ dependencies: AppDependencies) async -> MockVoiceTransport {
        let transport = MockVoiceTransport(
            scenario: VoiceScenario(name: "manual", steps: []),
            delayProvider: { _ in }
        )
        await dependencies.voice.attach(transport: transport, configuration: configuration())
        // Zdarzenia mocka płyną strumieniem asynchronicznym — czekamy na stan
        // połączony, zamiast zakładać, że dotarł synchronicznie.
        await transport.emitManually(.connectionChanged(.connected))
        await settle()
        return transport
    }

    /// Krótka pauza na przejście zdarzenia przez strumień (wzorzec z testów koordynatora).
    private func settle(_ milliseconds: Int = 80) async {
        try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    func testShellMirrorFollowsSessionLifecycle() async {
        let dependencies = AppDependencies.demo()
        XCTAssertFalse(dependencies.voiceState.showsGlobalVoicePanel)

        _ = await attachManualSession(dependencies)
        XCTAssertTrue(
            dependencies.voiceState.showsGlobalVoicePanel,
            "Panel nie pojawił się po starcie sesji"
        )
        XCTAssertEqual(dependencies.voiceState.connection, .connected)
        XCTAssertEqual(dependencies.voiceState.sessionID, VoiceSessionID("session-mirror"))

        await dependencies.endVoiceSession()
        XCTAssertFalse(
            dependencies.voiceState.showsGlobalVoicePanel,
            "Panel został po zakończeniu rozmowy"
        )
    }

    /// Jedna sesja: wyciszenie mikrofonu nie tworzy drugiego połączenia.
    ///
    /// Po starcie mikrofon jest jeszcze „niedostępny”, więc pierwsze dotknięcie
    /// go **włącza** (to samo, co użytkownik widzi jako „Włącz mikrofon”),
    /// a drugie wycisza.
    func testTogglingMicrophoneUsesTheSingleSession() async {
        let dependencies = AppDependencies.demo()
        _ = await attachManualSession(dependencies)
        let sessionID = dependencies.voice.state.sessionID
        XCTAssertFalse(dependencies.voiceState.isCapturingMicrophone)

        await dependencies.toggleVoiceMicrophone()
        await settle()
        XCTAssertEqual(dependencies.voiceState.microphone, .capturing)
        XCTAssertTrue(dependencies.voiceState.isCapturingMicrophone)
        XCTAssertEqual(dependencies.voiceState.sessionHeadline, "Emma czeka")

        await dependencies.toggleVoiceMicrophone()
        await settle()
        XCTAssertEqual(dependencies.voiceState.microphone, .muted)
        XCTAssertEqual(dependencies.voiceState.sessionHeadline, "Mikrofon wyciszony")
        XCTAssertTrue(dependencies.voiceState.showsGlobalVoicePanel)
        XCTAssertEqual(dependencies.voice.state.sessionID, sessionID, "Sesja zmieniła się przy wyciszeniu")
    }

    func testEndingFromShellReleasesSession() async {
        let dependencies = AppDependencies.demo()
        _ = await attachManualSession(dependencies)

        await dependencies.endVoiceSession()
        XCTAssertEqual(dependencies.voice.state.connection, .ended)
        XCTAssertNil(
            dependencies.voice.state.sessionID,
            "Zakończona sesja nadal trzyma identyfikator"
        )
    }
}
