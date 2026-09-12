import XCTest
@testable import Emma

// MARK: - Dostęp do aplikacji (D-16)
//
// Testujemy maszynę stanów, nie wygląd: czy świeża instalacja pokazuje logowanie,
// czy zapamiętana sesja wymaga odblokowania, czy błędne dane nie wpuszczają dalej
// i co się dzieje, gdy urządzenie nie ma skonfigurowanego Face ID.
//
// Plik leży w `EmmaTests/App`, a nie w `EmmaTests/Logic`, bo `AuthStore` należy do
// warstwy SwiftUI i nie wchodzi do pakietu `swift test` (patrz `Package.swift`).

@MainActor
final class AuthStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "emma.auth.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Klucz zapamiętanej sesji z `AuthStore.signedInKey`.
    private let signedInKey = "emma.auth.signedIn"

    private func makeStore(
        signedIn: Bool = false,
        result: Bool = true,
        availability: BiometricAvailability = .available(.faceID)
    ) -> AuthStore {
        if signedIn { defaults.set(true, forKey: signedInKey) }
        return AuthStore(
            authenticator: PreviewBiometricAuthenticator(result: result, availabilityResult: availability),
            defaults: defaults
        )
    }

    // MARK: Stan początkowy

    func testFreshInstallStartsAtLoginScreen() {
        XCTAssertEqual(makeStore().state, .signedOut)
    }

    func testRememberedSessionStartsLocked() {
        XCTAssertEqual(makeStore(signedIn: true).state, .locked)
    }

    // MARK: Logowanie

    func testSignInRejectsMalformedEmail() {
        let store = makeStore()
        XCTAssertFalse(store.signIn(email: "kancelaria", password: "emma"))
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertFalse(defaults.bool(forKey: signedInKey))
        XCTAssertNotNil(store.notice)
    }

    func testSignInRejectsShortPassword() {
        let store = makeStore()
        XCTAssertFalse(store.signIn(email: "kancelaria@emma.pl", password: "emm"))
        XCTAssertEqual(store.state, .signedOut)
    }

    func testSignInUnlocksAndRemembersSession() {
        let store = makeStore()
        XCTAssertTrue(store.signIn(email: "  kancelaria@emma.pl ", password: "emma"))
        XCTAssertEqual(store.state, .unlocked)
        XCTAssertNil(store.notice)
        XCTAssertTrue(defaults.bool(forKey: signedInKey))
    }

    // MARK: Blokada, wylogowanie

    func testLockMovesUnlockedSessionToLocked() {
        let store = makeStore()
        store.signIn(email: "kancelaria@emma.pl", password: "emma")
        store.lock()
        XCTAssertEqual(store.state, .locked)
    }

    func testLockDoesNotTouchSignedOutState() {
        let store = makeStore()
        store.lock()
        XCTAssertEqual(store.state, .signedOut)
    }

    func testSignOutClearsRememberedSession() {
        let store = makeStore()
        store.signIn(email: "kancelaria@emma.pl", password: "emma")
        store.signOut()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertFalse(defaults.bool(forKey: signedInKey))
        XCTAssertNil(store.notice)
    }

    // MARK: Face ID

    func testUnlockSucceedsWithBiometrics() async {
        let store = makeStore(signedIn: true, result: true)
        await store.unlock()
        XCTAssertEqual(store.state, .unlocked)
    }

    func testUnlockFailureKeepsAppLockedAndExplains() async {
        let store = makeStore(signedIn: true, result: false)
        await store.unlock()
        XCTAssertEqual(store.state, .locked)
        XCTAssertNotNil(store.notice)
    }

    func testUnlockWithoutConfiguredBiometricsLetsDemoIn() async {
        let store = makeStore(signedIn: true, availability: .unavailable("Face ID nie jest skonfigurowane."))
        XCTAssertFalse(store.canUseBiometrics)
        await store.unlock()
        XCTAssertEqual(store.state, .unlocked)
        XCTAssertEqual(store.availabilityNotice, "Face ID nie jest skonfigurowane.")
    }

    func testUnlockButtonTitleFollowsDeviceCapabilities() {
        XCTAssertEqual(makeStore(availability: .available(.faceID)).unlockButtonTitle, "Odblokuj Face ID")
        XCTAssertEqual(makeStore(availability: .available(.touchID)).unlockButtonTitle, "Odblokuj Touch ID")
        XCTAssertEqual(makeStore(availability: .available(.passcode)).unlockButtonTitle, "Odblokuj hasłem")
        XCTAssertEqual(makeStore(availability: .unavailable("brak")).unlockButtonTitle, "Odblokuj")
    }
}
