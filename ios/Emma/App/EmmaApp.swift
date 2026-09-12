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
    @StateObject private var auth = AuthStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let configuration = AppConfiguration.resolve()
        _dependencies = StateObject(
            wrappedValue: AppDependencies(
                configuration: configuration,
                fixtureName: AppConfiguration.fixtureName()
            )
        )
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
            }
        }
    }
}
