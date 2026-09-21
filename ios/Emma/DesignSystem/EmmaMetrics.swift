import SwiftUI

// MARK: - Odstępy, promienie, wymiary
//
// Wartości z referencji (DESIGN_CONTRACT §2). Widoki używają wyłącznie tych stałych.

public enum EmmaRadii {
    public static let card: CGFloat = 17
    public static let emmaCard: CGFloat = 21
    public static let segmented: CGFloat = 10
    public static let segmentedInner: CGFloat = 8
    public static let search: CGFloat = 11
    public static let button: CGFloat = 12
    public static let iconButton: CGFloat = 12
    public static let bubble: CGFloat = 17
    /// Promień narożnika po stronie nadawcy w dymku.
    public static let bubbleTail: CGFloat = 5
    public static let composer: CGFloat = 24
    public static let composerInner: CGFloat = 11
    public static let pill: CGFloat = 6
    public static let field: CGFloat = 10
    public static let choiceList: CGFloat = 13
    public static let sheet: CGFloat = 23
    public static let dayCell: CGFloat = 15
    public static let avatar: CGFloat = 41
    public static let badge: CGFloat = 20
    /// `.emma-turn` — wypowiedź w rozmowie z Emmą
    public static let emmaTurn: CGFloat = 15
    /// `.emma-turn` — narożnik po stronie nadawcy
    public static let emmaTurnTail: CGFloat = 5
    /// `.emma-suggestions`
    public static let emmaSuggestions: CGFloat = 15
    /// `.assistant-compose` — pole polecenia
    public static let emmaComposer: CGFloat = 14
    /// `.emma-context` — selektor kontekstu
    public static let emmaContext: CGFloat = 11
    /// `.small-suggestions button`
    public static let emmaSmallSuggestion: CGFloat = 10
    /// `.emma-action` — karta propozycji
    public static let actionCard: CGFloat = 15
    /// `.case-emma` — promień karty Emmy w sprawie
    public static let caseEmmaCard: CGFloat = 14
}

public enum EmmaSpacing {
    /// Margines boczny ekranu (`.content` w podglądzie).
    public static let screenH: CGFloat = 20
    /// Margines boczny otwartego wątku — węższy (§3.2).
    public static let threadH: CGFloat = 16
    /// Margines boczny na bardzo małych ekranach (`@media max-width:365px`).
    public static let smallScreenH: CGFloat = 15
    public static let contentTop: CGFloat = 16
    public static let contentBottom: CGFloat = 18
    public static let sectionTop: CGFloat = 16
    public static let sectionBottom: CGFloat = 9
    public static let sectionHeaderMinHeight: CGFloat = 38
    public static let cardGap: CGFloat = 11
    /// `.case-emma` — odstęp między orbem a tekstem
    public static let caseEmmaGap: CGFloat = 11
    public static let rowGap: CGFloat = 10
    /// Minimalny obszar dotykowy. Referencja miała mniejsze ikony; powiększamy
    /// obszar dotyku bez zmiany wyglądu (§2.2).
    public static let hitTarget: CGFloat = 44
    public static let listBottomInset: CGFloat = 12
    public static let chatScrollBottomInset: CGFloat = 12
}

public enum EmmaMetrics {
    /// Szerokość wnętrza referencji: 412 − 2 × 7 pt obramowania.
    public static let referenceContentWidth: CGFloat = 398
    public static let phoneWidth: CGFloat = 412
    public static let avatar: CGFloat = 41
    public static let userAvatar: CGFloat = 44
    public static let conversationAvatar: CGFloat = 48
    public static let clientHeroAvatar: CGFloat = 63
    public static let threadHeaderAvatar: CGFloat = 39
    public static let tabBarHeight: CGFloat = 74
    public static let tabBarTopPadding: CGFloat = 8
    public static let tabBarBottomPadding: CGFloat = 3
    public static let tabItemMinHeight: CGFloat = 52
    public static let tabEmmaChipWidth: CGFloat = 43
    public static let tabEmmaChipHeight: CGFloat = 34
    public static let tabBadgeMinWidth: CGFloat = 17
    public static let tabBadgeHeight: CGFloat = 17
    public static let primaryButtonMinHeight: CGFloat = 44
    public static let previewButtonMinHeight: CGFloat = 46
    public static let searchMinHeight: CGFloat = 43
    public static let segmentedMinHeight: CGFloat = 38
    public static let fieldMinHeight: CGFloat = 45
    public static let choiceRowMinHeight: CGFloat = 51
    public static let quickActionMinHeight: CGFloat = 67
    public static let dayCellMinHeight: CGFloat = 74
    public static let taskCheckSize: CGFloat = 24
    public static let iconButtonSize: CGFloat = 44
    public static let composerIconButton: CGFloat = 36
    public static let micButtonSize: CGFloat = 43
    public static let sheetMaxWidth: CGFloat = 398
    public static let sheetCloseSize: CGFloat = 44
    // MARK: Asystent
    /// `.emma-context` — minimalna wysokość selektora kontekstu
    public static let emmaContextMinHeight: CGFloat = 41
    /// `.mic-button` i `.send-button`
    public static let emmaComposerButtonSize: CGFloat = 43
    /// Główne wejście w rozmowę „Rozmawiaj” (etap 4 audytu: mikrofon 56–64 pt).
    public static let emmaVoiceButtonSize: CGFloat = 56
    /// `.emma-action .draft` — minimalna wysokość szkicu
    public static let actionDraftMinHeight: CGFloat = 130

}

// MARK: - Adaptacja do rozmiaru ekranu

/// Referencja ma osobną warstwę dla szerokości ≤ 365 pt. W SwiftUI nie czytamy
/// `UIScreen.main` (§2.2) — margines zależy od realnej szerokości kontenera.
public struct EmmaLayoutMetrics: Sendable {
    public var horizontalPadding: CGFloat
    public var welcomeSize: CGFloat
    public var isCompactWidth: Bool

    public init(width: CGFloat) {
        // 320 pt = iPhone SE 1. generacji; 375 pt = iPhone SE 2/3, mini.
        isCompactWidth = width <= 365
        horizontalPadding = width <= 365 ? EmmaSpacing.smallScreenH : EmmaSpacing.screenH
        welcomeSize = width <= 365 ? 24 : 25
    }

    public var threadHorizontalPadding: CGFloat {
        isCompactWidth ? EmmaSpacing.smallScreenH : EmmaSpacing.threadH
    }
}

private struct EmmaLayoutMetricsKey: EnvironmentKey {
    static let defaultValue = EmmaLayoutMetrics(width: EmmaMetrics.phoneWidth)
}

public extension EnvironmentValues {
    var emmaLayout: EmmaLayoutMetrics {
        get { self[EmmaLayoutMetricsKey.self] }
        set { self[EmmaLayoutMetricsKey.self] = newValue }
    }
}

// MARK: - Skalowanie tekstu

/// Odstępy rosnące razem z ustawieniem rozmiaru tekstu użytkownika.
