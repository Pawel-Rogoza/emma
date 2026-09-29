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
