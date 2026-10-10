import XCTest

// MARK: - Przepływ planowania: zadania i terminy od początku do końca
//
// 0.23.0 — właściciel: „sprawdź cały flow kalendarza, dodawania zadań,
// terminów — ma być przetestowane”. Każdy test przechodzi drogę użytkownika
// na danych demo (repozytorium w pamięci) i sprawdza, że zapis jest widoczny
// tam, gdzie adwokat go szuka.

final class PlanningFlowUITests: XCTestCase {

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

    // MARK: Zadania

    /// Nowe zadanie z listy zadań trafia na listę.
    func testNewTaskAppearsOnTaskList() {
        openTaskList()
        addTask("Zadanie z testu UI")

        XCTAssertTrue(
            element(containing: "Zadanie z testu UI").waitForExistence(timeout: 10),
            "Nowe zadanie nie pojawiło się na liście"
        )
    }

    /// Zadanie da się otworzyć, odhaczyć w szczegółach i przywrócić.
    func testTaskCanBeCompletedAndRestoredFromDetails() {
        openTaskList()
        addTask("Odhacz mnie w teście")

        let row = application.buttons.matching(identifier: "task-open")
            .matching(NSPredicate(format: "label CONTAINS %@", "Odhacz mnie w teście")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Brak nowego zadania na liście")
        tapVisible(row)

        let toggle = application.buttons["task-detail-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Szczegóły zadania się nie otworzyły")
        XCTAssertTrue(waitForLabel(toggle, "Oznacz jako wykonane"), "Nowe zadanie nie jest otwarte")
        toggle.tap()

        XCTAssertTrue(waitForLabel(toggle, "Przywróć zadanie"), "Zadanie nie zmieniło stanu na wykonane")
        XCTAssertTrue(element(containing: "Wykonane").exists, "Brak oznaczenia „Wykonane”")

        toggle.tap()
        XCTAssertTrue(waitForLabel(toggle, "Oznacz jako wykonane"), "Zadanie nie wróciło do otwartych")
    }

    /// Pusty tytuł nie zakłada zadania — formularz mówi, co poprawić.
    func testEmptyTaskTitleShowsError() {
        openTaskList()
        openNewTaskForm()
        application.buttons["task-save"].tap()
        XCTAssertTrue(
            application.staticTexts["Wpisz, co trzeba zrobić."].waitForExistence(timeout: 5),
            "Brak komunikatu o pustym zadaniu"
        )
    }

    // MARK: Terminy

    /// Nowy termin z kalendarza trafia na oś wybranego dnia i otwiera szczegóły.
    func testNewEventAppearsInCalendarDayAndOpensDetails() {
        openTab("calendar")
        let add = application.buttons["Dodaj termin"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Brak „Dodaj termin” w kalendarzu")
        add.tap()

        let title = application.textFields["event-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Formularz terminu się nie otworzył")
        replaceText(in: title, with: "Spotkanie z testu UI")

        let save = application.buttons["event-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        let created = application.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Spotkanie z testu UI")).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 10), "Nowy termin nie pojawił się w dniu kalendarza")
        tapVisible(created)

        XCTAssertTrue(
            application.buttons["Edytuj termin"].waitForExistence(timeout: 10),
            "Szczegóły nowego terminu się nie otworzyły"
        )
    }

    /// Termin bez nazwy nie zostaje zapisany.
    func testEventWithoutTitleShowsError() {
        openTab("calendar")
        application.buttons["Dodaj termin"].tap()
        let title = application.textFields["event-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        replaceText(in: title, with: "")
        application.buttons["event-save"].tap()
        XCTAssertTrue(
            application.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Nazwij termin'")).firstMatch
                .waitForExistence(timeout: 5),
            "Brak komunikatu o pustej nazwie terminu"
        )
    }

    /// Trzy widoki kalendarza przełączają się i pokazują swoją treść.
    func testCalendarModesSwitch() {
        openTab("calendar")
        for mode in ["Tydzień", "Lista", "Miesiąc"] {
            let button = application.buttons[mode]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Brak trybu \(mode)")
            button.tap()
        }
        XCTAssertTrue(application.buttons["Następny miesiąc"].waitForExistence(timeout: 10), "Brak nawigacji miesiąca")
        application.buttons["Następny miesiąc"].tap()
        XCTAssertTrue(application.buttons["Wróć do dzisiaj"].waitForExistence(timeout: 10), "Brak powrotu do dzisiaj")
        application.buttons["Wróć do dzisiaj"].tap()
    }

    // MARK: Pomocnicze

    /// Dowolny element, którego etykieta zawiera tekst — wiersze list scalają
    /// tekst w etykietę przycisku, więc `staticTexts[...]` ich nie widzi.
    private func element(containing text: String) -> XCUIElement {
        application.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Przewija ekran, aż element da się nacisnąć (oś dnia bywa pod kartami).
    private func tapVisible(_ element: XCUIElement) {
        var attempts = 0
        while !element.isHittable && attempts < 4 {
            application.swipeUp()
            attempts += 1
        }
        element.tap()
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func openTab(_ identifier: String) {
        let tab = application.buttons["tab.\(identifier)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Brak zakładki \(identifier)")
        tab.tap()
    }

    private func openTaskList() {
        openTab("today")
        let entry = application.buttons["pulse-tasks"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Brak wejścia do zadań na „Dzisiaj”")
        entry.tap()
        XCTAssertTrue(application.staticTexts["Zadania"].waitForExistence(timeout: 10), "Lista zadań się nie otworzyła")
    }

    private func openNewTaskForm() {
        let add = application.buttons["Dodaj zadanie"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Brak „Dodaj zadanie”")
        add.tap()
        XCTAssertTrue(application.textFields["task-title"].waitForExistence(timeout: 10), "Formularz zadania się nie otworzył")
    }

    private func addTask(_ title: String) {
        openNewTaskForm()
        let field = application.textFields["task-title"]
        field.tap()
        field.typeText(title)
        let save = application.buttons["task-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(
            application.textFields["task-title"].waitForNonExistence(timeout: 10),
            "Formularz zadania nie zamknął się po zapisie"
        )
    }

    /// Czyści pole i wpisuje nowy tekst (pole terminu ma nazwę podpowiedzianą).
    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 5))
        }
        if !text.isEmpty {
            field.typeText(text)
        }
    }
}
