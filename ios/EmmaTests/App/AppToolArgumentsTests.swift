import XCTest
@testable import Emma

// MARK: - Argumenty narzędzi `app_*` od modelu
//
// Narzędzia CRM zwracają modelowi surowe liczby (`"id": 12`), a aplikacja zna
// identyfikatory z prefiksem (`client-12`). Model może też przepisać je
// z wcześniejszego wyniku w obu postaciach — normalizacja musi przyjąć każdą.

@MainActor
final class AppToolArgumentsTests: XCTestCase {

    func testNumericAndPrefixedIDsNormalize() {
        XCTAssertEqual(AssistantStore.entityID(NSNumber(value: 12), prefix: "client"), "client-12")
        XCTAssertEqual(AssistantStore.entityID("12", prefix: "client"), "client-12")
        XCTAssertEqual(AssistantStore.entityID("client-12", prefix: "client"), "client-12")
        XCTAssertNil(AssistantStore.entityID(NSNumber(value: 0), prefix: "client"))
        XCTAssertNil(AssistantStore.entityID("  ", prefix: "client"))
    }

    func testLeadIsUsedWhenClientIsMissing() {
        let args = AssistantStore.arguments(from: #"{"lead_id":7}"#)
        XCTAssertEqual(AssistantStore.contactID(from: args), "lead-7")
    }

    func testToolErrorIsValidJSONObject() throws {
        let json = AssistantStore.toolError(#"Brak "danych""#)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["error"] as? String, #"Brak "danych""#)
    }

    /// Bez podpiętego ekranu narzędzie nie udaje sukcesu.
    func testUnattachedStoreRefusesTools() async throws {
        let store = AssistantStore()
        let json = await store.handleAppTool(name: "app_open_screen", argumentsJSON: #"{"screen":"today"}"#)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertNotNil(object["error"])
    }
}
