import XCTest
@testable import Emma

// MARK: - Prowadzenie sesji mobilnej (M1)
//
// Reguły, które wynikają z realnego backendu i łatwo je zepsuć:
//   • token ważny → żadnego odświeżania (każde odświeżenie to nowy wpis w bazie),
//   • token wygasa → jedno odświeżenie, nawet przy równoległych żądaniach
//     (rotacja unieważnia poprzedni token odświeżania!),
//   • odrzucone odnowienie → sesja wyczyszczona, nie „zalogowany bez dostępu”,
//   • wylogowanie unieważnia sesję na serwerze i kasuje ją lokalnie nawet bez sieci.

final class MobileSessionKeeperTests: XCTestCase {

    // MARK: Podwójny klient

    private final class FakeClient: MobileAuthServicing, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var loginCalls: [(email: String, password: String, totp: String, installationID: String)] = []
        private(set) var refreshCalls: [String] = []
        private(set) var revokeCalls: [(token: String, reason: String)] = []

        var loginResult: Result<MobileAuthSession, MobileAuthError> = .success(FakeClient.session())
        var refreshResults: [Result<MobileAuthSession, MobileAuthError>] = []
        var revokeError: MobileAuthError?
        /// Opóźnienie odnowienia: pozwala wywołać dwa odświeżenia równolegle.
        var refreshDelay: UInt64 = 0

        func login(
            email: String,
            password: String,
            totp: String,
            installationID: String,
            deviceName: String
        ) async throws -> MobileAuthSession {
            // `withLock`, nie `lock()/unlock()`: ręczne blokowanie w funkcji
            // `async` to w trybie Swift 6 błąd, nie ostrzeżenie.
            let result = lock.withLock { () -> Result<MobileAuthSession, MobileAuthError> in
                loginCalls.append((email, password, totp, installationID))
                return loginResult
            }
            return try result.get()
        }

        func refreshSession(refreshToken: String, installationID: String) async throws -> MobileAuthSession {
            let (result, delay) = lock.withLock {
                refreshCalls.append(refreshToken)
                let result = refreshResults.isEmpty ? loginResult : refreshResults.removeFirst()
                return (result, refreshDelay)
            }
            if delay > 0 { try await Task.sleep(nanoseconds: delay) }
            return try result.get()
        }

        func revokeSession(accessToken: String, installationID: String, reason: String) async throws {
            let error = lock.withLock { () -> MobileAuthError? in
                revokeCalls.append((accessToken, reason))
                return revokeError
            }
            if let error { throw error }
        }

        static func session(
            accessToken: String = "access-1",
            refreshToken: String = "refresh-1",
            expiresIn: TimeInterval = 1800
        ) -> MobileAuthSession {
            MobileAuthSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: Date(timeIntervalSince1970: 1_800_000_000 + expiresIn),
                user: MobileAuthUser(
                    id: "user-1",
                    displayName: "Paweł Rogoża",
                    initials: "PR",
                    interfaceLanguage: "pl",
                    assistantLanguage: "pl"
                )
            )
        }
    }

    /// Zegar sterowany ręcznie: testy nie zależą od prawdziwego czasu.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_800_000_000)
        func now() -> Date {
            lock.withLock { value }
        }
        func advance(_ seconds: TimeInterval) {
            lock.withLock { value += seconds }
        }
    }

    private func makeKeeper(
        client: FakeClient,
        store: InMemoryMobileSessionStore = InMemoryMobileSessionStore(),
        clock: Clock = Clock()
    ) -> MobileSessionKeeper {
        MobileSessionKeeper(
            client: client,
            store: store,
            installationID: "instalacja-1",
            deviceName: "iPhone",
            refreshLeeway: 120,
            now: { clock.now() }
        )
    }

    // MARK: Logowanie

    func testSignInStoresSessionAndIsUsableWithoutRefresh() async throws {
        let client = FakeClient()
        let store = InMemoryMobileSessionStore()
        let keeper = makeKeeper(client: client, store: store)

        let session = try await keeper.signIn(email: "pawel@majkuny.pl", password: "haslo", totp: "123456")
        XCTAssertEqual(session.accessToken, "access-1")
        XCTAssertEqual(try store.load()?.accessToken, "access-1")
        let user = await keeper.currentUser
        XCTAssertEqual(user?.initials, "PR")
        XCTAssertEqual(client.loginCalls.count, 1)
        XCTAssertEqual(client.loginCalls.first?.totp, "123456")
        XCTAssertEqual(client.loginCalls.first?.installationID, "instalacja-1")

        let token = try await keeper.accessToken()
        XCTAssertEqual(token, "access-1")
        XCTAssertTrue(client.refreshCalls.isEmpty)
    }

    func testFailedSignInKeepsDeviceClean() async throws {
        let client = FakeClient()
        client.loginResult = .failure(.unauthorized("Nieprawidłowe dane logowania."))
        let store = InMemoryMobileSessionStore()
        let keeper = makeKeeper(client: client, store: store)

        do {
            _ = try await keeper.signIn(email: "a@b.pl", password: "zle", totp: "")
            XCTFail("Oczekiwano błędu")
        } catch let error as MobileAuthError {
            XCTAssertEqual(error, .unauthorized("Nieprawidłowe dane logowania."))
        }
        XCTAssertNil(try store.load())
        let signedIn = await keeper.hasStoredSession
        XCTAssertFalse(signedIn)
    }

    // MARK: Odświeżanie

    func testExpiringTokenIsRefreshedOnceForConcurrentCallers() async throws {
        let client = FakeClient()
        client.refreshDelay = 50_000_000 // 50 ms
        client.refreshResults = [
            .success(FakeClient.session(accessToken: "access-2", refreshToken: "refresh-2", expiresIn: 1800)),
            .success(FakeClient.session(accessToken: "access-3", refreshToken: "refresh-3", expiresIn: 1800)),
        ]
        let clock = Clock()
        let store = InMemoryMobileSessionStore(session: FakeClient.session(expiresIn: 10))
        let keeper = makeKeeper(client: client, store: store, clock: clock)

        // Trzy równoległe żądania w chwili, gdy token już wygasa.
        async let first = keeper.accessToken()
        async let second = keeper.accessToken()
        async let third = keeper.accessToken()
        let tokens = try await [first, second, third]

        XCTAssertEqual(Set(tokens), ["access-2"], "Wszyscy dostają token z jednego odnowienia")
        XCTAssertEqual(client.refreshCalls.count, 1, "Rotacja nie może się nakładać")
        XCTAssertEqual(try store.load()?.refreshToken, "refresh-2")
    }

    func testStoredSessionIsRestoredOnNextLaunch() async throws {
        let client = FakeClient()
        let store = InMemoryMobileSessionStore(session: FakeClient.session(accessToken: "z-kopii"))
        let keeper = makeKeeper(client: client, store: store)

        let restored = await keeper.hasStoredSession
        XCTAssertTrue(restored)
        let restoredToken = try await keeper.accessToken()
        XCTAssertEqual(restoredToken, "z-kopii")
        XCTAssertTrue(client.refreshCalls.isEmpty)
    }

    func testRejectedRefreshClearsSessionSoAppReturnsToLogin() async throws {
        let client = FakeClient()
        client.refreshResults = [.failure(.unauthorized("Sesja wygasła."))]
        let store = InMemoryMobileSessionStore(session: FakeClient.session(expiresIn: 1))
        let keeper = makeKeeper(client: client, store: store)

        do {
            _ = try await keeper.accessToken()
            XCTFail("Oczekiwano błędu")
        } catch let error as MobileAuthError {
            XCTAssertEqual(error, .unauthorized("Sesja wygasła."))
        }
        XCTAssertNil(try store.load())
        let stillSignedIn = await keeper.hasStoredSession
        XCTAssertFalse(stillSignedIn)
    }

    /// Awaria sieci nie może wylogować: token odświeżania nadal jest ważny.
    func testTransportFailureDuringRefreshKeepsSession() async throws {
        let client = FakeClient()
        client.refreshResults = [.failure(.transport("brak sieci"))]
        let store = InMemoryMobileSessionStore(session: FakeClient.session(expiresIn: 1))
        let keeper = makeKeeper(client: client, store: store)

        do {
            _ = try await keeper.accessToken()
            XCTFail("Oczekiwano błędu")
        } catch {
            XCTAssertTrue(error is MobileAuthError)
        }
        XCTAssertNotNil(try store.load(), "Sesja zostaje — użytkownik nie jest wylogowany bez powodu")
    }

    func testAccessTokenWithoutSessionIsUnauthorized() async throws {
        let keeper = makeKeeper(client: FakeClient())
        do {
            _ = try await keeper.accessToken()
            XCTFail("Oczekiwano błędu")
        } catch let error as MobileAuthError {
            XCTAssertEqual(error, .unauthorized(nil))
        }
    }

    // MARK: Wylogowanie

    func testSignOutRevokesOnServerAndClearsDevice() async throws {
        let client = FakeClient()
        let store = InMemoryMobileSessionStore(session: FakeClient.session())
        let keeper = makeKeeper(client: client, store: store)

        await keeper.signOut()

        XCTAssertEqual(client.revokeCalls.count, 1)
        XCTAssertEqual(client.revokeCalls.first?.token, "access-1")
        XCTAssertEqual(client.revokeCalls.first?.reason, "logout")
        XCTAssertNil(try store.load())
    }

    func testSignOutClearsDeviceEvenWhenServerIsUnreachable() async throws {
        let client = FakeClient()
        client.revokeError = .transport("brak sieci")
        let store = InMemoryMobileSessionStore(session: FakeClient.session())
        let keeper = makeKeeper(client: client, store: store)

        await keeper.signOut()
        XCTAssertNil(try store.load(), "Bez sieci też trzeba się wylogować lokalnie")
    }

    func testAccountSwitchUsesDedicatedReason() async throws {
        let client = FakeClient()
        let store = InMemoryMobileSessionStore(session: FakeClient.session())
        let keeper = makeKeeper(client: client, store: store)

        await keeper.prepareForAccountSwitch()
        XCTAssertEqual(client.revokeCalls.first?.reason, "account_switch")
        XCTAssertNil(try store.load())
    }

    func testSignInAfterSignOutStartsFromCleanState() async throws {
        let client = FakeClient()
        let store = InMemoryMobileSessionStore(session: FakeClient.session())
        let keeper = makeKeeper(client: client, store: store)

        await keeper.signOut()
        client.loginResult = .success(FakeClient.session(accessToken: "access-nowy", refreshToken: "refresh-nowy"))
        _ = try await keeper.signIn(email: "ktos@inny.pl", password: "haslo", totp: "")

        XCTAssertEqual(try store.load()?.accessToken, "access-nowy")
        let after = await keeper.currentUser
        XCTAssertEqual(after?.id, "user-1")
    }
}
