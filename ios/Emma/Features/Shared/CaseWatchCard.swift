import SwiftUI

// MARK: - Karta pilnowanej daty
//
// „Areszt — Jan Kowalski · do 12 listopada · 23 dni”. Duża liczba dni po
// prawej, bo to jedyna rzecz, którą trzeba zobaczyć w pół sekundy. Kolor
// idzie za pilnością: zapowiedź (≤ 30 dni) bursztynowa, ostatni tydzień
// i data po terminie czerwone. Ta sama karta jest na ekranie sprawy
// i na „Dzisiaj”.

struct CaseWatchCard: View {

    let watch: CaseWatch
    /// Linia pod tytułem: na „Dzisiaj” klient i sprawa, w sprawie — sama data.
    var subtitle: String? = nil
    let onOpen: () -> Void

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var tone: Color {
        switch watch.severity {
        case .critical, .expired: return EmmaTheme.pillDangerText
        case .soon: return EmmaTheme.pillAmberText
        case .calm: return EmmaTheme.accent
        }
    }

    private var toneBackground: Color {
        switch watch.severity {
        case .critical, .expired: return EmmaTheme.pillDangerBackground
        case .soon: return EmmaTheme.pillAmberBackground
        case .calm: return EmmaTheme.accentSoft
        }
    }

    var body: some View {
        Button {
            EmmaHaptics.tap()
            onOpen()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: watch.kind.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tone)
                    .frame(width: 36, height: 36)
                    .background(toneBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .scaleEffect(pulse ? 1.08 : 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(watch.kind.displayName) do \(dependencies.dateText.dayTitle(watch.until))")
                        .font(EmmaTypography.ui(14, .semibold))
                        .foregroundStyle(EmmaTheme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle ?? watch.kind.hint)
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                countdown
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(EmmaTheme.surface)
            .overlay(alignment: .leading) {
                Rectangle().fill(tone).frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .emmaCardShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(watch.kind.displayName) do \(dependencies.dateText.dayTitle(watch.until)), \(watch.countdownText). \(subtitle ?? "")")
        .accessibilityHint("Otwiera sprawę")
        .onAppear {
            // Ostatni tydzień delikatnie pulsuje — jak karta „Po terminie”.
            guard watch.severity >= .critical, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    /// „23 / dni”, „jutro”, „dziś”, „po terminie”.
    @ViewBuilder
    private var countdown: some View {
        VStack(alignment: .trailing, spacing: 0) {
            switch watch.daysLeft {
            case let days where days > 1:
                Text("\(days)")
                    .font(EmmaTypography.heading(24))
                    .foregroundStyle(tone)
                    .contentTransition(.numericText())
                Text(EmmaPlural.form(days, "dzień", "dni", "dni"))
                    .font(EmmaTypography.caption(.medium))
                    .foregroundStyle(tone)
            case 1:
                Text("jutro")
                    .font(EmmaTypography.ui(15, .semibold))
                    .foregroundStyle(tone)
            case 0:
                Text("dziś")
                    .font(EmmaTypography.ui(15, .semibold))
                    .foregroundStyle(tone)
            default:
                Text("minął")
                    .font(EmmaTypography.ui(13, .semibold))
                    .foregroundStyle(tone)
                Text("zaktualizuj")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.muted)
            }
        }
        .fixedSize()
    }
}
