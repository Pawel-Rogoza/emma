import SwiftUI

// MARK: - Dock Emmy (`#assistant-dock` → `.voice-controls-row`)
//
// Wiersz stanu z referencji: etykieta stanu („Słucham…”, „Emma mówi…”,
// „Rozmowa głosowa”, „Odpowiedzi tekstowe”), „Przerwij” i zakończenie rozmowy.
//
// Dock nie tworzy własnego silnika audio ani drugiej sesji — wyłącznie woła
// metody jednego koordynatora (§5.3). Odsłuch nigdy nie otwiera mikrofonu (§5.1).

@MainActor
struct VoiceDock: View {

    private let state: VoiceUIState
    private let speaksReplies: Bool
    private let onToggleSpeech: () -> Void
    private let onToggleMicrophone: () -> Void
    private let onInterrupt: () -> Void
    private let onEndSession: () -> Void

    init(
        state: VoiceUIState,
        speaksReplies: Bool,
        onToggleSpeech: @escaping () -> Void,
        onToggleMicrophone: @escaping () -> Void,
        onInterrupt: @escaping () -> Void,
        onEndSession: @escaping () -> Void
    ) {
        self.state = state
        self.speaksReplies = speaksReplies
        self.onToggleSpeech = onToggleSpeech
        self.onToggleMicrophone = onToggleMicrophone
        self.onInterrupt = onInterrupt
        self.onEndSession = onEndSession
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(stateLabel)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.dockStatusText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Stan rozmowy: \(stateLabel)")
                    // Zamrożona sygnatura przewiduje przełącznik odpowiedzi głosowych;
                    // widoczny przełącznik jest w nagłówku ekranu (jak w referencji),
                    // tutaj zostaje akcja dostępności.
                    .accessibilityAction(named: Text(speaksReplies ? "Wyłącz odpowiedzi głosowe" : "Włącz odpowiedzi głosowe")) {
                        onToggleSpeech()
                    }

                Spacer(minLength: 8)

                // Wyciszenie jest czynnością pierwszego rzędu, obok przerwania
                // i zakończenia (F06/F07) — nie ukrywamy go w menu.
                if state.sessionID != nil {
                    Button(action: onToggleMicrophone) {
                        Image(systemName: state.isCapturingMicrophone ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(
                                state.isCapturingMicrophone ? EmmaTheme.primaryButtonText : EmmaTheme.dockActionText
                            )
                            .frame(width: 44, height: 44)
                            .background(
                                state.isCapturingMicrophone ? EmmaTheme.primaryButton : Color.clear,
                                in: Circle()
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(state.isCapturingMicrophone ? "Wycisz mikrofon" : "Włącz mikrofon")
                    .accessibilityValue(state.microphone.displayName)
                }
                if state.canInterrupt {
                    dockButton("Przerwij", systemImage: "pause.fill", action: onInterrupt)
                }
                if state.canEndSession {
                    dockButton("Zakończ", systemImage: "xmark.circle", action: onEndSession)
                }
            }

            // Połączenie i mikrofon mówimy wprost, ale **tylko gdy sesja istnieje**
            // (F07). Bez sesji „Połączenie: Nieaktywna · Mikrofon niedostępny ·
            // Tryb: Bezczynny” to trzy sprzeczne komunikaty o niczym.
            if state.sessionID != nil {
                Text("Połączenie: \(state.connection.displayName) · Mikrofon: \(state.microphone.displayName) · Tryb: \(state.mode.displayName)")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.dockStatusText)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EmmaTheme.dockBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EmmaTheme.dockBorder)
                .frame(height: 1)
        }
    }

    /// Jeden stan bez żargonu (F07). Bazę daje rdzeń (`VoiceUIState.sessionHeadline`),
    /// żeby dock i mini-panel nie rozjechały się w nazwach.
    private var stateLabel: String {
        guard state.sessionID != nil else { return state.sessionHeadline }
        // Wyciszenie jest ważniejsze niż tryb: „Rozmowa głosowa” przy wyciszonym
        // mikrofonie obiecywało nasłuch, którego nie ma.
        if state.turn == .waiting, state.microphone != .muted, state.connection == .connected {
            return speaksReplies ? "Rozmowa głosowa" : "Odpowiedzi tekstowe"
        }
        return state.sessionHeadline
    }

    private func dockButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(EmmaTypography.caption())
            }
            .foregroundStyle(EmmaTheme.dockActionText)
            .frame(minHeight: EmmaSpacing.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
