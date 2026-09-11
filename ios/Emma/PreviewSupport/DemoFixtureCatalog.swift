import Foundation

// MARK: - Zestawy danych demo (fixtures)
//
// Schemat `Emma-Demo` przekazuje `--fixture <nazwa>`. Ten plik nadaje temu
// argumentowi realne znaczenie: wybiera dzień referencyjny, zalogowanego prawnika
// i scenariusz mocka głosowego.
//
// Dlaczego osobny katalog, a nie rozgałęzienia w widokach: zachowanie demo ma być
// **powtarzalne i nazwane**. Zestaw danych opisany w jednym miejscu można wskazać
// w schemacie, w testach interfejsu i w raporcie — i za każdym razem dostaje się
// ten sam dzień, ten sam użytkownik i ta sama sekwencja zdarzeń głosu.
//
// Nieznana nazwa **nie jest po cichu ignorowana**: demo działa dalej na zestawie
// domyślnym, ale zapisuje czytelne zgłoszenie, które pokazuje właścicielowi,
// że przekazał nazwę, której nie ma.

public struct DemoFixture: Sendable, Equatable {

    /// Nazwa przekazywana argumentem `--fixture`.
    public let name: String
    /// Dzień referencyjny demo.
    public let referenceDay: LocalDate
    public let referenceHour: Int
    public let referenceMinute: Int
    /// Kto jest zalogowany w demo.
    public let currentUserID: UserID
    /// Scenariusz mocka głosowego (`MockVoiceScenarios.allNames`).
    public let voiceScenarioName: String
    /// Jednozdaniowy opis: co ten zestaw pokazuje.
    public let summary: String
}

public enum DemoFixtureCatalog {

    public static let defaultName = "today-default"

    public static let all: [DemoFixture] = [
        DemoFixture(
            name: "today-default",
            referenceDay: LocalDate(year: 2026, month: 9, day: 11),
            referenceHour: 9,
            referenceMinute: 41,
            currentUserID: .tomasz,
            voiceScenarioName: "standard-proposal-flow",
            summary: "Zwykły dzień kancelarii: propozycja Emmy, zgoda, wykonanie."
        ),
        DemoFixture(
            name: "second-lawyer",
            referenceDay: LocalDate(year: 2026, month: 9, day: 11),
            referenceHour: 9,
            referenceMinute: 41,
            currentUserID: .pawel,
            voiceScenarioName: "mixed-languages",
            summary: "Ten sam dzień oczami drugiego prawnika — inne liczniki nieprzeczytanych."
        ),
        DemoFixture(
            name: "voice-reconnect",
            referenceDay: LocalDate(year: 2026, month: 9, day: 11),
            referenceHour: 9,
            referenceMinute: 41,
            currentUserID: .tomasz,
            voiceScenarioName: "reconnect",
            summary: "Dzień ze zrywającym się połączeniem głosowym i zdarzeniami spóźnionymi."
        ),
        DemoFixture(
            name: "voice-permission-denied",
            referenceDay: LocalDate(year: 2026, month: 9, day: 11),
            referenceHour: 9,
            referenceMinute: 41,
            currentUserID: .tomasz,
            voiceScenarioName: "permission-denied",
            summary: "Odmowa dostępu do mikrofonu: interfejs działa dalej, tekst pozostaje dostępny."
        ),
        DemoFixture(
            name: "voice-barge-in",
            referenceDay: LocalDate(year: 2026, month: 9, day: 11),
            referenceHour: 9,
            referenceMinute: 41,
            currentUserID: .tomasz,
            voiceScenarioName: "barge-in",
            summary: "Przerwanie wypowiedzi Emmy głosem i korekta propozycji."
        )
    ]

    public static func named(_ name: String) -> DemoFixture? {
        all.first { $0.name == name }
    }

    public static var defaultFixture: DemoFixture {
        // Zestaw domyślny musi istnieć — brak oznaczałby błąd w tym pliku, nie stan
        // do obsłużenia w interfejsie.
        guard let fixture = named(defaultName) else {
            preconditionFailure("DemoFixtureCatalog: brak zestawu domyślnego '\(defaultName)'")
        }
        return fixture
    }

    public static var allNames: [String] { all.map(\.name) }

    /// Rozstrzygnięcie zestawu z argumentu startowego.
    ///
    /// - Returns: zestaw do użycia oraz — jeśli nazwa była nieznana — czytelne
    ///   zgłoszenie do pokazania w interfejsie.
    public static func resolve(_ requestedName: String?) -> (fixture: DemoFixture, notice: String?) {
        guard let requestedName, !requestedName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return (defaultFixture, nil)
        }
        guard let fixture = named(requestedName) else {
            let available = allNames.joined(separator: ", ")
            return (
                defaultFixture,
                "Nieznany zestaw danych „\(requestedName)”. Używam „\(defaultName)”. Dostępne: \(available)."
            )
        }
        return (fixture, nil)
    }

    /// Pomoc dla schematów i skryptów: wypisuje nazwy zestawów.
    public static func describeAll() -> String {
        all.map { "\($0.name) — \($0.summary)" }.joined(separator: "\n")
    }
}
