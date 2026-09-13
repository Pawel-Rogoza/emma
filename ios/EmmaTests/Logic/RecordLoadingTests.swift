import XCTest
@testable import Emma

// MARK: - Arkusze szczegółów: błąd odczytu ≠ wieczne „Wczytuję…” (F16)
//
// Wspólna reguła `RecordLoading` rozróżnia trzy wyniki: rekord, jawny brak
// (nieodwracalny) i błąd (z regułą ponowienia). Testujemy ją bez SwiftUI.

@MainActor
final class RecordLoadingTests: XCTestCase {

    private struct Record: Equatable {
        let value: String
    }

    func testReturnsLoadedValue() async {
        let phase: LoadPhase<Record> = await RecordLoading.phase(
            missingMessage: "Nie znaleziono.",
            fallback: "Nie udało się wczytać."
        ) {
            Record(value: "gotowe")
        }
        XCTAssertEqual(phase.value, Record(value: "gotowe"))
        XCTAssertNil(phase.failure)
    }

    func testMissingRecordIsExplicitAndNotRetryable() async {
        let phase: LoadPhase<Record> = await RecordLoading.phase(
            missingMessage: "Nie znaleziono tego zadania.",
            fallback: "Nie udało się wczytać."
        ) {
            nil
        }
        XCTAssertEqual(phase.failure?.message, "Nie znaleziono tego zadania.")
        XCTAssertEqual(phase.failure?.isRetryable, false, "Brak rekordu nie naprawi się ponowieniem")
    }

    func testDomainErrorKeepsItsMessageAndRetryRule() async {
        let offline: LoadPhase<Record> = await RecordLoading.phase(
            missingMessage: "brak",
            fallback: "Nie udało się wczytać."
        ) { () async throws -> Record? in
            throw DomainError.offline
        }
        XCTAssertEqual(offline.failure?.message, DomainError.offline.safeMessage)
        XCTAssertEqual(offline.failure?.isRetryable, true)

        let forbidden: LoadPhase<Record> = await RecordLoading.phase(
            missingMessage: "brak",
            fallback: "Nie udało się wczytać."
        ) { () async throws -> Record? in
            throw DomainError.forbidden
        }
        XCTAssertEqual(forbidden.failure?.message, DomainError.forbidden.safeMessage)
        XCTAssertEqual(forbidden.failure?.isRetryable, false)
    }

    func testUnknownErrorUsesFallbackAndIsRetryable() async {
        struct Boom: Error {}
        let phase: LoadPhase<Record> = await RecordLoading.phase(
            missingMessage: "brak",
            fallback: "Nie udało się wczytać zadania."
        ) { () async throws -> Record? in
            throw Boom()
        }
        XCTAssertEqual(phase.failure?.message, "Nie udało się wczytać zadania.")
        XCTAssertEqual(phase.failure?.isRetryable, true, "Nieznany błąd jest zwykle przejściowy")
    }
}
