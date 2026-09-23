import XCTest

// MARK: - Etap 6: układ z długim nazwiskiem w cyrylicy (§8, wiersz 12)
//
// Ostatnia luka symulatorowa z macierzy: duży tekst był pokryty tylko zrzutami bez
// asercji o nakładaniu, a długiego nazwiska w cyrylicy nie było w danych demo.
// Ten test uruchamia osobny zestaw `dlugie-nazwy` przy największym tekście
// dostępności i sprawdza **geometrię**: nazwisko nie wychodzi za ekran, awatar
// z nazwiskiem się nie przecinają, a decyzje na karcie są osiągalne.
//
// Czego nie sprawdza: VoiceOver i Reduce Motion wymagają urządzenia i pozostają
// poza zasięgiem (macierz §8, „Nieweryfikowalne”).

final class Stage6LayoutUITests: XCTestCase {

    private var application: XCUIApplication!
    private var outputDirectory: URL!
    private var report: [String] = []

    override func setUp() {
        continueAfterFailure = true
        application = XCUIApplication()
        outputDirectory = makeOutputDirectory()
        application.launchArguments = [
            "--demo",
            "--fixture", "dlugie-nazwy",
            "--skip-auth",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        application.launchEnvironment = ["EMMA_FIXTURE": "dlugie-nazwy"]
        application.launch()
        _ = application.buttons["tab.today"].waitForExistence(timeout: 20)
    }

    override func tearDown() {
        writeReport()
        application = nil
        super.tearDown()
    }

    private let longName = "Олександра Ковальчук-Шевченко"

    func testLongCyrillicNameKeepsLayoutAndControlsUsable() {
        let opened = openLongNameCard()

        capture("37-dlugie-nazwy-cyrylica", description: "Karta klientki o długim nazwisku w cyrylicy przy AccessibilityXXXL") {
            if let opened { return opened }
            return self.assertNameLayout()
        }

        capture("38-dlugie-nazwy-decyzje", description: "Decyzje karty osiągalne przy największym tekście") {
            if let opened { return opened }
            return self.assertDecisionsReachable()
        }
    }

    /// Nawigacja: zakładka klientów, wyszukanie klientki po cyrylicy, otwarcie karty.
    private func openLongNameCard() -> String? {
        let clientsTab = application.buttons["tab.clients"]
        guard clientsTab.waitForExistence(timeout: 15) else { return "brak zakładki klientów" }
        clientsTab.tap()

        // Przy największym tekście lista mieści kilka osób, a klientka z długim
        // nazwiskiem jest ostatnia — szukamy jej polem, a nie przewijaniem.
        let namedField = application.textFields["Szukaj osoby lub tematu"]
        let field = namedField.exists ? namedField : application.textFields.firstMatch
        guard field.waitForExistence(timeout: 15) else { return "brak pola szukania klientów" }
        field.tap()
        // „\n” zamyka klawiaturę: przy AccessibilityXXXL nagłówek i filtry zajmują
        // cały ekran nad klawiaturą, a leniwa lista tworzy wiersz dopiero po przewinięciu.
        field.typeText("Олександра\n")

        // Karta leada jest jednym elementem dostępności (nazwisko w etykiecie
        // przycisku), więc szukamy karty, a nie osobnego napisu z nazwiskiem.
        let row = application.buttons
            .matching(identifier: "lead-card")
            .matching(NSPredicate(format: "label CONTAINS %@", longName))
            .firstMatch
        for _ in 0..<5 where !(row.exists && withinWindow(row, named: "wiersz listy")) {
            drag(up: true)
            Thread.sleep(forTimeInterval: 0.3)
        }
        guard row.waitForExistence(timeout: 15) else {
            return "lista klientów nie pokazuje długiego nazwiska po wyszukaniu"
        }
        guard withinWindow(row, named: "wiersz listy") else { return "wiersz listy poza oknem" }
        row.tap()

        let back = application.buttons["Wróć"]
        guard back.waitForExistence(timeout: 15) else { return "karta klientki się nie otworzyła" }
        return back.isHittable ? nil : "przycisk „Wróć” nieosiągalny przy największym tekście"
    }

    /// Układ nagłówka: nazwisko wewnątrz okna i brak przecięcia z awatarem.
    private func assertNameLayout() -> String? {
        let name = application.staticTexts[longName].firstMatch
        guard name.waitForExistence(timeout: 10) else { return "brak nazwiska na karcie" }
        guard withinWindow(name, named: "nazwisko") else {
            return "nazwisko wychodzi za okno (przycięte lub przewinięte w poziomie)"
        }

        let initials = application.staticTexts["ОК"].firstMatch
        if initials.exists, initials.frame != .zero {
            let overlap = initials.frame.intersection(name.frame)
            if !overlap.isNull, overlap.height > 1, overlap.width > 1 {
                return "inicjały nachodzą na nazwisko: \(initials.frame) vs \(name.frame)"
            }
        }
        return nil
    }

    /// Decyzje karty: każda widoczna musi dać się osiągnąć (karta jest przewijana).
    private func assertDecisionsReachable() -> String? {
        let decisions = ["Dodaj", "Zadzwoń", "Napisz", "Rozpocznij prowadzenie sprawy"]
        var unreachable: [String] = []
        var disabled: [String] = []
        for label in decisions {
            // Ten sam napis może wystąpić w kilku miejscach karty, więc bierzemy
            // pierwsze trafienie i pytamy o jego geometrię.
            let matches = application.buttons.matching(NSPredicate(format: "label == %@", label))
            guard matches.count > 0 else { continue }
            let button = matches.firstMatch
            // Wyłączona decyzja to inna sprawa niż układ — `isHittable` jest wtedy
            // fałszywe z definicji, więc zapisujemy to jako obserwację.
            if !button.isEnabled {
                disabled.append(label)
                continue
            }
            if button.frame != .zero, !scrollIntoView(button) {
                unreachable.append(label)
            }
        }
        if !disabled.isEmpty {
            report.append(
                "uwaga · wyłączone przy AccessibilityXXXL (nie z powodu układu): "
                    + disabled.joined(separator: ", ")
            )
        }
        if !unreachable.isEmpty {
            return "nieosiągalne przy największym tekście: \(unreachable.joined(separator: ", "))"
        }
        return nil
    }

    // MARK: Pomocnicze

    /// Przewija kartę **w stronę** elementu, aż będzie osiągalny. Kierunek wynika
    /// z ramki, więc nie przeskakujemy elementu (karta przy XXXL jest długa).
    private func scrollIntoView(_ element: XCUIElement, attempts: Int = 24) -> Bool {
        let window = application.windows.firstMatch.frame
        for _ in 0..<attempts {
            if element.isHittable { return true }
            let frame = element.frame
            // Dolny pasek zakładek zasłania ostatnie ~120 pt okna: element pod
            // nim jest „w oknie”, ale nieosiągalny — trzeba przewinąć dalej.
            if frame.isEmpty || frame.maxY > window.maxY - 120 {
                drag(up: true)
            } else if frame.minY < window.minY {
                drag(up: false)
            } else {
                return element.isHittable
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return element.isHittable
    }

    /// Przewijanie karty gestem w **górnej** części ekranu: klawiatura po wyszukaniu
    /// zajmuje dół i `swipeUp()` na całym ekranie trafiałby w klawisze, a nie w kartę.
    private func drag(up: Bool) {
        let from = application.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.55 : 0.30))
        let to = application.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.30 : 0.55))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    private func withinWindow(_ element: XCUIElement, named what: String) -> Bool {
        let window = application.windows.firstMatch.frame
        guard !window.isEmpty else { return false }
        let frame = element.frame
        return frame.minX >= window.minX - 0.5
            && frame.maxX <= window.maxX + 0.5
            && frame.minY >= window.minY - 0.5
            && frame.maxY <= window.maxY + 0.5
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
        Zrzut ekranu Emmy — etap 6 (układ: długie nazwisko w cyrylicy)
        Data: \(ISO8601DateFormatter().string(from: Date()))
        Zestaw danych: dlugie-nazwy · tekst: AccessibilityXXXL
        Asercje: nazwisko wewnątrz okna, brak przecięcia z inicjałami, decyzje osiągalne.
        VoiceOver i Reduce Motion pozostają do sprawdzenia na urządzeniu.

        """
        let name = "raport-etap6-\(self.name.replacingOccurrences(of: "-[", with: "").replacingOccurrences(of: "]", with: "").replacingOccurrences(of: " ", with: "-")).txt"
        let body = report.isEmpty ? "Brak wykonanych scen." : report.joined(separator: "\n")
        try? (header + body + "\n").write(
            to: outputDirectory.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }
}
