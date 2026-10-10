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
        // `--skip-auth` pomija logowanie i Face ID — scenariusze przepływu demo
        // sprawdzają aplikację, a nie ekran dostępu (jest na to osobny test).
        application.launchArguments = ["--demo", "--fixture", "today-default", "--skip-auth"]
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
    /// Tryb „Leady” pokazuje zgłoszenia (np. Andriia Melnyka) — klientka ze statusem
    /// „Klient” (Olena) leży w trybie „Sprawy”, nie na liście leadów.
    func testClientListOpensClientCard() {
        openTab("clients")
        let client = application.staticTexts["Andrii Melnyk"]
        XCTAssertTrue(client.waitForExistence(timeout: 10), "Brak klienta z danych przykładowych")
        client.tap()
        let opened = application.navigationBars["Karta klienta"].waitForExistence(timeout: 10)
        XCTAssertTrue(opened, "Karta klienta nie otworzyła się. Ekran: \(screenSummary())")
    }

    /// Krótki opis ekranu do komunikatu porażki — widoczny w adnotacji CI
    /// bez pobierania logów i zrzutów.
    private func screenSummary() -> String {
        let bars = application.navigationBars.allElementsBoundByIndex.map(\.identifier).joined(separator: ",")
        let sheets = application.sheets.count
        let texts = application.staticTexts.allElementsBoundByIndex.prefix(14).map(\.label).joined(separator: " | ")
        return "paski=[\(bars)] arkusze=\(sheets) teksty=[\(texts)]"
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
        // Godziny terminów dnia (np. 12:00) są treścią kart, nie kolumną —
        // kolumnę zdradzają pełne godziny, których żaden termin demo nie ma.
        for hour in ["00:00", "01:00", "06:00", "23:00"] {
            XCTAssertFalse(
                application.staticTexts[hour].exists,
                "W kalendarzu pojawiła się kolumna godzin (\(hour))"
            )
        }
    }

    /// Zakładka Emmy pokazuje intro z orbem i umie uruchomić przykład na mocku.
    // Wejście w rozmowę to sugestia „Opowiedz mi o dzisiejszym dniu” — mock Emmy
    // odpowiada deterministycznie turą z briefingiem i przyciskiem odsłuchu.
    func testEmmaTabStartsMockConversation() {
        openTab("emma")
        let suggestion = application.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Opowiedz mi o dzisiejszym dniu'")
        ).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), "Brak sugestii na ekranie Emmy")
        suggestion.tap()
        let listen = application.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Odsłuchaj'")
        ).firstMatch
        XCTAssertTrue(listen.waitForExistence(timeout: 10), "Brak odpowiedzi Emmy po sugestii")
    }

    /// Wątek rozmowy: wejście z listy i widoczne pole wiadomości.
    func testConversationThreadOpens() {
        openTab("messages")
        let row = application.staticTexts["Olena Kovalenko"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Brak wątku w liście rozmów")
        row.tap()
        // Pole wiadomości to jednoliniowy `TextField`, który rośnie z treścią
        // (wcześniej był wysoki `TextEditor`).
        let composer = application.textFields.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "Brak pola wiadomości w wątku")
    }

    /// Ekran dostępu: logowanie raz na urządzenie, potem odblokowanie Face ID.
    /// Ten scenariusz nie używa `--skip-auth`, żeby sprawdzić właśnie tę bramkę.
    func testLoginScreenAcceptsDemoCredentials() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--fixture", "today-default", "--reset-auth"]
        app.launchEnvironment = ["EMMA_FIXTURE": "today-default"]
        app.launch()

        let signIn = app.buttons["Zaloguj się"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 15), "Brak ekranu logowania")

        // Puste pola nie wpuszczają dalej.
        signIn.tap()
        XCTAssertTrue(
            app.staticTexts["Podaj adres e-mail, np. imie@kancelaria.pl."].waitForExistence(timeout: 5),
            "Brak komunikatu o błędnym adresie e-mail"
        )

        let email = app.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 5), "Brak pola e-mail")
        email.tap()
        email.typeText("pawel@kancelaria.pl")

        let password = app.secureTextFields.firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 5), "Brak pola hasła")
        password.tap()
        password.typeText("emma")

        signIn.tap()
        XCTAssertTrue(
            tab("today").waitForExistence(timeout: 15),
            "Po poprawnym logowaniu nie weszliśmy do aplikacji"
        )
    }

    /// Profil otwiera się z nagłówka ekranu głównego (przycisk z inicjałami).
    func testProfileSheetOpens() {
        openTab("today")
        let profile = application.buttons["Profil kancelarii"]
        guard profile.waitForExistence(timeout: 10) else {
            XCTFail("Brak wejścia do profilu na ekranie Dzisiaj")
            return
        }
        profile.tap()
        XCTAssertTrue(application.staticTexts["Profil kancelarii"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["Wyloguj się"].exists, "Brak wylogowania w profilu")
    }
}
