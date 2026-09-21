import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Typografia
//
// Nazwy PostScript odczytane z tablicy `name` plików czcionek (ID 6), nie zgadywane:
//   DMSans-Regular, DMSans-Medium, DMSans-SemiBold, Manrope-Bold, Manrope-ExtraBold
//
// Zmierzona kontrola pokrycia glifów wykazała, że **DM Sans nie zawiera cyrylicy**,
// a Manrope zawiera. Dlatego `EmmaTypography.body(for:)` wybiera czcionkę jawnie:
// tekst łaciński — DM Sans (zgodnie z referencją), tekst cyrylicki — czcionka systemowa,
// dokładnie tak, jak robi to układ referencji `'DM Sans',-apple-system,…`.
// Szczegóły: docs/ios/DESIGN_CONTRACT.md §3 oraz DESIGN_DEVIATIONS.md (D-01).

public enum EmmaFontName {
    public static let dmSansRegular = "DMSans-Regular"
    public static let dmSansMedium = "DMSans-Medium"
    public static let dmSansSemiBold = "DMSans-SemiBold"
    public static let manropeBold = "Manrope-Bold"
    public static let manropeExtraBold = "Manrope-ExtraBold"

    /// Wszystkie nazwy czcionek wymagane przy starcie aplikacji. Używane przez
    /// kontrolę rejestracji czcionek z §2.3 planu.
    public static let all = [dmSansRegular, dmSansMedium, dmSansSemiBold, manropeBold, manropeExtraBold]
}

/// Waga czcionki z rodziny DM Sans.
public enum EmmaWeight: Sendable {
    case regular
    case medium
    case semibold

    public var postScriptName: String {
        switch self {
        case .regular: return EmmaFontName.dmSansRegular
        case .medium: return EmmaFontName.dmSansMedium
        case .semibold: return EmmaFontName.dmSansSemiBold
        }
    }

    /// Waga systemowa używana przy tekście cyrylickim (odpowiednik optyczny).
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

    // Plan wymaga, aby przy dużym Dynamic Type treść i obsługa zostały zachowane
    // (karty mogą urosnąć, nie wymagamy zgodności pikselowej z domyślnym rozmiarem).
    // Skalowanie dzieje się **tylko tutaj**: wszystkie style przechodzą przez trzy
    // konstruktory poniżej, więc żaden ekran nie musi o tym wiedzieć.
    //
    // Wszystkie style skalują się względem stylu treści `.body`. To świadomie jedna
    // krzywa zamiast dziewięciu: przewidywalne zachowanie jest ważniejsze niż
    // „optymalna” krzywa dla każdego rozmiaru. Przy domyślnej wielkości tekstu
    // wynik jest identyczny z referencją, bo mnożnik wynosi wtedy 1.
    //
    // Odstępy i szerokości pozostają stałe (siatka karty z referencji). Tekst rośnie,
    // a kontenery mają minimalne wysokości, więc treść nie jest obcinana.

    // MARK: Podstawa

    /// Czcionka treści z jawnym wyborem ze względu na pismo.
    /// To jedyne miejsce, w którym decydujemy, czy użyć DM Sans, czy czcionki systemowej.
    public static func body(for text: String, size: CGFloat, weight: EmmaWeight = .regular) -> Font {
        body(script: LanguageCode.detectedScript(of: text), size: size, weight: weight)
    }

    /// Wariant dla miejsc, w których pismo jest już znane.
    public static func body(script: ScriptKind, size: CGFloat, weight: EmmaWeight = .regular) -> Font {
        switch script {
        case .cyrillic, .mixed:
            // DM Sans nie ma glifów cyrylickich. Referencja w przeglądarce również
            // spada wtedy na `-apple-system`, więc zachowanie jest zgodne.
            #if canImport(UIKit)
            let font = UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
            return Font(UIFontMetrics(forTextStyle: .body).scaledFont(for: font))
            #else
            return .system(size: size, weight: weight.systemWeight)
            #endif
        case .latin, .unknown:
            return .custom(weight.postScriptName, size: size, relativeTo: .body)
        }
    }

    /// Czcionka interfejsu (etykiety, przyciski) — zawsze DM Sans.
    public static func ui(_ size: CGFloat, _ weight: EmmaWeight = .regular) -> Font {
        .custom(weight.postScriptName, size: size, relativeTo: .body)
    }

    /// Czcionka nagłówków — Manrope (obsługuje cyrylicę, więc nie ma wariantu).
    public static func heading(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom(
            bold ? EmmaFontName.manropeExtraBold : EmmaFontName.manropeBold,
            size: size,
            relativeTo: .body
        )
    }

    // MARK: Skala tekstu

    /// Metadana i podpis — **najniższy dopuszczalny rozmiar tekstu** w interfejsie.
    ///
    /// F09 audytu: dawne `ui(10…)`/`ui(11…)`/`ui(12…)` w ekranach dawały tekst
    /// 10–11 pt z kontrastem poniżej 4,5:1. Teraz każda metadana przechodzi przez
    /// ten styl (12 pt), więc skala jest jedna, a próg kontrastu dotyczy znanego
    /// rozmiaru. Ekrany nie deklarują już własnych rozmiarów.
    public static func caption(_ weight: EmmaWeight = .regular) -> Font { ui(12, weight) }

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
