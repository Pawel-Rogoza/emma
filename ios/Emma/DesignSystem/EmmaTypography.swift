import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Typografia
//
// Redesign 0.22.0 (iOS 26): interfejs i treść piszemy **czcionką systemową
// (SF Pro)**. Wcześniej DM Sans z referencji HTML nie miała cyrylicy, więc
// rosyjskie imiona i wiadomości wpadały w SF Pro, a polskie w DM Sans — dwie
// czcionki w jednym wierszu listy. SF Pro ma polskie znaki i cyrylicę, cyfry
// tabelaryczne i pełny Dynamic Type.
//
// Manrope (ma cyrylicę) zostaje wyłącznie w dużych tytułach i liczbach-bohaterach
// — to jedyny akcent charakteru marki w typografii.

public enum EmmaFontName {
    public static let manropeBold = "Manrope-Bold"
    public static let manropeExtraBold = "Manrope-ExtraBold"

    /// Czcionki dołączone do aplikacji, sprawdzane przy starcie.
    public static let all = [manropeBold, manropeExtraBold]
}

/// Waga tekstu interfejsu.
public enum EmmaWeight: Sendable {
    case regular
    case medium
    case semibold

    public var systemWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        }
    }

    #if canImport(UIKit)
    /// Ten sam odpowiednik dla `UIFont`, potrzebny przy skalowaniu Dynamic Type.
    public var uiWeight: UIFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        }
    }
    #endif
}

public enum EmmaTypography {

    // MARK: Dynamic Type
    //
    // Wszystkie style skalują się względem stylu `.body` (jedna, przewidywalna
    // krzywa). Przy domyślnym rozmiarze tekstu mnożnik wynosi 1.

    // MARK: Podstawa

    /// Czcionka treści. Pismo nie ma już znaczenia — SF Pro obsługuje łacinę
    /// i cyrylicę — parametr `text` zostaje, żeby miejsca wywołań się nie zmieniały.
    public static func body(for text: String, size: CGFloat, weight: EmmaWeight = .regular) -> Font {
        system(size, weight)
    }

    /// Czcionka interfejsu (etykiety, przyciski, treść).
    public static func ui(_ size: CGFloat, _ weight: EmmaWeight = .regular) -> Font {
        system(size, weight)
    }

    /// Czcionka nagłówków — Manrope (obsługuje cyrylicę, więc nie ma wariantu).
    public static func heading(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom(
            bold ? EmmaFontName.manropeExtraBold : EmmaFontName.manropeBold,
            size: size,
            relativeTo: .body
        )
    }

    /// SF Pro w danym rozmiarze, skalowana z ustawieniem rozmiaru tekstu.
    private static func system(_ size: CGFloat, _ weight: EmmaWeight) -> Font {
        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        return Font(UIFontMetrics(forTextStyle: .body).scaledFont(for: font))
        #else
        return .system(size: size, weight: weight.systemWeight)
        #endif
    }

    // MARK: Skala tekstu

    /// Metadana i podpis — **najniższy dopuszczalny rozmiar tekstu** w interfejsie.
    ///
    /// F09 audytu: dawne `ui(10…)`/`ui(11…)`/`ui(12…)` w ekranach dawały tekst
    /// 10–11 pt z kontrastem poniżej 4,5:1. Teraz każda metadana przechodzi przez
    /// ten styl (12 pt), więc skala jest jedna, a próg kontrastu dotyczy znanego
    /// rozmiaru. Ekrany nie deklarują już własnych rozmiarów.
    public static func caption(_ weight: EmmaWeight = .regular) -> Font { ui(13, weight) }

    // MARK: Style interfejsu (DESIGN_CONTRACT §3)

    /// Nagłówek główny: „Dzień dobry, Tomaszu”.
    public static var welcome: Font { heading(25) }
    /// Kicker / data: „PIĄTEK, 11 WRZEŚNIA”.
    public static var kicker: Font { ui(12, .semibold) }
    /// Tytuł sekcji.
    public static var sectionTitle: Font { ui(16, .semibold) }
    /// Nazwa osoby w wierszu listy.
    public static var personName: Font { ui(15, .semibold) }
    /// Podtytuł wiersza listy.
    public static var personSubtitle: Font { caption() }
    /// Tytuł karty spotkania.
    public static var meetingTitle: Font { ui(14, .semibold) }
    /// Metadane w karcie.
    public static var meetingMeta: Font { ui(12) }
    /// Nagłówek szczegółu.
    public static var detailTitle: Font { ui(13, .semibold) }
    /// Podpis szczegółu.
    public static var detailCaption: Font { caption() }
    /// Hero klienta.
    public static var clientHero: Font { heading(24) }
    /// Tytuł sprawy.
    public static var caseTitle: Font { heading(25) }
    /// Numer sprawy.
    public static var caseNumber: Font { ui(12, .medium) }
    /// Tytuł zadania.
    public static var taskTitle: Font { ui(13, .medium) }
    /// Metadane zadania.
    public static var taskMeta: Font { ui(12) }
    /// Termin zadania.
    public static var taskDate: Font { ui(12) }
    /// Nazwa w liście rozmów.
    public static var threadName: Font { ui(16, .medium) }
    /// Czas w liście rozmów.
    public static var threadTime: Font { ui(12) }
    /// Podgląd wiadomości na liście.
    public static var threadPreview: Font { ui(14) }
    /// Nagłówek otwartego wątku.
    public static var chatHeader: Font { ui(16, .semibold) }
    /// Treść dymku.
    public static func bubbleText(_ text: String) -> Font { body(for: text, size: 16) }
    /// Cytat w dymku.
    public static func quotedText(_ text: String) -> Font { body(for: text, size: 13) }
    /// Metadane dymku.
    public static var bubbleMeta: Font { ui(12) }
    /// Separator dnia.
    public static var daySeparator: Font { ui(12, .medium) }
    /// Etykieta „Nowe wiadomości”.
    public static var unreadDivider: Font { ui(12, .medium) }
    /// Pole wiadomości.
    public static var composerField: Font { ui(16) }
    /// Wypowiedź Emmy w rozmowie z asystentem.
    public static func emmaBody(_ text: String) -> Font { body(for: text, size: 14) }
    /// Tytuł propozycji działania.
    public static var actionTitle: Font { ui(15, .semibold) }
    /// Treść propozycji.
    public static func actionBody(_ text: String) -> Font { body(for: text, size: 14) }
    /// Etykieta pola formularza.
    public static var fieldLabel: Font { caption(.medium) }
    /// Wartość pola formularza. 16 pt zapobiega automatycznemu powiększaniu
    /// widoku przy kursorze (iOS).
    public static var fieldValue: Font { ui(16) }
    /// Etykieta zakładki.
    public static var tabLabel: Font { ui(12, .medium) }
    /// Przycisk.
    public static var button: Font { ui(16, .semibold) }
    /// Pigułka statusu.
    public static var pill: Font { ui(12, .medium) }
    /// Pomocniczy tekst błędu.
    public static var error: Font { caption() }
    /// Tekst stanu pustego.
    public static var emptyState: Font { ui(13) }
}
