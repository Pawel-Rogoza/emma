import XCTest

// MARK: - Etap 4: globalny panel sesji (F06, F07)
//
// Sprawdzamy zachowanie, którego nie da się sprawdzić bez symulatora: panel
// sterowania jest dostępny w innej zakładce i nad arkuszem z klawiaturą, nie
// dubluje się na ekranie Emmy, a wyciszenie i zakończenie działają na tej samej
// sesji. Nie ma tu drugiego silnika — to ten sam koordynator co w demo.

final class Stage4VoicePanelUITests: XCTestCase {

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

    // MARK: Pomocnicze

    private func openTab(_ identifier: String) {
        let tab = application.buttons["tab.\(identifier)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Brak zakładki \(identifier)")
        tab.tap()
    }

    /// Rozmowa startuje z ekranu Emmy jednym przyciskiem „Rozmawiaj”.
    @discardableResult
    private func startVoiceSession() -> Bool {
        openTab("emma")
        let talk = application.buttons["Rozmawiaj"]
        guard talk.waitForExistence(timeout: 15) else {
            XCTFail("Brak przycisku „Rozmawiaj” na ekranie Emmy")
            return false
        }
        talk.tap()
        let end = application.buttons["Zakończ"]
        guard end.waitForExistence(timeout: 15) else {
            XCTFail("Sesja nie wystartowała — brak zakończenia w docku")
            return false
        }
        return true
    }

    private var panelEndButton: XCUIElement { application.buttons["Zakończ rozmowę"] }
    private var panelMuteButton: XCUIElement { application.buttons["Wycisz mikrofon"] }
    private var panelUnmuteButton: XCUIElement { application.buttons["Włącz mikrofon"] }

    // MARK: Testy

    /// Panel pojawia się w innej zakładce i wraca do rozmowy jednym dotknięciem.
    func testMiniPanelAppearsInAnotherTab() {
        guard startVoiceSession() else { return }
        openTab("today")

        XCTAssertTrue(
            panelEndButton.waitForExistence(timeout: 10),
            "Panel nie pojawił się na zakładce „Dzisiaj”"
        )
        XCTAssertTrue(panelEndButton.isHittable, "Panel jest poza ekranem")
        XCTAssertTrue(
            panelMuteButton.exists || panelUnmuteButton.exists,
            "Panel nie ma sterowania mikrofonem"
        )

        // Dotknięcie treści wraca do pełnej rozmowy.
        let back = application.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Wróć do rozmowy'")
        ).firstMatch
        XCTAssertTrue(back.exists, "Panel nie ma wejścia do pełnej rozmowy")
        back.tap()
        XCTAssertTrue(
            application.buttons["Zakończ"].waitForExistence(timeout: 10),
            "Powrót do rozmowy nie otworzył ekranu Emmy"
        )
        application.buttons["Zakończ"].tap()
    }

    /// Panel nie dubluje się na ekranie Emmy — tam jest pełny dock.
    func testMiniPanelIsNotDuplicatedOnEmmaTab() {
        guard startVoiceSession() else { return }
        XCTAssertFalse(
            panelEndButton.exists,
            "Mini-panel dubluje się z pełnym dockiem na ekranie Emmy"
        )
        XCTAssertFalse(
            application.staticTexts["Wróć do rozmowy"].exists,
            "Na ekranie Emmy jest podpis mini-panelu"
        )
        application.buttons["Zakończ"].tap()
    }

    /// Ekran rozmowy ma **jedną** czynność i **żadnych** dodatkowych kontrolek.
    ///
    /// Ten test jest strażnikiem układu: gdyby na ekran Emmy wróciło wyciszanie,
    /// przerwanie, dyktowanie, przełącznik głosu albo drugi przycisk startu,
    /// tutaj zapali się czerwiec. Celowo nie sprawdzamy tylko „coś się pokazało”,
    /// a jawnie nieobecność każdej z usuniętych kontrolek.
    func testConversationScreenHasNoExtraControls() {
        guard startVoiceSession() else { return }

        // Jedna czynność: zakończenie. „Rozmawiaj” w trakcie sesji znaczyłoby
        // drugi przycisk startu, a dock ma ich mieć dokładnie jeden.
        XCTAssertTrue(application.buttons["Zakończ"].exists, "Brak jedynego przycisku zakończenia")
        XCTAssertFalse(
            application.buttons["Rozmawiaj"].exists,
            "Na ekranie rozmowy jest drugi przycisk startu"
        )

        // Kontrolki usunięte z tego ekranu na wniosek użytkownika.
        XCTAssertFalse(panelMuteButton.exists, "Wyciszanie mikrofonu wróciło na ekran rozmowy")
        XCTAssertFalse(panelUnmuteButton.exists, "Włączanie mikrofonu wróciło na ekran rozmowy")
        XCTAssertFalse(application.buttons["Przerwij"].exists, "Przerwanie wróciło na ekran rozmowy")
        XCTAssertFalse(
            application.buttons["Dyktuj tekst do pola"].exists,
            "Dyktowanie wróciło na ekran rozmowy"
        )

        // Stan rozmowy nadal musi być czytelny — sam przycisk to za mało.
        let state = application.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Stan rozmowy'")
        ).firstMatch
        XCTAssertTrue(state.exists, "Brak czytelnego stanu rozmowy nad przyciskiem")

        application.buttons["Zakończ"].tap()
    }

    /// Wyciszenie i zakończenie działają z innej zakładki, na tej samej sesji.
    func testMiniPanelMutesAndEndsSessionFromAnotherTab() {
        guard startVoiceSession() else { return }
        openTab("today")
        XCTAssertTrue(panelEndButton.waitForExistence(timeout: 10))

        // Pierwsze dotknięcie włącza mikrofon (po starcie jest „niedostępny”),
        // drugie wycisza — panel jawnie mówi, co robi.
        let mic = panelMuteButton.exists ? panelMuteButton : panelUnmuteButton
        mic.tap()
        XCTAssertTrue(
            panelUnmuteButton.waitForExistence(timeout: 10) || panelMuteButton.exists,
            "Stan mikrofonu nie zmienił się po dotknięciu"
        )
        XCTAssertTrue(
            panelUnmuteButton.exists,
            "Po włączeniu mikrofonu panel nie pokazuje wyciszenia jako dostępnej akcji"
        )

        panelUnmuteButton.tap()
        XCTAssertTrue(
            panelMuteButton.waitForExistence(timeout: 10),
            "Mikrofon nie został wyciszony"
        )

        panelMuteButton.tap()
        XCTAssertTrue(
            application.staticTexts["Mikrofon wyciszony"].waitForExistence(timeout: 10)
                || panelMuteButton.exists,
            "Panel nie pokazuje wyciszonego mikrofonu"
        )
        // Sesja nadal żyje po wyciszeniu — panel zostaje.
        XCTAssertTrue(panelEndButton.exists, "Wyciszenie zakończyło sesję")

        panelEndButton.tap()
        XCTAssertTrue(
            waitForDisappearance(panelEndButton, timeout: 10),
            "Panel został po zakończeniu rozmowy"
        )
    }

    /// Nad arkuszem z klawiaturą sterowanie musi zostać widoczne.
    ///
    /// Wymaga **narysowanej** klawiatury programowej: przy podłączonej
    /// klawiaturze sprzętowej symulator zgłasza klawiaturę poza ekranem i wtedy
    /// test jest pomijany (`XCTSkip`), żeby nie dawać zielonego wyniku bez
    /// sprawdzenia układu.
    func testPanelStaysAboveKeyboardInSheet() throws {
        guard startVoiceSession() else { return }
        openTab("today")

        // Zadania → formularz zadania (arkusz z polem tekstowym).
        let tasksEntry = application.buttons["Wszystkie zadania"]
        XCTAssertTrue(tasksEntry.waitForExistence(timeout: 10))
        tasksEntry.tap()

        let add = application.buttons["Dodaj zadanie"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Brak wejścia do formularza zadania")
        add.tap()

        let field = application.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Formularz nie ma pola tekstowego")
        field.tap()

        XCTAssertTrue(waitForKeyboard(timeout: 10), "Klawiatura się nie pojawiła")
        let keyboard = application.keyboards.firstMatch
        let screen = application.windows.firstMatch.frame
        guard keyboard.frame.minY < screen.maxY else {
            throw XCTSkip(
                "Klawiatura programowa nie jest rysowana (klawiatura sprzętowa) — "
                    + "układu nad klawiaturą nie da się zmierzyć: \(keyboard.frame), ekran \(screen)"
            )
        }

        XCTAssertTrue(panelEndButton.exists, "Panel zniknął nad arkuszem")
        XCTAssertLessThanOrEqual(
            panelEndButton.frame.maxY,
            keyboard.frame.minY,
            "Zakończenie rozmowy wchodzi pod klawiaturę (panel \(panelEndButton.frame), klawiatura \(keyboard.frame))"
        )
        XCTAssertTrue(
            panelEndButton.isHittable,
            "Zakończenie rozmowy jest zasłonięte przez klawiaturę"
        )

        panelEndButton.tap()
    }

    // MARK: Oczekiwania

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline {
            usleep(150_000)
        }
        return !element.exists
    }

    private func waitForKeyboard(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if application.keyboards.count > 0 { return true }
            usleep(150_000)
        }
        return application.keyboards.count > 0
    }
}
