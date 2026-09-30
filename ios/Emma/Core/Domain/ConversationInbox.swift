import Foundation

// MARK: - Stan rozmowy na liście
//
// Przebudowa „Rozmów” 29.09.2026 (jak „Klienci”): lista ma odpowiadać na jedno
// pytanie — **czyj jest ruch**. Klient napisał i nikt nie przeczytał, klient
// czeka na odpowiedź, czy to my odpisaliśmy i czekamy na klienta. Reguła
// mieszka tutaj, a nie w widoku, bo te same stany liczą kafelki, chipy filtra
// i grupy listy — rozjechanie się liczb byłoby od razu widać.
//
// Nieprzeczytane liczy wyłącznie `ReadStatePolicy` (§3.3); tutaj tylko
// nazywamy stan na podstawie gotowego licznika i ostatniej wiadomości.

public enum ConversationStatus: String, Sendable, CaseIterable {
    /// Są nieprzeczytane wiadomości od klienta (albo ręczne „nieprzeczytane”).
    case unread
    /// Przeczytane, ale ostatnia wiadomość jest od klienta — ruch po naszej stronie.
    case awaitingReply
    /// Odpisaliśmy; klient jeszcze nie przeczytał odpowiedzi.
    case replied
    /// Odpisaliśmy i klient odczytał odpowiedź.
    case seen
    /// Wątek bez wiadomości.
    case empty

    /// Czy ruch jest po stronie kancelarii.
    public var needsReply: Bool {
        self == .unread || self == .awaitingReply
    }
}

public enum ConversationInbox {

    /// Stan wątku z ostatniej wiadomości i licznika nieprzeczytanych.
    public static func status(lastMessage: Message?, unreadCount: Int) -> ConversationStatus {
        if unreadCount > 0 { return .unread }
        guard let lastMessage else { return .empty }
        if !lastMessage.isOutgoing { return .awaitingReply }
        return lastMessage.transport == .read ? .seen : .replied
    }

    /// Od kiedy klient czeka na odpowiedź: pierwsza wiadomość klienta po naszej
    /// ostatniej odpowiedzi. `nil`, gdy ostatnie słowo należy do kancelarii.
    /// Oczekuje wiadomości w kolejności `MessageOrdering.sorted`.
    public static func waitingSince(_ sortedMessages: [Message]) -> Date? {
        guard let last = sortedMessages.last, !last.isOutgoing else { return nil }
        var since = last.sentAt
        for message in sortedMessages.reversed() {
            if message.isOutgoing { break }
            since = message.sentAt
        }
        return since
    }

    /// „przed chwilą”, „12 min”, „3 godz.”, „2 dni” — ile trwa czekanie.
    public static func waitingText(since: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(since) / 60))
        if minutes < 1 { return "przed chwilą" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) godz." }
        return EmmaPlural.days(hours / 24)
    }

    /// Klient czeka dłużej niż godzinę — licznik czekania robi się bursztynowy.
    public static func isWaitingLong(since: Date, now: Date) -> Bool {
        now.timeIntervalSince(since) >= 3600
    }
}

// MARK: - Okno odpowiedzi WhatsApp
//
// Meta pozwala wysłać zwykły tekst tylko przez 24 godziny od ostatniej
// wiadomości klienta; później przyjmuje wyłącznie zatwierdzony szablon (backend
// odrzuca wysyłkę kodem `window_closed`). Wcześniej aplikacja dowiadywała się
// o tym dopiero po naciśnięciu „Wyślij”. Teraz lista i wątek mówią o tym
// zawczasu: ile zostało do zamknięcia okna i kiedy trzeba już zadzwonić.

public enum ReplyWindow: Equatable, Sendable {
    /// Można odpisać zwykłym tekstem do podanej chwili.
    case open(until: Date)
    /// Okno minęło (`since`) albo klient nigdy nie napisał (`nil`).
    case closed(since: Date?)
    /// We wczytanym fragmencie nie ma wiadomości klienta, a starsze nie są
    /// znane — nie zgadujemy i nie blokujemy wysyłki.
    case unknown

    /// Czas okna obsługowego Meta.
    public static let duration: TimeInterval = 24 * 60 * 60
    /// Od kiedy ostrzegamy, że okno się zamyka.
    public static let warningLead: TimeInterval = 3 * 60 * 60

    /// Stan okna z wiadomości posortowanych jak `MessageOrdering.sorted`.
    /// `isComplete` — czy wczytano całą historię wątku (wtedy brak wiadomości
    /// klienta znaczy „nigdy nie napisał”, a nie „nie wiemy”).
    public static func state(sortedMessages: [Message], now: Date, isComplete: Bool) -> ReplyWindow {
        guard let lastCustomer = sortedMessages.last(where: { !$0.isOutgoing && $0.kind != .system }) else {
            return isComplete ? .closed(since: nil) : .unknown
        }
        let until = lastCustomer.sentAt.addingTimeInterval(duration)
        return until > now ? .open(until: until) : .closed(since: until)
    }

    public var isClosed: Bool {
        if case .closed = self { return true }
        return false
    }

    /// Okno otwarte, ale zamknie się w ciągu `warningLead`.
    public func isClosingSoon(now: Date) -> Bool {
        guard case .open(let until) = self else { return false }
        return until.timeIntervalSince(now) <= Self.warningLead
    }

    /// „2 godz. 15 min”, „40 min”, „chwilę” — ile zostało do zamknięcia okna.
    public func remainingText(now: Date) -> String? {
        guard case .open(let until) = self else { return nil }
        let minutes = Int(until.timeIntervalSince(now) / 60)
        if minutes < 1 { return "chwilę" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 || hours >= 3 ? "\(hours) godz." : "\(hours) godz. \(rest) min"
    }
}
