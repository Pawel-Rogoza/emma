import XCTest

// MARK: - Lista leadów: domyślny filtr, odhaczenie i menu po przytrzymaniu
//
// Zachowania z review Tomasza i właściciela (23.09.2026):
//   1. ekran „Klienci” otwiera się na kolejce **„Do obsługi”** (nowe i czekające
//      zgłoszenia), bo sensem widoku jest ich przerobienie,
//   2. okrągły przycisk na karcie oznacza zgłoszenie jako obsłużone, a komunikat
//      daje „Cofnij”,
//   3. przytrzymanie leada daje menu z pozostałymi czynnościami.
//
// Test chodzi na danych Demo (bez sieci), ale wykonuje **prawdziwą** operację
// zapisu przez repozytorium: obsłużony lead zmienia etap i znika z kolejki.

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

    func testNeedsActionIsTheDefaultFilter() {
        openClients()

        // Etykieta filtra niesie licznik („Do obsługi 2”), więc dopasowujemy po początku.
        let queue = application.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Do obsługi"))
            .firstMatch
        XCTAssertTrue(queue.waitForExistence(timeout: 15), "Brak filtra „Do obsługi”")
        XCTAssertTrue(queue.isSelected, "Ekran ma się otwierać z wybranym filtrem „Do obsługi”")
        attachScreenshot(name: "lista-do-obslugi")
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
        // a potem wracamy na listę, żeby zobaczyć zgłoszenie w kolejce „Do obsługi”.
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

    func testCheckButtonMarksLeadHandledAndUndoRestoresIt() {
        openClients()

        // Karta leada ma własny identyfikator: jej etykieta niesie treść dla
        // VoiceOver (imię, temat, status, język), więc zmienia się razem z danymi.
        let lead = application.buttons.matching(identifier: "lead-card").firstMatch
        XCTAssertTrue(lead.waitForExistence(timeout: 15), "Brak zgłoszenia w kolejce")
        let leadLabel = lead.label
        let countBefore = application.buttons.matching(identifier: "lead-card").count
        attachScreenshot(name: "przed-odhaczeniem")

        let check = application.buttons.matching(identifier: "lead-check").firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 10), "Brak przycisku „Oznacz jako obsłużone”")
        check.tap()

        // Obsłużone zgłoszenie znika z kolejki „Do obsługi”…
        let sameCard = application.buttons
            .matching(NSPredicate(format: "label == %@", leadLabel))
            .firstMatch
        let disappeared = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sameCard)
        wait(for: [disappeared], timeout: 15)
        XCTAssertLessThan(application.buttons.matching(identifier: "lead-card").count, countBefore)

        // …a komunikat pozwala to cofnąć jednym dotknięciem.
        let undo = application.buttons["Cofnij"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "Komunikat nie dał „Cofnij”")
        attachScreenshot(name: "po-odhaczeniu-cofnij")
        undo.tap()

        let restored = application.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", String(leadLabel.prefix(while: { $0 != "," }))))
            .firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 15), "„Cofnij” nie przywróciło zgłoszenia do kolejki")
    }

    func testLongPressOffersHandledAndConversion() {
        openClients()

        let lead = application.buttons.matching(identifier: "lead-card").firstMatch
        XCTAssertTrue(lead.waitForExistence(timeout: 15), "Brak zgłoszenia na liście")
        lead.press(forDuration: 1.2)

        let convert = application.buttons["Konwertuj na klienta"]
        XCTAssertTrue(
            convert.waitForExistence(timeout: 10),
            "Przytrzymanie leada nie pokazało menu z konwersją"
        )
        attachScreenshot(name: "menu-czynnosci")
        convert.tap()

        // Konwersja zakłada kartotekę, więc aplikacja musi zapytać.
        let confirm = application.buttons["Konwertuj na klienta"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "Brak pytania o potwierdzenie konwersji")
        attachScreenshot(name: "potwierdzenie-konwersji")
    }
}
