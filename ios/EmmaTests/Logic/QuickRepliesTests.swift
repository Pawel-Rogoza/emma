import XCTest
@testable import Emma

final class QuickRepliesTests: XCTestCase {

    func testEveryLanguageHasSameLabelsInSameOrder() {
        let labels = LanguageCode.allCases.map { QuickReplies.templates(for: $0).map(\.label) }
        XCTAssertFalse(labels[0].isEmpty)
        for other in labels.dropFirst() {
            XCTAssertEqual(other, labels[0], "Chipy muszą wyglądać tak samo niezależnie od języka klienta")
        }
    }

    func testTemplatesAreWrittenInClientLanguage() {
        let cyrillic = CharacterSet(charactersIn: "\u{0400}"..."\u{04FF}")
        for language in [LanguageCode.uk, .ru] {
            for reply in QuickReplies.templates(for: language) {
                XCTAssertNotNil(reply.text.rangeOfCharacter(from: cyrillic), "\(language): \(reply.label) nie jest cyrylicą")
            }
        }
        for reply in QuickReplies.templates(for: .pl) {
            XCTAssertNil(reply.text.rangeOfCharacter(from: cyrillic))
        }
        // Ukraiński to nie rosyjski: „і/ї/є” tylko w ukraińskim.
        XCTAssertTrue(QuickReplies.templates(for: .uk).contains { $0.text.contains("і") })
        XCTAssertFalse(QuickReplies.templates(for: .ru).contains { $0.text.contains("і") })
    }

    // MARK: Język odpowiedzi (02.10.2026): polski albo rosyjski, nigdy ukraiński

    func testReplyLanguageFollowsHowTheClientWrites() {
        XCTAssertEqual(ReplyLanguage.forReply(clientLanguage: .uk, lastIncomingText: "Dzień dobry, mam pytanie"), .pl)
        XCTAssertEqual(ReplyLanguage.forReply(clientLanguage: .pl, lastIncomingText: "Доброго дня, мого брата затримали"), .ru)
        XCTAssertEqual(ReplyLanguage.forReply(clientLanguage: .pl, lastIncomingText: "Здравствуйте, нужна консультация"), .ru)
    }

    func testReplyLanguageNeverUkrainianWithoutMessages() {
        XCTAssertEqual(ReplyLanguage.forReply(clientLanguage: .uk, lastIncomingText: nil), .ru)
        XCTAssertEqual(ReplyLanguage.forReply(clientLanguage: .ru, lastIncomingText: "👍"), .ru)
        XCTAssertEqual(ReplyLanguage.forReply(clientLanguage: .pl, lastIncomingText: "+48 600 100 200"), .pl)
        for language in LanguageCode.allCases {
            XCTAssertNotEqual(ReplyLanguage.forReply(clientLanguage: language, lastIncomingText: nil), .uk)
        }
    }
}
