import XCTest

// MARK: - Zrzuty etapu 2 (czytelność, nawigacja)
//
// Ten sam wzorzec co `ScreenshotCaptureUITests`, ale osobny plik raportu i sceny
// dla etapu 2: nagłówek karty klienta i zadań (F12), kolumna licznika rozmów (F13)
// oraz ten sam materiał przy **największym rozmiarze tekstu** (F09).
//
// Katalog wyjściowy: `EMMA_SHOT_DIR`. Ten sam test uruchamiamy na dwóch
// destination (mały i duży ekran) i zapisujemy do osobnych podkatalogów, żeby
// raporty się nie nadpisywały.

final class Stage2ScreenshotUITests: XCTestCase {

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

    /// Zwykły tekst: nagłówki szczegółów i kolumna licznika.
    func testCaptureStage2Screens() {
        capture("15-karta-klienta-naglowek", description: "Karta klienta — jeden nagłówek i jeden powrót") {
            selectTab("clients")
            let row = application.staticTexts["Andrii Melnyk"]
            guard row.waitForExistence(timeout: 10) else { return "brak klienta w liście" }
            row.tap()
            guard application.buttons["Wróć"].waitForExistence(timeout: 10) else {
                return "brak własnego powrotu w nagłówku"
            }
            return nil
        }

        capture("16-zadania-naglowek", description: "Zadania — jeden nagłówek z powrotem i akcją") {
            selectTab("today")
            let entry = application.buttons["Wszystkie zadania"]
            guard entry.waitForExistence(timeout: 10) else { return "brak wejścia do zadań" }
            entry.tap()
            guard application.staticTexts["Zadania"].waitForExistence(timeout: 10) else {
                return "lista zadań się nie otworzyła"
            }
            return nil
        }

        capture("17-rozmowy-kolumna-licznika", description: "Rozmowy — licznik w osobnej kolumnie wiersza") {
            selectTab("messages")
            let badge = application.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'nieprzeczyt'")
            ).firstMatch
            guard badge.waitForExistence(timeout: 10) else { return "brak licznika nieprzeczytanych" }
            return nil
        }
    }

    /// Największy rozmiar tekstu: sprawdzamy, że układ się nie nakłada i nie ucina.
    func testCaptureStage2LargeTextScreens() {
        relaunchWithLargestText()

        capture("18-duzy-tekst-rozmowy", description: "Rozmowy przy największym tekście dostępności") {
            selectTab("messages")
            guard application.staticTexts["Rozmowy"].waitForExistence(timeout: 10) else {
                return "lista rozmów nie wczytała się przy dużym tekście"
            }
            return nil
        }

        capture("19-duzy-tekst-karta-klienta", description: "Karta klienta przy największym tekście dostępności") {
            selectTab("clients")
            let row = application.staticTexts["Andrii Melnyk"]
            guard row.waitForExistence(timeout: 10) else { return "brak klienta przy dużym tekście" }
            row.tap()
            guard application.buttons["Wróć"].waitForExistence(timeout: 10) else {
                return "brak nagłówka przy dużym tekście"
            }
            return nil
        }

        capture("20-duzy-tekst-zadania", description: "Zadania przy największym tekście dostępności") {
            selectTab("today")
            let entry = application.buttons["Wszystkie zadania"]
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
        Zrzuty ekranu Emmy — etap 2 (czytelność, nawigacja)
        Data: \(ISO8601DateFormatter().string(from: Date()))
        Uwaga: zrzut „NIE UDAŁO SIĘ” oznacza, że ekran nie wczytał się w założonym czasie.
        Zrzut i tak powstał — pokazuje, co było na ekranie w tym momencie.

        """
        let body = report.isEmpty ? "Brak wykonanych scen." : report.joined(separator: "\n")
        let sanitized = self.name
            .replacingOccurrences(of: "-[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: " ", with: "-")
        let name = "raport-etap2-\(sanitized).txt"
        try? (header + body + "\n").write(
            to: outputDirectory.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }
}
