import SwiftUI

// MARK: - Orb Emmy
//
// Jeden komponent w pięciu rozmiarach z referencji (DESIGN_CONTRACT §4).
// Wypełnienie odtwarzamy natywnie gradientem promienistym z tymi samymi punktami
// koloru co `radial-gradient(circle at 28% 24%, …)`.

public struct EmmaOrb: View {

    public enum Size: Sendable {
        case inline
        case small
        case medium
        case card
        case hero

        var diameter: CGFloat {
            switch self {
            case .inline: return 18
            case .small: return 25
            case .medium: return 32
            case .card: return 37
            case .hero: return 100
            }
        }

        var insetShadowScale: CGFloat {
            switch self {
            case .inline, .small: return 0.18
            case .medium: return 0.30
            case .card: return 0.35
            case .hero: return 1.0
            }
        }
    }

    private let size: Size
    private let isActive: Bool
    private let breathing: Bool

    /// - Parameters:
    ///   - size: rozmiar z referencji.
    ///   - isActive: pulsowanie wyłącznie w stanie aktywnym (listening/speaking/thinking).
    ///     Przy włączonym „Ograniczeniu ruchu” pulsowanie jest wyłączone, a stan
    ///     pozostaje czytelny dzięki etykiecie tekstowej.
    ///   - breathing: spokojna animacja obecności (delikatne oddychanie i poświata),
    ///     dla ekranu głównego, gdzie orb ma „żyć” także bez rozmowy. Pusta
    ///     animacja nigdy nie oznacza stanu sesji — do tego służy `isActive`.
    public init(size: Size = .card, isActive: Bool = false, breathing: Bool = false) {
        self.size = size
        self.isActive = isActive
        self.breathing = breathing
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Napędza pętlę oddychania — sama zmiana stanu w `onAppear`, pętla jest
    /// w animacji, więc widok nie przebija się klatką po klatce.
    @State private var isBreathing = false

    private var orbScale: CGFloat {
        if isActive && !reduceMotion { return 1.06 }
        if breathing && !reduceMotion && isBreathing { return 1.035 }
        return 1.0
    }

    public var body: some View {
        Circle()
            .fill(Self.gradient)
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.32), Color.clear],
                            center: UnitPoint(x: 0.28, y: 0.24),
                            startRadius: 0,
                            endRadius: size.diameter * 0.62
                        )
                    )
            }
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: max(0.5, size.diameter * 0.02))
            }
            .background {
                if breathing && !reduceMotion {
                    Circle()
                        .strokeBorder(Color(hex: 0x9CBFDD, opacity: 0.5), lineWidth: 1)
                        .scaleEffect(isBreathing ? 1.32 : 1.08)
                        .opacity(isBreathing ? 0 : 0.55)
                }
            }
            .frame(width: size.diameter, height: size.diameter)
            .shadow(color: Color(hex: 0x9CBFDD, opacity: 0.18), radius: size.diameter * 0.18, x: 0, y: size.diameter * 0.08)
            .scaleEffect(orbScale)
            .animation(
                isActive && !reduceMotion
                    ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                    : .default,
                value: isActive
            )
            .animation(
                .easeInOut(duration: 3.6).repeatForever(autoreverses: true),
                value: isBreathing
            )
            .onAppear {
                isBreathing = breathing && !reduceMotion
            }
            .accessibilityHidden(true)
    }

    /// Punkty koloru z referencji (`.orb`), z pozycjami 0 / .20 / .33 / .46 / .61 / .84 / 1.
    private static let stops: [(CGFloat, UInt32)] = [
        (0.00, 0xE0F7EE),
        (0.20, 0x95BBD3),
        (0.33, 0x769BBF),
        (0.46, 0x8A83A8),
        (0.61, 0x384D78),
        (0.84, 0xCCD7CE),
        (1.00, 0x7896BB)
    ]

    private static var gradient: RadialGradient {
        RadialGradient(
            stops: stops.map { Gradient.Stop(color: Color(hex: $0.1), location: $0.0) },
            center: UnitPoint(x: 0.28, y: 0.24),
            startRadius: 0,
            endRadius: 26
        )
    }
}

#Preview("Orb Emmy — rozmiary") {
    VStack(spacing: 24) {
        HStack(spacing: 16) {
            EmmaOrb(size: .inline)
            EmmaOrb(size: .small)
            EmmaOrb(size: .medium)
            EmmaOrb(size: .card)
        }
        EmmaOrb(size: .hero)
        EmmaOrb(size: .hero, isActive: true)
        EmmaOrb(size: .hero, breathing: true)
    }
    .padding(30)
    .background(EmmaTheme.bg)
}
