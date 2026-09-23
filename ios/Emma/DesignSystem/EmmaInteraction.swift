import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Dotyk, reakcja i głębia
//
// Review z 23.09.2026: aplikacja reagowała na dotknięcia „płasko” — karta nie
// dawała znać, że ją wciśnięto, a odhaczenie zadania czy obsłużenie leada nie
// miało żadnego potwierdzenia poza zmianą koloru. Tu są trzy drobne elementy,
// które składają się na wrażenie dopracowanej aplikacji:
//
//   • `EmmaHaptics`         — krótka odpowiedź dotykowa po ważnej czynności,
//   • `EmmaCardButtonStyle` — karta lekko się zapada pod palcem,
//   • `emmaCardShadow()`    — miękki cień zamiast samej ramki.
//
// Kolory pochodzą wyłącznie z `EmmaTheme` (cień to atrament z przezroczystością).

@MainActor
public enum EmmaHaptics {

    /// Czynność zakończona powodzeniem: odhaczone zadanie, obsłużony lead.
    public static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Lekkie potwierdzenie dotknięcia (przełączenie, cofnięcie).
    public static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// Zmiana wyboru: zakładka, filtr, dzień w kalendarzu.
    public static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}

/// Styl przycisku-karty: lekkie zapadnięcie i przygaszenie pod palcem.
public struct EmmaCardButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

public extension View {
    /// Miękki, dwuwarstwowy cień karty. Ramka zostaje — cień tylko ją podnosi.
    func emmaCardShadow() -> some View {
        shadow(color: EmmaTheme.ink.opacity(0.035), radius: 1, x: 0, y: 1)
            .shadow(color: EmmaTheme.ink.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}
