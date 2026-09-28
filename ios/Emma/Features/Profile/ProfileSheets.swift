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

            Text(environmentNote)
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.mutedSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            // „Przywróć dane przykładowe" ma sens tylko tam, gdzie dane
            // przykładowe istnieją. Prawdziwa kartoteka nie ma „resetu do
            // fixture", więc w produkcji ten przycisk znika, zamiast udawać
            // czynność, której repozytorium nie potrafi wykonać.
            if dependencies.repository is any DemoFixtureRepository {
                SecondaryButton("Przywróć dane przykładowe") {
                    dependencies.present(.resetDemo)
                }
            }

            ReminderDefaultPicker()
                .padding(.top, 20)

            if !dependencies.configuration.usesMockServices {
                VoiceDuplexToggle()
                    .padding(.top, 20)
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

            // Właściciel rozpoznaje wydanie z TestFlight po numerze wersji.
            Text(versionText)
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.mutedSoft)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 24)
                .accessibilityIdentifier("profile-version")
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Emma \(version) (build \(build))"
    }

    /// Nota o środowisku. W Demo mówi o scenariuszach i wspólnej dacie; poza Demo
    /// opisuje stan faktyczny — dane i głos idą z serwera kancelarii, a jedyne, co
    /// pozostaje symulowane, to wysyłka wiadomości (WhatsApp nie jest podłączony).
    private var environmentNote: String {
        if dependencies.configuration.usesMockServices {
            return "Jedno wspólne konto zespołu: te same sprawy, zadania i rozmowy. "
                + "AI i integracja WhatsApp są symulowane. Głos działa w trybie demonstracyjnym. "
                + "Data przykładowego dnia: 11 września 2026."
        }
        return "Konto zespołu: te same sprawy, zadania i rozmowy. Dane, kartoteka i rozmowa "
            + "głosowa pochodzą z serwera kancelarii — klucz dostawcy nigdy nie trafia do "
            + "aplikacji. WhatsApp nie jest jeszcze podłączony, więc wysyłka wiadomości "
            + "pozostaje symulowana."
    }
}

/// Przełącznik trybu rozmowy głosowej. Działa od następnej rozmowy — bieżąca
/// ma już zbudowany tor audio.
private struct VoiceDuplexToggle: View {

    @AppStorage(VoiceDuplexMode.defaultsKey) private var rawMode = VoiceDuplexMode.halfDuplex.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { rawMode == VoiceDuplexMode.fullDuplex.rawValue },
                set: { rawMode = ($0 ? VoiceDuplexMode.fullDuplex : .halfDuplex).rawValue }
            )) {
                Text("Przerywanie Emmy głosem (eksperymentalne)")
                    .font(EmmaTypography.ui(14))
                    .foregroundStyle(EmmaTheme.ink)
            }
            .tint(EmmaTheme.accent)

            Text("Włącza kasowanie echa: mikrofon zostaje otwarty, gdy Emma mówi, więc można jej przerwać w pół zdania, a odpowiedź przychodzi szybciej. Jeśli Emma słyszy samą siebie albo ucina Twoją mowę, wyłącz. Działa od następnej rozmowy.")
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.mutedSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Domyślne przypomnienie o terminach — obowiązuje każdy termin, któremu
/// nie ustawiono własnego w formularzu (także terminy dodane w panelu).
private struct ReminderDefaultPicker: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @AppStorage(ReminderPreferences.defaultKey) private var rawDefault = ReminderOffset.standard.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Przypomnienia o terminach")
                    .font(EmmaTypography.ui(14))
                    .foregroundStyle(EmmaTheme.ink)
                Spacer(minLength: 8)
                Picker("Przypomnienia o terminach", selection: Binding(
                    get: { ReminderOffset(rawValue: rawDefault) ?? .standard },
                    set: { value in
                        rawDefault = value.rawValue
                        Task {
                            if value != .none {
                                await dependencies.reminders.requestAuthorizationIfNeeded()
                            }
                            dependencies.reminders.scheduleRefresh(dependencies)
                        }
                    }
                )) {
                    ForEach(ReminderOffset.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(EmmaTheme.accent)
            }
            Text("Telefon przypomni o każdym terminie z kalendarza kancelarii, a o 8:00 poda skrót dnia. Przy terminie możesz wybrać inne przypomnienie.")
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.mutedSoft)
                .fixedSize(horizontal: false, vertical: true)
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
