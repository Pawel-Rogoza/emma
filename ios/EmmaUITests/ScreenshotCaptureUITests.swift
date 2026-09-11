import XCTest

// MARK: - Zrzuty ekranu aplikacji do obejrzenia bez Maca
//
// Po co: właściciel pracuje na Linuksie i nie ma pod ręką MacBooka. Ten test
// przechodzi po ekranach aplikacji na symulatorze i zapisuje zrzuty do katalogu
// wskazanego zmienną `EMMA_SHOT_DIR`. Uruchamiany przez workflow GitHub Actions
// (`macos-15`), zrzuty wracają jako artefakt do pobrania.
//
// Zasada: **nie udajemy, że wszystko się udało.** Jeśli ekran nie wczyta się
// w założonym czasie, zrzut mimo to powstaje (z tym, co jest na ekranie),
// a w raporcie tekstowym ląduje pozycja „NIE UDAŁO SIĘ” z powodem. Dzięki temu
// brakujący ekran widać od razu, a nie po braku pliku.
//
// Czego ten test NIE robi: nie zastępuje testów funkcjonalnych. Sprawdza, że ekran
// da się otworzyć, a nie że działa poprawnie. Testy zachowania są w XCUITest
// (`DemoFlowUITests`) i w testach logiki.

final class ScreenshotCaptureUITests: XCTestCase {

    private var application: XCUIApplication!
    private var outputDirectory: URL!
    private var report: [String] = []

    override func setUp() {
        continueAfterFailure = true
        application = XCUIApplication()
        application.launchArguments = ["--demo", "--fixture", "today-default"]
        application.launchEnvironment = ["EMMA_FIXTURE": "today-default"]

        let base = ProcessInfo.processInfo.environment["EMMA_SHOT_DIR"] ?? NSTemporaryDirectory()
        outputDirectory = URL(fileURLWithPath: base, isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        application.launch()
        // Pierwsze uruchomienie z pełną bazą demo potrzebuje chwili na wczytanie.
        _ = application.buttons["tab.today"].waitForExistence(timeout: 20)
    }

    override func tearDown() {
        writeReport()
        application = nil
        super.tearDown()
    }

    // MARK: Test

    func testCaptureAllScreens() {
        capture("01-dzisiaj", description: "Dzisiaj — dzień referencyjny") {
            selectTab("today")
            return nil
        }

        capture("02-klienci", description: "Klienci — lista leadów") {
            selectTab("clients")
            return nil
        }

        capture("03-karta-klienta", description: "Karta klienta Oleny Kovalenko") {
            selectTab("clients")
            let row = application.staticTexts["Olena Kovalenko"]
            guard row.waitForExistence(timeout: 10) else { return "brak klientki w liście" }
            row.tap()
            return nil
        }

        capture("04-sprawa", description: "Ekran sprawy z podziałem na sekcje") {
            selectTab("clients")
            // Sprawy są drugim trybem listy klientów.
            let caseMode = application.buttons["Sprawy"]
            if caseMode.waitForExistence(timeout: 10) {
                caseMode.tap()
            } else {
                return "brak przełącznika trybu „Sprawy”"
            }
            let firstCase = application.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Sprawa' OR label CONTAINS[c] 'case-'")
            ).firstMatch
            guard firstCase.waitForExistence(timeout: 10) else { return "brak sprawy na liście" }
            firstCase.tap()
            return nil
        }

        capture("05-zadania", description: "Wspólna lista zadań") {
            selectTab("today")
            let tasks = application.buttons["Zadania"]
            guard tasks.waitForExistence(timeout: 10) else { return "brak wejścia do zadań na ekranie Dzisiaj" }
            tasks.tap()
            return nil
        }

        capture("06-kalendarz", description: "Kalendarz — tydzień bez kolumny godzin") {
            selectTab("calendar")
            return nil
        }

        capture("07-rozmowy", description: "Rozmowy — liczniki nieprzeczytanych") {
            selectTab("messages")
            return nil
        }

        capture("08-watek", description: "Wątek z tłumaczeniami i separatorem nowych") {
            selectTab("messages")
            let row = application.staticTexts["Olena Kovalenko"]
            guard row.waitForExistence(timeout: 10) else { return "brak wątku w liście rozmów" }
            row.tap()
            return nil
        }

        capture("09-emma", description: "Emma — orb i kontekst") {
            selectTab("emma")
            return nil
        }

        capture("10-emma-rozmowa", description: "Emma — rozmowa po rozpoczęciu sesji na mocku") {
            selectTab("emma")
            let start = application.buttons["Rozpocznij rozmowę"]
            guard start.waitForExistence(timeout: 10) else { return "brak przycisku rozpoczęcia rozmowy" }
            start.tap()
            // Mock odpowiada deterministycznie; czekamy na stan połączenia.
            let connected = application.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Połączona' OR label CONTAINS[c] 'Słucham'")
            ).firstMatch.waitForExistence(timeout: 15)
            if !connected { return "sesja nie pokazała stanu połączenia w 15 s" }
            return nil
        }

        capture("11-profil", description: "Profil i przełączanie użytkownika") {
            selectTab("today")
            let profile = application.buttons["Twój profil"]
            guard profile.waitForExistence(timeout: 10) else { return "brak wejścia do profilu" }
            profile.tap()
            return nil
        }
    }

    // MARK: Pomocnicze

    private func selectTab(_ identifier: String) {
        let tab = application.buttons["tab.\(identifier)"]
        if tab.waitForExistence(timeout: 10) {
            tab.tap()
            // Krótka chwila na animację i wczytanie danych ekranu.
            _ = application.staticTexts.firstMatch.waitForExistence(timeout: 3)
        }
    }

    /// Wykonuje scenę, robi zrzut i zapisuje wynik do raportu — także wtedy,
    /// gdy scena się nie udała.
    ///
    /// Scena zwraca `nil`, gdy się powiodła, albo powód niepowodzenia. Dzięki temu
    /// raport mówi wprost, dlaczego ekranu nie ma — bez zgadywania po braku pliku.
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
        Zrzuty ekranu Emmy — stan faktyczny
        Data: \(ISO8601DateFormatter().string(from: Date()))
        Uwaga: zrzut „NIE UDAŁO SIĘ” oznacza, że ekran nie wczytał się w założonym czasie.
        Zrzut i tak powstał — pokazuje, co było na ekranie w tym momencie.

        """
        let body = report.isEmpty ? "Brak wykonanych scen." : report.joined(separator: "\n")
        try? (header + body + "\n").write(
            to: outputDirectory.appendingPathComponent("raport.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
