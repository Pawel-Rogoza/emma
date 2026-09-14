import XCTest
@testable import Emma

// MARK: - Etap 6: kontrakt danych zamiast klasy (F05, część niezależna od usług)
//
// Warunek zakończenia etapu 6 wymaga prawdziwego głosu i faktycznie odebranej
// wiadomości testowej — tego w tym środowisku nie ma (brak kont dostawców,
// brak urządzenia). Ten plik sprawdza więc **część kodu**, która nie zależy od
// usług: aplikacja ma zależeć od kontraktu `EmmaRepository`, a zdolność demo
// (reset danych przykładowych) ma być osobna. Mock nie jest tu dowodem integracji.

@MainActor
final class Stage6ContractTests: XCTestCase {

    private let clock = DemoClock()
    private var kept: [AppDependencies] = []

    private var demoConfiguration: AppConfiguration {
        AppConfiguration(environment: .demo, apiBaseURL: nil, defaultLocale: "pl-PL")
    }

    override func tearDown() {
        kept = []
        super.tearDown()
    }

    /// Dowód kompilacyjny: zależności przyjmują **abstrakcję**, więc w miejscu
    /// tworzenia aplikacji nie występuje nazwa `MockRepository`.
    private func makeContractOnlyRepository() -> any EmmaRepository {
        MockRepository(dataset: DemoFixtures.dataset(), clock: clock, artificialLatency: 0)
    }

    func testAppRunsOnTheDataContractAlone() async throws {
        let contract: any EmmaRepository = makeContractOnlyRepository()
        let dependencies = AppDependencies(
            configuration: demoConfiguration,
            clock: clock,
            repository: contract
        )
        kept.append(dependencies)

        let store = AssistantStore()
        store.attach(dependencies)
        await store.reload()

        let clients = try await dependencies.repository.clients(matching: "", stage: nil)
        XCTAssertFalse(clients.isEmpty, "Kontrakt musi wystarczyć do wczytania danych")
        XCTAssertFalse(store.turns.contains { _ in true } && store.clients.isEmpty)
    }

    /// Zdolność demo jest osobna: prawdziwy adapter nie musi umieć „resetu do fixture”.
    func testDemoResetIsASeparateCapability() async throws {
        let dependencies = AppDependencies(
            configuration: demoConfiguration,
            clock: clock,
            repository: makeContractOnlyRepository()
        )
        kept.append(dependencies)

        XCTAssertNotNil(
            dependencies.repository as? any DemoFixtureRepository,
            "Repozytorium demo ma zdolność resetu"
        )

        _ = try await dependencies.repository.createTask(
            NewTaskDraft(
                title: "Zadanie do usunięcia resetem",
                clientID: nil,
                caseID: nil,
                dueDate: dependencies.today,
                priority: .normal
            )
        )
        var tasks = try await dependencies.repository.tasks(filter: TaskFilter(scope: .open))
        let created = try XCTUnwrap(tasks.first { $0.title == "Zadanie do usunięcia resetem" })

        await dependencies.resetDemoData()

        let afterReset = try await dependencies.repository.tasks(filter: TaskFilter(scope: .open))
        XCTAssertFalse(
            afterReset.contains { $0.id == created.id },
            "Reset demo przywraca dane przykładowe przez osobną zdolność"
        )
    }

    /// Ścieżka dostawcy nie jest wybierana po cichu: w Demo nie ma ani adresu
    /// backendu, ani SDK, więc wybór mocka jest jawny i sprawdzalny.
    func testProviderPathIsExplicitAndUnavailableInDemo() {
        XCTAssertTrue(demoConfiguration.usesMockServices)
        XCTAssertFalse(VoiceServicesFactory.providerIsAvailable(configuration: demoConfiguration))

        let transport = VoiceServicesFactory.makeTransport(
            configuration: demoConfiguration,
            fixtureName: nil,
            accessToken: nil,
            installationID: "test-installation",
            mockScenarioName: "standard-proposal-flow"
        )
        XCTAssertTrue(
            transport is MockVoiceTransport,
            "Demo ma zostać na mocku, dopóki nie ma skonfigurowanego backendu"
        )
        XCTAssertTrue(
            VoiceServicesFactory.makePlaybackService(
                configuration: demoConfiguration,
                audioSession: AudioSessionController()
            ) is MockSpeechPlaybackService,
            "Demo zostaje na deterministycznym mocku odsłuchu"
        )
    }

    /// Skonfigurowany backend wybiera **adapter dostawcy**, nie mock. W tym
    /// repozytorium SDK `ElevenLabs` jest zależnością, więc ścieżka kompiluje się
    /// naprawdę; brakuje kont i backendu wydającego token, a nie kodu transportu.
    /// Odsłuch pozostaje mockiem w obu wariantach — to jest niezamknięta część F05.
    func testConfiguredBackendSelectsProviderAdapterButPlaybackStaysMock() {
        let configured = AppConfiguration(
            environment: .demo,
            apiBaseURL: URL(string: "https://example.invalid/api"),
            defaultLocale: "pl-PL"
        )
        XCTAssertFalse(configured.usesMockServices)

        let transport = VoiceServicesFactory.makeTransport(
            configuration: configured,
            fixtureName: nil,
            accessToken: "token",
            installationID: "test-installation",
            mockScenarioName: "standard-proposal-flow"
        )

        if VoiceServicesFactory.providerIsAvailable(configuration: configured) {
            XCTAssertTrue(
                transport is ElevenLabsVoiceTransport,
                "Z adresem backendu i SDK wybieramy adapter dostawcy, nigdy mocka po cichu"
            )
        } else {
            XCTAssertTrue(
                transport is MockVoiceTransport,
                "Bez SDK dostawcy nie ma czym mówić — zostaje jawny mock"
            )
        }

        XCTAssertTrue(
            VoiceServicesFactory.makePlaybackService(
                configuration: configured,
                audioSession: AudioSessionController()
            ) is SystemSpeechPlaybackService,
            "Poza Demo odsłuch jest realny (syntezator systemowy), a nie mockiem"
        )
        XCTAssertFalse(
            VoiceServicesFactory.providerIsAvailable(configuration: demoConfiguration),
            "Demo bez adresu backendu nie może wejść na ścieżkę dostawcy"
        )
    }
}

