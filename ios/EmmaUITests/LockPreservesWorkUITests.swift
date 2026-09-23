import XCTest

// MARK: - Blokada nie kasuje pracy (audyt 23.09.2026)
//
// Wcześniej przejście do innej aplikacji (np. po numer telefonu) zamieniało
// całą powłokę na ekran blokady: po odblokowaniu otwarty formularz znikał,
// a pisana notatka przepadała. Teraz blokada zasłania powłokę, a nie ją niszczy.

final class LockPreservesWorkUITests: XCTestCase {

    func testNoteDraftSurvivesBackgroundAndUnlock() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--fixture", "today-default", "--reset-auth"]
        app.launchEnvironment = ["EMMA_FIXTURE": "today-default"]
        app.launch()

        // Logowanie demonstracyjne (dowolne dane o poprawnym kształcie).
        let email = app.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 15), "Brak ekranu logowania")
        email.tap()
        email.typeText("test@kancelaria.pl")
        let password = app.secureTextFields.firstMatch
        password.tap()
        password.typeText("emma")
        app.buttons["Zaloguj się"].tap()

        let leadRow = app.buttons["today-lead-row"].firstMatch
        XCTAssertTrue(leadRow.waitForExistence(timeout: 15), "Nie weszliśmy do aplikacji")
        // iOS po wpisaniu hasła potrafi zapytać „Zachować hasło?” — zamykamy.
        for label in ["Nie teraz", "Nie zapisuj", "Not Now"] {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 3) { button.tap(); break }
        }
        leadRow.tap()

        let noteButton = app.buttons["Notatka"].firstMatch
        XCTAssertTrue(noteButton.waitForExistence(timeout: 15), "Brak wejścia do notatki na karcie")
        noteButton.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15), "Arkusz notatki się nie otworzył")
        editor.tap()
        let draft = "Ustalenia z rozmowy do zachowania"
        editor.typeText(draft)

        // Wyjście do ekranu głównego i powrót — aplikacja się blokuje.
        XCUIDevice.shared.press(.home)
        app.activate()

        let unlock = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Odblokuj")).firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Po powrocie aplikacja nie jest zablokowana")
        if unlock.isHittable { unlock.tap() }

        XCTAssertTrue(
            app.textViews.firstMatch.waitForExistence(timeout: 15),
            "Po odblokowaniu arkusz notatki zniknął"
        )
        let kept = expectation(
            for: NSPredicate(format: "value CONTAINS %@", draft),
            evaluatedWith: app.textViews.firstMatch
        )
        wait(for: [kept], timeout: 10)
    }
}
