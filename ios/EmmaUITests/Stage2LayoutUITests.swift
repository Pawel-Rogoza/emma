import XCTest

// MARK: - Etap 2: czytelność i nawigacja (F12, F13)
//
// Testy layoutu, których nie da się sprawdzić w testach jednostkowych:
//   • jeden powrót na ekranie szczegółu i działający gest krawędzi (F12),
//   • kolumna znaczników w wierszu rozmów nie nachodzi na menu (F13).
//
// Ograniczenie: dokładnego nachodzenia licznika na **tekst podglądu** nie da się
// tu zmierzyć, bo wiersz rozmowy scala dzieci w jeden element dostępności
// (`.accessibilityElement(children: .combine)`). To pokrywa zrzut ekranu
// (`Stage2ScreenshotUITests`) — patrz ograniczenia raportu etapu 2.

final class Stage2LayoutUITests: XCTestCase {

    private var application: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        application = XCUIApplication()
        application.launchArguments = ["--demo", "--fixture", "today-default", "--skip-auth"]
        application.launchEnvironment = ["EMMA_FIXTURE": "today-default"]
        application.launch()
        _ = application.buttons["tab.today"].waitForExistence(timeout: 20)
    }

    override func tearDown() {
        application = nil
        super.tearDown()
    }

    private func openTab(_ identifier: String) {
        let tab = application.buttons["tab.\(identifier)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Brak zakładki \(identifier)")
        tab.tap()
    }

    // MARK: F12 — jeden powrót (od 0.22.0 systemowy, w pasku nawigacji iOS 26)

    /// Karta klienta: jeden powrót — systemowy przycisk w pasku nawigacji.
    func testClientCardHasSingleBackControl() {
        openTab("clients")
        let client = application.staticTexts["Andrii Melnyk"]
        XCTAssertTrue(client.waitForExistence(timeout: 10), "Brak klienta w liście")
        client.tap()

        let back = application.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Brak systemowego powrotu")
        XCTAssertFalse(application.buttons["Wróć"].exists, "Własny przycisk „Wróć” nadal jest na ekranie — dwa powroty")
    }

    /// Gest przesunięcia od lewej krawędzi wraca na listę klientów.
    func testSwipeFromEdgeGoesBackFromClientCard() {
        openTab("clients")
        let client = application.staticTexts["Andrii Melnyk"]
        XCTAssertTrue(client.waitForExistence(timeout: 10), "Brak klienta w liście")
        client.tap()
        XCTAssertTrue(application.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10))

        let start = application.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = application.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(
            application.buttons["tab.clients"].waitForExistence(timeout: 5),
            "Po geście krawędzi nie wróciliśmy na listę klientów"
        )
    }

    /// Zadania: tytuł raz (w pasku nawigacji), powrót i „Dodaj zadanie” w pasku.
    func testTasksScreenHasSingleHeader() {
        openTab("today")
        let entry = application.buttons["Wszystkie zadania"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Brak wejścia do zadań")
        entry.tap()

        XCTAssertTrue(application.staticTexts["Zadania"].waitForExistence(timeout: 10))
        XCTAssertTrue(application.navigationBars.buttons.firstMatch.exists, "Brak powrotu w pasku zadań")
        XCTAssertTrue(application.buttons["Dodaj zadanie"].exists, "Brak „Dodaj zadanie” w pasku")
        XCTAssertEqual(
            application.staticTexts.matching(
                NSPredicate(format: "label ==[c] 'Zadania'")
            ).count,
            1,
            "Tytuł „Zadania” jest na ekranie więcej niż raz — to podwójny nagłówek"
        )
    }

    // MARK: F13 — kolumna znaczników

    /// Wiersz rozmowy (jak w WhatsAppie, 02.10.2026) mówi czytnikowi ekranu
    /// o nowych wiadomościach, a opcje są czynnością wiersza, nie osobnym „…”.
    func testConversationRowAnnouncesUnreadAndOffersOptions() {
        openTab("messages")

        let row = application.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Andrii Melnyk'")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Brak wiersza rozmowy z Andriiem Melnykiem")
        XCTAssertTrue(row.label.localizedCaseInsensitiveContains("nieprzeczyt"), "Wiersz nie mówi o nowych wiadomościach")
        XCTAssertFalse(
            application.buttons["Opcje rozmowy z Andrii Melnyk"].exists,
            "Wiersz nadal ma osobny przycisk „…”"
        )
    }
}
