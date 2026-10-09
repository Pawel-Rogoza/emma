import Foundation

// MARK: - Rozmówca spoza kartoteki
//
// Decyzja właściciela 03.10.2026: „Rozmowy” nie dzielą ludzi na tych z kartoteki
// i resztę. Numer kancelarii jest służbowy, więc każda rozmowa jest zwykłym
// wierszem i otwiera zwykły wątek z odpowiedzią. Osoba spoza kartoteki to
// „kontakt WhatsApp”: nazwa z WhatsAppa albo numer — bez wymyślonej sprawy,
// etapu czy notatek. Identyfikator jest pochodną wątku (`wa-…`), więc nigdy
// nie trafi do kartoteki ani nie pomyli się z klientem lub leadem z serwera.

extension ClientID {

    static let whatsAppContactPrefix = "wa-"

    /// Rozmówca wątku bez osoby w kartotece.
    public static func whatsAppContact(_ threadID: ThreadID) -> ClientID {
        ClientID(whatsAppContactPrefix + threadID.rawValue)
    }

    /// Kontakt WhatsApp spoza kartoteki — bez karty klienta, spraw i notatek.
    public var isWhatsAppContact: Bool { rawValue.hasPrefix(Self.whatsAppContactPrefix) }
}

extension Client {

    public var isWhatsAppContact: Bool { id.isWhatsAppContact }

    /// Rozmówca spoza kartoteki jako osoba rozmowy. Język zostaje polski —
    /// odpowiedź i tak dobiera `ReplyLanguage` z tego, jak ktoś pisze.
    public static func whatsAppContact(_ conversation: UnassignedConversation, createdAt: LocalDate) -> Client {
        Client(
            id: .whatsAppContact(conversation.threadID),
            displayName: conversation.name,
            initials: ChatIdentity.initials(conversation.name),
            language: .pl,
            topic: conversation.email == nil ? "Spoza kartoteki" : "E-mail spoza kartoteki",
            stage: .new,
            source: .whatsApp,
            createdAt: createdAt,
            briefing: "",
            phone: conversation.phone.isEmpty ? nil : conversation.phone
        )
    }
}

extension ConversationThread {

    /// Wątek rozmówcy spoza kartoteki.
    public static func whatsAppContact(_ conversation: UnassignedConversation) -> ConversationThread {
        ConversationThread(
            id: conversation.threadID,
            clientID: .whatsAppContact(conversation.threadID),
            sequenceHighWatermark: conversation.preview?.sequence ?? 0,
            emailAddress: conversation.email
        )
    }
}

// MARK: - Rozpoznawanie osoby bez zdjęcia
//
// WhatsApp Business API nie udostępnia zdjęć profilowych. Zamiast samej
// sylwetki awatar mówi to, po czym kancelaria naprawdę rozpoznaje ludzi:
// inicjały (gdy jest imię), końcówkę numeru (trzy ostatnie cyfry — jak
// „ten z 709”) i flagę kraju numeru, gdy nie jest polski.

public enum ChatIdentity {

    /// Inicjały z nazwy („Olena Kowalenko” → „OK”, „Ołeh” → „O”). Pusto dla
    /// samego numeru.
    public static func initials(_ name: String) -> String {
        let words = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .filter { word in word.unicodeScalars.contains { $0.properties.isAlphabetic } }
        let letters = words.prefix(2).compactMap { word in
            word.first { $0.unicodeScalars.allSatisfy { $0.properties.isAlphabetic } }
        }
        return letters.map { String($0).uppercased() }.joined()
    }

    /// Czy „nazwa” to w rzeczywistości sam numer (brak liter).
    public static func isBareNumber(_ name: String) -> Bool {
        !name.unicodeScalars.contains { $0.properties.isAlphabetic }
    }

    /// Trzy ostatnie cyfry numeru („+48 579 910 709” → „709”).
    public static func phoneSuffix(_ phone: String?) -> String? {
        guard let phone else { return nil }
        let digits = phone.filter { ("0"..."9").contains($0) }
        guard digits.count >= 6 else { return nil }
        return String(digits.suffix(3))
    }

    /// Kod kraju numeru (ISO 3166) dla krajów, z których piszą klienci
    /// kancelarii. `nil` dla nieznanego prefiksu — lepiej nic niż zła flaga.
    public static func countryCode(phone: String?) -> String? {
        guard let phone, let digits = ContactLinks.internationalDigits(phone) else { return nil }
        // Najdłuższe prefiksy najpierw: „380” przed „38”, „77” przed „7”.
        let prefixes: [(String, String)] = [
            ("380", "UA"), ("375", "BY"), ("373", "MD"), ("374", "AM"), ("994", "AZ"),
            ("995", "GE"), ("996", "KG"), ("992", "TJ"), ("993", "TM"), ("998", "UZ"),
            ("370", "LT"), ("371", "LV"), ("372", "EE"), ("420", "CZ"), ("421", "SK"),
            ("359", "BG"), ("381", "RS"),
            ("76", "KZ"), ("77", "KZ"), ("7", "RU"),
            ("48", "PL"), ("49", "DE"), ("40", "RO"), ("90", "TR"), ("44", "GB"),
            ("43", "AT"), ("39", "IT"), ("34", "ES"), ("33", "FR"), ("31", "NL"),
            ("32", "BE"), ("46", "SE"), ("47", "NO"), ("45", "DK"), ("36", "HU"),
            ("91", "IN"), ("86", "CN"), ("84", "VN"), ("63", "PH"), ("1", "US"),
        ]
        return prefixes.first { digits.hasPrefix($0.0) }?.1
    }

    /// Flaga kraju numeru, ale nie dla polskiego — przy polskich numerach
    /// byłaby wszędzie i nic by nie mówiła.
    public static func foreignFlag(phone: String?) -> String? {
        guard let code = countryCode(phone: phone), code != "PL" else { return nil }
        return flag(code)
    }

    static func flag(_ isoCode: String) -> String {
        isoCode.uppercased().unicodeScalars
            .compactMap { Unicode.Scalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }
}

extension MessageKind {

    /// Zdjęcie, film, naklejka — kafel zamiast wiersza pliku.
    public var hasMediaTile: Bool {
        self == .image || self == .video || self == .sticker
    }
}

// MARK: - Wiadomości, których Emma nie pokaże

extension Message {

    /// Serwer zapisuje jako `system` wiadomości, których WhatsApp nie oddaje
    /// przez API (ankieta, zdjęcie „do jednorazowego wyświetlenia”, usunięta
    /// lub edytowana wiadomość, wydarzenie). Treść jest tylko w WhatsAppie.
    public var isUnavailableInApp: Bool {
        kind == .system && text.localizedCaseInsensitiveContains("nieobsługiwana")
    }

    /// Rozszerzenie pliku do znacznika na karcie („PDF”, „DOCX”).
    public var attachmentExtension: String? {
        guard let name = attachmentName, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let ext = name[name.index(after: dot)...]
        guard (1...5).contains(ext.count), ext.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return ext.uppercased()
    }
}

// MARK: - Układ historii rozmowy
//
// Kolejne wiadomości jednej strony w krótkim odstępie tworzą grupę — jak
// w WhatsAppie: mniejszy odstęp, „ogonek” dymka tylko przy ostatniej
// wiadomości grupy. Dzięki temu długie wymiany czyta się jak rozmowę,
// a nie jak listę osobnych kart.

public enum ChatLayout {

    /// Maksymalna przerwa między wiadomościami jednej grupy.
    public static let groupingInterval: TimeInterval = 5 * 60

    public struct Position: Equatable, Sendable {
        /// Pierwsza wiadomość grupy (większy odstęp nad nią).
        public let startsGroup: Bool
        /// Ostatnia wiadomość grupy (ogonek dymka).
        public let endsGroup: Bool
    }

    /// Pozycja wiadomości w grupie. `messages` — posortowane chronologicznie.
    public static func position(at index: Int, in messages: [Message], calendar: Calendar = .current) -> Position {
        let message = messages[index]
        let previous = index > 0 ? messages[index - 1] : nil
        let next = index + 1 < messages.count ? messages[index + 1] : nil
        return Position(
            startsGroup: !continues(previous, into: message, calendar: calendar),
            endsGroup: !continues(message, into: next, calendar: calendar)
        )
    }

    private static func continues(_ earlier: Message?, into later: Message?, calendar: Calendar) -> Bool {
        guard let earlier, let later else { return false }
        guard earlier.direction == later.direction,
              earlier.kind != .system, later.kind != .system,
              calendar.isDate(earlier.sentAt, inSameDayAs: later.sentAt) else { return false }
        return later.sentAt.timeIntervalSince(earlier.sentAt) <= groupingInterval
    }

    /// Wiadomość z samych emoji (1–3) — pokazujemy ją dużą, bez dymka.
    public static func isEmojiOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 3 else { return false }
        return trimmed.allSatisfy { character in
            guard let first = character.unicodeScalars.first else { return false }
            // Cyfry i „#” też mają właściwość emoji — liczy się tylko obraz.
            return first.properties.isEmojiPresentation
                || (first.properties.isEmoji && character.unicodeScalars.count > 1)
        }
    }
}
