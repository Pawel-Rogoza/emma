import XCTest

// MARK: - Zrzuty etapu 4 (globalny panel sesji)
//
// Sceny zapisywane do `EMMA_SHOT_DIR` wraz z raportem tekstowym: ekran Emmy
// w spoczynku (jedno „Rozmawiaj” i pole polecenia), dock z żywą sesją, mini-panel
// w innej zakładce i mini-panel nad arkuszem z klawiaturą.

final class Stage4ScreenshotUITests: XCTestCase {

    private var application: XCUIApplication!
    private var outputDirectory: URL!
    private var report: [String] = []

    override func setUp() {
        continueAfterFailure = true
        application = XCUIApplication()
        outputDirectory = makeOutputDirectory()
        launch(textSize: nil)
    }

    override func tearDown() {
        writeReport()
        application = nil
        super.tearDown()
    }

    // MARK: Scenariusze

    func testCaptureStage4Screens() {
        capture("26-emma-kompozytor", description: "Emma — jedno „Rozmawiaj” i pole polecenia tekstowego") {
            self.openTab("emma")
            guard self.application.buttons["Rozmawiaj"].waitForExistence(timeout: 15) else {
                return "brak przycisku „Rozmawiaj”"
            }
            guard !self.application.buttons["Zakończ"].exists else {
                return "sesja powinna być nieaktywna przy zrzucie spoczynku"
            }
            guard self.application.textFields["Polecenie dla Emmy"].exists else {
                return "brak pola polecenia tekstowego"
            }
            guard !self.application.buttons["Dyktuj tekst do pola"].exists else {
                return "„Dyktuj tekst” wciąż jest na ekranie rozmowy"
            }
            return nil
        }

        capture("27-emma-dock-sesji", description: "Emma — dock z żywą sesją: stan, mikrofon, przerwanie, zakończenie") {
            guard self.startSessionIfNeeded() else { return "sesja nie wystartowała" }
            guard self.application.buttons["Zakończ"].exists else { return "brak zakończenia w docku" }
            return nil
        }

        capture("28-mini-panel-dzisiaj", description: "Dzisiaj — mini-panel nad paskiem zakładek, inna zakładka niż Emma") {
            guard self.startSessionIfNeeded() else { return "sesja nie wystartowała" }
            self.openTab("today")
            guard self.application.buttons["Zakończ rozmowę"].waitForExistence(timeout: 10) else {
                return "brak mini-panelu na zakładce Dzisiaj"
            }
            return nil
        }

        capture("29-mini-panel-klawiatura", description: "Arkusz z klawiaturą — sterowanie sesją widoczne nad klawiaturą") {
            guard self.startSessionIfNeeded() else { return "sesja nie wystartowała" }
            self.openTab("today")
            let entry = self.application.buttons["Wszystkie zadania"]
            guard entry.waitForExistence(timeout: 10) else { return "brak wejścia do zadań" }
            entry.tap()
            let add = self.application.buttons["Dodaj zadanie"]
            guard add.waitForExistence(timeout: 10) else { return "brak formularza zadania" }
            add.tap()
            let field = self.application.textFields.firstMatch
            guard field.waitForExistence(timeout: 10) else { return "brak pola tekstowego" }
            field.tap()
            guard self.waitForKeyboard(timeout: 10) else { return "klawiatura się nie pojawiła" }
            let keyboard = self.application.keyboards.firstMatch
            let screen = self.application.windows.firstMatch.frame
            guard keyboard.frame.minY < screen.maxY else {
                return "klawiatura programowa poza ekranem (\(keyboard.frame)) — zrzut nie pokazuje układu nad klawiaturą"
            }
            guard self.application.buttons["Zakończ rozmowę"].isHittable else {
                return "zakończenie rozmowy zasłonięte przez klawiaturę"
            }
            return nil
        }
    }

    /// Największy tekst dostępności: panel nie może się rozjechać.
    func testCaptureStage4LargeTextScreens() {
        relaunchWithLargestText()

        capture("30-duzy-tekst-mini-panel", description: "Mini-panel przy największym tekście dostępności") {
            guard self.startSessionIfNeeded() else { return "sesja nie wystartowała" }
            self.openTab("today")
            guard self.application.buttons["Zakończ rozmowę"].waitForExistence(timeout: 15) else {
                return "brak mini-panelu przy dużym tekście"
            }
            guard self.application.buttons["Zakończ rozmowę"].isHittable else {
                return "panel poza ekranem przy dużym tekście"
            }
            return nil
        }
    }

    // MARK: Uruchomienie

    private func launch(textSize: String?) {
        application.launchArguments = ["--demo", "--fixture", "today-default", "--skip-auth"]
        if let textSize {
            application.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        application.launchEnvironment = ["EMMA_FIXTURE": "today-default"]
        application.launch()
        _ = application.buttons["tab.today"].waitForExistence(timeout: 20)
    }

    private func relaunchWithLargestText() {
        application.terminate()
        application = XCUIApplication()
        launch(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    private func makeOutputDirectory() -> URL {
        let base = ProcessInfo.processInfo.environment["EMMA_SHOT_DIR"] ?? NSTemporaryDirectory()
        let directory = URL(fileURLWithPath: base, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: Pomocnicze

    private func openTab(_ identifier: String) {
        let tab = application.buttons["tab.\(identifier)"]
        if tab.waitForExistence(timeout: 10) {
            tab.tap()
            _ = application.staticTexts.firstMatch.waitForExistence(timeout: 2)
        }
    }

    /// `true`, gdy sesja jest już uruchomiona; w przeciwnym razie uruchamia ją.
    ///
    /// Sesję widać albo w docku Emmy („Zakończ”), albo w mini-panelu innej
    /// zakładki („Zakończ rozmowę”) — oba znaczniki trzeba sprawdzić.
    @discardableResult
    private func startSessionIfNeeded() -> Bool {
        if application.buttons["Zakończ"].exists || application.buttons["Zakończ rozmowę"].exists {
            return true
        }
        openTab("emma")
        let talk = application.buttons["Rozmawiaj"]
        guard talk.waitForExistence(timeout: 15) else { return false }
        talk.tap()
        return application.buttons["Zakończ"].waitForExistence(timeout: 15)
    }

    private func waitForKeyboard(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if application.keyboards.count > 0 { return true }
            usleep(150_000)
        }
        return application.keyboards.count > 0
    }

    private func capture(_ name: String, description: String, scene: () -> String?) {
        let failure = scene()
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = outputDirectory.appendingPathComponent("\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: url)
        } catch {
            report.append("BŁĄD ZAPISU · \(name).png · \(description) · \(error.localizedDescription)")
            XCTFail("Nie udało się zapisać zrzutu \(name): \(error.localizedDescription)")
            return
        }

        if let failure {
            report.append("NIE  UDAŁO SIĘ · \(name).png · \(description) · powód: \(failure)")
            XCTFail("Scena \(name) nie powiodła się: \(failure)")
        } else {
            report.append("zapisano · \(name).png · \(description)")
        }
    }

    private func writeReport() {
        guard let outputDirectory else { return }
        let header = """
        Zrzuty ekranu Emmy — etap 4 (globalny panel sesji)
        Data: \(ISO8601DateFormatter().string(from: Date()))
        Uwaga: zrzut „NIE UDAŁO SIĘ” oznacza, że ekran nie wczytał się w założonym czasie.
        Zrzut i tak powstał — pokazuje, co było na ekranie w tym momencie.

        """
        let body = report.isEmpty ? "Brak wykonanych scen." : report.joined(separator: "\n")
        let sanitized = self.name
            .replacingOccurrences(of: "-[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: " ", with: "-")
        let name = "raport-etap4-\(sanitized).txt"
        try? (header + body + "\n").write(
            to: outputDirectory.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }
}
