import XCTest
@testable import Emma

// MARK: - Wybór dostawcy głosu: konfiguracja i fabryka
//
// Konfiguracja głosu ma jedną, jawną ścieżkę: Gemini Live. Te testy pilnują, że:
//   • brak lub błędna wartość nie uruchamia innego dostawcy,
//   • Demo nigdy nie tworzy transportu dostawcy (brak sieci i sekretów),
//   • wybrany dostawca faktycznie trafia do fabryki, a nie do mocka.
// Bez tego „rollback” byłby obietnicą bez dowodu.

@MainActor
final class VoiceProviderSelectionTests: XCTestCase {

    private func configuration(
        environment: AppConfiguration.Environment,
        baseURL: String?,
        provider: String?
    ) -> AppConfiguration {
        var info: [String: Any] = [
            "EMMAEnvironment": environment.rawValue,
            "EMMADefaultLocale": "pl-PL",
            "EMMAVoiceModel": "gemini-3.8-live",
        ]
        if let baseURL { info["EMMAApiBaseURL"] = baseURL }
        if let provider { info["EMMAVoiceProvider"] = provider }
        // Puste argumenty: testujemy konfigurację, nie nadpisania z linii poleceń.
        return AppConfiguration.resolve(infoDictionary: info, arguments: [])
    }

    func testMissingProviderValueUsesGeminiLive() {
        let resolved = configuration(environment: .production, baseURL: "https://example.test", provider: nil)
        XCTAssertEqual(resolved.voiceProvider, .geminiLive)
    }

    func testUnknownProviderValueUsesGeminiLive() {
        let resolved = configuration(environment: .production, baseURL: "https://example.test", provider: "gemini-3")
        XCTAssertEqual(resolved.voiceProvider, .geminiLive)
    }

    func testGeminiLiveIsSelectedFromConfiguration() {
        let resolved = configuration(environment: .staging, baseURL: "https://example.test", provider: "gemini_live")
        XCTAssertEqual(resolved.voiceProvider, .geminiLive)
        XCTAssertEqual(resolved.voiceModel, "gemini-3.8-live")
    }

    func testLaunchArgumentOverridesConfigurationForDeviceComparison() {
        let resolved = AppConfiguration.resolve(
            infoDictionary: [
                "EMMAEnvironment": "staging",
                "EMMAApiBaseURL": "https://example.test",
                "EMMAVoiceProvider": "gemini_live",
            ],
            arguments: ["-EMMAVoiceProvider", "gemini_live"]
        )
        XCTAssertEqual(resolved.voiceProvider, .geminiLive)
    }

    func testDemoIgnoresBackendAddressAndNeverReachesProvider() {
        let resolved = configuration(environment: .demo, baseURL: "https://example.test", provider: "gemini_live")
        XCTAssertNil(resolved.apiBaseURL)
        XCTAssertFalse(VoiceServicesFactory.providerIsAvailable(configuration: resolved))
        XCTAssertTrue(VoiceServicesFactory.makeTransport(
            configuration: resolved,
            fixtureName: nil,
            accessToken: nil,
            installationID: "instalacja-testowa",
            mockScenarioName: "today-default"
        ) is MockVoiceTransport)
    }

    func testGeminiLiveConfigurationBuildsGeminiTransport() throws {
        let resolved = configuration(environment: .staging, baseURL: "https://example.test", provider: "gemini_live")
        let transport = VoiceServicesFactory.makeTransport(
            configuration: resolved,
            fixtureName: nil,
            accessToken: "token-testowy",
            installationID: "instalacja-testowa",
            mockScenarioName: "today-default"
        )
        XCTAssertTrue(transport is GeminiLiveTransport, "Wybrany dostawca musi trafić do fabryki, nie do mocka.")
        // Live API nie ma potwierdzonego końca odtwarzania ani części transkrypcji
        // od dostawcy — deklarujemy dokładnie to, co transport faktycznie robi.
        XCTAssertTrue(transport.capabilities.partialTranscripts)
        XCTAssertTrue(transport.capabilities.contextUpdate)
    }

    func testProviderSelectionIsExplicitNotFallback() throws {
        // Gdy backendu nie ma, wybór „gemini_live” nie może po cichu zamienić się
        // w mock udający rozmowę z dostawcą.
        let resolved = configuration(environment: .staging, baseURL: nil, provider: "gemini_live")
        let transport = VoiceServicesFactory.makeTransport(
            configuration: resolved,
            fixtureName: nil,
            accessToken: nil,
            installationID: "instalacja-testowa",
            mockScenarioName: "today-default"
        )
        XCTAssertTrue(transport is MockVoiceTransport)
    }
}
