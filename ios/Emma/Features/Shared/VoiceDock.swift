import SwiftUI

// MARK: - Sterowanie rozmową na ekranie Emmy (`emma-voice-controls`)
//
// Ekran rozmowy ma **jedną** czynność pierwszego rzędu: rozpocznij albo zakończ
// rozmowę. Wyciszenie mikrofonu, przerwanie i dyktowanie zostały z tego ekranu
// usunięte na wniosek użytkownika — stan sesji czyta `VoiceUIState` (połączenie,
// słuchanie, mowa Emmy, błąd), więc przycisk nie musi dublować go etykietami.
//
// Dock nie tworzy własnego silnika audio ani drugiej sesji — wyłącznie woła
// metody jednego koordynatora (§5.3). Wyciszenie mikrofonu nadal jest dostępne
// w globalnym mini-panelu poza ekranem Emmy, a pole tekstowe zostaje dla poleceń
// pisanych.

@MainActor
struct VoiceDock: View {

    private let state: VoiceUIState
    private let onStart: () -> Void
    private let onEnd: () -> Void

    init(
        state: VoiceUIState,
        onStart: @escaping () -> Void,
        onEnd: @escaping () -> Void
    ) {
        self.state = state
        self.onStart = onStart
        self.onEnd = onEnd
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Jedna linijka: stan po lewej, zwarta pigułka po prawej. Wcześniej
            // przycisk zajmował całą szerokość i 56 pt wysokości — wyglądał
            // ciężko i staroświecko obok reszty aplikacji (02.10.2026).
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 7) {
                    if state.sessionID != nil {
                        Circle()
                            .fill(EmmaTheme.pillGreenText)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                    Text(stateLabel)
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.dockStatusText)
                        .lineLimit(2)
                        .accessibilityLabel("Stan rozmowy: \(stateLabel)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                primaryButton
            }

            // Błąd pokazujemy **przy przycisku**, a nie tylko w przewijanej
            // treści: brak zgody na mikrofon albo brak toru wejścia musi być
            // widoczny bez szukania, tuż pod jedyną czynnością rozmowy.
            if let error = state.lastError {
                Text(error)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Problem: \(error)")
            }

            if let toolLabel = state.toolLabel {
                Text("Emma: \(toolLabel)")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Emma pracuje: \(toolLabel)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EmmaTheme.dockBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EmmaTheme.dockBorder)
                .frame(height: 1)
        }
        .animation(EmmaMotion.smooth, value: state.sessionID != nil)
    }

    /// Jedyny przycisk: „Rozmawiaj” bez sesji, „Zakończ” w trakcie rozmowy.
    /// Etykiety celowo są krótkie i zgodne z dotychczasowym nazewnictwem Emmy.
    private var primaryButton: some View {
        let isActive = state.sessionID != nil
        return Button(action: isActive ? onEnd : onStart) {
            HStack(spacing: 7) {
                Image(systemName: isActive ? "phone.down.fill" : "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(isActive ? "Zakończ" : "Rozmawiaj")
                    .font(EmmaTypography.ui(14, .semibold))
            }
            .foregroundStyle(isActive ? EmmaTheme.danger : EmmaTheme.primaryButtonText)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(isActive ? EmmaTheme.danger.opacity(0.12) : EmmaTheme.primaryButton, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .accessibilityLabel(isActive ? "Zakończ" : "Rozmawiaj")
        .accessibilityHint(isActive ? "Kończy rozmowę z Emmą" : "Rozpoczyna rozmowę głosową z Emmą")
    }

    /// Jeden stan bez żargonu (F07). Bazę daje rdzeń (`VoiceUIState.sessionHeadline`),
    /// żeby ekran i mini-panel nie rozjechały się w nazwach.
    private var stateLabel: String {
        guard state.sessionID != nil else { return state.sessionHeadline }
        // W trakcie spokojnej rozmowy mówimy wprost, że to rozmowa, a nie
        // powtarzamy „Emma czeka”, co przy żywym mikrofonie brzmi jak bezczynność.
        if state.turn == .waiting, state.microphone != .muted, state.connection == .connected {
            return "Rozmowa głosowa"
        }
        return state.sessionHeadline
    }
}
