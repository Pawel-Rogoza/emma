import XCTest

// MARK: - Pasek zakładek: położenie i Emma w środku
//
// 0.22.1 wyszło z paskiem na środku ekranu (puste gniazdo bez limitu wysokości
// rozciągnęło kapsułę), a CI było zielone, bo nic nie mierzyło paska. Ten test
// sprawdza po wejściu na każdą zakładkę, że:
//   • wszystkie pięć zakładek istnieje i da się je nacisnąć,
//   • pasek leży przy dolnej krawędzi i nie jest wyższy niż zwykły pasek,
//   • zwykłe zakładki są w jednym rzędzie, a Emma dokładnie na środku.

final class TabBarLayoutUITests: XCTestCase {

    private var application: XCUIApplication!
    private let tabs = ["today", "clients", "emma", "messages", "calendar"]

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

    func testTabBarStaysAtBottomOnEveryTab() {
        // Najpierw tam i z powrotem, potem jeszcze raz — błąd mrugania
        // pojawiał się dopiero przy kolejnych przełączeniach.
        for identifier in tabs + tabs.reversed() {
            let tab = application.buttons["tab.\(identifier)"]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "Brak zakładki \(identifier)")
            tab.tap()
            assertTabBarLayout(after: identifier)
        }
    }

    private func assertTabBarLayout(after identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let window = application.windows.firstMatch.frame
        let frames = Dictionary(uniqueKeysWithValues: tabs.map { ($0, application.buttons["tab.\($0)"].frame) })

        for (name, frame) in frames {
            XCTAssertFalse(frame.isEmpty, "Zakładka \(name) bez ramki (po \(identifier))", file: file, line: line)
            XCTAssertTrue(
                application.buttons["tab.\(name)"].isHittable,
                "Zakładki \(name) nie da się nacisnąć (po \(identifier))", file: file, line: line
            )
            // Pasek przy dolnej krawędzi: dół zakładki w ostatnich 15% ekranu.
            XCTAssertGreaterThan(
                frame.maxY, window.height * 0.85,
                "Zakładka \(name) nie leży przy dole ekranu: \(frame) w oknie \(window) (po \(identifier))",
                file: file, line: line
            )
            XCTAssertLessThan(
                frame.height, 110,
                "Zakładka \(name) jest rozciągnięta w pionie: \(frame) (po \(identifier))", file: file, line: line
            )
        }

        let regular = tabs.filter { $0 != "emma" }.compactMap { frames[$0] }
        if let first = regular.first {
            for frame in regular {
                XCTAssertEqual(frame.midY, first.midY, accuracy: 3, "Zwykłe zakładki nie są w jednym rzędzie (po \(identifier))", file: file, line: line)
            }
        }
        if let emma = frames["emma"] {
            XCTAssertEqual(emma.midX, window.midX, accuracy: 6, "Emma nie jest na środku paska: \(emma) (po \(identifier))", file: file, line: line)
        }
    }
}
