import XCTest
@testable import Emma

/// Strażnik wyglądu postaci Emmy.
///
/// Powód istnienia: ikonka ma **mrugać**, a nie zmieniać rozmiaru. Render 3D
/// (relief) i obrazek zapasowy rysują tę samą twarz w dwóch różnych układach, więc
/// każda zmiana skali obrazka zapasowego albo powrót do skali `1` kończy się tym,
/// że przy przełączeniu renderu (wejście do tła, „Reduce Motion”) postać rośnie
/// lub maleje. Te testy pilnują, żeby ta zgodność została.
@MainActor
final class EmmaOrbTests: XCTestCase {

    /// Rozmiary reliefowe muszą używać skali dopasowanej do renderu 3D.
    func testReliefSizesMatchTheReliefFraming() {
        for size in [EmmaOrb.Size.hero, .stage] {
            XCTAssertTrue(size.usesRelief, "\(size) ma render 3D")
            XCTAssertEqual(
                size.portraitScale,
                EmmaOrb.reliefMatchScale,
                accuracy: 0.0001,
                "Obrazek zapasowy dla \(size) musi mieć wielkość reliefu"
            )
        }
    }

    /// Wartość sama w sobie musi być sensowna: postać w reliefie nie zajmuje całej
    /// ramki (jest odsunięta od krawędzi), więc obrazek trzeba powiększyć.
    func testReliefCoverageIsPlausible() {
        XCTAssertGreaterThan(EmmaOrb.reliefCoverage, 0.8)
        XCTAssertLessThan(EmmaOrb.reliefCoverage, 1)
        XCTAssertGreaterThan(EmmaOrb.reliefMatchScale, 1)
        XCTAssertLessThan(EmmaOrb.reliefMatchScale, 1.2)
    }

    /// Małe rozmiary rysuje wyłącznie obrazek — ich skale są dostrojone do czytelności
    /// i nie mają nic wspólnego z reliefem, więc nie mogą się zmienić przypadkiem.
    func testSmallSizesKeepTheirTunedScale() {
        XCTAssertEqual(EmmaOrb.Size.inline.portraitScale, 1.34, accuracy: 0.0001)
        XCTAssertEqual(EmmaOrb.Size.small.portraitScale, 1.34, accuracy: 0.0001)
        XCTAssertEqual(EmmaOrb.Size.medium.portraitScale, 1.18, accuracy: 0.0001)
        XCTAssertEqual(EmmaOrb.Size.card.portraitScale, 1.18, accuracy: 0.0001)
        XCTAssertEqual(EmmaOrb.Size.compact.portraitScale, 1.18, accuracy: 0.0001)
        XCTAssertFalse(EmmaOrb.Size.compact.usesRelief)
    }

    /// Średnice są stałe — to wskaźnik stanu, nie element elastyczny.
    func testDiametersAreFixed() {
        XCTAssertEqual(EmmaOrb.Size.inline.diameter, 18, accuracy: 0.0001)
        XCTAssertEqual(EmmaOrb.Size.compact.diameter, 52, accuracy: 0.0001)
        XCTAssertEqual(EmmaOrb.Size.hero.diameter, 100, accuracy: 0.0001)
        XCTAssertEqual(EmmaOrb.Size.stage.diameter, 148, accuracy: 0.0001)
    }
}
