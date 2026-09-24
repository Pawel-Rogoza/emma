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
        application.launchArguments = ["--demo", "--fixture", "today-default", "--skip-auth"]
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

        capture("03-karta-klienta", description: "Karta klienta Andriia Melnyka") {
            selectTab("clients")
            // Tryb „Leady” pokazuje zgłoszenia; Olena ma status „Klient” i jest w „Sprawach”.
            let row = application.staticTexts["Andrii Melnyk"]
            guard row.waitForExistence(timeout: 10) else { return "brak klienta w liście" }
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
                NSPredicate(format: "label CONTAINS[c] 'KR / 2026'")
            ).firstMatch
            guard firstCase.waitForExistence(timeout: 10) else { return "brak sprawy na liście" }
            firstCase.tap()
            return nil
        }

        capture("05-zadania", description: "Wspólna lista zadań") {
            selectTab("today")
            let tasks = application.buttons["Wszystkie zadania"]
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

        capture("08-watek", description: "Wątek z separatorem nowych wiadomości") {
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

        capture("10-emma-rozmowa", description: "Emma — odpowiedź mocka po wybraniu sugestii") {
            selectTab("emma")
            let suggestion = application.buttons.matching(
                NSPredicate(format: "label BEGINSWITH[c] 'Opowiedz mi o dzisiejszym dniu'")
            ).firstMatch
            guard suggestion.waitForExistence(timeout: 10) else { return "brak sugestii na ekranie Emmy" }
            suggestion.tap()
            // Mock odpowiada deterministycznie; czekamy na turę z briefingiem.
            let answered = application.buttons.matching(
                NSPredicate(format: "label BEGINSWITH[c] 'Odsłuchaj'")
            ).firstMatch.waitForExistence(timeout: 15)
            if !answered { return "Emma nie odpowiedziała w 15 s" }
            return nil
        }

        capture("11-profil", description: "Profil kancelarii") {
            selectTab("today")
            let profile = application.buttons["Profil kancelarii"]
            if !profile.waitForExistence(timeout: 3) {
                // Zakładka „Dzisiaj” pamięta wejście w listę zadań z wcześniejszej
                // sceny, a to nie jest ekran główny z wejściem do profilu. Drugie
                // dotknięcie aktywnej zakładki wraca na wierzch stosu.
                selectTab("today")
            }
            guard profile.waitForExistence(timeout: 10) else { return "brak wejścia do profilu" }
            profile.tap()
            return nil
        }

        closeSheet()

        capture("12-termin-formularz", description: "Formularz terminu otwarty z wybranego dnia kalendarza") {
            selectTab("calendar")
            let add = application.buttons["Dodaj termin"]
            guard add.waitForExistence(timeout: 10) else { return "brak przycisku „Dodaj termin”" }
            add.tap()
            guard application.staticTexts["Nowy termin"].waitForExistence(timeout: 10) else {
                return "formularz terminu się nie otworzył"
            }
            return nil
        }

        closeSheet()

        capture("13-zadanie-formularz", description: "Formularz nowego zadania") {
            selectTab("today")
            let tasks = application.buttons["Wszystkie zadania"]
            guard tasks.waitForExistence(timeout: 10) else { return "brak wejścia do zadań" }
            tasks.tap()
            let add = application.buttons["Dodaj zadanie"]
            guard add.waitForExistence(timeout: 10) else { return "brak przycisku „Dodaj zadanie”" }
            add.tap()
            guard application.staticTexts["Nowe zadanie"].waitForExistence(timeout: 10) else {
                return "formularz zadania się nie otworzył"
            }
            return nil
        }

        closeSheet()

        capture("14-nowa-rozmowa", description: "Arkusz nowej rozmowy z wyszukiwaniem kontaktu") {
            // Świeży start: po scenie 08 zakładka „Rozmowy” pamięta otwarty wątek,
            // a arkusz nowej rozmowy jest dostępny właśnie z listy rozmów.
            application.terminate()
            application.launch()
            _ = application.buttons["tab.today"].waitForExistence(timeout: 20)
            selectTab("messages")
            let newConversation = application.buttons["Nowa rozmowa"]
            guard newConversation.waitForExistence(timeout: 10) else { return "brak przycisku „Nowa rozmowa”" }
            newConversation.tap()
            guard application.staticTexts["Nowa rozmowa"].waitForExistence(timeout: 10) else {
                return "arkusz nowej rozmowy się nie otworzył"
            }
            return nil
        }
    }

    /// Zamknięcie arkusza przyciskiem „Zamknij”; brak arkusza nie jest błędem sceny.
    private func closeSheet() {
        let close = application.buttons["Zamknij"]
        if close.waitForExistence(timeout: 5) {
            close.tap()
            _ = application.buttons["tab.today"].waitForExistence(timeout: 3)
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
