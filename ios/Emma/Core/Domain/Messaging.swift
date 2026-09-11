import Foundation

// MARK: - Kierunek i pochodzenie wiadomości

public enum MessageDirection: String, Codable, Sendable {
    case incoming
    case outgoing
}

/// Kto wprowadził wiadomość do systemu. Przy koegzystencji wiadomość wysłana
/// z Business App może nie mieć znanego autora wśród braci (§4.3) — wtedy
/// pokazujemy „WhatsApp Business”, a nie zalogowaną osobę.
public enum MessageSource: String, Codable, Sendable {
    /// Ręcznie zatwierdzona treść z aplikacji.
    case app
    /// Potwierdzona akcja voice (ten sam backendowy action engine).
    case appVoice
    /// Wiadomość przychodząca z WhatsApp Cloud API.
    case whatsAppInbound
    /// Echo wiadomości wysłanej z Business App przy koegzystencji.
    case whatsAppBusinessEcho
    /// Treść demo. Nie występuje w trybie live.
    case demoFixture
    /// Załącznik/treść źródłowa od klienta (audio). Transkrypcja ma `source=clientMedia`,
    /// nigdy `authenticatedLawyerTurn` (§5.1).
    case clientMedia
}

/// Stan transportu (§3.3 pkt 11). `accepted` **nie** znaczy `delivered`.
public enum MessageTransport: String, Codable, Sendable, CaseIterable {
    /// Lokalny szkic — wiadomość jeszcze nie istnieje po stronie backendu.
    case localDraft
    /// Wysłana do backendu, oczekuje na przyjęcie.
    case pending
    /// Trwa wysyłanie.
    case sending
    /// Przyjęta przez API dostawcy. To nie jest dostarczenie.
    case accepted
    case sent
    case delivered
    case read
    /// Potwierdzony błąd.
    case failed
    /// Wynik nieznany (timeout po możliwym przyjęciu). Bez automatycznego retry (§8.3).
    case unknown

    public var displayName: String {
        switch self {
        case .localDraft: return "Szkic lokalny"
        case .pending: return "Oczekuje"
        case .sending: return "Wysyłanie"
        case .accepted: return "Przyjęta przez WhatsApp"
        case .sent: return "Wysłano"
        case .delivered: return "Dostarczono"
        case .read: return "Odczytano"
        case .failed: return "Błąd wysyłki"
        case .unknown: return "Sprawdzamy status wysyłki"
        }
    }

    /// Kolejność postępu. Użyta do odrzucania zdarzeń statusu wychodzących poza kolejnością.
    public var progressRank: Int {
        switch self {
        case .localDraft: return 0
        case .pending: return 1
        case .sending: return 2
        case .accepted: return 3
        case .sent: return 4
        case .delivered: return 5
        case .read: return 6
        case .unknown: return -1 // poza monotonicznym postępem
        case .failed: return -2
        }
    }

    /// Czy status pochodzi z rzeczywistego zdarzenia dostawcy, czy z symulacji demo.
    public var isProviderConfirmed: Bool {
        switch self {
        case .accepted, .sent, .delivered, .read: return true
        default: return false
        }
    }

    /// Znaczniki w interfejsie: brak, jeden lub dwa znaczniki.
    public enum ReceiptGlyph: Sendable { case none, clock, single, double }
    public var receiptGlyph: ReceiptGlyph {
        switch self {
        case .localDraft, .pending, .sending: return .clock
        case .accepted, .sent: return .single
        case .delivered, .read: return .double
        default: return .none
        }
    }
}

public enum MessageKind: String, Codable, Sendable {
    case text
    case image
    case document
    case audio
    case video
    case sticker
    case location
    case system
}

/// Cytat wiadomości. Zniknięcie cytowanej wiadomości **nie** kieruje odpowiedzi
/// do innego wątku (§3.3 pkt 9) — pokazujemy niedostępną referencję.
public struct QuotedReference: Hashable, Codable, Sendable {
    public var messageID: MessageID?
    public var authorLabel: String
    public var text: String
    public var isAvailable: Bool

    public init(messageID: MessageID?, authorLabel: String, text: String, isAvailable: Bool = true) {
        self.messageID = messageID
        self.authorLabel = authorLabel
        self.text = text
        self.isAvailable = isAvailable
    }
}

public struct Message: Identifiable, Hashable, Codable, Sendable {
    public let id: MessageID
    public var threadID: ThreadID
    public var direction: MessageDirection
    /// Autor, jeśli znany. `nil` przy echu z Business App lub nieznanym nadawcy.
    public var authorID: UserID?
    /// Etykieta autora do prezentacji, gdy autor nie jest znanym adwokatem.
    public var authorLabel: String?
    /// Identyfikator wiadomości u dostawcy (deduplikacja).
    public var providerMessageID: String?
    public var kind: MessageKind
    public var text: String
    public var translation: String?
    public var quote: QuotedReference?
    /// Znacznik czasu dostawcy. Sam w sobie **nie wystarcza** do liczenia nieprzeczytanych (§3.3 pkt 2).
    public var sentAt: Date
    /// Monotoniczny numer ingestu po stronie serwera.
    public var sequence: Int
    public var transport: MessageTransport
    public var source: MessageSource
    public var version: Version

    public init(
        id: MessageID,
        threadID: ThreadID,
        direction: MessageDirection,
        authorID: UserID?,
        authorLabel: String? = nil,
        providerMessageID: String? = nil,
        kind: MessageKind = .text,
        text: String,
        translation: String? = nil,
        quote: QuotedReference? = nil,
        sentAt: Date,
        sequence: Int,
        transport: MessageTransport,
        source: MessageSource,
        version: Version = .initial
    ) {
        self.id = id
        self.threadID = threadID
        self.direction = direction
        self.authorID = authorID
        self.authorLabel = authorLabel
        self.providerMessageID = providerMessageID
        self.kind = kind
        self.text = text
        self.translation = translation
        self.quote = quote
        self.sentAt = sentAt
        self.sequence = sequence
        self.transport = transport
        self.source = source
        self.version = version
    }

    /// Autor do pokazania w dymku wychodzącym.
    public var outgoingAuthorLabel: String {
        if let authorID { return OwnerName.of(authorID) }
        if let authorLabel { return authorLabel }
        return "WhatsApp Business"
    }

    public var isOutgoing: Bool { direction == .outgoing }
}

// MARK: - Wątek

public struct ConversationThread: Identifiable, Hashable, Codable, Sendable {
    public let id: ThreadID
    public var clientID: ClientID
    /// Najwyższy znany numer ingestu w tym wątku.
    public var sequenceHighWatermark: Int
    public var version: Version

    public init(id: ThreadID, clientID: ClientID, sequenceHighWatermark: Int, version: Version = .initial) {
        self.id = id
        self.clientID = clientID
        self.sequenceHighWatermark = sequenceHighWatermark
        self.version = version
    }
}

/// Stan użytkownika w wątku. Tomasz i Paweł mają **osobne** kursory, przypięcia
/// i szkice (§3.3 pkt 3).
public struct ThreadUserState: Hashable, Codable, Sendable {
    public var userID: UserID
    public var threadID: ThreadID
    /// Jawny kursor użytkownika: wszystkie wiadomości przychodzące o
    /// `sequence <= readCursorSequence` są przeczytane przez tego użytkownika.
    public var readCursorSequence: Int
    /// Osobny znacznik przypomnienia — nie mylić z nieprzeczytanymi (§3.3 pkt 2).
    public var manualUnread: Bool
    public var isPinned: Bool
    public var draft: Draft?

    public init(
        userID: UserID,
        threadID: ThreadID,
        readCursorSequence: Int = 0,
        manualUnread: Bool = false,
        isPinned: Bool = false,
        draft: Draft? = nil
    ) {
        self.userID = userID
        self.threadID = threadID
        self.readCursorSequence = readCursorSequence
        self.manualUnread = manualUnread
        self.isPinned = isPinned
        self.draft = draft
    }
}

/// Szkic zawiera tekst, język, odbiorcę/wątek, opcjonalny cytat i wersję (§3.3 pkt 8).
public struct Draft: Hashable, Codable, Sendable {
    public var threadID: ThreadID
    public var text: String
    /// Język dyktowania/szkicu wybrany jawnie; nie dziedziczymy go po kliencie (§5.1).
    public var language: LanguageCode
    public var quote: QuotedReference?
    public var version: Version
    public var updatedAt: Date

    public init(
        threadID: ThreadID,
        text: String,
        language: LanguageCode,
        quote: QuotedReference? = nil,
        version: Version = .initial,
        updatedAt: Date = Date()
    ) {
        self.threadID = threadID
        self.text = text
        self.language = language
        self.quote = quote
        self.version = version
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

// MARK: - Reguły nieprzeczytanych wiadomości
//
// Otwarcie końca rozmowy oznacza jako przeczytane wiadomości do **jawnie znanego**
// snapshotu sekwencji. Samo odświeżenie listy, pobranie w tle ani przeglądanie
// starszej strony nie przesuwa kursora do końca (§3.3 pkt 1).

public enum ReadStatePolicy {

    /// Kursor, jaki powstaje po otwarciu wątku przy znanym snapshocie końca.
    /// Nigdy nie cofa kursora i nigdy nie wyprzedza znanego snapshotu.
    public static func cursorAfterOpeningThread(
        current: Int,
        snapshotSequenceAtOpen: Int
    ) -> Int {
        max(current, snapshotSequenceAtOpen)
    }

    /// Wiadomości nieprzeczytane dla danego użytkownika.
    /// Reguła: wyłącznie kierunek przychodzący i `sequence` większa od kursora.
    public static func unreadMessages(
        in messages: [Message],
        state: ThreadUserState
    ) -> [Message] {
        messages.filter { message in
            message.direction == .incoming && message.sequence > state.readCursorSequence
        }
    }

    /// Licznik prezentowany na liście i w pasku zakładek.
    /// `manualUnread` podnosi wynik do co najmniej 1, nie tworzy fałszywej wiadomości.
    public static func unreadCount(in messages: [Message], state: ThreadUserState) -> Int {
        let natural = unreadMessages(in: messages, state: state).count
        if natural > 0 { return natural }
        return state.manualUnread ? 1 : 0
    }

    /// Pierwsza wiadomość, nad którą rysujemy separator „Nowe wiadomości”.
    /// `nil`, gdy nie ma nic nowego.
    public static func firstUnreadMessageID(in messages: [Message], state: ThreadUserState) -> MessageID? {
        unreadMessages(in: messages, state: state)
            .min(by: { $0.sequence < $1.sequence })?
            .id
    }

    /// Kursory Tomasza i Pawła są niezależne: odczyt jednego **nie** zmienia drugiego.
    public static func markRead(
        states: [ThreadUserState],
        userID: UserID,
        threadID: ThreadID,
        snapshotSequence: Int
    ) -> [ThreadUserState] {
        states.map { state in
            guard state.userID == userID, state.threadID == threadID else { return state }
            var updated = state
            updated.readCursorSequence = cursorAfterOpeningThread(
                current: state.readCursorSequence,
                snapshotSequenceAtOpen: snapshotSequence
            )
            updated.manualUnread = false
            return updated
        }
    }
}

// MARK: - Porządkowanie wiadomości i statusów

public enum MessageOrdering {

    /// Kolejność prezentacji: czas dostawcy, potem numer ingestu jako rozstrzygnięcie remisu.
    public static func sorted(_ messages: [Message]) -> [Message] {
        messages.sorted { lhs, rhs in
            if lhs.sentAt != rhs.sentAt { return lhs.sentAt < rhs.sentAt }
            return lhs.sequence < rhs.sequence
        }
    }

    /// Status dostarczenia może się wyłącznie poprawić. Zdarzenie statusu poza kolejnością
    /// (np. `sent` po `read`) nie cofa interfejsu (§9.2).
    public static func applyingStatus(
        _ newStatus: MessageTransport,
        to current: MessageTransport
    ) -> MessageTransport {
        // Wynik nieznany i błąd to stany decyzyjne, nie postęp — nadpisują postęp.
        if newStatus == .unknown || newStatus == .failed { return newStatus }
        guard current != .unknown && current != .failed else { return current }
        return newStatus.progressRank >= current.progressRank ? newStatus : current
    }

    /// Sortowanie listy rozmów: przypięte na górze, potem ostatnia wiadomość,
    /// z deterministycznym rozstrzygnięciem remisów (§3.3 pkt 6).
    public static func conversationSortKey(
        lastMessage: Message?,
        state: ThreadUserState,
        threadID: ThreadID
    ) -> ConversationSortKey {
        ConversationSortKey(
            isPinned: state.isPinned,
            lastActivity: lastMessage?.sentAt ?? .distantPast,
            lastSequence: lastMessage?.sequence ?? -1,
            tieBreaker: threadID.rawValue
        )
    }

    public struct ConversationSortKey: Comparable, Sendable {
        public var isPinned: Bool
        public var lastActivity: Date
        public var lastSequence: Int
        public var tieBreaker: String

        public static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.lastActivity != rhs.lastActivity { return lhs.lastActivity > rhs.lastActivity }
            if lhs.lastSequence != rhs.lastSequence { return lhs.lastSequence > rhs.lastSequence }
            return lhs.tieBreaker < rhs.tieBreaker
        }
    }
}

// MARK: - Deduplikacja dostawcy

public enum ProviderIngest {
    /// Wiadomość dostawcy jest odrzucana jako duplikat, jeśli znamy już jej
    /// identyfikator u dostawcy **albo** ten sam numer ingestu (§9.2).
    public static func isDuplicate(
        providerMessageID: String?,
        sequence: Int,
        existing: [Message]
    ) -> Bool {
        for message in existing {
            if let providerMessageID, message.providerMessageID == providerMessageID { return true }
            if message.sequence == sequence { return true }
        }
        return false
    }
}
