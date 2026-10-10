import XCTest

// MARK: - Zrzuty etapu 3 (pierwszy widok dnia, grupowanie zadań)
//
// Ten sam wzorzec co `Stage2ScreenshotUITests`: sceny zapisywane do katalogu
// `EMMA_SHOT_DIR` wraz z raportem tekstowym. Cel etapu 3 to sprawdzić, że
// najbliższy termin i wejście do zadań są widoczne **bez przewijania**, że
// zadania mają nagłówki grup, a cała zmiana wytrzymuje największy tekst
// dostępności (F08, F09).

final class Stage3ScreenshotUITests: XCTestCase {

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

    /// Zwykły tekst: pierwszy widok dnia, zadania i grupowanie.
    func testCaptureStage3Screens() {
        capture("21-dzisiaj-pierwszy-widok", description: "Dzisiaj — kompaktowa Emma, najbliższy termin i zadania bez przewijania") {
            let section = application.staticTexts["Następne"]
            guard section.waitForExistence(timeout: 10) else { return "brak sekcji najbliższego terminu" }
            guard section.isHittable else { return "najbliższy termin poza pierwszym widokiem" }
            // Od 0.3.0 wejściem do zadań w pierwszym widoku jest kafelek pulsu dnia.
            guard application.buttons["pulse-tasks"].isHittable else {
                return "wejście do zadań poza pierwszym widokiem"
            }
            return nil
        }

        capture("22-dzisiaj-dalsze-terminy", description: "Dzisiaj — dalsze terminy dnia po przewinięciu") {
            application.swipeUp()
            guard application.staticTexts["Później dziś"].waitForExistence(timeout: 10) else {
                return "brak sekcji dalszych terminów"
            }
            return nil
        }

        capture("23-zadania-grupy", description: "Zadania — grupa „NA DZIŚ” zamiast płaskiej listy") {
            selectTab("today")
            let entry = application.buttons["pulse-tasks"]
            guard entry.waitForExistence(timeout: 10) else { return "brak wejścia do zadań" }
            entry.tap()
            guard application.staticTexts["Zadania"].waitForExistence(timeout: 10) else {
                return "lista zadań się nie otworzyła"
            }
            guard application.staticTexts["NA DZIŚ"].exists else { return "brak nagłówka grupy zadań" }
            return nil
        }
    }

    /// Największy rozmiar tekstu: układ nie może się nakładać ani ucinać.
    func testCaptureStage3LargeTextScreens() {
        relaunchWithLargestText()

        capture("24-duzy-tekst-dzisiaj", description: "Dzisiaj przy największym tekście dostępności") {
            let section = application.staticTexts["Następne"]
            guard section.waitForExistence(timeout: 10) else {
                return "ekran dnia nie wczytał się przy dużym tekście"
            }
            guard application.buttons["pulse-tasks"].exists else {
                return "brak wejścia do zadań przy dużym tekście"
            }
            return nil
        }

        capture("25-duzy-tekst-zadania", description: "Zadania przy największym tekście dostępności") {
            let entry = application.buttons["pulse-tasks"]
            guard entry.waitForExistence(timeout: 10) else { return "brak wejścia do zadań" }
            entry.tap()
            guard application.staticTexts["Zadania"].waitForExistence(timeout: 10) else {
                return "lista zadań nie wczytała się przy dużym tekście"
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

    private func selectTab(_ identifier: String) {
        let tab = application.buttons["tab.\(identifier)"]
        if tab.waitForExistence(timeout: 10) {
            tab.tap()
            _ = application.staticTexts.firstMatch.waitForExistence(timeout: 3)
        }
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
        Zrzuty ekranu Emmy — etap 3 (pierwszy widok dnia, grupowanie zadań)
        Data: \(ISO8601DateFormatter().string(from: Date()))
        Uwaga: zrzut „NIE UDAŁO SIĘ” oznacza, że ekran nie wczytał się w założonym czasie.
        Zrzut i tak powstał — pokazuje, co było na ekranie w tym momencie.

        """
        let body = report.isEmpty ? "Brak wykonanych scen." : report.joined(separator: "\n")
        let sanitized = self.name
            .replacingOccurrences(of: "-[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: " ", with: "-")
        let name = "raport-etap3-\(sanitized).txt"
        try? (header + body + "\n").write(
            to: outputDirectory.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }
}
