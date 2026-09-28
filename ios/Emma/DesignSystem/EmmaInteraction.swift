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

    /// Odrzucony zapis — formularz pokazuje przy tym komunikat.
    public static func error() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
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

// MARK: - Ruch
//
// Audyt designu 28.09.2026: aplikacja prawie się nie ruszała — zmiana filtra,
// zakładki czy odhaczenie zadania działy się skokiem, więc wyglądała „płasko”
// i tańszo, niż jest. Trzy krzywe na całą aplikację, żeby ruch był spójny:
// krótki i sprężysty, nigdy nie opóźnia pracy (≤ 0,35 s).

public enum EmmaMotion {
    /// Wybór: segment, chip, zakładka — szybka sprężyna bez przestrzelenia.
    public static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.86)
    /// Potwierdzenie: odhaczenie, plakietka — lekko sprężyste, „przyjemne”.
    public static let bouncy = Animation.spring(response: 0.34, dampingFraction: 0.62)
    /// Zmiana treści: przełączenie listy, pojawienie się karty.
    public static let smooth = Animation.easeInOut(duration: 0.22)
}

/// Połyskujący placeholder ładowania (szkielet treści zamiast kręciołka).
/// Przy „Ogranicz ruch” zostaje statyczny.
public struct EmmaShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    public init() {}

    public func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, EmmaTheme.surface.opacity(0.7), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width * 1.4)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

public extension View {
    func emmaShimmer() -> some View { modifier(EmmaShimmer()) }
}
