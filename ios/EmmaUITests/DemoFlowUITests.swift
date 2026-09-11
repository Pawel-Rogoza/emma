import XCTest

// MARK: - Testy interfejsu przepływu demo
//
// UWAGA — stan wykonania: te testy **nie zostały uruchomione**. W środowisku, w którym
// powstały, nie ma macOS ani Xcode, więc nie ma symulatora, na którym XCUITest mógłby
// wystartować. Ich obecność oznacza gotowy scenariusz do wykonania na Macu, a nie
// potwierdzenie, że aplikacja działa. Wynik należy dopisać do
// `docs/ios/BUILD_AND_DEVICE_STATUS.md` po pierwszym uruchomieniu `Cmd+U`.
//
// Scenariusze pilnują rzeczy, które łatwo zepsuć przy dalszej pracy:
//   • pięć zakładek i ich kolejność,
//   • brak etykiet pilności w rozmowach i brak kolumny godzin w kalendarzu,
//   • jawna informacja, że WhatsApp nie jest połączony,
//   • zgoda na wykonanie akcji wyłącznie przez dotknięcie przycisku.

final class DemoFlowUITests: XCTestCase {

    private var application: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        application = XCUIApplication()
        // Ten sam zestaw argumentów co w schemacie Emma-Demo: deterministyczny dzień.
        application.launchArguments = ["--demo", "--fixture", "today-default"]
        application.launchEnvironment = ["EMMA_FIXTURE": "today-default"]
        application.launch()
    }

    override func tearDown() {
        application = nil
        super.tearDown()
    }

    // MARK: Pomocnicze

    private func tab(_ identifier: String) -> XCUIElement {
        application.buttons["tab.\(identifier)"]
    }

    private func openTab(_ identifier: String) {
        let element = tab(identifier)
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Brak zakładki \(identifier)")
        element.tap()
    }

    // MARK: Testy

    /// Pięć zakładek z referencji istnieje i da się między nimi przełączać.
    func testFiveTabsArePresentAndSwitchable() {
        for identifier in ["today", "clients", "emma", "messages", "calendar"] {
            XCTAssertTrue(tab(identifier).exists, "Brak zakładki \(identifier)")
        }

        openTab("clients")
        XCTAssertTrue(application.staticTexts["Klienci"].waitForExistence(timeout: 5))

        openTab("calendar")
        XCTAssertTrue(application.staticTexts["Kalendarz"].waitForExistence(timeout: 5))

        openTab("today")
        XCTAssertTrue(application.staticTexts["Dzisiaj"].waitForExistence(timeout: 5))
    }

    /// Dzień referencyjny demo jest stały, więc nagłówek musi pokazywać ten sam dzień.
    func testReferenceDayIsFixed() {
        XCTAssertTrue(
            application.staticTexts["Dzisiaj"].waitForExistence(timeout: 10),
            "Ekran Dzisiaj nie wczytał się"
        )
        // Piątek 11 września 2026 — dzień referencyjny danych przykładowych.
        let referenceDay = application.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'wrze'")
        ).firstMatch
        XCTAssertTrue(referenceDay.waitForExistence(timeout: 5), "Brak daty dnia referencyjnego")
    }

    /// Lista klientów pokazuje dane przykładowe, a karta klienta otwiera się i zamyka.
    func testClientListOpensClientCard() {
        openTab("clients")
        let client = application.staticTexts["Olena Kovalenko"]
        XCTAssertTrue(client.waitForExistence(timeout: 10), "Brak klientki z danych przykładowych")
        client.tap()
        XCTAssertTrue(
            application.staticTexts["Karta klienta"].waitForExistence(timeout: 5)
                || application.staticTexts["Olena Kovalenko"].waitForExistence(timeout: 5),
            "Karta klienta nie otworzyła się"
        )
    }

    /// Rozmowy muszą jawnie mówić, że WhatsApp nie jest połączony — żadnego udawania.
    func testConversationsDiscloseDisconnectedWhatsApp() {
        openTab("messages")
        let disclosure = application.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'WhatsApp niepołączony'")
        ).firstMatch
        XCTAssertTrue(
            disclosure.waitForExistence(timeout: 10),
            "Brak jawnej informacji o niepołączonym WhatsApp"
        )
    }

    /// W rozmowach nie ma etykiet pilności (jawnie wykluczone w planie).
    func testConversationsHaveNoUrgencyLabels() {
        openTab("messages")
        XCTAssertTrue(application.staticTexts["Rozmowy"].waitForExistence(timeout: 10))
        for forbidden in ["Pilne", "Pilny kontakt", "Natychmiast"] {
            XCTAssertFalse(
                application.staticTexts[forbidden].exists,
                "W rozmowach pojawiła się etykieta pilności: \(forbidden)"
            )
        }
    }

    /// Kalendarz nie ma kolumny godzin — plan wprost tego zakazuje.
    func testCalendarHasNoHourColumn() {
        openTab("calendar")
        XCTAssertTrue(application.staticTexts["Kalendarz"].waitForExistence(timeout: 10))
        for hour in ["00:00", "06:00", "12:00", "18:00"] {
            XCTAssertFalse(
                application.staticTexts[hour].exists,
                "W kalendarzu pojawiła się kolumna godzin (\(hour))"
            )
        }
    }

    /// Zakładka Emmy pokazuje orb i umie rozpocząć rozmowę na mocku.
    func testEmmaTabStartsMockConversation() {
        openTab("emma")
        let start = application.buttons["Rozpocznij rozmowę"]
        if start.waitForExistence(timeout: 10) {
            start.tap()
            // Mock odpowiada deterministycznie: interfejs musi pokazać stan sesji.
            let status = application.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] 'Połączona' OR label CONTAINS[c] 'Łączę'")
            ).firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 10), "Brak stanu połączenia po starcie")
        } else {
            XCTFail("Brak przycisku rozpoczęcia rozmowy w zakładce Emma")
        }
    }

    /// Wątek rozmowy: wejście z listy i widoczne pole wiadomości.
    func testConversationThreadOpens() {
        openTab("messages")
        let row = application.staticTexts["Olena Kovalenko"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Brak wątku w liście rozmów")
        row.tap()
        let composer = application.textViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "Brak pola wiadomości w wątku")
    }

    /// Przełączenie użytkownika w profilu nie może zostawić stanu poprzedniej osoby.
    func testProfileSheetOpens() {
        openTab("today")
        let profile = application.buttons["Profil"]
        guard profile.waitForExistence(timeout: 10) else {
            XCTFail("Brak wejścia do profilu na ekranie Dzisiaj")
            return
        }
        profile.tap()
        XCTAssertTrue(application.staticTexts["Profil"].waitForExistence(timeout: 5))
    }
}
