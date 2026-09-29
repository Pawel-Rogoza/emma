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
