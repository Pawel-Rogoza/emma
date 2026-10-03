import XCTest
@testable import Emma

final class ChatPresentationTests: XCTestCase {

    // MARK: Rozmówca spoza kartoteki

    func testContactFromUnassignedConversationIsAnOrdinaryConversationPerson() {
        let conversation = UnassignedConversation(
            threadID: ThreadID("thread-8"),
            name: "Ołeh Hnatiuk",
            phone: "+380671112233",
            preview: nil
        )
        let client = Client.whatsAppContact(conversation, createdAt: LocalDate(year: 2026, month: 10, day: 3))
        XCTAssertEqual(client.id, ClientID("wa-thread-8"))
        XCTAssertTrue(client.isWhatsAppContact)
        XCTAssertEqual(client.displayName, "Ołeh Hnatiuk")
        XCTAssertEqual(client.initials, "OH")
        XCTAssertEqual(client.phone, "+380671112233")

        let thread = ConversationThread.whatsAppContact(conversation)
        XCTAssertEqual(thread.id, ThreadID("thread-8"))
        XCTAssertEqual(thread.clientID, client.id)
    }

    func testServerClientsAndLeadsAreNotContacts() {
        XCTAssertFalse(ClientID("client-3").isWhatsAppContact)
        XCTAssertFalse(ClientID("lead-9").isWhatsAppContact)
    }

    // MARK: Awatar bez zdjęcia

    func testInitialsSkipNumbersAndPunctuation() {
        XCTAssertEqual(ChatIdentity.initials("Olena Kowalenko-Nowak"), "OK")
        XCTAssertEqual(ChatIdentity.initials("Ołeh"), "O")
        XCTAssertEqual(ChatIdentity.initials("+48 579 910 709"), "")
        XCTAssertEqual(ChatIdentity.initials("Андрій Мельник"), "АМ")
    }

    func testPhoneSuffixIsLastThreeDigits() {
        XCTAssertEqual(ChatIdentity.phoneSuffix("+48 579 910 709"), "709")
        XCTAssertEqual(ChatIdentity.phoneSuffix("+380-67-111-22-33"), "233")
        XCTAssertNil(ChatIdentity.phoneSuffix("112"))
        XCTAssertNil(ChatIdentity.phoneSuffix(nil))
    }

    func testFlagOnlyForForeignNumbers() {
        XCTAssertNil(ChatIdentity.foreignFlag(phone: "+48 600 100 200"))
        XCTAssertNil(ChatIdentity.foreignFlag(phone: "600100200"), "9 cyfr bez prefiksu to numer polski")
        XCTAssertEqual(ChatIdentity.foreignFlag(phone: "+380671112233"), "🇺🇦")
        XCTAssertEqual(ChatIdentity.foreignFlag(phone: "+375291234567"), "🇧🇾")
        XCTAssertEqual(ChatIdentity.foreignFlag(phone: "+995555123456"), "🇬🇪")
        XCTAssertEqual(ChatIdentity.countryCode(phone: "+77011234567"), "KZ")
        XCTAssertEqual(ChatIdentity.countryCode(phone: "+79161234567"), "RU")
        XCTAssertNil(ChatIdentity.foreignFlag(phone: "+999123456789"), "Nieznany prefiks — bez flagi")
    }

    // MARK: Grupy dymków

    func testConsecutiveMessagesOfOneSideFormAGroup() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let messages = [
            message("1", .incoming, start),
            message("2", .incoming, start.addingTimeInterval(60)),
            message("3", .outgoing, start.addingTimeInterval(120)),
            message("4", .incoming, start.addingTimeInterval(180)),
            message("5", .incoming, start.addingTimeInterval(180 + ChatLayout.groupingInterval + 1)),
        ]
        let calendar = Calendar(identifier: .gregorian)
        let positions = messages.indices.map { ChatLayout.position(at: $0, in: messages, calendar: calendar) }
        XCTAssertEqual(positions.map(\.startsGroup), [true, false, true, true, true])
        XCTAssertEqual(positions.map(\.endsGroup), [false, true, true, true, true])
    }

    func testEmojiOnlyDetection() {
        XCTAssertTrue(ChatLayout.isEmojiOnly("👍"))
        XCTAssertTrue(ChatLayout.isEmojiOnly("🙏🙏"))
        XCTAssertTrue(ChatLayout.isEmojiOnly("❤️"))
        XCTAssertFalse(ChatLayout.isEmojiOnly("Ok 👍"))
        XCTAssertFalse(ChatLayout.isEmojiOnly("12"))
        XCTAssertFalse(ChatLayout.isEmojiOnly("👍👍👍👍"))
    }

    // MARK: Pliki i wiadomości niedostępne

    func testAttachmentExtensionAndUnavailableMessage() {
        var file = message("1", .incoming, Date())
        file.kind = .document
        file.attachmentName = "postanowienie sądu.pdf"
        XCTAssertEqual(file.attachmentExtension, "PDF")
        file.attachmentName = "bez rozszerzenia"
        XCTAssertNil(file.attachmentExtension)

        var unsupported = message("2", .incoming, Date())
        unsupported.kind = .system
        unsupported.text = "[Wiadomość nieobsługiwana w aplikacji — otwórz WhatsApp]"
        XCTAssertTrue(unsupported.isUnavailableInApp)
    }

    private func message(_ id: String, _ direction: MessageDirection, _ sentAt: Date) -> Message {
        Message(
            id: MessageID(id),
            threadID: ThreadID("thread-1"),
            direction: direction,
            authorID: nil,
            text: "Tekst \(id)",
            sentAt: sentAt,
            sequence: Int(id) ?? 0,
            transport: .delivered,
            source: direction == .incoming ? .whatsAppInbound : .app
        )
    }
}
