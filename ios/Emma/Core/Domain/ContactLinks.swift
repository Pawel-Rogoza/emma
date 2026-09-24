import Foundation

// MARK: - Telefon, WhatsApp i e-mail jednym dotknięciem
//
// Zgłoszenie ze strony to w praktyce „oddzwoń do tej osoby”. Bez numeru pod
// ręką trzeba było szukać go w panelu na komputerze. Gdy backend poda telefon,
// karta i lista proponują połączenie, WhatsApp i e-mail.
//
// Numer z formularza bywa zapisany dowolnie („600 100 200”, „+48 600-100-200”,
// „0048…”), więc normalizacja jest jedna i ma testy. Dziewięć cyfr bez prefiksu
// traktujemy jak numer polski — tak wpisuje go większość klientów kancelarii.

public enum ContactLinks {

    /// Numer w zapisie międzynarodowym, same cyfry bez „+” (np. `48600100200`).
    /// `nil`, gdy z napisu nie da się złożyć sensownego numeru.
    public static func internationalDigits(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var digits = trimmed.filter { ("0"..."9").contains($0) }
        if trimmed.hasPrefix("00") {
            digits = String(digits.dropFirst(2))
        } else if !trimmed.hasPrefix("+") && digits.count == 9 {
            digits = "48" + digits
        }
        guard (8...15).contains(digits.count) else { return nil }
        return digits
    }

    public static func phoneURL(_ raw: String) -> URL? {
        internationalDigits(raw).flatMap { URL(string: "tel:+\($0)") }
    }

    /// Rozmowa w aplikacji WhatsApp (poza Emmą — skrzynka WhatsApp w aplikacji
    /// nie jest jeszcze połączona z numerem kancelarii).
    public static func whatsAppURL(_ raw: String) -> URL? {
        internationalDigits(raw).flatMap { URL(string: "https://wa.me/\($0)") }
    }

    /// Adres pochodzi z publicznego formularza strony, więc jest niezaufany:
    /// `a@b.pl?bcc=obcy@x.pl&body=…` dopisałby do wiadomości ukrytego odbiorcę
    /// i treść, a przecinek — kolejnych adresatów. Przepuszczamy tylko jeden
    /// adres ze znaków dozwolonych w zwykłym e-mailu, bez `?`, `&`, `%`, `,`.
    public static func mailURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...64).contains(parts[0].count), (3...253).contains(parts[1].count),
              parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix(".") else { return nil }
        let localAllowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!#$'*+/=^_`{|}~-")
        let domainAllowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard parts[0].allSatisfy(localAllowed.contains), parts[1].allSatisfy(domainAllowed.contains) else { return nil }
        return URL(string: "mailto:\(trimmed)")
    }
}
