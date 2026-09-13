import SwiftUI

// MARK: - Profil i zespół
//
// Port `profile()` oraz `resetPrompt()`/`resetDemo()`. Arkusz jest miejscem,
// w którym uczciwie mówimy, co w tej wersji jest symulowane.

struct ProfileSheet: View {

    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        SheetScaffold(title: "Profil kancelarii", onClose: { dependencies.dismissSheet() }) {
            Text("Kancelaria Rogoża")
                .font(EmmaTypography.heading(20))
                .foregroundStyle(EmmaTheme.ink)
                .padding(.bottom, 12)

            Text("Jedno wspólne konto zespołu: te same sprawy, zadania i rozmowy. AI i integracja WhatsApp są symulowane. Głos działa w trybie demonstracyjnym. Data przykładowego dnia: 11 września 2026.")
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.mutedSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            SecondaryButton("Przywróć dane przykładowe") {
                dependencies.present(.resetDemo)
            }

            AccountActionsSection()
                .padding(.top, 20)

            if dependencies.configuration.usesMockServices {
                Text("Tryb Demo: \(dependencies.configuration.environment.displayName). Aplikacja nie wykonuje żadnych połączeń sieciowych i nie zawiera kluczy dostawców.")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        }
    }
}

/// Potwierdzenie przywrócenia danych przykładowych.
struct ResetDemoSheet: View {

    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        SheetScaffold(title: "Przywrócić dane przykładowe?", onClose: { dependencies.dismissSheet() }) {
            Text("Usuniesz zmiany, wiadomości, notatki, sprawy i zadania dodane w tej sesji prototypu.")
                .font(EmmaTypography.ui(13))
                .foregroundStyle(EmmaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            HStack(spacing: 10) {
                SecondaryButton("Wróć") {
                    dependencies.present(.profile)
                }
                PrimaryButton("Przywróć dane") {
                    Task { await dependencies.resetDemoData() }
                }
            }
        }
    }
}

#Preview("Profil") {
    ProfileSheet()
        .environmentObject(AppDependencies.demo())
        .environmentObject(
            AuthStore(
                authenticator: PreviewBiometricAuthenticator(),
                defaults: UserDefaults(suiteName: "preview.profile")!
            )
        )
}
