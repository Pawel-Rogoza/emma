import SwiftUI
import UserNotifications

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
    /// Szybkie akcje z ikony aplikacji (`HomeScreenQuickActions`).
    @UIApplicationDelegateAdaptor(EmmaAppDelegate.self) private var appDelegate
    @StateObject private var dependencies: AppDependencies
    @StateObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase
    /// Delegat centrum powiadomień musi żyć tak długo jak aplikacja
    /// (`UNUserNotificationCenter` trzyma go słabo).
    private static let notificationRouter = EventNotificationRouter()
    /// Blokada po powrocie z tła żyje w osobnym oknie nad arkuszami
    /// (`LockOverlayWindow`), bo warstwa w `ZStack` leżała pod nimi.
    @MainActor private static let lockOverlay = LockOverlayWindow()

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
            AssistantStoreRegistry.shared.clearForSignOut()
            switch reason {
            case .loggedOut:
                await dependencies.voice.handleUserLoggedOut()
            case .accountSwitched:
                await dependencies.voice.handleAccountSwitched()
            }
            // Przypomnienia z nazwami klientów nie przeżywają końca sesji.
            await dependencies.reminders.removeAll()
        }
        // Po zalogowaniu powłoka ma używać prawdziwego użytkownika, a nie konta demo.
        authStore.onUserChanged = { [weak dependencies] remote in
            dependencies?.adoptRemoteUser(remote)
        }
        _auth = StateObject(wrappedValue: authStore)
        _dependencies = StateObject(wrappedValue: dependencies)
        // Dotknięcie przypomnienia o terminie otwiera jego szczegóły.
        Self.notificationRouter.dependencies = dependencies
        UNUserNotificationCenter.current().delegate = Self.notificationRouter
        EmmaFontRegistration.verifyRegisteredFonts()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch auth.state {
                case .signedOut:
                    LoginScreen()
                case .locked, .unlocked:
                    // Blokada zasłania powłokę, a nie ją niszczy: wcześniej każde
                    // wyjście do innej aplikacji kasowało otwarty formularz
                    // (np. pisaną notatkę) i pozycję list. Przed pierwszym
                    // odblokowaniem powłoki jeszcze nie ma — nic się nie wczytuje
                    // i blokada może być zwykłym widokiem. Gdy powłoka już żyje,
                    // blokadę pokazuje `LockOverlayWindow` — nad arkuszami.
                    ZStack {
                        if auth.hasUnlockedSession {
                            RootShell()
                                .environmentObject(dependencies)
                                .accessibilityHidden(auth.state == .locked)
                                .allowsHitTesting(auth.state == .unlocked)
                        }
                        if auth.state == .locked && !auth.hasUnlockedSession {
                            LockScreen()
                        }
                    }
                }
            }
            .onChange(of: auth.state) { _, _ in
                syncLockOverlay()
            }
            .environmentObject(auth)
            .tint(EmmaTheme.accent)
            .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { _, phase in
            // Przejście w tło wstrzymuje mikrofon i blokuje zapisy głosem,
            // ale nie usuwa przygotowanego szkicu (§5.6). Wychodząc w tło
            // zamykamy też dostęp — powrót wymaga Face ID.
            //
            // Tylko `.background`, nie `.inactive`: stan nieaktywny to także
            // ściągnięte Centrum powiadomień, Centrum sterowania czy systemowy
            // alert — rozmowa nie może się wtedy urywać. Prawdziwe wyjście
            // z aplikacji i tak przechodzi przez `.background`.
            switch phase {
            case .background:
                // Klawiatura nie może zostać nad ekranem blokady.
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                )
                auth.lock()
                // Od razu, nie w następnym przebiegu widoku: zrzut do
                // przełącznika aplikacji powstaje tuż po przejściu w tło.
                syncLockOverlay()
                Task { await dependencies.voice.handleApplicationBackgrounded() }
            case .active:
                // Powrót na pierwszy plan: pytamy backend o faktyczny stan sesji,
                // żeby przejęcie przez inne urządzenie nie uszło uwadze (§5.6).
                Task { await dependencies.voice.handleApplicationForegrounded() }
                // Powłoka przeżywa blokadę, więc ekrany nie wczytują się same od
                // nowa — prosimy je o odświeżenie (np. nowy lead ze strony).
                if auth.hasUnlockedSession {
                    dependencies.dataChanged()
                }
            default:
                break
            }
        }
    }

    /// Okno blokady widoczne dokładnie wtedy, gdy zablokowana jest żyjąca powłoka.
    private func syncLockOverlay() {
        if auth.state == .locked && auth.hasUnlockedSession {
            Self.lockOverlay.show(auth: auth)
        } else {
            Self.lockOverlay.hide()
        }
    }
}
