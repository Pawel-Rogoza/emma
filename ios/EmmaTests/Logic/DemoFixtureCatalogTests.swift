import XCTest
@testable import Emma

// MARK: - Zestawy danych demo
//
// Argument `--fixture` ze schematu `Emma-Demo` ma realne znaczenie tylko wtedy, gdy
// każda nazwa istnieje, prowadzi do znanego scenariusza głosu i nie da się jej
// przeoczyć. Te testy pilnują właśnie tego — bez uruchamiania interfejsu.

final class DemoFixtureCatalogTests: XCTestCase {

    func testDefaultFixtureExistsAndIsFirstInCatalog() {
        XCTAssertEqual(DemoFixtureCatalog.defaultFixture.name, DemoFixtureCatalog.defaultName)
        XCTAssertEqual(DemoFixtureCatalog.all.first?.name, DemoFixtureCatalog.defaultName)
    }

    func testEveryFixtureNameIsUniqueAndNonEmpty() {
        let names = DemoFixtureCatalog.allNames
        XCTAssertEqual(Set(names).count, names.count, "Nazwy zestawów muszą być unikalne")
        for name in names {
            XCTAssertFalse(name.isEmpty)
            XCTAssertFalse(name.contains(" "), "Nazwa zestawu nie może zawierać spacji: \(name)")
        }
    }

    /// Każdy zestaw musi wskazywać scenariusz, który mock faktycznie zna —
    /// inaczej demo po cichu pokazywałoby inny przebieg, niż zapowiada nazwa.
    func testEveryFixtureUsesKnownMockScenario() {
        for fixture in DemoFixtureCatalog.all {
            XCTAssertTrue(
                MockVoiceScenarios.allNames.contains(fixture.voiceScenarioName),
                "Zestaw \(fixture.name) wskazuje nieznany scenariusz \(fixture.voiceScenarioName)"
            )
        }
    }

    func testEveryFixtureHasPlausibleTime() {
        for fixture in DemoFixtureCatalog.all {
            XCTAssertTrue((0...23).contains(fixture.referenceHour))
            XCTAssertTrue((0...59).contains(fixture.referenceMinute))
        }
    }

    func testEveryFixtureHasSummary() {
        for fixture in DemoFixtureCatalog.all {
            XCTAssertFalse(
                fixture.summary.trimmingCharacters(in: .whitespaces).isEmpty,
                "Zestaw \(fixture.name) nie ma opisu"
            )
        }
    }

    func testResolveWithoutNameUsesDefaultWithoutNotice() {
        let resolution = DemoFixtureCatalog.resolve(nil)
        XCTAssertEqual(resolution.fixture.name, DemoFixtureCatalog.defaultName)
        XCTAssertNil(resolution.notice)
    }

    func testResolveBlankNameUsesDefaultWithoutNotice() {
        for blank in ["", "   "] {
            let resolution = DemoFixtureCatalog.resolve(blank)
            XCTAssertEqual(resolution.fixture.name, DemoFixtureCatalog.defaultName)
            XCTAssertNil(resolution.notice, "Puste „\(blank)” nie jest błędem użytkownika")
        }
    }

    /// Nieznana nazwa: demo działa dalej, ale zgłoszenie musi być czytelne
    /// i wymieniać dostępne zestawy.
    func testResolveUnknownNameFallsBackWithNotice() {
        let resolution = DemoFixtureCatalog.resolve("takiego-nie-ma")
        XCTAssertEqual(resolution.fixture.name, DemoFixtureCatalog.defaultName)
        let notice = try? XCTUnwrap(resolution.notice)
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice?.contains("takiego-nie-ma") == true)
        for name in DemoFixtureCatalog.allNames {
            XCTAssertTrue(notice?.contains(name) == true, "Zgłoszenie pomija zestaw \(name)")
        }
    }

    func testResolveKnownNameReturnsThatFixture() {
        for fixture in DemoFixtureCatalog.all {
            let resolution = DemoFixtureCatalog.resolve(fixture.name)
            XCTAssertEqual(resolution.fixture, fixture)
            XCTAssertNil(resolution.notice)
        }
    }

    /// Demo ma jedno wspólne konto kancelarii, więc licznik nieprzeczytanych jest
    /// jeden: Andrii (2) + Maria (1). Wcześniej ten test porównywał dwóch prawników
    /// — razem z podziałem na osoby zniknęło to porównanie (D-17).
    func testSharedAccountHasSingleUnreadTotal() async throws {
        let repository = MockRepository(
            dataset: DemoFixtures.dataset(),
            clock: DemoClock(),
            artificialLatency: 0
        )
        let total = try await repository.unreadTotal(userID: .kancelaria)
        XCTAssertEqual(total, 2, "Rozmowy Andrii i Maria — liczymy osoby, nie wiadomości")
    }
}
