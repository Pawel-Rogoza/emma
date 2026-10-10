import XCTest

// MARK: - Etap 3: pierwszy widok dnia i wejście do zadań (F08)
//
// Sprawdzamy to, czego nie da się sprawdzić bez symulatora: czy najbliższy termin
// i wejście do zadań są **widoczne bez przewijania** oraz czy z listy zadań da się
// przejść do powiązanego rekordu. Wcześniej pełna scena Emmy spychała oba poza
// pierwszy ekran.

final class Stage3LayoutUITests: XCTestCase {

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

    /// Najbliższy termin i wejście do zadań muszą być na pierwszym widoku.
    func testNextEventAndTaskEntryAreAboveTheFold() {
        let section = application.staticTexts["Najbliższy termin"]
        XCTAssertTrue(section.waitForExistence(timeout: 10), "Brak sekcji „Najbliższy termin”")
        XCTAssertTrue(section.isHittable, "Sekcja najbliższego terminu jest poza pierwszym widokiem")

        // Godzina referencyjnego terminu z danych demo (DemoClock = 09:41).
        XCTAssertTrue(
            application.staticTexts["10:30"].waitForExistence(timeout: 10),
            "Brak godziny najbliższego terminu"
        )

        // Od 0.3.0 wejściem do zadań w pierwszym widoku jest kafelek pulsu dnia.
        let entry = application.buttons["pulse-tasks"]
        XCTAssertTrue(entry.exists, "Brak kafelka zadań")
        XCTAssertTrue(entry.isHittable, "Wejście do zadań jest poza pierwszym widokiem")

        XCTAssertTrue(
            application.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'do wykonania'")
            ).firstMatch.exists,
            "Brak liczby otwartych zadań przy nagłówku sekcji"
        )
    }

    /// Jedno dotknięcie z „Dzisiaj” otwiera listę zadań.
    func testTaskEntryOpensTaskListInOneTap() {
        let entry = application.buttons["pulse-tasks"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Brak wejścia do zadań")
        entry.tap()

        XCTAssertTrue(
            application.staticTexts["Zadania"].waitForExistence(timeout: 10),
            "Lista zadań się nie otworzyła"
        )
        XCTAssertTrue(application.navigationBars.buttons.firstMatch.exists, "Brak powrotu na liście zadań")
    }

    /// Zadania otwarte są pogrupowane, a nie płaskie.
    func testOpenTasksAreGrouped() {
        application.buttons["pulse-tasks"].tap()
        XCTAssertTrue(application.staticTexts["Zadania"].waitForExistence(timeout: 10))

        // Dane demo mają zadania na dzień referencyjny, więc widoczna jest grupa
        // „NA DZIŚ”. Grupę „ZALEGŁE” pokrywa test rdzenia (DayPlanningTests).
        XCTAssertTrue(
            application.staticTexts["NA DZIŚ"].waitForExistence(timeout: 10),
            "Brak nagłówka grupy zadań"
        )
    }

    /// Link do powiązanego rekordu przy najbliższym terminie otwiera kartę klienta.
    func testClientLinkOnNextEventOpensClientCard() {
        let link = application.buttons["Olena Kovalenko"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "Brak linku do klienta przy terminie")
        link.tap()

        XCTAssertTrue(
            application.staticTexts["Karta klienta"].waitForExistence(timeout: 10),
            "Karta klienta się nie otworzyła"
        )
    }
}
