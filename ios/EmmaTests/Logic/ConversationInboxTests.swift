import XCTest
@testable import Emma

/// Stany listy rozmów (przebudowa „Rozmów” 29.09.2026): czyj jest ruch.
final class ConversationInboxTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_789_100_000)

    private func message(
        _ sequence: Int,
        _ direction: MessageDirection,
        minutes: Double,
        transport: MessageTransport = .delivered
    ) -> Message {
        Message(
            id: MessageID("m-\(sequence)"),
            threadID: ThreadID("t"),
            direction: direction,
            authorID: direction == .outgoing ? .kancelaria : nil,
            text: "\(sequence)",
            sentAt: base.addingTimeInterval(minutes * 60),
            sequence: sequence,
            transport: transport,
            source: .demoFixture
        )
    }

    func testStatusFollowsUnreadThenLastMessage() {
        let incoming = message(1, .incoming, minutes: 0)
        let sent = message(2, .outgoing, minutes: 1, transport: .sent)
        let read = message(2, .outgoing, minutes: 1, transport: .read)

        XCTAssertEqual(ConversationInbox.status(lastMessage: incoming, unreadCount: 2), .unread)
        XCTAssertEqual(ConversationInbox.status(lastMessage: incoming, unreadCount: 0), .awaitingReply)
        XCTAssertEqual(ConversationInbox.status(lastMessage: sent, unreadCount: 0), .replied)
        XCTAssertEqual(ConversationInbox.status(lastMessage: read, unreadCount: 0), .seen)
        XCTAssertEqual(ConversationInbox.status(lastMessage: nil, unreadCount: 0), .empty)
        // Ręczne „nieprzeczytane” podnosi licznik — stan idzie za licznikiem.
        XCTAssertEqual(ConversationInbox.status(lastMessage: read, unreadCount: 1), .unread)
    }

    func testNeedsReplyOnlyWhenMoveIsOnFirmSide() {
        XCTAssertTrue(ConversationStatus.unread.needsReply)
        XCTAssertTrue(ConversationStatus.awaitingReply.needsReply)
        XCTAssertFalse(ConversationStatus.replied.needsReply)
        XCTAssertFalse(ConversationStatus.seen.needsReply)
        XCTAssertFalse(ConversationStatus.empty.needsReply)
    }

    func testWaitingStartsAtFirstClientMessageAfterOurReply() {
        let messages = [
            message(1, .incoming, minutes: 0),
            message(2, .outgoing, minutes: 5),
            message(3, .incoming, minutes: 10),
            message(4, .incoming, minutes: 12)
        ]
        XCTAssertEqual(ConversationInbox.waitingSince(messages), base.addingTimeInterval(600))
        XCTAssertNil(ConversationInbox.waitingSince(Array(messages.prefix(2))), "Ostatnie słowo nasze — nikt nie czeka")
        XCTAssertNil(ConversationInbox.waitingSince([]))
    }

    func testWaitingText() {
        XCTAssertEqual(ConversationInbox.waitingText(since: base, now: base.addingTimeInterval(20)), "przed chwilą")
        XCTAssertEqual(ConversationInbox.waitingText(since: base, now: base.addingTimeInterval(12 * 60)), "12 min")
        XCTAssertEqual(ConversationInbox.waitingText(since: base, now: base.addingTimeInterval(3 * 3600)), "3 godz.")
        XCTAssertEqual(ConversationInbox.waitingText(since: base, now: base.addingTimeInterval(26 * 3600)), "1 dzień")
        XCTAssertEqual(ConversationInbox.waitingText(since: base, now: base.addingTimeInterval(72 * 3600)), "3 dni")
        XCTAssertFalse(ConversationInbox.isWaitingLong(since: base, now: base.addingTimeInterval(59 * 60)))
        XCTAssertTrue(ConversationInbox.isWaitingLong(since: base, now: base.addingTimeInterval(60 * 60)))
    }

    /// Demo pokazuje wszystkie stany listy: dwie nowe, jedną do odpowiedzi
    /// i jedną odpisaną — bez tego ekran nie ma czego pokazać.
    func testDemoCoversEveryListState() async throws {
        let repository = MockRepository(dataset: DemoFixtures.dataset(), clock: DemoClock(), artificialLatency: 0)
        let states = try await repository.readStates(userID: .kancelaria)
        var statuses: [ThreadID: ConversationStatus] = [:]
        for thread in try await repository.threads() {
            let messages = MessageOrdering.sorted(try await repository.latestMessages(threadID: thread.id, limit: 60))
            let state = states.first { $0.threadID == thread.id }
                ?? ThreadUserState(userID: .kancelaria, threadID: thread.id)
            statuses[thread.id] = ConversationInbox.status(
                lastMessage: messages.last,
                unreadCount: ReadStatePolicy.unreadCount(in: messages, state: state)
            )
        }
        XCTAssertEqual(statuses[DemoFixtures.andriiThread], .unread)
        XCTAssertEqual(statuses[DemoFixtures.mariaThread], .unread)
        XCTAssertEqual(statuses[DemoFixtures.olenaThread], .awaitingReply)
        XCTAssertEqual(statuses[DemoFixtures.dmytroThread], .replied)
    }

    // MARK: Okno odpowiedzi WhatsApp

    func testReplyWindowRunsTwentyFourHoursFromLastClientMessage() {
        let messages = [
            message(1, .incoming, minutes: 0),
            message(2, .outgoing, minutes: 5),
            message(3, .incoming, minutes: 60)
        ]
        let until = base.addingTimeInterval(60 * 60 + ReplyWindow.duration)
        // Nasza odpowiedź nie przedłuża okna — liczy się wiadomość klienta.
        XCTAssertEqual(
            ReplyWindow.state(sortedMessages: messages, now: base.addingTimeInterval(120 * 60), isComplete: true),
            .open(until: until)
        )
        XCTAssertEqual(
            ReplyWindow.state(sortedMessages: messages, now: until, isComplete: true),
            .closed(since: until)
        )
    }

    func testReplyWindowWithoutClientMessageDependsOnCompleteness() {
        let ours = [message(1, .outgoing, minutes: 0)]
        XCTAssertEqual(ReplyWindow.state(sortedMessages: ours, now: base, isComplete: true), .closed(since: nil))
        XCTAssertEqual(
            ReplyWindow.state(sortedMessages: ours, now: base, isComplete: false),
            .unknown,
            "Starsza wiadomość klienta może być poza wczytaną stroną — nie blokujemy wysyłki"
        )
        XCTAssertFalse(ReplyWindow.unknown.isClosed)
    }

    func testReplyWindowWarnsInLastThreeHours() {
        let window = ReplyWindow.state(sortedMessages: [message(1, .incoming, minutes: 0)], now: base, isComplete: true)
        let hour: TimeInterval = 3600
        XCTAssertFalse(window.isClosingSoon(now: base.addingTimeInterval(20 * hour)))
        XCTAssertTrue(window.isClosingSoon(now: base.addingTimeInterval(21 * hour)))
        XCTAssertEqual(window.remainingText(now: base.addingTimeInterval(21 * hour)), "3 godz.")
        XCTAssertEqual(window.remainingText(now: base.addingTimeInterval(22 * hour + 45 * 60)), "1 godz. 15 min")
        XCTAssertEqual(window.remainingText(now: base.addingTimeInterval(23 * hour + 20 * 60)), "40 min")
        XCTAssertNil(ReplyWindow.closed(since: nil).remainingText(now: base))
    }

    // MARK: Odświeżanie otwartego wątku

    func testMergeAddsNewMessagesKeepsOlderAndNeverDowngradesStatus() {
        let older = message(1, .incoming, minutes: 0)
        let ours = message(2, .outgoing, minutes: 1, transport: .read)
        // Spóźnione zdarzenie „sent” po „read” w świeżej stronie.
        var staleStatus = ours
        staleStatus.transport = .sent
        let incoming = message(3, .incoming, minutes: 2)

        let merged = MessageOrdering.merged([older, ours], with: [staleStatus, incoming])

        XCTAssertEqual(merged.map(\.sequence), [1, 2, 3], "Starsza wiadomość spoza świeżej strony zostaje")
        XCTAssertEqual(merged[1].transport, .read, "Status dostarczenia się nie cofa")
    }

    func testMergeTakesDeliveryProgressFromFreshPage() {
        let sent = message(1, .outgoing, minutes: 0, transport: .sent)
        var delivered = sent
        delivered.transport = .delivered
        XCTAssertEqual(MessageOrdering.merged([sent], with: [delivered]).first?.transport, .delivered)
    }
}
