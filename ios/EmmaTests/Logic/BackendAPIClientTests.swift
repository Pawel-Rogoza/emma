import XCTest
@testable import Emma

// MARK: - Klient HTTP danych kancelarii: żądanie i odpowiedź
//
// Sprawdzamy dwie rzeczy, których nie da się zobaczyć w interfejsie:
//   1. co dokładnie leci do backendu (ścieżka, parametry zapytania, nagłówek),
//   2. jak rozumiemy odpowiedzi — także błędne.
//
// Testy nie używają sieci: `StubURLProtocol` (z `MobileAuthClientTests`)
// podmienia transport, więc sprawdzamy kontrakt, a nie dostępność serwera.

final class BackendAPIClientTests: XCTestCase {

    private var baseURL: URL { URL(string: "https://majkuny.pl")! }

    private func makeClient(token: String? = "token-dostepu") -> BackendAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return BackendAPIClient(
            baseURL: baseURL,
            accessToken: { token },
            session: URLSession(configuration: configuration)
        )
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func queryItems(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    // MARK: Żądanie

    func testClientsRequestSendsQueryStageLimitAndBearerHeader() async throws {
        StubURLProtocol.respond(json: Data(#"{"items":[],"next_cursor":null,"has_more":false}"#.utf8), status: 200)
        _ = try await makeClient().clients(query: "olena", stage: .inContact, limit: 25)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/mobile/v1/clients")
        XCTAssertEqual(request.httpMethod, "GET")
        // Token trafia w nagłówku, nigdy w adresie (adres ląduje w logach proxy).
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-dostepu")

        let query = queryItems(request)
        XCTAssertEqual(query["query"], "olena")
        // Etap jest w aplikacji opisany po polsku, a w kontrakcie tokenem.
        XCTAssertEqual(query["stage"], "in_contact")
        XCTAssertEqual(query["limit"], "25")
    }

    func testTasksRequestSendsScopeAndFilters() async throws {
        StubURLProtocol.respond(json: Data(#"{"items":[]}"#.utf8), status: 200)
        _ = try await makeClient().tasks(filter: TaskFilter(
            scope: .done,
            dueOnOrBefore: LocalDate(year: 2026, month: 9, day: 14),
            clientID: ClientID("client-12"),
            caseID: CaseID("case-041")
        ))

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/mobile/v1/tasks")
        let query = queryItems(request)
        XCTAssertEqual(query["scope"], "done")
        XCTAssertEqual(query["due_on_or_before"], "2026-09-14")
        XCTAssertEqual(query["client_id"], "client-12")
        XCTAssertEqual(query["case_id"], "case-041")
    }

    func testEventsRequestSendsFromAndThrough() async throws {
        StubURLProtocol.respond(json: Data(#"{"items":[]}"#.utf8), status: 200)
        _ = try await makeClient().events(in: DateIntervalFilter(
            from: LocalDate(year: 2026, month: 9, day: 1),
            through: LocalDate(year: 2026, month: 9, day: 30)
        ))

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/mobile/v1/events")
        let query = queryItems(request)
        XCTAssertEqual(query["from"], "2026-09-01")
        XCTAssertEqual(query["through"], "2026-09-30")
    }

    func testClientCardRequestUsesIdentifierPath() async throws {
        StubURLProtocol.respond(json: Data(Self.cardJSON.utf8), status: 200)
        let card = try await makeClient().clientCard(id: ClientID("client-12"))

        XCTAssertEqual(card.client.id, "client-12")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/api/mobile/v1/clients/client-12")
    }

    func testMissingTokenOmitsAuthorizationHeader() async throws {
        StubURLProtocol.respond(json: Data(#"{"items":[],"next_cursor":null,"has_more":false}"#.utf8), status: 200)
        _ = try await makeClient(token: nil).clients(query: "", stage: nil)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: Odpowiedź

    func testDecodesClientPage() async throws {
        let json = Data(#"""
        {"items":[{"id":"lead-7","display_name":"Ihor","initials":"I","language":"uk",
          "topic":"Zapytanie","stage":"new","source":"web_form","created_at":"2026-09-01",
          "briefing":null,"needs_reply":true,"version":3}],
         "next_cursor":null,"has_more":false}
        """#.utf8)
        StubURLProtocol.respond(json: json, status: 200)
        let page = try await makeClient().clients(query: "", stage: nil)
        XCTAssertEqual(page.items.map(\.id), ["lead-7"])
        XCTAssertEqual(page.items.first?.displayName, "Ihor")
        XCTAssertFalse(page.hasMore)
    }

    // MARK: Błędy

    func testUnauthorizedMapsToUnauthorized() async throws {
        StubURLProtocol.respond(json: Data(#"{"code":"unauthorized","message":"Sesja wygasła."}"#.utf8), status: 401)
        await assertError(.unauthorized) {
            _ = try await self.makeClient().clients(query: "", stage: nil)
        }
    }

    func testNotFoundMapsToNotFound() async throws {
        StubURLProtocol.respond(json: Data(#"{"code":"not_found","message":"Nie ma."}"#.utf8), status: 404)
        await assertError(.notFound) {
            _ = try await self.makeClient().clientCard(id: ClientID("client-12"))
        }
    }

    func testServerErrorCarriesStatusAndMessage() async throws {
        StubURLProtocol.respond(
            json: Data(#"{"code":"internal_error","message":"Błąd serwera."}"#.utf8),
            status: 500
        )
        await assertError(.server(status: 500, message: "Błąd serwera.")) {
            _ = try await self.makeClient().clients(query: "", stage: nil)
        }
    }

    func testTransportFailureMapsToTransport() async throws {
        StubURLProtocol.fail(with: URLError(.notConnectedToInternet))
        do {
            _ = try await makeClient().clients(query: "", stage: nil)
            XCTFail("Oczekiwano błędu transportu")
        } catch let error as BackendRepositoryError {
            guard case .transport = error else {
                return XCTFail("Oczekiwano .transport, a jest \(error)")
            }
            XCTAssertTrue(error.isRetryable)
        }
    }

    // MARK: Pomocnicze

    private func assertError(
        _ expected: BackendRepositoryError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Oczekiwano błędu \(expected)", file: file, line: line)
        } catch let error as BackendRepositoryError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Oczekiwano BackendRepositoryError, a jest \(error)", file: file, line: line)
        }
    }

    private static let cardJSON = #"""
    {"client":{"id":"client-12","display_name":"Olena","initials":"OK","language":"pl",
      "topic":"Sprawa","stage":"client","source":"whatsapp","created_at":"2026-08-01",
      "briefing":null,"needs_reply":false,"version":5},
     "events":[],"tasks":[],"notes":[],"activity":[]}
    """#
}
