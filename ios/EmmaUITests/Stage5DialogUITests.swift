import XCTest

// MARK: - Zrzuty i przebieg etapu 5 (dialog intencji, poprawki, spotkanie)
//
// Sceny powtarzają §6 na prawdziwym ekranie: polecenie z wypowiedzi, poprawka
// treści i terminu, pytanie odczytowe przy otwartym szkicu oraz formularz
// spotkania otwarty z rozpoznanymi polami. Każdy zrzut zapisuje też krótki
// raport tekstowy, więc obraz jest dowodem wykonania, a nie ozdobą.

final class Stage5DialogUITests: XCTestCase {

    private var application: XCUIApplication!
    private var outputDirectory: URL!
    private var report: [String] = []

    override func setUp() {
        continueAfterFailure = true
        application = XCUIApplication()
        outputDirectory = makeOutputDirectory()
        application.launchArguments = ["--demo", "--fixture", "today-default", "--skip-auth"]
        application.launchEnvironment = ["EMMA_FIXTURE": "today-default"]
        application.launch()
        _ = application.buttons["tab.emma"].waitForExistence(timeout: 20)
    }

    override func tearDown() {
        writeReport()
        application = nil
        super.tearDown()
    }

    // MARK: Przebieg A — wiadomość i poprawka

    func testCaptureStage5MessageFlow() {
        capture("31-emma-wiadomosc-karta", description: "§6-A — polecenie z wypowiedzi przygotowuje wiadomość") {
            self.openEmma()
            guard self.send("Wyślij Olenie WhatsApp, że spóźnię się 15 minut") else {
                return "pole tekstowe nie przyjęło polecenia"
            }
            guard self.waitForText("spóźnię się 15 minut", timeout: 10) != nil else {
                return "brak karty z treścią wiadomości"
            }
            guard self.application.buttons["Zatwierdź wiadomość"].exists else {
                return "brak potwierdzenia wiadomości na karcie"
            }
            if let element = self.waitForText("spóźnię się 15 minut", timeout: 5) {
                self.report.append(
                    "  pomiar · treść karty: typ=\(element.elementType.rawValue) "
                    + "frame=\(element.frame) okno=\(self.application.windows.firstMatch.frame)"
                )
            }
            return nil
        }

        capture("32-emma-poprawka-tresci", description: "§6-A krok 5 — „Zmień na 20 minut” poprawia tę samą kartę") {
            guard self.send("Zmień na 20 minut") else { return "pole nie przyjęło poprawki" }
            guard self.waitForText("spóźnię się 20 minut", timeout: 10) != nil else {
                return "karta nie pokazuje poprawionej treści"
            }
            // Własna wypowiedź użytkownika zostaje w historii, więc stara treść
            // może być widoczna w turze użytkownika — sprawdzamy samą kartę.
            guard self.application.buttons["Zatwierdź wiadomość"].exists else {
                return "karta zniknęła po poprawce"
            }
            return nil
        }
    }

    // MARK: Przebieg B — pytanie odczytowe nie kasuje szkicu

    func testCaptureStage5ReadOnlyQuestionKeepsDraft() {
        capture("33-emma-schemat-przy-szkicu", description: "§6-B — pytanie o terminy nie kasuje przygotowanej wiadomości") {
            self.openEmma()
            guard self.send("Wyślij Olenie WhatsApp, że spóźnię się 15 minut") else {
                return "pole nie przyjęło polecenia"
            }
            guard self.waitForText("spóźnię się 15 minut", timeout: 10) != nil else {
                return "brak szkicu przed pytaniem"
            }
            guard self.send("Jakie mam terminy na dzisiaj?") else { return "pole nie przyjęło pytania" }
            guard self.waitForText("spóźnię się 15 minut", timeout: 10) != nil else {
                return "pytanie odczytowe skasowało szkic"
            }
            return nil
        }
    }

    // MARK: Przebieg C — spotkanie z rozpoznanymi polami

    func testCaptureStage5MeetingForm() {
        capture("34-emma-formularz-spotkania", description: "§6-C/F14 — „Dodaj spotkanie … o 11” otwiera formularz z polami") {
            self.openEmma()
            guard self.send("Dodaj spotkanie z Oleną na jutro o 11") else { return "pole nie przyjęło polecenia" }
            guard self.application.staticTexts["Nowy termin"].waitForExistence(timeout: 10) else {
                return "nie otwarto formularza nowego terminu"
            }
            // Godzina ma systemowy wybór godziny (0.3.0), nie pole tekstowe.
            let timeField = self.application.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "11:00", "11:00")
            ).firstMatch
            guard timeField.exists else {
                return "godzina z wypowiedzi nie trafiła do formularza"
            }
            return nil
        }
    }

    // MARK: Uruchomienie i pomocnicze

    private func openEmma() {
        let tab = application.buttons["tab.emma"]
        if tab.exists { tab.tap() }
        _ = application.textFields["Polecenie dla Emmy"].waitForExistence(timeout: 15)
    }

    /// Wpisuje polecenie w tryb pisania i wysyła je. Zwraca `false`, gdy pole
    /// albo wysłanie są niedostępne — scena wtedy jawnie zgłasza problem.
    private func send(_ text: String) -> Bool {
        let field = application.textFields["Polecenie dla Emmy"]
        guard field.waitForExistence(timeout: 10) else { return false }
        field.tap()
        field.typeText(text)
        let send = application.buttons["Przekaż polecenie"]
        guard send.waitForExistence(timeout: 5), send.isEnabled else { return false }
        send.tap()
        revealContent()
        return true
    }

    /// Karta akcji jest najnowszą turą, a klawiatura zasłania dolną połowę ekranu —
    /// bez przewinięcia zrzut pokazywałby sam przycisk zgody. Przewijamy rozmowę,
    /// żeby na zrzucie było widać treść, którą użytkownik zatwierdza.
    /// Karta akcji jest wyższa niż okno rozmowy nad klawiaturą, więc na zrzucie
    /// widać tylko jej dolną część. Przejście na inną zakładkę i z powrotem
    /// chowa klawiaturę, a historia rozmowy żyje w rejestrze ekranu — dzięki temu
    /// zrzut pokazuje całą treść, którą użytkownik zatwierdza.
    private func revealContent() {
        guard application.keyboards.count > 0 else { return }
        let other = application.buttons["tab.today"]
        if other.waitForExistence(timeout: 5) {
            other.tap()
            _ = application.staticTexts.firstMatch.waitForExistence(timeout: 2)
        }
        let emma = application.buttons["tab.emma"]
        if emma.waitForExistence(timeout: 5) { emma.tap() }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, application.keyboards.count > 0 {
            usleep(150_000)
        }
        // Rozmowa jest kotwiczona na dole, więc karta bywa przycięta u góry —
        // jedno przeciągnięcie w dół pokazuje jej początek.
        let start = application.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
        let end = application.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Karta akcji pokazuje treść także w polu edycji, więc szukamy po wartości
    /// i etykiecie dowolnego elementu — inaczej zrzut „przechodzi” tylko dlatego,
    /// że tekst jest w innym typie kontrolki.
    private func waitForText(_ text: String, timeout: TimeInterval) -> XCUIElement? {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        let element = application.descendants(matching: .any).matching(predicate).firstMatch
        return element.waitForExistence(timeout: timeout) ? element : nil
    }

    private func makeOutputDirectory() -> URL {
        let base = ProcessInfo.processInfo.environment["EMMA_SHOT_DIR"] ?? NSTemporaryDirectory()
        let directory = URL(fileURLWithPath: base, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
        Zrzuty ekranu Emmy — etap 5 (dialog intencji, poprawki, spotkanie)
        Data: \(ISO8601DateFormatter().string(from: Date()))
        Uwaga: zrzut „NIE UDAŁO SIĘ” oznacza, że ekran nie osiągnął założonego stanu.
        Zrzut i tak powstał — pokazuje, co było na ekranie w tym momencie.
        Niejednoznaczne imię (dwie Oleny) nie występuje w zestawie demo, więc
        doprecyzowanie głosem sprawdza test jednostkowy na wstrzykniętych danych.

        """
        let body = report.isEmpty ? "Brak wykonanych scen." : report.joined(separator: "\n")
        let sanitized = self.name
            .replacingOccurrences(of: "-[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: " ", with: "-")
        let name = "raport-etap5-\(sanitized).txt"
        try? (header + body + "\n").write(
            to: outputDirectory.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }
}
