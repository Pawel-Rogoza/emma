import SwiftUI

// MARK: - Wejście aplikacji
//
// Aplikacja nie zawiera żadnych kluczy dostawców. W trybie Demo nie wykonuje
// też żadnych wywołań sieciowych: dane pochodzą z jednego repozytorium demo,
// a głos z deterministycznych mocków (§6, §14).

@main
struct EmmaApp: App {
    @StateObject private var dependencies: AppDependencies
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
            RootShell()
                .environmentObject(dependencies)
                .tint(EmmaTheme.accent)
                .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { _, phase in
            // Przejście w tło wstrzymuje mikrofon i blokuje zapisy głosem,
            // ale nie usuwa przygotowanego szkicu (§5.6).
            if phase != .active {
                Task { await dependencies.voice.handleApplicationBackgrounded() }
            }
        }
    }
}
