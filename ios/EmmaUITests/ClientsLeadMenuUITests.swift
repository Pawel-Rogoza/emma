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
