#if canImport(UIKit)
import UIKit

// MARK: - Kontrola rejestracji czcionek
//
// Referencja używa DM Sans i Manrope. Nazwy PostScript zostały odczytane
// z tablicy `name` plików czcionek, ale **obecność pliku w pakiecie nie jest
// dowodem, że czcionka jest zarejestrowana** — wymaga to wpisu `UIAppFonts`
// w Info.plist. Ta kontrola sprawdza to w czasie działania i zgłasza brak,
// zamiast po cichu podstawić czcionkę systemową.

enum EmmaFontRegistration {

    /// Nazwy wymagane przy starcie.
    static var required: [String] { EmmaFontName.all }

    /// Czcionki brakujące w systemie. Pusta lista oznacza poprawną konfigurację.
    static func missingFonts() -> [String] {
        required.filter { UIFont(name: $0, size: 12) == nil }
    }

    /// Sprawdzenie przy starcie. W buildzie debug brak czcionki jest głośno
    /// raportowany; w wydaniu nie zatrzymujemy aplikacji, bo tekst nadal
    /// pozostaje czytelny w czcionce systemowej (patrz D-01).
    static func verifyRegisteredFonts() {
        let missing = missingFonts()
        guard !missing.isEmpty else { return }
        #if DEBUG
        assertionFailure(
            """
            Nie zarejestrowano czcionek: \(missing.joined(separator: ", ")).
            Sprawdź wpis UIAppFonts w Info.plist i obecność plików w Resources/Fonts.
            """
        )
        #else
        NSLog("Emma: brak zarejestrowanych czcionek: %@", missing.joined(separator: ", "))
        #endif
    }
}
#endif
