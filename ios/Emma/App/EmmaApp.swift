import SwiftUI

// MARK: - Wejście aplikacji
//
// Aplikacja nie zawiera żadnych kluczy dostawców. W trybie Demo nie wykonuje
// też żadnych wywołań sieciowych: dane pochodzą z jednego repozytorium demo,
// a głos z deterministycznych mocków (§6, §14).
//
// Przed powłoką stoją dwa ekrany dostępu: logowanie (raz, do wylogowania)
// i odblokowanie Face ID przy każdym powrocie do aplikacji.

@main
struct EmmaApp: App {
    @StateObject private var dependencies: AppDependencies
    @StateObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let configuration = AppConfiguration.resolve()
        // Kolejność jest istotna: `AuthStore` powstaje pierwszy, bo to on ma
        // token dostępu, którym warstwy API podpisują żądania. Powłoka nie
        // tworzy własnej sesji i nie zna implementacji logowania.
        let authStore = AuthStore(configuration: configuration)
        let dependencies = AppDependencies(
            configuration: configuration,
            fixtureName: AppConfiguration.fixtureName(),
            accessTokenProvider: { [weak authStore] in authStore?.accessToken },
            // FIX B/C: repozytoria pytają o ważny token (z odnowieniem) i mogą
            // raz wymusić odnowienie po 401, zamiast iść bez `Authorization`.
            sessionTokenProvider: { [weak authStore] in
                await authStore?.sessionAccessToken()
            },
            sessionTokenRefresher: { [weak authStore] in
                await authStore?.refreshSessionAccessToken()
            },
            // Użytkownik pochodzi z sesji mobilnej (świeżo zalogowanej albo
            // odtworzonej z kluczyka), a nie z danych demo.
            currentUserProvider: { [weak authStore] in
                guard let remote = authStore?.remoteUser else { return nil }
                return AppDependencies.mapRemoteUser(remote)
            }
        )
        // Rozmowa głosowa nie może przeżyć wylogowania ani zmiany konta: jedno
        // złącze łączy logowanie z koordynatorem, więc żaden ekran nie musi
        // o tym pamiętać.
        authStore.onSessionEnded = { [weak dependencies] reason in
            guard let dependencies else { return }
            switch reason {
            case .loggedOut:
                await dependencies.voice.handleUserLoggedOut()
            case .accountSwitched:
                await dependencies.voice.handleAccountSwitched()
            }
        }
        // Po zalogowaniu powłoka ma używać prawdziwego użytkownika, a nie konta demo.
        authStore.onUserChanged = { [weak dependencies] remote in
            dependencies?.adoptRemoteUser(remote)
        }
        _auth = StateObject(wrappedValue: authStore)
        _dependencies = StateObject(wrappedValue: dependencies)
        EmmaFontRegistration.verifyRegisteredFonts()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch auth.state {
                case .signedOut:
                    LoginScreen()
                case .locked:
                    LockScreen()
                case .unlocked:
                    RootShell()
                        .environmentObject(dependencies)
                }
            }
            .environmentObject(auth)
            .tint(EmmaTheme.accent)
            .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { _, phase in
            // Przejście w tło wstrzymuje mikrofon i blokuje zapisy głosem,
            // ale nie usuwa przygotowanego szkicu (§5.6). Wychodząc w tło
            // zamykamy też dostęp — powrót wymaga Face ID.
            if phase == .background {
                auth.lock()
            }
            if phase != .active {
                Task { await dependencies.voice.handleApplicationBackgrounded() }
            } else {
                // Powrót na pierwszy plan: pytamy backend o faktyczny stan sesji,
                // żeby przejęcie przez inne urządzenie nie uszło uwadze (§5.6).
                Task { await dependencies.voice.handleApplicationForegrounded() }
            }
        }
    }
}
