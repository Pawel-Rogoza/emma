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

// MARK: - Wejście kart
//
// Backlog audytu 28.09.2026 (P2, pkt 7): karty listy wchodzą lekkim
// przenikaniem z przesunięciem 8 pt, kaskadowo po 35 ms. Tylko przy pierwszym
// pokazaniu widoku — odświeżenie danych nie „miga” całą listą. Kaskada ma
// górny limit, żeby długa lista nie czekała na ostatnią kartę.

public struct EmmaAppear: ViewModifier {
    private let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    public init(index: Int) {
        self.index = index
    }

    public func body(content: Content) -> some View {
        let shown = visible || reduceMotion
        return content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                guard !visible else { return }
                let delay = Double(min(index, 8)) * 0.035
                withAnimation(EmmaMotion.smooth.delay(delay)) { visible = true }
            }
    }
}

public extension View {
    /// Kaskadowe wejście karty listy (`index` — pozycja na liście).
    func emmaAppear(_ index: Int = 0) -> some View { modifier(EmmaAppear(index: index)) }
}

/// Miękko pulsująca obwódka — „tu jest coś nowego”. Jedyny ciągły ruch listy,
/// dlatego bardzo wolny i delikatny; przy „Ogranicz ruch” obwódka stoi.
public struct EmmaPulseRing: View {
    private let color: Color
    private let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    public init(color: Color, diameter: CGFloat) {
        self.color = color
        self.diameter = diameter
    }

    public var body: some View {
        ZStack {
            Circle()
                .strokeBorder(color, lineWidth: 2)
            if !reduceMotion {
                Circle()
                    .strokeBorder(color.opacity(expanded ? 0 : 0.45), lineWidth: 2)
                    .scaleEffect(expanded ? 1.28 : 1)
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                expanded = true
            }
        }
    }
}
