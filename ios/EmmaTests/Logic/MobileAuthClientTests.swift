import XCTest
@testable import Emma

// MARK: - Klient logowania mobilnego: żądanie i odpowiedź (M1)
//
// Sprawdzamy dwie rzeczy, których nie da się zobaczyć w interfejsie:
//   1. co dokładnie leci do backendu (ścieżka, pola, brak hasła w query),
//   2. jak rozumiemy odpowiedzi — także te błędne.
//
// Testy nie używają sieci: `StubURLProtocol` podmienia transport.

final class MobileAuthClientTests: XCTestCase {

    private var baseURL: URL { URL(string: "https://advokat-varshava.pl")! }

    private func makeClient() -> MobileAuthClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return MobileAuthClient(
            baseURL: baseURL,
            session: URLSession(configuration: configuration)
        )
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: Żądanie

    func testLoginSendsCredentialsToMobileEndpoint() async throws {
        StubURLProtocol.respond(json: Self.sessionJSON, status: 200)
        _ = try await makeClient().login(
            email: "pawel@advokat-varshava.pl",
            password: "tajne-haslo",
            totp: "123456",
            installationID: "instalacja-1",
            deviceName: "iPhone Pawła"
        )

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://advokat-varshava.pl/api/mobile/v1/auth/login")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        // Hasło musi iść w ciele, nigdy w adresie (adres trafia do logów proxy).
        XCTAssertFalse(request.url?.absoluteString.contains("tajne-haslo") ?? true)

        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        XCTAssertEqual(body["email"] as? String, "pawel@advokat-varshava.pl")
        XCTAssertEqual(body["password"] as? String, "tajne-haslo")
        XCTAssertEqual(body["totp"] as? String, "123456")
        XCTAssertEqual(body["installation_id"] as? String, "instalacja-1")
        XCTAssertEqual(body["device_name"] as? String, "iPhone Pawła")
    }

    func testLoginOmitsEmptyTotpInsteadOfSendingEmptyString() async throws {
        StubURLProtocol.respond(json: Self.sessionJSON, status: 200)
        _ = try await makeClient().login(
            email: "pawel@advokat-varshava.pl",
            password: "tajne-haslo",
            totp: "",
            installationID: "instalacja-1",
            deviceName: ""
        )

        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        XCTAssertNil(body["totp"])
        XCTAssertNil(body["device_name"])
    }

    func testRefreshSendsRefreshTokenWithoutAuthorizationHeader() async throws {
        StubURLProtocol.respond(json: Self.sessionJSON, status: 200)
        _ = try await makeClient().refreshSession(refreshToken: "odswiezacz", installationID: "instalacja-1")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://advokat-varshava.pl/api/mobile/v1/auth/refresh")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(try XCTUnwrap(StubURLProtocol.lastBody)["refresh_token"] as? String, "odswiezacz")
    }

    func testRevokeSendsBearerTokenAndReason() async throws {
        StubURLProtocol.respond(json: Data(), status: 204)
        try await makeClient().revokeSession(
            accessToken: "token-dostepu",
            installationID: "instalacja-1",
            reason: "logout"
        )

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://advokat-varshava.pl/api/mobile/v1/auth/revoke")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-dostepu")
        XCTAssertEqual(try XCTUnwrap(StubURLProtocol.lastBody)["reason"] as? String, "logout")
    }

    /// Wylogowanie nie może się nie udać tylko dlatego, że sesja już wygasła.
    func testRevokeTreatsUnauthorizedAsSuccess() async throws {
        StubURLProtocol.respond(json: Data(#"{"code":"unauthorized","message":"Sesja wygasła."}"#.utf8), status: 401)
        try await makeClient().revokeSession(
            accessToken: "stary",
            installationID: "instalacja-1",
            reason: "logout"
        )
    }

    // MARK: Odpowiedź

    func testDecodesSessionWithMillisecondDate() async throws {
        StubURLProtocol.respond(json: Self.sessionJSON, status: 200)
        let session = try await makeClient().login(
            email: "pawel@advokat-varshava.pl",
            password: "x",
            totp: "",
            installationID: "instalacja-1",
            deviceName: ""
        )

        XCTAssertEqual(session.accessToken, "access-abc")
        XCTAssertEqual(session.refreshToken, "refresh-xyz")
        XCTAssertEqual(session.user.id, "user-1")
        XCTAssertEqual(session.user.displayName, "Paweł Rogoża")
        XCTAssertEqual(session.user.initials, "PR")
        XCTAssertEqual(session.user.interfaceLanguage, "pl")
        XCTAssertEqual(session.user.assistantLanguage, "pl")
        // 2026-09-14T11:39:09.844Z — format faktycznie zwracany przez backend.
        XCTAssertEqual(session.expiresAt.timeIntervalSince1970, 1_789_385_949.844, accuracy: 0.001)
    }

    func testDecodesSessionWithoutMilliseconds() async throws {
        let json = Data(#"""
        {"access_token":"a","refresh_token":"r","expires_at":"2026-09-14T11:39:09Z",
         "user":{"id":"user-1","display_name":"Paweł","initials":"P","interface_language":"pl","assistant_language":"uk"}}
        """#.utf8)
        StubURLProtocol.respond(json: json, status: 200)
        let session = try await makeClient().refreshSession(refreshToken: "r", installationID: "i")
        XCTAssertEqual(session.user.assistantLanguage, "uk")
    }

    // MARK: Błędy

    func testUnauthorizedCarriesServerMessage() async throws {
        StubURLProtocol.respond(
            json: Data(#"{"code":"unauthorized","message":"Nieprawidłowe dane logowania."}"#.utf8),
            status: 401
        )
        do {
            _ = try await makeClient().login(
                email: "a@b.pl", password: "zle", totp: "", installationID: "i", deviceName: ""
            )
            XCTFail("Oczekiwano błędu unauthorized")
        } catch let error as MobileAuthError {
            XCTAssertEqual(error, .unauthorized("Nieprawidłowe dane logowania."))
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(error.userMessage, "Nieprawidłowe dane logowania.")
        }
    }

    func testRateLimitedReadsRetryAfterHeader() async throws {
        StubURLProtocol.respond(
            json: Data(#"{"code":"rate_limited","message":"Zbyt wiele prób."}"#.utf8),
            status: 429,
            headers: ["Retry-After": "600"]
        )
        do {
            _ = try await makeClient().login(
                email: "a@b.pl", password: "x", totp: "", installationID: "i", deviceName: ""
            )
            XCTFail("Oczekiwano błędu rate_limited")
        } catch let error as MobileAuthError {
            XCTAssertEqual(error, .rateLimited(retryAfterSeconds: 600, message: "Zbyt wiele prób."))
            XCTAssertTrue(error.isRetryable)
        }
    }

    /// Strona publiczna i złe wdrożenie zwracają HTML, nie JSON. To musi być
    /// czytelny błąd formatu, a nie zawieszone logowanie.
    func testHtmlErrorPageBecomesMalformedOrServerError() async throws {
        StubURLProtocol.respond(json: Data("<html>404</html>".utf8), status: 404)
        do {
            _ = try await makeClient().login(
                email: "a@b.pl", password: "x", totp: "", installationID: "i", deviceName: ""
            )
            XCTFail("Oczekiwano błędu")
        } catch let error as MobileAuthError {
            XCTAssertEqual(error, .notFound(nil))
        }
    }

    func testTransportFailureIsReportedAsConnectionProblem() async throws {
        StubURLProtocol.fail(with: URLError(.notConnectedToInternet))
        do {
            _ = try await makeClient().login(
                email: "a@b.pl", password: "x", totp: "", installationID: "i", deviceName: ""
            )
            XCTFail("Oczekiwano błędu transportu")
        } catch let error as MobileAuthError {
            guard case .transport = error else {
                return XCTFail("Oczekiwano .transport, a jest \(error)")
            }
            XCTAssertTrue(error.isRetryable)
        }
    }

    func testUnknownErrorCodeFallsBackToStatus() async throws {
        StubURLProtocol.respond(json: Data(#"{"code":"cos_nowego","message":"?"}"#.utf8), status: 500)
        do {
            _ = try await makeClient().login(
                email: "a@b.pl", password: "x", totp: "", installationID: "i", deviceName: ""
            )
            XCTFail("Oczekiwano błędu")
        } catch let error as MobileAuthError {
            XCTAssertEqual(error, .server(status: 500, message: "?"))
        }
    }

    private static let sessionJSON = Data(#"""
    {"access_token":"access-abc","refresh_token":"refresh-xyz",
     "expires_at":"2026-09-14T11:39:09.844Z",
     "user":{"id":"user-1","display_name":"Paweł Rogoża","initials":"PR",
             "interface_language":"pl","assistant_language":"pl"}}
    """#.utf8)
}

// MARK: - Podstawiony transport

/// Podstawia odpowiedź HTTP bez sieci. Handler jest chroniony zamkiem, bo
/// klasa `URLProtocol` jest współdzielona dla całego procesu testowego.
final class StubURLProtocol: URLProtocol {

    private struct Stub {
        var status: Int
        var body: Data
        var headers: [String: String]
        var failure: URLError?
    }

    private static let lock = NSLock()
    // `nonisolated(unsafe)`: to stan współdzielony dla całego procesu testowego,
    // ale każdy dostęp przechodzi przez `lock`. Bez tego adnotacji tryb Swift 6
    // odrzuca statyczną mutowalną własność.
    nonisolated(unsafe) private static var stub = Stub(status: 200, body: Data(), headers: [:], failure: nil)
    /// Kolejka odpowiedzi dla jednego wywołania: pozwala sprawdzić ponowienie
    /// po 401 (pierwsza odpowiedź 401, druga 200). Pusta = używamy `stub`.
    nonisolated(unsafe) private static var stubQueue: [Stub] = []
    nonisolated(unsafe) private static var recordedRequest: URLRequest?
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []
    nonisolated(unsafe) private static var recordedBody: [String: Any]?

    static var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequest
    }

    /// Wszystkie żądania od ostatniego `reset()` — w kolejności wysłania.
    static var allRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests.count
    }

    static var lastBody: [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return recordedBody
    }

    static func respond(json: Data, status: Int, headers: [String: String] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        stubQueue = []
        stub = Stub(status: status, body: json, headers: headers, failure: nil)
    }

    /// Odpowiedzi po kolei na kolejne żądania. Po wyczerpaniu kolejki wraca `stub`.
    static func respond(sequence: [(json: Data, status: Int)]) {
        lock.lock()
        defer { lock.unlock() }
        stubQueue = sequence.map { Stub(status: $0.status, body: $0.json, headers: [:], failure: nil) }
    }

    static func fail(with error: URLError) {
        lock.lock()
        defer { lock.unlock() }
        stubQueue = []
        stub = Stub(status: 0, body: Data(), headers: [:], failure: error)
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        stub = Stub(status: 200, body: Data(), headers: [:], failure: nil)
        stubQueue = []
        recordedRequest = nil
        recordedRequests = []
        recordedBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // `httpBody` bywa przenoszony do strumienia, więc czytamy strumień.
        let body = request.httpBody ?? Self.readStream(request.httpBodyStream)
        Self.lock.lock()
        Self.recordedRequest = request
        Self.recordedRequests.append(request)
        if let body, let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            Self.recordedBody = parsed
        } else {
            Self.recordedBody = nil
        }
        let current: Stub
        if !Self.stubQueue.isEmpty {
            current = Self.stubQueue.removeFirst()
        } else {
            current = Self.stub
        }
        Self.lock.unlock()

        if let failure = current.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        var headers = current.headers
        headers["Content-Type"] = "application/json"
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: current.status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !current.body.isEmpty {
            client?.urlProtocol(self, didLoad: current.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}
