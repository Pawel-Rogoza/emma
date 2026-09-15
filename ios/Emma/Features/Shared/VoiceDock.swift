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
        VStack(alignment: .leading, spacing: 8) {
            Text(stateLabel)
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.dockStatusText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Stan rozmowy: \(stateLabel)")

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

            primaryButton

            if let toolLabel = state.toolLabel {
                Text("Emma: \(toolLabel)")
                    .font(EmmaTypography.emmaBody(toolLabel))
                    .foregroundStyle(EmmaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Emma pracuje: \(toolLabel)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EmmaTheme.dockBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EmmaTheme.dockBorder)
                .frame(height: 1)
        }
    }

    /// Jedyny przycisk: „Rozmawiaj” bez sesji, „Zakończ” w trakcie rozmowy.
    /// Etykiety celowo są krótkie i zgodne z dotychczasowym nazewnictwem Emmy.
    private var primaryButton: some View {
        let isActive = state.sessionID != nil
        return Button(action: isActive ? onEnd : onStart) {
            HStack(spacing: 9) {
                Image(systemName: isActive ? "phone.down.fill" : "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                Text(isActive ? "Zakończ" : "Rozmawiaj")
                    .font(EmmaTypography.button)
            }
            .foregroundStyle(EmmaTheme.primaryButtonText)
            .frame(maxWidth: .infinity, minHeight: EmmaMetrics.emmaVoiceButtonSize)
            .background(EmmaTheme.primaryButton)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.composerInner, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
