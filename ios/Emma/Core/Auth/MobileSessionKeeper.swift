import Foundation

// MARK: - Trwałość sesji mobilnej
//
// Token dostępu i token odświeżania muszą przeżyć restart aplikacji, ale nie
// mogą leżeć w `UserDefaults` (czytelne dla każdego procesu i w kopii
// zapasowej). Protokół jest tutaj, a implementacja kluczyka — w warstwie
// aplikacji (`Features/Auth/KeychainMobileSessionStore.swift`), bo `Security`
// istnieje tylko na platformach Apple.

public protocol MobileSessionStoring: Sendable {
    func load() throws -> MobileAuthSession?
    func save(_ session: MobileAuthSession) throws
    func clear() throws
}

/// Implementacja w pamięci: podglądy Xcode i testy logiki.
public final class InMemoryMobileSessionStore: MobileSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var session: MobileAuthSession?

    public init(session: MobileAuthSession? = nil) {
        self.session = session
    }

    public func load() throws -> MobileAuthSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    public func save(_ session: MobileAuthSession) throws {
        lock.lock()
        defer { lock.unlock() }
        self.session = session
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        session = nil
    }
}

// MARK: - Prowadzenie sesji
//
// Jedno miejsce, które wie, kiedy token dostępu jest jeszcze ważny, a kiedy
// trzeba go odnowić. `AuthStore` nie zna HTTP, a widoki nie znają tokenów.
//
// Trzy zasady, które wynikają z realnego backendu:
//   • token dostępu żyje 30 minut, więc odświeżamy z wyprzedzeniem,
//   • rotacja unieważnia poprzedni token odświeżania, więc równoległe
//     odświeżenia muszą być sklejone w jedno (inaczej drugie żądanie
//     unieważniłoby pierwsze i wylogowało użytkownika),
//   • token jest nieprzezroczysty — aplikacja nigdy nie próbuje czytać z niego
//     danych, bo ich tam nie ma (świadoma różnica wobec JWT).

public actor MobileSessionKeeper {

    private let client: any MobileAuthServicing
    private let store: any MobileSessionStoring
    private let installationID: String
    private let deviceName: String
    private let refreshLeeway: TimeInterval
    private let now: @Sendable () -> Date

    private var session: MobileAuthSession?
    private var refreshTask: Task<MobileAuthSession, Error>?

    /// Czy na urządzeniu była zapamiętana sesja w chwili startu. `let` na aktorze
    /// jest dostępny bez `await` — `AuthStore` potrzebuje tej odpowiedzi
    /// synchronicznie, przy tworzeniu stanu początkowego.
    public nonisolated let restoredAtLaunch: Bool
    /// Użytkownik z odtworzonej sesji, jeśli była. `nonisolated`, bo powłoka musi
    /// umieć odczytać go synchronicznie przy starcie — bez tego po restarcie
    /// aplikacja nie wiedziałaby, kto jest zalogowany, dopóki nie odnowi tokenu.
    public nonisolated let restoredUser: MobileAuthUser?

    public init(
        client: any MobileAuthServicing,
        store: any MobileSessionStoring,
        installationID: String,
        deviceName: String,
        refreshLeeway: TimeInterval = 120,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.store = store
        self.installationID = installationID
        self.deviceName = deviceName
        self.refreshLeeway = refreshLeeway
        self.now = now
        let restored = try? store.load()
        self.session = restored
        self.restoredAtLaunch = restored != nil
        self.restoredUser = restored?.user
    }

    public var currentUser: MobileAuthUser? { session?.user }

    /// Sesja zapamiętana na urządzeniu. `nil` = trzeba się zalogować.
    public var hasStoredSession: Bool { session != nil }

    /// Logowanie. Sukces zapisuje sesję na urządzeniu; porażka nic nie zmienia.
    @discardableResult
    public func signIn(email: String, password: String, totp: String) async throws -> MobileAuthSession {
        let result = try await client.login(
            email: email,
            password: password,
            totp: totp,
            installationID: installationID,
            deviceName: deviceName
        )
        try? store.save(result)
        session = result
        refreshTask?.cancel()
        refreshTask = nil
        return result
    }

    /// Token dostępu gotowy do użycia: odnawia, gdy wygasł albo wygasa w ciągu
    /// `refreshLeeway`. Rzuca `MobileAuthError.unauthorized`, gdy odnowienie się
    /// nie uda — wtedy warstwa wyżej wraca na ekran logowania.
    public func accessToken() async throws -> String {
        guard let session else {
            throw MobileAuthError.unauthorized(nil)
        }
        if session.expiresAt.timeIntervalSince(now()) > refreshLeeway {
            return session.accessToken
        }
        return try await refresh().accessToken
    }

    /// Wymuszone odnowienie (np. po odpowiedzi 401 z innego zasobu).
    @discardableResult
    public func refresh() async throws -> MobileAuthSession {
        if let inFlight = refreshTask {
            return try await inFlight.value
        }
        guard let current = session else {
            throw MobileAuthError.unauthorized(nil)
        }
        let client = self.client
        let installationID = self.installationID
        let task = Task<MobileAuthSession, Error> {
            try await client.refreshSession(
                refreshToken: current.refreshToken,
                installationID: installationID
            )
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let refreshed = try await task.value
            try? store.save(refreshed)
            session = refreshed
            return refreshed
        } catch {
            // Token odświeżania też przestał działać (wylogowanie na innym
            // urządzeniu albo wygaśnięcie) — czyścimy sesję, żeby aplikacja nie
            // wyglądała na zalogowaną bez możliwości wykonania żądania.
            if case MobileAuthError.unauthorized = error {
                try? store.clear()
                session = nil
            }
            throw error
        }
    }

    /// Wylogowanie z powiadomieniem serwera. Nieudane powiadomienie nie blokuje
    /// usunięcia tokenów z urządzenia — użytkownik ma być wylogowany lokalnie
    /// nawet bez sieci (token i tak wygaśnie na serwerze).
    public func signOut(reason: String = "logout") async {
        refreshTask?.cancel()
        refreshTask = nil
        if let current = session {
            try? await client.revokeSession(
                accessToken: current.accessToken,
                installationID: installationID,
                reason: reason
            )
        }
        try? store.clear()
        session = nil
    }

    /// Zmiana konta na tym samym urządzeniu: unieważniamy poprzednią instalację
    /// po stronie serwera, zanim ktokolwiek się zaloguje ponownie (kontrakt,
    /// `reason: account_switch`).
    public func prepareForAccountSwitch() async {
        await signOut(reason: "account_switch")
    }
}
