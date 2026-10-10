import SwiftUI

// MARK: - Tokeny kolorów
//
// Redesign 0.22.0: kończymy zamrożony kontrakt z referencją HTML. Kolory mają
// znaczenie, a nie pochodzenie z selektora CSS:
//
//   • `accent`   — czynności, wybrana zakładka, linki,
//   • `emma`     — wszystko, co przygotowała Emma (szkic, propozycja, zakładka),
//   • `critical` — termin procesowy dziś / po terminie, areszt, zamknięte okno 24 h,
//   • `warning`  — termin w 1–3 dni, okno 24 h się zamyka, zadanie po terminie,
//   • `positive` — nowe w WhatsAppie, załatwione, zapłacone.
//
// Czerwony (`critical`) jest **tylko** dla terminów. Starsze nazwy tokenów
// zostają jako aliasy semantycznych, żeby ekrany nie musiały zmieniać się naraz.
// Bramka `scripts/check-color-tokens.py` pilnuje, że widoki nie mają literałów
// kolorów; `check-readability.py` — kontrastu tekstu (≥ 4,5:1).
//
// Motyw jest jasny (decyzja właściciela 10.10.2026 — tryb ciemny niepotrzebny).

public enum EmmaTheme {

    // MARK: Semantyka

    /// Akcent czynności: przyciski tekstowe, wybrana zakładka, linki.
    public static let accent = Color(hex: 0x2F5BD3)
    public static let accentSoft = Color(hex: 0xE9EFFC)
    /// Kolor Emmy — szkice, propozycje i środkowa zakładka.
    public static let emma = Color(hex: 0x6B4FD8)
    public static let emmaSoft = Color(hex: 0xEFEBFC)
    /// Termin dziś lub po terminie. Jedyny „krzyk” w aplikacji.
    public static let critical = Color(hex: 0xC2362B)
    public static let criticalSoft = Color(hex: 0xFBEAE8)
    /// Termin wkrótce, okno 24 h się zamyka.
    public static let warning = Color(hex: 0x9A5A0C)
    public static let warningSoft = Color(hex: 0xFCF1E2)
    /// Załatwione, zapłacone.
    public static let positive = Color(hex: 0x1E7346)
    public static let positiveSoft = Color(hex: 0xE6F3EB)

    // Powierzchnie i tekst
    public static let bg = Color(hex: 0xF5F6F8)
    public static let surface = Color.white
    public static let ink = Color(hex: 0x152337)
    public static let muted = Color(hex: 0x687688)
    public static let mutedSoft = Color(hex: 0x5F6D7D)
    public static let border = Color(hex: 0xE2E7ED)
    public static let cardBorder = Color(hex: 0xE8ECF0)
    public static let rowSeparator = Color(hex: 0xEDF0F4)
    public static let checkboxBorder = Color(hex: 0xCBD4DF)
    public static let taskMetaText = Color(hex: 0x66768B)
    public static let taskDateText = Color(hex: 0x66768B)

    // Akcenty
    public static let unreadBadge = accent
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
    public static let bubbleMeta = Color(hex: 0x66768B)
    public static let composerBorder = Color(hex: 0xDCE3EC)
    public static let quoteRule = Color(hex: 0x7895B5)
    public static let quoteBackground = Color(hex: 0xEAF0F6)
    public static let receiptDefault = Color(hex: 0x4E6882)
    public static let receiptRead = Color(hex: 0x2674D8)
    /// Zieleń WhatsAppa na liście rozmów: godzina i licznik **nowych**
    /// wiadomości — ten sam sygnał, co w aplikacji, z której kancelaria
    /// przychodzi. Po przeczytaniu wiersz gaśnie (03.10.2026).
    public static let chatGreen = Color(hex: 0x1DAA61)
    /// Dyskretna kropka „bez odpowiedzi” przy przeczytanej rozmowie.
    public static let chatAwaitingDot = Color(hex: 0xA9B6C6)
    /// Wzór tła historii rozmowy (kropki jak tapeta WhatsAppa, bardzo cicho).
    public static let chatWallpaperDot = Color(hex: 0xD9DFE7)
    /// Cień dymka zamiast obramowania.
    public static let bubbleShadow = Color(hex: 0x1A2E47).opacity(0.07)
    /// Wiadomość, której Emma nie umie pokazać (ankieta, zdjęcie jednorazowe…).
    public static let chatNoticeBackground = Color(hex: 0xFBF4E6)
    public static let chatNoticeBorder = Color(hex: 0xEEDDBB)
    public static let chatNoticeText = Color(hex: 0x7A5A26)
    /// Karta pliku: kolor znacznika rozszerzenia.
    public static let filePDF = Color(hex: 0xC8463D)
    public static let fileWord = Color(hex: 0x2F64B5)
    public static let fileSheet = Color(hex: 0x23824F)
    public static let fileOther = Color(hex: 0x6B7C92)
    /// Kafel zdjęcia/filmu bez podglądu.
    public static let mediaTileStart = Color(hex: 0xDCE6F2)
    public static let mediaTileEnd = Color(hex: 0xC9D7E8)
    /// Ptaszki „odczytane” na liście — błękit WhatsAppa.
    public static let chatReadTicks = Color(hex: 0x53BDEB)
    public static let chatDayChip = Color(hex: 0xE5EAF0)
    public static let chatDayChipText = Color(hex: 0x4E6882)
    public static let dictationAccent = Color(hex: 0x9A622C)
    // Tłumaczenia wiadomości usunięte z interfejsu na życzenie właściciela
    // (zespół rozumie uk/ru) — tokeny `.bubble-translation` świadomie bez
    // odpowiedników. Rejestr: docs/ios/DESIGN_DEVIATIONS.md.

    // Status i komunikaty
    public static let danger = critical
    public static let toastBackground = Color(hex: 0x213953)
    public static let pillNeutralBackground = Color(hex: 0xF0F3FC)
    public static let pillNeutralText = Color(hex: 0x5770AB)
    public static let pillGreenBackground = positiveSoft
    public static let pillGreenText = positive
    public static let pillAmberBackground = warningSoft
    public static let pillAmberText = warning
    public static let pillUrgentBackground = warningSoft
    public static let pillUrgentText = warning
    /// Plakietka „termin dziś / za 2 dni” na liście spraw — jedyny czerwony
    /// akcent listy, żeby pilna sprawa nie wyglądała jak „czeka na klienta”.
    public static let pillDangerBackground = criticalSoft
    public static let pillDangerText = critical

    // Awatary
    // Tokeny awatara zalogowanego użytkownika (`avatarBackground`/`avatarText`)
    // usunięte razem z plakietką „KR” w nagłówkach — konto jest jedno i wspólne.
    public static let personAvatarBackground = Color(hex: 0xEAF0F4)
    public static let personAvatarText = Color(hex: 0x4E6882)

    // Kalendarz
    public static let daySelected = Color(hex: 0x1C314B)
    public static let daySelectedNumber = Color.white
    public static let daySelectedLabel = Color(hex: 0xBFCCDF)
    public static let dayTodayDot = Color(hex: 0x8BA0B7)
    public static let weekControlBackground = Color(hex: 0xEDF1F5)
    public static let weekControlText = Color(hex: 0x526F91)

    // Pasek zakładek
    public static let tabBarBackground = Color(hex: 0xFBFCFD)
    public static let tabBarBorder = Color(hex: 0xE1E7EE)
    public static let tabActive = accent
    public static let tabInactive = Color(hex: 0x5F6D7D)
    public static let tabEmmaChip = emma
    public static let tabEmmaChipText = Color.white

    // Pozostałe
    public static let contextStripBackground = Color(hex: 0xEAF0F6)
    public static let contextStripText = Color(hex: 0x526F91)
    public static let contextStripBorder = Color(hex: 0xDFE7EF)
    public static let activityMarker = Color(hex: 0xA6B5C7)
    /// `.case-emma` — początek gradientu tła (110°)
    public static let emmaGradientStart = Color(hex: 0xEAF0F6)
    /// `.case-emma` — koniec gradientu tła
    public static let emmaGradientEnd = Color(hex: 0xF6F8FA)
    /// `.case-emma` — obramowanie karty
    public static let caseEmmaBorder = Color(hex: 0xDFE7EF)
    /// `.case-emma small` — podtytuł karty
    public static let caseEmmaSubtitle = Color(hex: 0x526F91)
    /// `.case-emma>svg` — ikona odsłuchu
    public static let caseEmmaIcon = Color(hex: 0x557799)
    public static let linkedCaseBackground = Color(hex: 0xEDF2F8)
    public static let linkedCaseBorder = Color(hex: 0xDCE5F0)
    public static let draftBackground = Color(hex: 0xFAFCFE)
    public static let draftBorder = Color(hex: 0xDBE5EE)
    public static let actionCardBorder = Color(hex: 0xCCDBE9)

    /// Stały ton awatara osoby (`IdentityTone`): stonowane pary tło/tekst
    /// w rodzinie kolorów aplikacji — rozróżniają osoby, nie krzyczą.
    /// Review 27.09.2026, odstępstwo D-34.
    public static func identityAvatar(_ index: Int) -> (background: Color, foreground: Color) {
        switch index % IdentityTone.count {
        case 1: return (Color(hex: 0xEFE6DA), Color(hex: 0x86653F))
        case 2: return (Color(hex: 0xF0E3E8), Color(hex: 0x8E5A6E))
        case 3: return (Color(hex: 0xE2ECE4), Color(hex: 0x4F7560))
        case 4: return (Color(hex: 0xE8E5F3), Color(hex: 0x5E5692))
        case 5: return (Color(hex: 0xE0ECEF), Color(hex: 0x3F6F7B))
        default: return (Color(hex: 0xE3EAF4), Color(hex: 0x40628F))
        }
    }

    // MARK: Asystent i dok głosowy
    //
    // Wartości odczytane z kaskady CSS referencji. Zebrane tutaj, bo rozsiane po
    // widokach prywatne kolory rozjeżdżają się przy pierwszej zmianie wzorca.

    /// `.emma-intro p`
    public static let emmaIntroText = Color(hex: 0x5F6D7D)
    /// `.emma-turn` — obramowanie wypowiedzi
    public static let emmaTurnBorder = Color(hex: 0xE4EAF1)
    /// `.emma-turn > span` — kto mówi
    public static let emmaTurnLabel = Color(hex: 0x526F91)
    /// `.listen-text` — „Odsłuchaj”
    public static let emmaListenText = Color(hex: 0x5F80A2)
    /// `.emma-suggestions button svg`
    public static let emmaSuggestionIcon = Color(hex: 0x6383A4)
    /// `.emma-suggestions button svg:last-child`
    public static let emmaSuggestionChevron = Color(hex: 0x9EAFBF)
    /// `.emma-suggestions small`
    public static let emmaSuggestionSubtitle = Color(hex: 0x66768B)
    /// `.voice-status-line`
    public static let emmaStatusText = Color(hex: 0x536B88)
    /// `.demo-foot` — nota o danych przykładowych
    public static let emmaDemoFootText = Color(hex: 0x5F6D7D)
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
    public static let dockStatusText = Color(hex: 0x5F6D7D)
    /// `.voice-controls-row .text-button`
    public static let dockActionText = Color(hex: 0x4C7399)
    /// `.emma-action-heading span:first-child`
    public static let actionHeadingText = Color(hex: 0x526F91)
    /// `.action-meta`
    public static let actionMetaText = Color(hex: 0x66768B)
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
