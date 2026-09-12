import SwiftUI

// MARK: - Tokeny kolorów
//
// Wartości przeniesione z referencji po rozstrzygnięciu kaskady CSS
// (`reference/prototype/style.css`, warstwy z linii 2, 4, 11–24).
// Szczegóły i pochodzenie każdego tokenu: docs/ios/DESIGN_CONTRACT.md §1.
//
// Zasada: widoki nie zawierają literałów kolorów. Wyłącznie te tokeny.

public enum EmmaTheme {

    // Powierzchnie i tekst
    public static let bg = Color(hex: 0xF5F6F8)
    public static let surface = Color.white
    public static let ink = Color(hex: 0x152337)
    public static let muted = Color(hex: 0x687688)
    public static let mutedSoft = Color(hex: 0x7A8492)
    public static let border = Color(hex: 0xE2E7ED)
    public static let cardBorder = Color(hex: 0xE8ECF0)
    public static let rowSeparator = Color(hex: 0xEDF0F4)
    public static let checkboxBorder = Color(hex: 0xCBD4DF)
    public static let taskMetaText = Color(hex: 0x8A95A3)
    public static let taskDateText = Color(hex: 0x8B96A5)

    // Akcenty
    public static let accent = Color(hex: 0x3B61D9)
    public static let accentSoft = Color(hex: 0xEDF2F8)
    public static let unreadBadge = Color(hex: 0x365FD0)
    public static let unreadDivider = Color(hex: 0xE1E9F5)
    public static let unreadDividerText = Color(hex: 0x365D98)

    // Karta Emmy
    public static let emmaCard = Color(hex: 0x14263C)
    public static let emmaCardText = Color(hex: 0xDBE3ED)

    // Przyciski
    public static let primaryButton = Color(hex: 0x1B314D)
    public static let primaryButtonText = Color.white
    public static let secondaryButton = Color(hex: 0xEDF0F5)
    public static let secondaryButtonText = Color(hex: 0x365373)
    public static let disabledButton = Color(hex: 0xE5EAF1)
    public static let disabledButtonText = Color(hex: 0x9DA9B7)

    // Sterowanie
    public static let controlBackground = Color(hex: 0xE9EDF2)
    public static let controlSelected = Color.white
    public static let fieldBorder = Color(hex: 0xDCE5EE)
    public static let infoRowBorder = Color(hex: 0xE5EAF0)
    public static let sheetBackground = Color(hex: 0xF5F6F8)
    public static let closeButton = Color(hex: 0xE8ECF1)

    // Komunikator
    public static let chatBackground = Color(hex: 0xEEF1F5)
    public static let chatDockBackground = Color(hex: 0xF9FAFC)
    public static let chatHeaderBorder = Color(hex: 0xE1E6ED)
    public static let bubbleIncoming = Color.white
    public static let bubbleOutgoing = Color(hex: 0xDFE8F1)
    public static let bubbleMeta = Color(hex: 0x738398)
    public static let composerBorder = Color(hex: 0xDCE3EC)
    public static let quoteRule = Color(hex: 0x7895B5)
    public static let quoteBackground = Color(hex: 0xEAF0F6)
    public static let receiptDefault = Color(hex: 0x82909E)
    public static let receiptRead = Color(hex: 0x2674D8)
    public static let chatDayChip = Color(hex: 0xE5EAF0)
    public static let chatDayChipText = Color(hex: 0x788697)
    public static let dictationAccent = Color(hex: 0x9A622C)
    // Tłumaczenia wiadomości usunięte z interfejsu na życzenie właściciela
    // (zespół rozumie uk/ru) — tokeny `.bubble-translation` świadomie bez
    // odpowiedników. Rejestr: docs/ios/DESIGN_DEVIATIONS.md.

    // Status i komunikaty
    public static let danger = Color(hex: 0xA1533E)
    public static let toastBackground = Color(hex: 0x213953)
    public static let pillNeutralBackground = Color(hex: 0xF0F3FC)
    public static let pillNeutralText = Color(hex: 0x5770AB)
    public static let pillGreenBackground = Color(hex: 0xEDF4EF)
    public static let pillGreenText = Color(hex: 0x4B7966)
    public static let pillAmberBackground = Color(hex: 0xFAF0E5)
    public static let pillAmberText = Color(hex: 0x986B36)
    public static let pillUrgentBackground = Color(hex: 0xFBF0E3)
    public static let pillUrgentText = Color(hex: 0xA47740)

    // Awatary
    public static let avatarBackground = Color(hex: 0xE9E3D9)
    public static let avatarText = Color(hex: 0x79664A)
    public static let personAvatarBackground = Color(hex: 0xEAF0F4)
    public static let personAvatarText = Color(hex: 0x62778A)

    // Kalendarz
    public static let daySelected = Color(hex: 0x1C314B)
    public static let daySelectedNumber = Color.white
    public static let daySelectedLabel = Color(hex: 0xBFCCDF)
    public static let dayTodayDot = Color(hex: 0x8BA0B7)
    public static let weekControlBackground = Color(hex: 0xEDF1F5)
    public static let weekControlText = Color(hex: 0x69819B)

    // Pasek zakładek
    public static let tabBarBackground = Color(hex: 0xFBFCFD)
    public static let tabBarBorder = Color(hex: 0xE1E7EE)
    public static let tabActive = Color(hex: 0x254D9D)
    public static let tabInactive = Color(hex: 0x8A93A0)
    public static let tabEmmaChip = Color(hex: 0x1A2E47)
    public static let tabEmmaChipText = Color.white

    // Pozostałe
    public static let contextStripBackground = Color(hex: 0xEAF0F6)
    public static let contextStripText = Color(hex: 0x6B84A0)
    public static let contextStripBorder = Color(hex: 0xDFE7EF)
    public static let activityMarker = Color(hex: 0xA6B5C7)
    /// `.case-emma` — początek gradientu tła (110°)
    public static let emmaGradientStart = Color(hex: 0xEAF0F6)
    /// `.case-emma` — koniec gradientu tła
    public static let emmaGradientEnd = Color(hex: 0xF6F8FA)
    /// `.case-emma` — obramowanie karty
    public static let caseEmmaBorder = Color(hex: 0xDFE7EF)
    /// `.case-emma small` — podtytuł karty
    public static let caseEmmaSubtitle = Color(hex: 0x8494A7)
    /// `.case-emma>svg` — ikona odsłuchu
    public static let caseEmmaIcon = Color(hex: 0x557799)
    public static let linkedCaseBackground = Color(hex: 0xEDF2F8)
    public static let linkedCaseBorder = Color(hex: 0xDCE5F0)
    public static let draftBackground = Color(hex: 0xFAFCFE)
    public static let draftBorder = Color(hex: 0xDBE5EE)
    public static let actionCardBorder = Color(hex: 0xCCDBE9)

    /// Kolor awatara z prezentacji listy rozmów. Zależy od **stabilnej pozycji**,
    /// nie od identyfikatora (§4.3).
    public static func conversationAvatar(_ tone: Client.AvatarTone) -> (background: Color, foreground: Color) {
        switch tone {
        case .none: return (Color(hex: 0xE3EBF1), Color(hex: 0x4E6882))
        case .one: return (Color(hex: 0xEAE3DA), Color(hex: 0x88704E))
        case .two: return (Color(hex: 0xEEE4E8), Color(hex: 0x926778))
        case .three: return (Color(hex: 0xE4E9E2), Color(hex: 0x6A7A60))
        }
    }

    /// Stabilne przypisanie tonu do pozycji na liście rozmów.
    public static func avatarTone(forPresentationIndex index: Int) -> Client.AvatarTone {
        switch index % 4 {
        case 1: return .one
        case 2: return .two
        case 3: return .three
        default: return .none
        }
    }

    // MARK: Asystent i dok głosowy
    //
    // Wartości odczytane z kaskady CSS referencji. Zebrane tutaj, bo rozsiane po
    // widokach prywatne kolory rozjeżdżają się przy pierwszej zmianie wzorca.

    /// `.emma-intro p`
    public static let emmaIntroText = Color(hex: 0x7F8D9E)
    /// `.emma-turn` — obramowanie wypowiedzi
    public static let emmaTurnBorder = Color(hex: 0xE4EAF1)
    /// `.emma-turn > span` — kto mówi
    public static let emmaTurnLabel = Color(hex: 0x728AA4)
    /// `.listen-text` — „Odsłuchaj”
    public static let emmaListenText = Color(hex: 0x5F80A2)
    /// `.emma-suggestions button svg`
    public static let emmaSuggestionIcon = Color(hex: 0x6383A4)
    /// `.emma-suggestions button svg:last-child`
    public static let emmaSuggestionChevron = Color(hex: 0x9EAFBF)
    /// `.emma-suggestions small`
    public static let emmaSuggestionSubtitle = Color(hex: 0x8D9AAB)
    /// `.voice-status-line`
    public static let emmaStatusText = Color(hex: 0x8395A9)
    /// `.demo-foot` — nota o danych przykładowych
    public static let emmaDemoFootText = Color(hex: 0x8E9AAA)
    /// `.assistant-compose` — obramowanie pola polecenia
    public static let emmaComposerBorder = Color(hex: 0xD8E3EE)
    /// `.mic-button` — tekst na przycisku mikrofonu
    public static let emmaMicText = Color(hex: 0x4C7399)
    /// `.small-suggestions button` — obramowanie
    public static let emmaSmallSuggestionBorder = Color(hex: 0xDEE7F0)
    /// `.small-suggestions button` — tekst
    public static let emmaSmallSuggestionText = Color(hex: 0x6382A1)
    /// `#assistant-dock` — tło doku
    public static let dockBackground = Color(hex: 0xF5F7F9)
    /// `#assistant-dock` — górne obramowanie
    public static let dockBorder = Color(hex: 0xE3E9F0)
    /// `.voice-controls-row` — etykieta stanu
    public static let dockStatusText = Color(hex: 0x8A9AAC)
    /// `.voice-controls-row .text-button`
    public static let dockActionText = Color(hex: 0x8196AD)
    /// `.emma-action-heading span:first-child`
    public static let actionHeadingText = Color(hex: 0x617F9F)
    /// `.action-meta`
    public static let actionMetaText = Color(hex: 0x8796A6)
}

extension Color {
    /// Kolor z zapisu szesnastkowego `0xRRGGBB` w przestrzeni sRGB.
    public init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
