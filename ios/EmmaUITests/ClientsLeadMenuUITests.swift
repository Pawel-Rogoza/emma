import XCTest

// MARK: - Lista leadów: domyślny filtr i menu po przytrzymaniu
//
// Dwa zachowania z review Tomasza:
//   1. ekran „Klienci” ma otwierać się na **nowych** zgłoszeniach, bo leady to
//      rezerwacje konsultacji ze strony i sensem widoku jest ich przerobienie,
//   2. przytrzymanie leada ma dawać menu z przeniesieniem między etapami.
//
// Test chodzi na danych Demo (bez sieci), ale wykonuje **prawdziwą** operację
// zapisu przez repozytorium: przeniesienie leada zmienia jego etap i po
// odświeżeniu zgłoszenie znika z filtra „Nowe”.

final class ClientsLeadMenuUITests: XCTestCase {

    private var application: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        application = XCUIApplication()
        application.launchArguments = ["--demo", "--fixture", "today-default", "--skip-auth"]
        application.launchEnvironment = ["EMMA_FIXTURE": "today-default"]
        application.launch()
    }

    override func tearDown() {
        application = nil
        super.tearDown()
    }

    private func openClients() {
        let clientsTab = application.buttons["tab.clients"]
        XCTAssertTrue(clientsTab.waitForExistence(timeout: 20), "Brak zakładki „Klienci”")
        clientsTab.tap()
    }

    func testNoweIsTheDefaultFilter() {
        openClients()

        // Etykieta filtra niesie licznik („Nowe 3”), więc dopasowujemy po początku.
        let nowe = application.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Nowe"))
            .firstMatch
        XCTAssertTrue(nowe.waitForExistence(timeout: 15), "Brak filtra „Nowe”")
        XCTAssertTrue(nowe.isSelected, "Ekran ma się otwierać z wybranym filtrem „Nowe”")
        attachScreenshot(name: "lista-nowe")
    }

    /// Zrzuty zmienionych ekranów zostają w wyniku testu — po to, żeby dało się
    /// obejrzeć listę i menu, a nie tylko przeczytać, że asercje przeszły.
    private func attachScreenshot(name: String) {
        let shot = XCTAttachment(screenshot: application.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Przycisk „+” ma naprawdę zakładać zgłoszenie. Przed tą zmianą w produkcji
    /// kończył się komunikatem „Backend nie udostępnia jeszcze…”, bo repozytorium
    /// nie wołało istniejącej trasy `POST /clients`.
    func testAddingLeadShowsItInNewList() {
        openClients()

        let countBefore = application.buttons.matching(identifier: "lead-card").count
        application.buttons["Dodaj leada"].tap()

        let nameField = application.textFields["Imię i nazwisko"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Arkusz „Nowy kontakt” się nie otworzył")
        nameField.tap()
        nameField.typeText("Anna Testowa")

        let topicField = application.textFields["Temat zgłoszenia"]
        topicField.tap()
        topicField.typeText("Zaległe alimenty")

        // Kontekst trafia do tej samej treści zgłoszenia (`leads.message`).
        let contextField = application.textViews["Kontekst zgłoszenia"]
        if contextField.waitForExistence(timeout: 5) {
            contextField.tap()
            contextField.typeText("Proszę o kontakt po 16:00.")
        }
        attachScreenshot(name: "nowy-kontakt-formularz")

        // Klawiatura zasłania przycisk zapisu — chowamy ją, dotykając nagłówka.
        application.staticTexts["Nowy kontakt"].tap()
        let submit = application.buttons["Dodaj kontakt"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        submit.tap()

        // Po zapisie aplikacja otwiera kartę nowego kontaktu — sprawdzamy to,
        // a potem wracamy na listę, żeby zobaczyć zgłoszenie na filtrze „Nowe”.
        let cardTitle = application.staticTexts["Anna Testowa"]
        XCTAssertTrue(cardTitle.waitForExistence(timeout: 20), "Nie otworzyła się karta nowego kontaktu")
        XCTAssertTrue(application.staticTexts["DODANO RĘCZNIE"].exists, "Nowy kontakt nie ma źródła „Dodano ręcznie”")
        attachScreenshot(name: "nowy-kontakt-na-liscie")

        let back = application.buttons["Wróć"]
        if back.waitForExistence(timeout: 5) {
            back.tap()
        }
        let created = application.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Anna Testowa")
        ).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 20), "Nowe zgłoszenie nie pojawiło się na liście")
        XCTAssertGreaterThan(
            application.buttons.matching(identifier: "lead-card").count,
            countBefore,
            "Liczba zgłoszeń na liście nie wzrosła"
        )
    }

    /// Usunięcie zgłoszenia z menu po przytrzymaniu. Sprawdzamy **całą** drogę:
    /// pozycję menu, pytanie o potwierdzenie i zniknięcie karty z listy.
    func testLongPressDeleteRemovesLead() {
        openClients()

        let lead = application.buttons.matching(identifier: "lead-card").firstMatch
        XCTAssertTrue(lead.waitForExistence(timeout: 15), "Brak zgłoszenia na liście")
        let leadLabel = lead.label
        let countBefore = application.buttons.matching(identifier: "lead-card").count

        lead.press(forDuration: 1.2)
        let deleteItem = application.buttons["Usuń zgłoszenie"]
        XCTAssertTrue(
            deleteItem.waitForExistence(timeout: 10),
            "Przytrzymanie leada nie pokazało usuwania"
        )
        deleteItem.tap()

        // Usunięcie jest nieodwracalne, więc aplikacja musi zapytać.
        let confirm = application.alerts.buttons["Usuń"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "Brak pytania o potwierdzenie usunięcia")
        attachScreenshot(name: "potwierdzenie-usuniecia")
        confirm.tap()

        let sameCard = application.buttons
            .matching(NSPredicate(format: "label == %@", leadLabel))
            .firstMatch
        let disappeared = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sameCard)
        wait(for: [disappeared], timeout: 15)
        XCTAssertLessThan(
            application.buttons.matching(identifier: "lead-card").count,
            countBefore,
            "Liczba zgłoszeń nie spadła po usunięciu"
        )
    }

    func testLongPressMovesLeadToContact() {
        openClients()

        // Karta leada ma własny identyfikator: jej etykieta niesie treść dla
        // VoiceOver (imię, temat, status, język), więc zmienia się razem z danymi.
        let lead = application.buttons.matching(identifier: "lead-card").firstMatch
        XCTAssertTrue(lead.waitForExistence(timeout: 15), "Brak nowego zgłoszenia na liście")
        let leadLabel = lead.label

        attachScreenshot(name: "przed-menu")
        lead.press(forDuration: 1.2)

        let moveToContact = application.buttons["Przenieś do: w kontakcie"]
        XCTAssertTrue(
            moveToContact.waitForExistence(timeout: 10),
            "Przytrzymanie leada nie pokazało menu z przeniesieniem"
        )
        attachScreenshot(name: "menu-etapy")
        moveToContact.tap()

        // Po przeniesieniu zgłoszenie ma zniknąć z filtra „Nowe”.
        let sameCard = application.buttons
            .matching(NSPredicate(format: "label == %@", leadLabel))
            .firstMatch
        let disappeared = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sameCard)
        wait(for: [disappeared], timeout: 15)
    }
}
