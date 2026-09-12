import SwiftUI

// MARK: - Ekran główny
//
// Decyzja właściciela: ekran startowy to Emma — animowany orb, powitanie
// i wejście do rozmowy. Kokpit (briefing, statystyki, najbliższa konsultacja,
// zadania, prowadzone sprawy) zniknął ze startu: statystyki i sprawy są na
// zakładkach „Klienci” i „Kalendarz”, a zadania dnia pozostają osiągalne
// jednym dyskretnym łączem poniżej. Odstępstwo od referencji `home()`
// jest zapisane w docs/ios/DESIGN_DEVIATIONS.md.
//
// Ekran nie ładuje repozytorium — powitanie bierze z bieżącego użytkownika,
// więc start jest natychmiastowy i bez stanu „Wczytuję…”.

struct TodayScreen: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout: EmmaLayoutMetrics

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                kicker: dependencies.dateText.headline(for: dependencies.today),
                title: "Dzień dobry, \(EmmaBriefing.vocative(dependencies.currentUser.displayName))",
                userInitials: dependencies.currentUser.initials,
                onUserTap: { dependencies.present(.profile) }
            )

            Spacer(minLength: 0)

            orb

            subline

            Spacer(minLength: 0)

            actions

            tasksLink
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, EmmaSpacing.contentTop)
        .padding(.bottom, EmmaSpacing.contentBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EmmaTheme.bg)
    }

    // MARK: Orb

    /// Orb „żyje” sam (breathing), a przy aktywnym głosie Emmy sygnalizuje
    /// to wyraźniejszym pulsowaniem (`isActive`). Dotknięcie zaczyna rozmowę.
    private var orb: some View {
        Button {
            dependencies.openEmma(clientID: nil, startVoice: true)
        } label: {
            EmmaOrb(
                size: .hero,
                isActive: dependencies.voice.state.isPlaybackActive,
                breathing: true
            )
            .padding(26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Emma")
        .accessibilityHint("Dotknij, aby porozmawiać głosem")
    }

    // MARK: Powitanie

    private var subline: some View {
        VStack(spacing: 10) {
            Text("Jestem Emma.")
                .font(EmmaTypography.heading(24))
                .tracking(-0.7)
                .foregroundStyle(EmmaTheme.ink)

            Text("Pytaj o sprawy, wiadomości i terminy —\ngłosem albo na piśmie.")
                .font(EmmaTypography.ui(14))
                .foregroundStyle(EmmaTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
    }

    // MARK: Wejście do rozmowy

    private var actions: some View {
        VStack(spacing: 10) {
            PrimaryButton("Porozmawiaj głosem", systemImage: "mic.fill") {
                dependencies.openEmma(clientID: nil, startVoice: true)
            }
            SecondaryButton("Napisz do Emmy", systemImage: "keyboard") {
                dependencies.openEmma(clientID: nil)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: Dyskretne łącze do zadań

    /// `TasksScreen` nie ma własnej zakładki — to łącze jest jedynym wejściem
    /// do zbiorczej listy zadań po uproszczeniu ekranu głównego.
    private var tasksLink: some View {
        Button {
            dependencies.openTasks()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 13, weight: .medium))
                Text("Zadania na dziś")
                    .font(EmmaTypography.ui(13, .medium))
            }
            .foregroundStyle(EmmaTheme.muted)
            .frame(minHeight: EmmaSpacing.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .accessibilityLabel("Otwórz listę zadań na dziś")
    }
}

#Preview("Dzisiaj") {
    TodayScreen()
        .environmentObject(AppDependencies.demo())
}
