import Foundation

// MARK: - Gotowe odpowiedzi w wątku
//
// Audyt 28.09.2026: adwokat pisze klientom w kółko te same krótkie wiadomości —
// „oddzwonimy”, „proszę przesłać dokumenty”, „potwierdzamy termin”. Szablon
// wstawia się do pola w **języku klienta** (etykieta chipu zostaje po polsku)
// i nic nie wysyła sam: tekst da się poprawić przed wysłaniem.
//
// Kancelaria pisze w liczbie mnogiej („oddzwonimy”), więc szablon nie zależy
// od płci osoby wysyłającej.

// MARK: - Język odpowiedzi
//
// Zasada kancelarii (02.10.2026): klient piszący po polsku dostaje odpowiedź
// po polsku, a piszący po ukraińsku albo rosyjsku — po rosyjsku. Po ukraińsku
// kancelaria nie odpisuje. Decyduje to, w jakim alfabecie klient faktycznie
// napisał ostatnią wiadomość; język z kartoteki jest tylko zapasem, gdy
// wiadomości od klienta jeszcze nie ma.

public enum ReplyLanguage {

    /// Język odpowiedzi: zawsze `.pl` albo `.ru`, nigdy `.uk`.
    public static func forReply(clientLanguage: LanguageCode, lastIncomingText: String?) -> LanguageCode {
        if let text = lastIncomingText, let detected = detect(text) { return detected }
        return clientLanguage == .pl ? .pl : .ru
    }

    /// Ta sama zasada na wiadomościach wątku (ostatnia od klienta z tekstem).
    public static func forReply(clientLanguage: LanguageCode, messages: [Message]) -> LanguageCode {
        let lastIncoming = messages.last { !$0.isOutgoing && $0.kind == .text && detect($0.text) != nil }
        return forReply(clientLanguage: clientLanguage, lastIncomingText: lastIncoming?.text)
    }

    /// Cyrylica → rosyjski, łacinka → polski; `nil`, gdy w tekście nie ma liter
    /// (sama emotka, numer, załącznik).
    public static func detect(_ text: String) -> LanguageCode? {
        var cyrillic = 0
        var latin = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x0400...0x04FF: cyrillic += 1
            case 0x0041...0x024F: latin += 1
            default: break
            }
        }
        guard cyrillic + latin > 0 else { return nil }
        return cyrillic > latin ? .ru : .pl
    }
}

public struct QuickReply: Equatable, Sendable, Identifiable {
    /// Etykieta chipu (po polsku, dla adwokata).
    public let label: String
    /// Treść w języku klienta.
    public let text: String
    public var id: String { label }
}

public enum QuickReplies {

    public static func templates(for language: LanguageCode) -> [QuickReply] {
        switch language {
        case .pl:
            return [
                QuickReply(label: "Oddzwonimy", text: "Dzień dobry, oddzwonimy do Pana/Pani w ciągu godziny."),
                QuickReply(label: "Dokumenty", text: "Proszę przesłać w tej rozmowie zdjęcia dokumentów: paszport, kartę pobytu i otrzymane pisma."),
                QuickReply(label: "Potwierdzamy termin", text: "Potwierdzamy termin spotkania. Do zobaczenia!"),
                QuickReply(label: "Otrzymaliśmy", text: "Dziękujemy, otrzymaliśmy. Przeanalizujemy i wrócimy z odpowiedzią.")
            ]
        case .uk:
            return [
                QuickReply(label: "Oddzwonimy", text: "Добрий день! Ми передзвонимо Вам протягом години."),
                QuickReply(label: "Dokumenty", text: "Будь ласка, надішліть у цьому чаті фото документів: паспорт, карту побуту та отримані листи."),
                QuickReply(label: "Potwierdzamy termin", text: "Підтверджуємо час зустрічі. До зустрічі!"),
                QuickReply(label: "Otrzymaliśmy", text: "Дякуємо, отримали. Проаналізуємо та повернемося з відповіддю.")
            ]
        case .ru:
            return [
                QuickReply(label: "Oddzwonimy", text: "Здравствуйте! Мы перезвоним Вам в течение часа."),
                QuickReply(label: "Dokumenty", text: "Пожалуйста, пришлите в этом чате фото документов: паспорт, карту побыту и полученные письма."),
                QuickReply(label: "Potwierdzamy termin", text: "Подтверждаем время встречи. До встречи!"),
                QuickReply(label: "Otrzymaliśmy", text: "Спасибо, получили. Проанализируем и вернёмся с ответом.")
            ]
        }
    }
}
