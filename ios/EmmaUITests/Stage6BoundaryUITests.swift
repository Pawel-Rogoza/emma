import XCTest

// MARK: - Zrzut etapu 6: jawna granica mocka na ekranie Emmy
//
// Etap 6 nie zamyka się bez prawdziwych usług (patrz UX_VOICE_STAGES.md), więc
// jedynym uczciwym zrzutem jest ten, który pokazuje **co jest mockiem, a co nie**:
// stopka Emmy mówi wprost o scenariuszowym głosie, braku integracji z ElevenLabs
// i WhatsApp oraz o scenariuszowym odsłuchu w demo.

final class Stage6BoundaryUITests: XCTestCase {

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

    func testCaptureStage6MockBoundaryNotice() {
        capture("35-emma-nota-o-demo", description: "Stopka Emmy: jawna granica mocka (głos, WhatsApp, odsłuch)") {
            let tab = self.application.buttons["tab.emma"]
            if tab.exists { tab.tap() }
            guard self.application.buttons["Dyktuj tekst do pola"].waitForExistence(timeout: 15) else {
                return "brak kompozytora na ekranie Emmy"
            }
            // Stopka jest pod rozmową — przewijamy, żeby była w kadrze.
            let start = self.application.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end = self.application.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
            start.press(forDuration: 0.05, thenDragTo: end)

            let notice = self.application.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "Odsłuch w demo jest scenariuszowy")
            ).firstMatch
            guard notice.waitForExistence(timeout: 10) else {
                return "stopka nie mówi o scenariuszowym odsłuchu w demo"
            }
            guard self.application.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "nie ma integracji z ElevenLabs")
            ).firstMatch.exists else {
                return "stopka nie mówi o braku integracji z dostawcą"
            }
            return nil
        }
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
        Zrzut ekranu Emmy — etap 6 (granica mocka)
        Data: \(ISO8601DateFormatter().string(from: Date()))
        Scena pokazuje stopkę, która mówi wprost, co w demo jest scenariuszowe.
        Brak prawdziwego odsłuchu i wysyłki to stan faktyczny, nie usterka zrzutu.

        """
        let body = report.isEmpty ? "Brak wykonanych scen." : report.joined(separator: "\n")
        let name = "raport-etap6-\(self.name.replacingOccurrences(of: "-[", with: "").replacingOccurrences(of: "]", with: "").replacingOccurrences(of: " ", with: "-")).txt"
        try? (header + body + "\n").write(
            to: outputDirectory.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }
}
