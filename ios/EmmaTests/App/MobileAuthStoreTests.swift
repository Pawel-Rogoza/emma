import XCTest
@testable import Emma

// MARK: - Logowanie do backendu w warstwie aplikacji (M1)
//
// `MobileSessionKeeperTests` (EmmaTests/Logic) sprawdzają samą sesję. Tutaj
// sprawdzamy to, co widzi użytkownik: który ekran się pokazuje, co mówi
// komunikat i czy w trybie Demo naprawdę nic nie wychodzi do sieci.
//
// Plik leży w `EmmaTests/App`, bo `AuthStore` należy do warstwy SwiftUI.

@MainActor
final class MobileAuthStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName = ""
    private let signedInKey = "emma.auth.signedIn"
    private let staging = AppConfiguration(
        environment: .staging,
        apiBaseURL: URL(string: "http://127.0.0.1:4399")!,
        defaultLocale: "pl-PL"
    )
    private let demo = AppConfiguration(environment: .demo, apiBaseURL: nil, defaultLocale: "pl-PL")

    override func setUp() {
        super.setUp()
        suiteName = "emma.mobile.auth.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: Pomocnicze

    private final class FakeClient: MobileAuthServicing, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var loginCount = 0
        private(set) var revokeReasons: [String] = []
        var result: Result<MobileAuthSession, MobileAuthError> = .success(FakeClient.session())

        func login(
            email: String,
            password: String,
            totp: String,
            installationID: String,
            deviceName: String
        ) async throws -> MobileAuthSession {
            lock.withLock { loginCount += 1 }
            return try result.get()
        }

        func refreshSession(refreshToken: String, installationID: String) async throws -> MobileAuthSession {
            try result.get()
        }

        func revokeSession(accessToken: String, installationID: String, reason: String) async throws {
            lock.withLock { revokeReasons.append(reason) }
        }

        static func session() -> MobileAuthSession {
            MobileAuthSession(
                accessToken: "access-testowy",
                refreshToken: "refresh-testowy",
                expiresAt: Date().addingTimeInterval(1800),
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

    private func makeRemoteStore(
        client: FakeClient = FakeClient(),
        stored: MobileAuthSession? = nil,
        rememberSession: Bool = false
    ) -> (AuthStore, FakeClient, InMemoryMobileSessionStore) {
        if rememberSession { defaults.set(true, forKey: signedInKey) }
        let store = InMemoryMobileSessionStore(session: stored)
        let keeper = MobileSessionKeeper(
            client: client,
            store: store,
            installationID: "instalacja-testowa",
            deviceName: "iPhone testowy"
        )
        let auth = AuthStore(
            configuration: staging,
            authenticator: PreviewBiometricAuthenticator(),
            defaults: defaults,
            session: keeper
        )
        return (auth, client, store)
    }

    // MARK: Stan początkowy

    func testStagingWithoutStoredSessionStartsAtLogin() {
        let (auth, _, _) = makeRemoteStore()
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertTrue(auth.usesRemoteAuth)
        XCTAssertNil(auth.accessToken)
    }

    /// „Zalogowany” w `UserDefaults` bez tokenu to nie sesja — to wspomnienie
    /// po niej. W trybie backendu musi prowadzić na logowanie, nie na Face ID.
    func testStagingWithRememberedFlagButNoTokenStartsAtLogin() {
        let (auth, _, _) = makeRemoteStore(rememberSession: true)
        XCTAssertEqual(auth.state, .signedOut)
    }

    func testStagingWithStoredSessionStartsLocked() {
        let (auth, _, _) = makeRemoteStore(stored: FakeClient.session(), rememberSession: true)
        XCTAssertEqual(auth.state, .locked)
    }

    /// Po restarcie token musi trafić do `AuthStore` z kluczyka, zanim powłoka
    /// zdąży wczytać dane. Inaczej ekrany lecą bez `Authorization` i dostają 401.
    func testRestoredSessionProvidesAccessTokenAtLaunch() async throws {
        let (auth, _, _) = makeRemoteStore(stored: FakeClient.session(), rememberSession: true)
        for _ in 0..<100 where auth.accessToken == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(auth.accessToken, "access-testowy")
    }

    // MARK: Odświeżenie i koniec sesji (FIX B/C)

    /// Odnowienie odrzucone przez backend (401) kończy sesję: wracamy na logowanie.
    func testUnauthorizedRefreshEndsSessionAndClearsKeychain() async {
        let client = FakeClient()
        let (auth, _, store) = makeRemoteStore(
            client: client,
            stored: FakeClient.session(),
            rememberSession: true
        )
        client.result = .failure(.unauthorized("Token odświeżania wygasł."))

        let token = await auth.refreshSessionAccessToken()

        XCTAssertNil(token)
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertEqual(auth.notice, "Sesja wygasła. Zaloguj się ponownie.")
        XCTAssertNil(try? store.load())
    }

    /// Brak sieci przy odnowieniu **nie** może wylogować: sesja i kluczyk zostają.
    func testTransportFailureDuringRefreshKeepsSession() async {
        let client = FakeClient()
        let (auth, _, store) = makeRemoteStore(
            client: client,
            stored: FakeClient.session(),
            rememberSession: true
        )
        client.result = .failure(.transport("brak sieci"))

        let token = await auth.refreshSessionAccessToken()

        XCTAssertNil(token)
        XCTAssertEqual(auth.state, .locked)
        XCTAssertNotNil(try? store.load())
    }

    // MARK: Logowanie

    func testSuccessfulRemoteSignInUnlocksAndKeepsToken() async {
        let (auth, client, store) = makeRemoteStore()
        let ok = await auth.signIn(email: "pawel@majkuny.pl", password: "haslo", totp: "123456")

        XCTAssertTrue(ok)
        XCTAssertEqual(auth.state, .unlocked)
        XCTAssertEqual(auth.accessToken, "access-testowy")
        XCTAssertEqual(auth.remoteUser?.initials, "PR")
        XCTAssertNil(auth.notice)
        XCTAssertEqual(client.loginCount, 1)
        XCTAssertEqual(try store.load()?.refreshToken, "refresh-testowy")
        XCTAssertTrue(defaults.bool(forKey: signedInKey))
    }

    func testRejectedRemoteSignInShowsServerMessageAndStaysSignedOut() async {
        let client = FakeClient()
        client.result = .failure(.unauthorized("Nieprawidłowe dane logowania."))
        let (auth, _, store) = makeRemoteStore(client: client)

        let ok = await auth.signIn(email: "pawel@majkuny.pl", password: "zle", totp: "")

        XCTAssertFalse(ok)
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertNil(auth.accessToken)
        XCTAssertEqual(auth.notice, "Nieprawidłowe dane logowania.")
        XCTAssertNil(try store.load())
    }

    func testRemoteSignInRejectsMalformedEmailWithoutCallingServer() async {
        let (auth, client, _) = makeRemoteStore()
        let ok = await auth.signIn(email: "kancelaria", password: "haslo", totp: "")
        XCTAssertFalse(ok)
        XCTAssertEqual(client.loginCount, 0, "Walidacja lokalna nie może wysyłać żądania")
        XCTAssertNotNil(auth.notice)
    }

    func testRateLimitedSignInExplainsAndIsNotSilent() async {
        let client = FakeClient()
        client.result = .failure(.rateLimited(retryAfterSeconds: 600, message: nil))
        let (auth, _, _) = makeRemoteStore(client: client)

        let ok = await auth.signIn(email: "pawel@majkuny.pl", password: "haslo", totp: "")
        XCTAssertFalse(ok)
        XCTAssertEqual(auth.notice, "Zbyt wiele prób logowania. Odczekaj chwilę i spróbuj ponownie.")
    }

    // MARK: Demo pozostaje demo

    func testDemoSignInIsUnchangedAndSendsNothing() async {
        let auth = AuthStore(
            configuration: demo,
            authenticator: PreviewBiometricAuthenticator(),
            defaults: defaults,
            session: nil
        )
        XCTAssertFalse(auth.usesRemoteAuth)
        XCTAssertTrue(auth.signIn(email: "cokolwiek@emma.pl", password: "emma"))
        XCTAssertEqual(auth.state, .unlocked)
        XCTAssertNil(auth.accessToken, "Demo nie ma prawa mieć tokenu")
    }

    func testDemoPathIsClosedWhenBackendIsConfigured() {
        let (auth, client, _) = makeRemoteStore()
        XCTAssertFalse(auth.signIn(email: "cokolwiek@emma.pl", password: "emma"))
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertEqual(client.loginCount, 0)
    }

    func testUnlockWithoutBiometricsStillLetsDemoIn() async {
        var authenticator = PreviewBiometricAuthenticator()
        authenticator.availabilityResult = .unavailable("Face ID nie jest skonfigurowane.")
        let defaults = self.defaults!
        defaults.set(true, forKey: signedInKey)
        let auth = AuthStore(
            configuration: demo,
            authenticator: authenticator,
            defaults: defaults,
            session: nil
        )
        await auth.unlock()
        XCTAssertEqual(auth.state, .unlocked)
    }

    /// W trybie backendu brak Face ID nie może wpuszczać do prawdziwych danych.
    func testUnlockWithoutBiometricsDoesNotBypassBackendSession() async {
        // `result: false` = biometria odrzucona; brak skonfigurowanego Face ID
        // to dodatkowa informacja, a nie powód do wpuszczenia.
        let authenticator = PreviewBiometricAuthenticator(
            result: false,
            availabilityResult: .unavailable("Face ID nie jest skonfigurowane.")
        )
        let defaults = self.defaults!
        defaults.set(true, forKey: signedInKey)
        let keeper = MobileSessionKeeper(
            client: FakeClient(),
            store: InMemoryMobileSessionStore(session: FakeClient.session()),
            installationID: "instalacja-testowa",
            deviceName: "iPhone testowy"
        )
        let auth = AuthStore(
            configuration: staging,
            authenticator: authenticator,
            defaults: defaults,
            session: keeper
        )
        await auth.unlock()
        XCTAssertEqual(auth.state, .locked)
        XCTAssertNotNil(auth.notice)
    }

    // MARK: Wylogowanie

    func testSignOutClearsTokenImmediately() async {
        let (auth, _, store) = makeRemoteStore()
        _ = await auth.signIn(email: "pawel@majkuny.pl", password: "haslo", totp: "")
        auth.signOut()

        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertNil(auth.accessToken)
        XCTAssertFalse(defaults.bool(forKey: signedInKey))
    }

    func testSignOutAndRevokeTellsServerWhy() async {
        let (auth, client, store) = makeRemoteStore()
        _ = await auth.signIn(email: "pawel@majkuny.pl", password: "haslo", totp: "")

        await auth.signOutAndRevoke()

        XCTAssertEqual(client.revokeReasons, ["logout"])
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertNil(try store.load())
    }

    func testAccountSwitchRevokesPreviousSessionBeforeLogin() async {
        let (auth, client, store) = makeRemoteStore(stored: FakeClient.session(), rememberSession: true)
        await auth.prepareForAccountSwitch()

        XCTAssertEqual(client.revokeReasons, ["account_switch"])
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertNil(try store.load())
    }

    /// Rozmowa głosowa nie może przeżyć wylogowania: koordynator dowiaduje się
    /// o końcu sesji z jednego złącza, nie z obserwowania ekranu.
    func testSignOutNotifiesVoiceLayer() async {
        let (auth, _, _) = makeRemoteStore()
        _ = await auth.signIn(email: "pawel@majkuny.pl", password: "haslo", totp: "")

        var reasons: [AuthStore.SessionEndReason] = []
        let notified = expectation(description: "zakończenie sesji")
        auth.onSessionEnded = { reason in
            reasons.append(reason)
            notified.fulfill()
        }

        auth.signOut()
        await fulfillment(of: [notified], timeout: 5)
        XCTAssertEqual(reasons, [.loggedOut])
    }

    func testAccountSwitchNotifiesVoiceLayerBeforeLogin() async {
        let (auth, _, _) = makeRemoteStore(stored: FakeClient.session(), rememberSession: true)

        var reasons: [AuthStore.SessionEndReason] = []
        auth.onSessionEnded = { reasons.append($0) }

        await auth.prepareForAccountSwitch()
        XCTAssertEqual(reasons, [.accountSwitched])
    }
}

// MARK: - Token w zależnościach aplikacji

@MainActor
final class AppDependenciesTokenTests: XCTestCase {

    /// Token dostępu musi pochodzić z `AuthStore`, a nie z drugiego źródła.
    func testAccessTokenComesFromProvider() {
        var token: String? = "token-z-logowania"
        let dependencies = AppDependencies(
            configuration: AppConfiguration(environment: .staging, apiBaseURL: URL(string: "https://example.invalid")!, defaultLocale: "pl-PL"),
            accessTokenProvider: { token }
        )
        XCTAssertEqual(dependencies.accessToken, "token-z-logowania")
        token = nil
        XCTAssertNil(dependencies.accessToken)
    }

    func testDemoHasNoAccessToken() {
        XCTAssertNil(AppDependencies.demo().accessToken)
    }

    // MARK: Dzień z fixture tylko w Demo (FIX D)

    /// Staging/Production muszą pytać backend o **prawdziwy** dzień, a nie o stałą
    /// 2026-09-11 z fixture. Inaczej `from`/`through` i `due_on_or_before` mijają
    /// się z dniem, który widzi użytkownik.
    func testProductionUsesRealClockAndNotFixtureDay() {
        let production = AppConfiguration(
            environment: .production,
            apiBaseURL: URL(string: "https://majkuny.pl")!,
            defaultLocale: "pl"
        )
        let dependencies = AppDependencies(configuration: production, fixtureName: "today-default")

        XCTAssertTrue(dependencies.clock is SystemClock)
        XCTAssertEqual(dependencies.today, SystemClock().today())
        XCTAssertNotEqual(dependencies.today, LocalDate(year: 2026, month: 9, day: 11))
    }

    /// Demo nadal ma deterministyczny dzień referencyjny z fixture.
    func testDemoKeepsFixtureReferenceDay() {
        let demo = AppConfiguration(environment: .demo, apiBaseURL: nil, defaultLocale: "pl")
        let dependencies = AppDependencies(configuration: demo, fixtureName: "today-default")

        XCTAssertTrue(dependencies.clock is DemoClock)
        XCTAssertEqual(dependencies.today, LocalDate(year: 2026, month: 9, day: 11))
    }
}
