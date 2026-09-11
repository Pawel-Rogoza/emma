import SwiftUI

// MARK: - Dock Emmy (`#assistant-dock` → `.voice-controls-row`)
//
// Wiersz stanu z referencji: etykieta stanu („Słucham…”, „Emma mówi…”,
// „Rozmowa głosowa”, „Odpowiedzi tekstowe”), „Przerwij” i zakończenie rozmowy.
//
// Dock nie tworzy własnego silnika audio ani drugiej sesji — wyłącznie woła
// metody jednego koordynatora (§5.3). Odsłuch nigdy nie otwiera mikrofonu (§5.1).

// Kolory referencji, których nie ma w `EmmaTheme` (plik `EmmaTheme.swift` edytują
// równolegle inne zadania, więc tokeny dopisujemy tutaj).
private extension Color {
    /// TODO(token): #F5F7F9 — `#assistant-dock` (tło)
    static let emmaDockBackground = Color(hex: 0xF5F7F9)
    /// TODO(token): #E3E9F0 — `#assistant-dock` (górne obramowanie)
    static let emmaDockBorder = Color(hex: 0xE3E9F0)
    /// TODO(token): #8A9AAC — `.voice-controls-row`
    static let emmaDockStatusText = Color(hex: 0x8A9AAC)
    /// TODO(token): #8196AD — `.voice-controls-row .text-button`
    static let emmaDockActionText = Color(hex: 0x8196AD)
}

@MainActor
struct VoiceDock: View {

    private let state: VoiceUIState
    private let speaksReplies: Bool
    private let onToggleSpeech: () -> Void
    private let onInterrupt: () -> Void
    private let onEndSession: () -> Void

    init(
        state: VoiceUIState,
        speaksReplies: Bool,
        onToggleSpeech: @escaping () -> Void,
        onInterrupt: @escaping () -> Void,
        onEndSession: @escaping () -> Void
    ) {
        self.state = state
        self.speaksReplies = speaksReplies
        self.onToggleSpeech = onToggleSpeech
        self.onInterrupt = onInterrupt
        self.onEndSession = onEndSession
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(stateLabel)
                    .font(EmmaTypography.ui(10))
                    .foregroundStyle(Color.emmaDockStatusText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Stan rozmowy: \(stateLabel)")
                    // Zamrożona sygnatura przewiduje przełącznik odpowiedzi głosowych;
                    // widoczny przełącznik jest w nagłówku ekranu (jak w referencji),
                    // tutaj zostaje akcja dostępności.
                    .accessibilityAction(named: Text(speaksReplies ? "Wyłącz odpowiedzi głosowe" : "Włącz odpowiedzi głosowe")) {
                        onToggleSpeech()
                    }

                Spacer(minLength: 8)

                if state.canInterrupt {
                    dockButton("Przerwij", systemImage: "pause.fill", action: onInterrupt)
                }
                if state.canEndSession {
                    dockButton("Zakończ rozmowę", systemImage: "xmark.circle", action: onEndSession)
                }
            }

            // Połączenie i mikrofon mówimy wprost — nigdy wyłącznie kolorem (§5.5).
            Text("Połączenie: \(state.connection.displayName) · Mikrofon: \(state.microphone.displayName) · Tryb: \(state.mode.displayName)")
                .font(EmmaTypography.ui(10))
                .foregroundStyle(Color.emmaDockStatusText)
                .fixedSize(horizontal: false, vertical: true)

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
        .background(Color.emmaDockBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.emmaDockBorder)
                .frame(height: 1)
        }
    }

    /// Etykiety z referencji `paintVoice()`.
    private var stateLabel: String {
        switch state.turn {
        case .listening: return "Słucham…"
        case .thinking: return "Przygotowuję odpowiedź…"
        case .speaking: return "Emma mówi…"
        case .interrupted: return "Przerwane"
        case .waiting:
            return speaksReplies ? "Rozmowa głosowa" : "Odpowiedzi tekstowe"
        }
    }

    private func dockButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(EmmaTypography.ui(10))
            }
            .foregroundStyle(Color.emmaDockActionText)
            .frame(minHeight: EmmaSpacing.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
