import Combine
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Sesja użytkownika
//
// Aplikacja ma jedno wspólne konto kancelarii. Stan trzymamy w trzech krokach,
// bo każdy z nich to inny ekran:
//
//   signedOut → ekran logowania (raz, dopóki użytkownik się nie wyloguje),
//   locked    → ekran odblokowania (Face ID / hasło urządzenia),
//   unlocked  → aplikacja.
//
// Ścieżki są dwie i celowo rozdzielone:
//
//   • **Demo** (`AppConfiguration.apiBaseURL == nil`) — logowanie sprawdza tylko
//     kształt danych i mówi o tym wprost. Żadne żądanie nie wychodzi z telefonu.
//   • **Backend** (Staging/Production) — `MobileSessionKeeper` loguje się do
//     `/api/mobile/v1/auth/*`, trzyma tokeny w kluczyku i odnawia je przed
//     wygaśnięciem. Token dostępu nie jest czytany przez interfejs.
//
// „Zalogowany” zapisujemy w `UserDefaults`, ale w trybie backendu dodatkowo
// wymagamy realnej sesji — brak tokenu oznacza ekran logowania, nie „prawie
// zalogowany” stan, który wygląda jak awaria sieci.

@MainActor
final class AuthStore: ObservableObject {

    enum State: Equatable {
        case signedOut
        case locked
        case unlocked
    }

    @Published private(set) var state: State {
        didSet { if state == .unlocked { hasUnlockedSession = true } }
    }
    /// Czy w tym uruchomieniu aplikacja była już odblokowana. Powłoka powstaje
    /// dopiero po pierwszym odblokowaniu, a potem **żyje pod blokadą** — powrót
    /// z innej aplikacji nie gubi wpisywanej notatki ani otwartego formularza.
    @Published private(set) var hasUnlockedSession = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var notice: String?

    /// Nazwa użytkownika z backendu (tryb zdalny). W Demo zostaje `nil`.
    @Published private(set) var remoteUser: MobileAuthUser?
    /// Bieżący token dostępu dla warstw, które muszą wołać API (głos, dane).
    ///
    /// To wartość z ostatniego udanego logowania/odnowienia. Odświeżaniem
    /// zajmuje się `MobileSessionKeeper`; to pole nie jest cache’em z prawem
    /// ważności, a jedynie dostępem do ostatnio znanego tokenu.
    @Published private(set) var accessToken: String?

    private let configuration: AppConfiguration
    private let authenticator: BiometricAuthenticating
    private let defaults: UserDefaults
    /// Sesja mobilna istnieje tylko wtedy, gdy skonfigurowano backend.
    private let session: MobileSessionKeeper?
    private static let signedInKey = "emma.auth.signedIn"
    /// Wylogowanie biegnące w tle (zamknięcie rozmowy, unieważnienie na
    /// serwerze). Kolejne logowanie czeka na jego koniec — inaczej spóźnione
    /// `signOut()` aktora sesji skasowałoby świeżo zalogowaną sesję.
    private var pendingSignOut: Task<Void, Never>?

    /// Powód zakończenia sesji. Rozdzielamy wylogowanie od zmiany konta, bo
    /// koordynator głosu kończy rozmowę inaczej w każdej z tych sytuacji
    /// (`handleUserLoggedOut` vs `handleAccountSwitched`) — patrz `EmmaApp`.
    enum SessionEndReason: Equatable {
        case loggedOut
        case accountSwitched
    }

    /// Wywoływane po zakończeniu sesji. Ekrany nie znają koordynatora głosu,
    /// a koordynator nie zna logowania — łączy ich to jedno złącze.
    @MainActor var onSessionEnded: ((SessionEndReason) async -> Void)?

    /// Wywoływane, gdy zmienia się tożsamość użytkownika: po udanym logowaniu
    /// z prawdziwego backendu (`user`) albo po wylogowaniu (`nil`). Powłoka
    /// używa tego, żeby nie pokazywać konta demo w trybie produkcyjnym.
    @MainActor var onUserChanged: (@MainActor (MobileAuthUser?) -> Void)?

    init(
        configuration: AppConfiguration = .current,
        authenticator: BiometricAuthenticating = LocalAuthenticationAuthenticator(),
        defaults: UserDefaults = .standard,
        session: MobileSessionKeeper? = nil,
        deviceName: String = AuthStore.defaultDeviceName()
    ) {
        self.configuration = configuration
        self.authenticator = authenticator
        self.defaults = defaults
        self.session = session ?? AuthStore.makeSession(configuration: configuration, defaults: defaults, deviceName: deviceName)
        self.accessToken = nil
        // Odtworzona sesja zna użytkownika od razu; świeże logowanie ustawi go później.
        self.remoteUser = self.session?.restoredUser

        // Testy interfejsu i zrzuty ekranu startują z `--skip-auth`: dzięki temu
        // nie zależą od biometrii symulatora ani od zapamiętanej sesji. To jedyne
        // miejsce, w którym dostęp da się pominąć — zwykły start zawsze przechodzi
        // przez logowanie i Face ID. Obejście działa wyłącznie bez backendu (Demo):
        // z prawdziwymi danymi kancelarii nie ma ścieżki z pominięciem logowania.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--skip-auth"), self.session == nil {
            self.state = .unlocked
        } else if arguments.contains("--reset-auth") {
            // Wymusza czysty start na ekranie logowania (test scenariusza logowania).
            defaults.set(false, forKey: Self.signedInKey)
            self.state = .signedOut
        } else {
            self.state = AuthStore.initialState(
                rememberSession: defaults.bool(forKey: Self.signedInKey),
                hasRemoteSession: self.session?.restoredAtLaunch ?? false,
                usesRemoteAuth: self.session != nil
            )
        }

        hasUnlockedSession = state == .unlocked

        // Odtworzona sesja nie ma jeszcze tokenu w pamięci: pobieramy go z kluczyka
        // (i odnawiamy, gdy jest blisko wygaśnięcia). Bez tego po restarcie aplikacji
        // każde żądanie głosu i danych szłoby bez nagłówka Authorization, a użytkownik
        // zobaczyłby 401 mimo ważnej sesji.
        if let session, session.restoredAtLaunch {
            Task { [weak self] in
                // Świeży albo odnowiony token; porażka odnowienia 401 kończy
                // sesję, a nie zostawia aplikacji bez nagłówka Authorization.
                _ = await self?.sessionAccessToken()
            }
        }
    }

    // MARK: Tryb pracy

    /// `true`, gdy logowanie idzie do prawdziwego backendu (Staging/Production).
    var usesRemoteAuth: Bool { session != nil }

    /// Nazwa trybu do interfejsu — ekran logowania ma mówić prawdę o tym,
    /// dokąd trafiają dane.
    var modeDescription: String {
        usesRemoteAuth ? "Dane logowania trafiają do serwera kancelarii." : "Wersja demonstracyjna: dane konta nie są nigdzie wysyłane."
    }

    // MARK: Logowanie

    /// Logowanie: do backendu, gdy go skonfigurowano; inaczej demonstracyjne.
    @discardableResult
    func signIn(email: String, password: String, totp: String) async -> Bool {
        guard let session else {
            return signIn(email: email, password: password)
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), trimmed.count >= 5 else {
            notice = "Podaj adres e-mail, np. imie@kancelaria.pl."
            return false
        }
        guard !password.isEmpty else {
            notice = "Podaj hasło do konta kancelarii."
            return false
        }
        guard !isAuthenticating else { return false }

        isAuthenticating = true
        defer { isAuthenticating = false }
        if let pending = pendingSignOut {
            await pending.value
            pendingSignOut = nil
        }
        do {
            let result = try await session.signIn(
                email: trimmed,
                password: password,
                totp: totp.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            accessToken = result.accessToken
            remoteUser = result.user
            notice = nil
            defaults.set(true, forKey: Self.signedInKey)
            state = .unlocked
            onUserChanged?(result.user)
            return true
        } catch let error as MobileAuthError {
            notice = error.userMessage
            return false
        } catch {
            notice = "Nie udało się zalogować. Spróbuj ponownie."
            return false
        }
    }

    /// Logowanie demonstracyjne (bez backendu): sprawdzamy tylko kształt danych
    /// i mówimy o tym wprost w interfejsie. Zwraca `true`, gdy wpuszczamy.
    ///
    /// W trybie backendu ta ścieżka jest zamknięta: wpuszczenie tutaj znaczyłoby
    /// „zalogowany bez sesji”, czyli aplikację, która wygląda na działającą,
    /// a nie może wykonać żadnego żądania.
    @discardableResult
    func signIn(email: String, password: String) -> Bool {
        guard !usesRemoteAuth else {
            notice = "To środowisko wymaga zalogowania do serwera kancelarii."
            return false
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), trimmed.count >= 5 else {
            notice = "Podaj adres e-mail, np. imie@kancelaria.pl."
            return false
        }
        guard password.count >= 4 else {
            notice = "Hasło musi mieć co najmniej 4 znaki."
            return false
        }
        notice = nil
        defaults.set(true, forKey: Self.signedInKey)
        state = .unlocked
        return true
    }

    // MARK: Token dla warstw API (FIX B i C)

    /// Token dostępu dla repozytoriów danych i głosu.
    ///
    /// Czeka na aktora sesji, więc dostaje token **ważny** (odnawiany z wyprzedzeniem
    /// przez `MobileSessionKeeper`), a nie migawkę, która mogła wygasnąć.
    /// Gdy odnowienie zawiedzie na 401 (token odświeżania też wygasł), kończymy
    /// sesję. Brak sieci **nie** kasuje sesji — zwracamy ostatni znany token,
    /// a żądanie samo zgłosi błąd transportu.
    func sessionAccessToken() async -> String? {
        guard let session else { return accessToken }
        do {
            let token = try await session.accessToken()
            accessToken = token
            return token
        } catch MobileAuthError.unauthorized {
            expireRemoteSession()
            return nil
        } catch {
            return accessToken
        }
    }

    /// Wymuszone odnowienie po 401 z zasobu danych. Klient HTTP woła to **raz**
    /// i ponawia żądanie z nowym tokenem. `nil` znaczy „nie udało się odnowić”:
    /// po 401 z odnowienia sesja jest już zamknięta, przy błędzie sieci zostaje
    /// jak jest (żadnego wylogowania z powodu samej sieci).
    func refreshSessionAccessToken() async -> String? {
        guard let session else { return accessToken }
        do {
            let refreshed = try await session.refresh()
            accessToken = refreshed.accessToken
            remoteUser = refreshed.user
            return refreshed.accessToken
        } catch MobileAuthError.unauthorized {
            expireRemoteSession()
            return nil
        } catch {
            return nil
        }
    }

    /// Koniec sesji po stronie aplikacji wywołany odrzuceniem odnowienia (401).
    /// Tokeny w kluczyku i w aktorze sesji są już usunięte przez
    /// `MobileSessionKeeper.refresh()`; tu wracamy na ekran logowania i mówimy
    /// wprost, dlaczego.
    private func expireRemoteSession() {
        guard state != .signedOut else { return }
        defaults.set(false, forKey: Self.signedInKey)
        accessToken = nil
        remoteUser = nil
        notice = "Sesja wygasła. Zaloguj się ponownie."
        state = .signedOut
        hasUnlockedSession = false
        onUserChanged?(nil)
        let notify = onSessionEnded
        Task { await notify?(.loggedOut) }
    }

    /// Wylogowanie kasuje zapamiętaną sesję — następny start to znów logowanie.
    /// Unieważnienie na serwerze idzie w tle, żeby przycisk reagował natychmiast.
    func signOut() {
        defaults.set(false, forKey: Self.signedInKey)
        notice = nil
        accessToken = nil
        remoteUser = nil
        state = .signedOut
        hasUnlockedSession = false
        onUserChanged?(nil)
        let session = self.session
        let notify = onSessionEnded
        // Kolejność celowa: najpierw rozmowa (jej `DELETE` potrzebuje jeszcze
        // tokenu), potem unieważnienie sesji. Zadanie zapamiętujemy, żeby
        // ponowne logowanie poczekało na jego koniec.
        pendingSignOut = Task {
            await notify?(.loggedOut)
            await session?.signOut()
        }
    }

    /// Wylogowanie czekające na unieważnienie sesji na serwerze. Używane przy
    /// zmianie konta na tym samym urządzeniu — tam kolejność ma znaczenie.
    func signOutAndRevoke() async {
        await session?.signOut()
        defaults.set(false, forKey: Self.signedInKey)
        notice = nil
        accessToken = nil
        remoteUser = nil
        state = .signedOut
        hasUnlockedSession = false
        onUserChanged?(nil)
        await onSessionEnded?(.loggedOut)
    }

    /// Zmiana konta: najpierw unieważniamy poprzednią instalację, potem ekran
    /// logowania. Bez tego poprzednia sesja żyłaby na serwerze do wygaśnięcia.
    func prepareForAccountSwitch() async {
        await onSessionEnded?(.accountSwitched)
        await session?.prepareForAccountSwitch()
        defaults.set(false, forKey: Self.signedInKey)
        notice = nil
        accessToken = nil
        remoteUser = nil
        state = .signedOut
        hasUnlockedSession = false
        onUserChanged?(nil)
    }

    // MARK: Blokada i Face ID

    /// Blokujemy przy zejściu aplikacji w tło; powrót wymaga Face ID.
    func lock() {
        guard state == .unlocked else { return }
        state = .locked
    }

    var availability: BiometricAvailability { authenticator.availability() }

    var canUseBiometrics: Bool { availability.kind != nil }

    /// Etykieta przycisku zależna od tego, co urządzenie naprawdę potrafi —
    /// nie piszemy „Face ID” na telefonie, który ma tylko hasło.
    var unlockButtonTitle: String {
        switch availability {
        case .available(let kind):
            return kind == .passcode ? "Odblokuj hasłem" : "Odblokuj \(kind.displayName)"
        case .unavailable:
            return "Odblokuj"
        }
    }

    var availabilityNotice: String? {
        if case .unavailable(let message) = availability { return message }
        return nil
    }

    func unlock() async {
        guard state == .locked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let unlocked = await authenticator.authenticate(reason: "Odblokuj aplikację Emma")
        if unlocked {
            notice = nil
            state = .unlocked
            return
        }

        // Demo bez skonfigurowanej biometrii nie może zamknąć użytkownika na
        // stałe — wpuszczamy, ale mówimy wprost, że to obejście demonstracyjne.
        // W trybie backendu nie ma obejścia: dane kancelarii są prawdziwe.
        if case .unavailable = availability, !usesRemoteAuth {
            notice = nil
            state = .unlocked
            return
        }
        notice = usesRemoteAuth
            ? "Nie udało się odblokować. Użyj hasła urządzenia i spróbuj ponownie."
            : "Nie udało się odblokować. Spróbuj ponownie albo użyj hasła urządzenia."
    }

    // MARK: Tworzenie sesji zdalnej

    private static func makeSession(
        configuration: AppConfiguration,
        defaults: UserDefaults,
        deviceName: String
    ) -> MobileSessionKeeper? {
        guard let baseURL = configuration.apiBaseURL else { return nil }
        // Pęk kluczy przeżywa usunięcie aplikacji, `UserDefaults` — nie. Brak
        // identyfikatora instalacji oznacza więc świeżą instalację, a sesja
        // w kluczyku należy do poprzedniej: kasujemy ją, zamiast trzymać
        // tokeny cudzej instalacji na urządzeniu.
        let store = KeychainMobileSessionStore()
        if defaults.string(forKey: InstallationIdentity.defaultsKey) == nil {
            try? store.clear()
        }
        return MobileSessionKeeper(
            client: MobileAuthClient(baseURL: baseURL),
            store: store,
            installationID: InstallationIdentity.current(defaults: defaults),
            deviceName: deviceName
        )
    }

    private static func initialState(
        rememberSession: Bool,
        hasRemoteSession: Bool,
        usesRemoteAuth: Bool
    ) -> State {
        // Tryb backendu: bez tokenu nie ma czego odblokowywać — ekran logowania.
        if usesRemoteAuth && !hasRemoteSession { return .signedOut }
        return rememberSession ? .locked : .signedOut
    }

    /// Nazwa urządzenia wysyłana do backendu (lista zaufanych urządzeń).
    static func defaultDeviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iPhone"
        #endif
    }
}

// MARK: - Podstawiony uwierzytelniacz (podglądy i testy)

/// Uwierzytelniacz, który nic nie robi i zawsze odblokowuje — wyłącznie do
/// podglądów Xcode. Zwykła aplikacja zawsze używa systemowego Face ID.
struct PreviewBiometricAuthenticator: BiometricAuthenticating {
    var result: Bool = true
    var availabilityResult: BiometricAvailability = .available(.faceID)

    func availability() -> BiometricAvailability { availabilityResult }
    func authenticate(reason: String) async -> Bool { result }
}
