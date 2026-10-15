import XCTest
@testable import Emma

// MARK: - Słownik kontraktu: jedna tabela na typ (audyt 16.10.2026)
//
// Zapis i odczyt tokenów korzystają z tej samej tabeli (`contractToken`), więc
// każdy zapisany token musi dać się odczytać z powrotem, a tokeny jednego typu
// nie mogą się powtarzać.

final class ContractTokenTests: XCTestCase {

    private func assertRoundTrip<Value: ContractTokenRepresentable & Equatable>(
        _ type: Value.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tokens = Value.allCases.map(\.contractToken)
        XCTAssertEqual(Set(tokens).count, tokens.count, "powtórzony token w \(Value.self)", file: file, line: line)
        for value in Value.allCases {
            XCTAssertEqual(Value(contractToken: value.contractToken), value, file: file, line: line)
        }
        XCTAssertNil(Value(contractToken: "nieznany_token"), file: file, line: line)
    }

    func testEveryTokenReadsBackAsTheSameValue() {
        assertRoundTrip(ClientStage.self)
        assertRoundTrip(CaseStatus.self)
        assertRoundTrip(TaskPriority.self)
        assertRoundTrip(TaskFilter.Scope.self)
        assertRoundTrip(EventKind.self)
        assertRoundTrip(EventStatus.self)
    }

    func testTokensMatchTheMobileContract() {
        XCTAssertEqual(ClientStage.inContact.contractToken, "in_contact")
        XCTAssertEqual(CaseStatus.awaitingClient.contractToken, "awaiting_client")
        XCTAssertEqual(TaskPriority.urgent.contractToken, "urgent")
        XCTAssertEqual(TaskFilter.Scope.done.contractToken, "done")
        XCTAssertEqual(EventKind.caseDeadline.contractToken, "case_deadline")
        XCTAssertEqual(EventStatus.toConfirm.contractToken, "to_confirm")
    }

    func testUnknownTokenIsADecodingErrorNotADefault() {
        XCTAssertThrowsError(try BackendRepository.decodeToken("archived", as: CaseStatus.self, "nieznany status sprawy")) { error in
            XCTAssertEqual(error as? BackendRepositoryError, .decoding("nieznany status sprawy: archived"))
        }
        XCTAssertEqual(try BackendRepository.decodeToken("closed", as: CaseStatus.self, "nieznany status sprawy"), .closed)
    }
}
