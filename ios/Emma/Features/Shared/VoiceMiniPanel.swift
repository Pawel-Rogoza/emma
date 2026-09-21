import SwiftUI

// MARK: - Globalny mini-panel sesji (§4, etap 4 audytu — F06)
//
// Jedno miejsce sterowania rozmową widoczne poza ekranem Emmy: nad paskiem
// zakładek oraz nad arkuszem modalnym, dopóki sesja istnieje. Panel **nie**
// tworzy drugiego silnika, drugiej sesji ani drugiej subskrypcji transportu —
// czyta stan jednego koordynatora i woła wyłącznie jego metody (§5.3).
//
// Zawartość z audytu: mały wizerunek, jeden stan („Słucham” / „Mikrofon
// wyciszony” / „Emma mówi”), wyciszenie i zakończenie. Dotknięcie treści
// wraca do pełnej rozmowy. Na ekranie Emmy panelu nie ma, żeby nie dublować
// pełnego panelu sterowania (§4).

@MainActor
struct VoiceMiniPanel: View {

    let state: VoiceUIState
    let onOpen: () -> Void
    let onToggleMicrophone: () -> Void
    let onEnd: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    EmmaOrb(
                        size: .small,
                        isActive: state.orbIsActive,
                        state: state.turn
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.sessionHeadline)
                            .font(EmmaTypography.caption(.semibold))
                            .foregroundStyle(EmmaTheme.ink)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                        // Podpis „Wróć do rozmowy” jest tylko wskazówką — przy
                        // największym tekście ustępuje miejsca stanowi, zamiast
                        // urywać się do „Wróć do ro…” (zrzut `30-duzy-tekst-*`).
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("Wróć do rozmowy")
                                .font(EmmaTypography.caption())
                                .foregroundStyle(EmmaTheme.dockStatusText)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wróć do rozmowy z Emmą. Stan: \(state.sessionHeadline)")

            Button(action: onToggleMicrophone) {
                Image(systemName: state.isCapturingMicrophone ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
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

            Button(action: onEnd) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(EmmaTheme.dockActionText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zakończ rozmowę")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EmmaTheme.dockBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EmmaTheme.dockBorder)
                .frame(height: 1)
        }
    }
}
