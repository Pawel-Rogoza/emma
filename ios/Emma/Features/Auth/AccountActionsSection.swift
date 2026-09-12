import SwiftUI

// MARK: - Sekcja dostępu w profilu
//
// Profil jest jedynym miejscem, w którym użytkownik zarządza dostępem:
// może zablokować aplikację od razu albo się wylogować. Trzymamy to osobno,
// żeby profil nie wiedział, jak działa logowanie i Face ID.

struct AccountActionsSection: View {

    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dostęp")
                .font(EmmaTypography.fieldLabel)
                .foregroundStyle(EmmaTheme.muted)

            Text("Aplikacja blokuje się, gdy wychodzi w tło. Wrócić możesz przez \(unlockName).")
                .font(EmmaTypography.ui(12))
                .foregroundStyle(EmmaTheme.mutedSoft)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryButton("Zablokuj teraz", systemImage: "lock") {
                auth.lock()
            }

            SecondaryButton("Wyloguj się", systemImage: "rectangle.portrait.and.arrow.right") {
                auth.signOut()
            }
        }
    }

    private var unlockName: String {
        switch auth.availability {
        case .available(let kind): return kind.displayName
        case .unavailable: return "przycisk odblokowania"
        }
    }
}

#Preview("Dostęp") {
    AccountActionsSection()
        .environmentObject(
            AuthStore(
                authenticator: PreviewBiometricAuthenticator(),
                defaults: UserDefaults(suiteName: "preview.account")!
            )
        )
        .padding(20)
        .background(EmmaTheme.bg)
}
