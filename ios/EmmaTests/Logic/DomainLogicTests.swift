import XCTest
@testable import Emma

// MARK: - Daty kalendarzowe (§12.2)
//
// Arytmetyka daty lokalnej nie może zależeć od strefy ani od europejskiej zmiany czasu.

final class LocalDateTests: XCTestCase {

    func testEpochAndFixtureDates() {
        XCTAssertEqual(LocalDate(year: 1970, month: 1, day: 1).daysSinceEpoch, 0)
        XCTAssertEqual(DemoFixtures.referenceDay.daysSinceEpoch, 20707)
    }

    func testMondayFirstWeekdayIndex() {
        XCTAssertEqual(DemoFixtures.weekStart.weekdayIndexMondayFirst, 0, "2026-09-07 to poniedziałek")
        XCTAssertEqual(DemoFixtures.referenceDay.weekdayIndexMondayFirst, 4, "2026-09-11 to piątek")
        XCTAssertTrue(LocalDate(year: 2026, month: 9, day: 12).isWeekend)
    }

    func testRoundTripAcrossLongRange() {
        // 73 049 dni: 1900-01-01 … 2099-12-31. Każdy dzień musi wrócić identyczny.
        var date = LocalDate(year: 1900, month: 1, day: 1)
        let end = LocalDate(year: 2099, month: 12, day: 31)
        var count = 0
        while date <= end {
            let roundTripped = LocalDate(daysSinceEpoch: date.daysSinceEpoch)
            XCTAssertEqual(roundTripped, date, "Nieudane przejście dla \(date.isoString)")
            date = date.adding(days: 1)
            count += 1
        }
        XCTAssertEqual(count, 73_049)
    }

    func testLeapYearDaysInMonth() {
        XCTAssertEqual(LocalDate(year: 2024, month: 2, day: 1).daysInMonth, 29)
        XCTAssertEqual(LocalDate(year: 2100, month: 2, day: 1).daysInMonth, 28)
        XCTAssertEqual(LocalDate(year: 2026, month: 9, day: 1).daysInMonth, 30)
        XCTAssertEqual(LocalDate(year: 2026, month: 12, day: 1).daysInMonth, 31)
    }

    func testWeekStartForEveryDayOfWeek() {
        for offset in 0..<7 {
            let date = DemoFixtures.weekStart.adding(days: offset)
            XCTAssertEqual(date.startOfWeekMonday, DemoFixtures.weekStart)
        }
        // Następny tydzień zaczyna się 7 dni później.
        XCTAssertEqual(DemoFixtures.weekStart.adding(days: 7).startOfWeekMonday, DemoFixtures.weekStart.adding(days: 7))
    }

    func testInvalidISODatesAreRejected() {
        XCTAssertNil(LocalDate(iso: "2026-13-01"))
        XCTAssertNil(LocalDate(iso: "2026-02-30"))
        XCTAssertNil(LocalDate(iso: "26-09-11"))
        XCTAssertNil(LocalDate(iso: "2026-09-11T10:30:00Z"))
        XCTAssertEqual(LocalDate(iso: "2026-09-11"), DemoFixtures.referenceDay)
    }

    func testTimeOfDayValidation() {
        XCTAssertNil(TimeOfDay(hhmm: "24:00"))
        XCTAssertNil(TimeOfDay(hhmm: "9:30"))
        XCTAssertEqual(TimeOfDay(hhmm: "10:30")?.minutes, 630)
        XCTAssertEqual(TimeOfDay(hhmm: "10:30")?.hhmm, "10:30")
    }

    func testLocalDateCodableUsesCanonicalForm() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(DemoFixtures.referenceDay)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"2026-09-11\"")
        let decoded = try JSONDecoder().decode(LocalDate.self, from: data)
        XCTAssertEqual(decoded, DemoFixtures.referenceDay)

        let invalid = "\"11.09.2026\"".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(LocalDate.self, from: invalid))
    }
}

// MARK: - Nieprzeczytane wiadomości (§3.3, §12.2)

final class ReadStateTests: XCTestCase {

    private func state(cursor: Int, manualUnread: Bool = false) -> ThreadUserState {
        ThreadUserState(
            userID: .tomasz,
            threadID: DemoFixtures.andriiThread,
            readCursorSequence: cursor,
            manualUnread: manualUnread
        )
    }

    private var andriiMessages: [Message] {
        DemoFixtures.messages.filter { $0.threadID == DemoFixtures.andriiThread }
    }

    func testIncomingMessagesAboveCursorAreUnread() {
        let unread = ReadStatePolicy.unreadMessages(in: andriiMessages, state: state(cursor: 1))
        XCTAssertEqual(unread.map(\.sequence), [2])
    }

    func testOutgoingClosureCountsAsReadForItsAuthor() throws {
        // Dmytro ma wiadomość przychodzącą i wychodzącą, obie poniżej kursora.
        let messages = DemoFixtures.messages.filter { $0.threadID == DemoFixtures.dmytroThread }
        let unread = ReadStatePolicy.unreadMessages(in: messages, state: state(cursor: 3))
        XCTAssertTrue(unread.isEmpty)
    }

    func testOutgoingMessageIsNeverCountedAsUnread() {
        // Nawet przy kursorze 0 wiadomość wychodząca nie jest nieprzeczytana.
        let messages = DemoFixtures.messages.filter { $0.threadID == DemoFixtures.dmytroThread }
        let unread = ReadStatePolicy.unreadMessages(in: messages, state: state(cursor: 0))
        XCTAssertEqual(unread.map(\.sequence), [1], "Tylko wiadomość przychodząca liczy się jako nieprzeczytana")
    }

    func testCursorNeverMovesPastKnownSnapshot() {
        // Otwarcie wątku z niepełną historią nie może oznaczyć nieznanych wiadomości.
        let cursor = ReadStatePolicy.cursorAfterOpeningThread(current: 0, snapshotSequenceAtOpen: 1)
        XCTAssertEqual(cursor, 1)
        let unread = ReadStatePolicy.unreadMessages(in: andriiMessages, state: state(cursor: cursor))
        XCTAssertEqual(unread.map(\.sequence), [2], "Wiadomość spoza snapshotu pozostaje nieprzeczytana")
    }

    func testCursorNeverGoesBackwards() {
        let cursor = ReadStatePolicy.cursorAfterOpeningThread(current: 7, snapshotSequenceAtOpen: 2)
        XCTAssertEqual(cursor, 7)
    }

    func testManualUnreadIsSeparateFromUnreadCount() {
        let readMessages = DemoFixtures.messages.filter { $0.threadID == DemoFixtures.dmytroThread }
        let flagged = state(cursor: 3, manualUnread: true)
        XCTAssertEqual(ReadStatePolicy.unreadCount(in: readMessages, state: flagged), 1)
        // Nie powstaje fałszywa wiadomość i nie pojawia się separator nowych wiadomości.
        XCTAssertTrue(ReadStatePolicy.unreadMessages(in: readMessages, state: flagged).isEmpty)
        XCTAssertNil(ReadStatePolicy.firstUnreadMessageID(in: readMessages, state: flagged))
    }

    func testFirstUnreadSeparatorPointsAtOldestUnread() {
        let first = ReadStatePolicy.firstUnreadMessageID(in: andriiMessages, state: state(cursor: 0))
        XCTAssertEqual(first, MessageID("msg-andrii-1"))
    }

    func testCursorsOfTwoLawyersAreIndependent() {
        var states = DemoFixtures.threadStates
        // Punkt odniesienia bierzemy z danych, a nie z założenia, że obaj prawnicy
        // mają identyczny stan — w demo mają różny (Paweł ma Andriia za sobą).
        let pawelBefore = states
            .first { $0.userID == .pawel && $0.threadID == DemoFixtures.andriiThread }?
            .readCursorSequence
        let tomaszBefore = states
            .first { $0.userID == .tomasz && $0.threadID == DemoFixtures.andriiThread }?
            .readCursorSequence

        states = ReadStatePolicy.markRead(
            states: states,
            userID: .tomasz,
            threadID: DemoFixtures.andriiThread,
            snapshotSequence: 2
        )

        let tomaszAfter = states
            .first { $0.userID == .tomasz && $0.threadID == DemoFixtures.andriiThread }?
            .readCursorSequence
        let pawelAfter = states
            .first { $0.userID == .pawel && $0.threadID == DemoFixtures.andriiThread }?
            .readCursorSequence

        XCTAssertEqual(tomaszAfter, 2)
        XCTAssertNotEqual(tomaszBefore, tomaszAfter, "Odczyt Tomasza musi przesunąć jego kursor")
        XCTAssertEqual(pawelAfter, pawelBefore, "Odczyt Tomasza nie zaznacza wiadomości Pawłowi")
    }

    func testOpeningThreadClearsManualUnreadFlag() {
        var states = DemoFixtures.threadStates
        if let index = states.firstIndex(where: { $0.userID == .tomasz && $0.threadID == DemoFixtures.mariaThread }) {
            states[index].manualUnread = true
        }
        states = ReadStatePolicy.markRead(
            states: states,
            userID: .tomasz,
            threadID: DemoFixtures.mariaThread,
            snapshotSequence: 1
        )
        let state = states.first { $0.userID == .tomasz && $0.threadID == DemoFixtures.mariaThread }
        XCTAssertEqual(state?.manualUnread, false)
        XCTAssertEqual(state?.readCursorSequence, 1)
    }
}

// MARK: - Porządkowanie wiadomości i statusów (§9.2, §12.2)

final class MessageOrderingTests: XCTestCase {

    func testStatusesOnlyImprove() {
        XCTAssertEqual(MessageOrdering.applyingStatus(.delivered, to: .sent), .delivered)
        XCTAssertEqual(MessageOrdering.applyingStatus(.read, to: .delivered), .read)
        // Zdarzenie poza kolejnością nie cofa interfejsu.
        XCTAssertEqual(MessageOrdering.applyingStatus(.sent, to: .read), .read)
        XCTAssertEqual(MessageOrdering.applyingStatus(.delivered, to: .read), .read)
        XCTAssertEqual(MessageOrdering.applyingStatus(.accepted, to: .delivered), .delivered)
    }

    func testUnknownAndFailedAreDecisionsNotProgress() {
        XCTAssertEqual(MessageOrdering.applyingStatus(.unknown, to: .read), .unknown)
        XCTAssertEqual(MessageOrdering.applyingStatus(.failed, to: .delivered), .failed)
        // Późniejsze „sent” nie przykrywa niepewnego wyniku.
        XCTAssertEqual(MessageOrdering.applyingStatus(.sent, to: .unknown), .unknown)
        XCTAssertEqual(MessageOrdering.applyingStatus(.read, to: .failed), .failed)
    }

    func testAcceptedIsNotDelivered() {
        XCTAssertFalse(MessageTransport.accepted.isProviderConfirmed == false)
        XCTAssertNotEqual(MessageTransport.accepted, .delivered)
        XCTAssertEqual(MessageTransport.accepted.displayName, "Przyjęta przez WhatsApp")
        XCTAssertEqual(MessageTransport.unknown.displayName, "Sprawdzamy status wysyłki")
    }

    func testSortingIsStableOnEqualTimestamps() {
        let base = Date(timeIntervalSince1970: 1_789_100_000)
        let messages = [
            Message(
                id: MessageID("b"), threadID: DemoFixtures.olenaThread, direction: .incoming,
                authorID: nil, text: "b", sentAt: base, sequence: 2, transport: .delivered, source: .demoFixture
            ),
            Message(
                id: MessageID("a"), threadID: DemoFixtures.olenaThread, direction: .incoming,
                authorID: nil, text: "a", sentAt: base, sequence: 1, transport: .delivered, source: .demoFixture
            )
        ]
        XCTAssertEqual(MessageOrdering.sorted(messages).map(\.sequence), [1, 2])
    }

    func testConversationSortPinsFirstThenLatestActivity() {
        let newer = MessageOrdering.conversationSortKey(
            lastMessage: DemoFixtures.messages[1],
            state: ThreadUserState(userID: .tomasz, threadID: DemoFixtures.olenaThread),
            threadID: DemoFixtures.olenaThread
        )
        let pinnedOld = MessageOrdering.conversationSortKey(
            lastMessage: DemoFixtures.messages[0],
            state: ThreadUserState(userID: .tomasz, threadID: DemoFixtures.andriiThread, isPinned: true),
            threadID: DemoFixtures.andriiThread
        )
        XCTAssertTrue(pinnedOld < newer, "Przypięty wątek jest wyżej mimo starszej wiadomości")
    }

    func testConversationSortIsDeterministicWithoutMessages() {
        let a = MessageOrdering.conversationSortKey(
            lastMessage: nil,
            state: ThreadUserState(userID: .tomasz, threadID: DemoFixtures.mariaThread),
            threadID: DemoFixtures.mariaThread
        )
        let b = MessageOrdering.conversationSortKey(
            lastMessage: nil,
            state: ThreadUserState(userID: .tomasz, threadID: DemoFixtures.olenaThread),
            threadID: DemoFixtures.olenaThread
        )
        XCTAssertNotEqual(a, b)
        XCTAssertTrue([a, b].sorted() == [a, b].sorted(), "Sortowanie pustych wątków jest powtarzalne")
    }

    func testProviderDeduplication() {
        let existing = DemoFixtures.messages
        XCTAssertTrue(
            ProviderIngest.isDuplicate(
                providerMessageID: "wamid.demo.andrii.1",
                sequence: 99,
                existing: existing
            )
        )
        XCTAssertTrue(
            ProviderIngest.isDuplicate(
                providerMessageID: "wamid.new.unknown",
                sequence: 1,
                existing: existing
            ),
            "Ten sam numer ingestu w istniejącym wątku to duplikat"
        )
        XCTAssertFalse(
            ProviderIngest.isDuplicate(
                providerMessageID: "wamid.new.unknown",
                sequence: 4242,
                existing: existing
            )
        )
    }

    func testEchoFromBusinessAppKeepsUnknownAuthorLabel() {
        let echo = DemoFixtures.messages.first { $0.source == .whatsAppBusinessEcho }
        XCTAssertNotNil(echo)
        XCTAssertNil(echo?.authorID, "Echo nie może udawać zalogowanego adwokata")
        XCTAssertEqual(echo?.outgoingAuthorLabel, "WhatsApp Business")
    }

    func testClientAudioIsNotALawyerTurn() {
        let attachment = Message(
            id: MessageID("msg-audio-1"),
            threadID: DemoFixtures.olenaThread,
            direction: .incoming,
            authorID: nil,
            kind: .audio,
            text: "Załącznik głosowy od klientki",
            sentAt: Date(timeIntervalSince1970: 1_789_100_000),
            sequence: 10,
            transport: .delivered,
            source: .clientMedia
        )
        XCTAssertEqual(attachment.source, .clientMedia)
        XCTAssertNotEqual(attachment.source, .appVoice)
        XCTAssertFalse(attachment.isOutgoing)
    }
}

// MARK: - Potwierdzenia i negacje (§8.2)

final class ConfirmationPhrasesTests: XCTestCase {

    func testExplicitFormsAreRecognised() {
        XCTAssertEqual(ConfirmationPhrases.classify("Wyślij tę wiadomość"), .explicitConfirmation)
        XCTAssertEqual(ConfirmationPhrases.classify("Отправь это сообщение"), .explicitConfirmation)
        XCTAssertEqual(ConfirmationPhrases.classify("wyślij tę wiadomość"), .explicitConfirmation)
    }

    func testBareAffirmationIsNotEnough() {
        XCTAssertEqual(ConfirmationPhrases.classify("tak"), .bareAffirmation)
        XCTAssertEqual(ConfirmationPhrases.classify("да"), .bareAffirmation)
    }

    func testCorrectionAndNegation() {
        XCTAssertEqual(ConfirmationPhrases.classify("tak, ale po piątej"), .correction)
        XCTAssertEqual(ConfirmationPhrases.classify("nie wysyłaj"), .negation)
        XCTAssertEqual(ConfirmationPhrases.classify("не отправляй"), .negation)
        XCTAssertEqual(ConfirmationPhrases.classify("popraw godzinę na 11:00"), .correction)
    }

    func testQuotedAffirmationIsData() {
        XCTAssertEqual(ConfirmationPhrases.classify("Klient napisał „tak, pasuje”"), .quotedData)
        XCTAssertEqual(ConfirmationPhrases.classify("«да» — tak odpowiedział klient"), .quotedData)
    }

    func testNeitherForUnrelatedText() {
        XCTAssertEqual(ConfirmationPhrases.classify("przygotuj odpowiedź"), .neither)
        XCTAssertEqual(ConfirmationPhrases.classify(""), .neither)
    }
}

// MARK: - Rozpoznawanie pisma i języka (§5.1)

final class ScriptDetectionTests: XCTestCase {

    func testPolishAndCyrillicDetection() {
        XCTAssertEqual(LanguageCode.detectedScript(of: "Zażółć gęślą jaźń"), .latin)
        XCTAssertEqual(LanguageCode.detectedScript(of: "Доброго дня, мого брата затримали"), .cyrillic)
        XCTAssertEqual(LanguageCode.detectedScript(of: "Дякую, надішлю документи"), .cyrillic)
        XCTAssertEqual(LanguageCode.detectedScript(of: "Olena Kovalenko"), .latin)
        XCTAssertEqual(LanguageCode.detectedScript(of: "Olena прізвище"), .mixed)
        XCTAssertEqual(LanguageCode.detectedScript(of: "12:30"), .unknown)
    }

    func testUkrainianCodeIsUKNeverUA() {
        XCTAssertEqual(LanguageCode.uk.rawValue, "uk")
        XCTAssertEqual(LanguageCode.uk.speechLocaleIdentifier, "uk-UA")
        XCTAssertNil(LanguageCode(lenient: "ua"))
        XCTAssertEqual(LanguageCode(lenient: "uk-UA"), .uk)
        XCTAssertEqual(LanguageCode(lenient: "RU"), .ru)
    }
}

// MARK: - Formatowanie

final class FormattingTests: XCTestCase {

    func testPolishPluralRules() {
        XCTAssertEqual(EmmaPlural.form(1, "zadanie", "zadania", "zadań"), "zadanie")
        XCTAssertEqual(EmmaPlural.form(2, "zadanie", "zadania", "zadań"), "zadania")
        XCTAssertEqual(EmmaPlural.form(4, "zadanie", "zadania", "zadań"), "zadania")
        XCTAssertEqual(EmmaPlural.form(5, "zadanie", "zadania", "zadań"), "zadań")
        XCTAssertEqual(EmmaPlural.form(12, "zadanie", "zadania", "zadań"), "zadań")
        XCTAssertEqual(EmmaPlural.form(13, "zadanie", "zadania", "zadań"), "zadań")
        XCTAssertEqual(EmmaPlural.form(22, "zadanie", "zadania", "zadań"), "zadania")
        XCTAssertEqual(EmmaPlural.consultations(3), "3 konsultacje")
        XCTAssertEqual(EmmaPlural.openTasks(5), "5 zadań do wykonania")
    }

    func testDayLabelsRelativeToClock() {
        let formatter = DateTextFormatter(today: DemoFixtures.referenceDay)
        XCTAssertEqual(formatter.dayLabel(DemoFixtures.referenceDay), "Dzisiaj")
        XCTAssertEqual(formatter.dayLabel(DemoFixtures.referenceDay.adding(days: 1)), "Jutro")
        XCTAssertEqual(formatter.dayLabel(DemoFixtures.referenceDay.adding(days: -1)), "Wczoraj")
        XCTAssertEqual(formatter.dayLabel(LocalDate(year: 2026, month: 9, day: 20)), "20 wrz")
        XCTAssertEqual(formatter.headline(for: DemoFixtures.referenceDay), "PIĄTEK, 11 WRZEŚNIA")
        XCTAssertEqual(formatter.monthTitle(for: DemoFixtures.referenceDay), "Wrzesień 2026")
        XCTAssertEqual(formatter.weekdayShort(for: DemoFixtures.weekStart), "Pn")
    }

    func testTimeAndDurationLabel() {
        let formatter = DateTextFormatter(today: DemoFixtures.referenceDay)
        XCTAssertEqual(formatter.timeAndDuration(TimeOfDay(hhmm: "10:30")!, minutes: 30), "10:30 · 30 min")
    }
}

// MARK: - Trasa audio i poufny odsłuch (§5.7)

final class AudioRoutePolicyTests: XCTestCase {

    func testHeadphonesDisconnectPausesSensitivePlayback() {
        XCTAssertEqual(
            AudioRoutePolicy.decision(previous: .headphones, current: .builtInSpeaker, isSensitivePlaybackActive: true),
            .pausePlaybackAndAsk
        )
        XCTAssertEqual(
            AudioRoutePolicy.decision(previous: .bluetooth, current: .builtInSpeaker, isSensitivePlaybackActive: true),
            .pausePlaybackAndAsk
        )
    }

    func testNoPauseWhenNothingSensitiveIsPlaying() {
        XCTAssertEqual(
            AudioRoutePolicy.decision(previous: .headphones, current: .builtInSpeaker, isSensitivePlaybackActive: false),
            .noChange
        )
    }

    func testConnectingHeadphonesDoesNotPause() {
        XCTAssertEqual(
            AudioRoutePolicy.decision(previous: .builtInSpeaker, current: .headphones, isSensitivePlaybackActive: true),
            .continuePlayback
        )
    }

    func testPrivateRouteClassification() {
        XCTAssertTrue(AudioRoute.headphones.isPrivate)
        XCTAssertTrue(AudioRoute.bluetooth.isPrivate)
        XCTAssertFalse(AudioRoute.builtInSpeaker.isPrivate)
        XCTAssertFalse(AudioRoute.builtInReceiver.isPrivate)
    }
}

// MARK: - Rozpoznawanie osoby (§4.3)

final class PersonResolverTests: XCTestCase {

    func testUniqueNameResolves() {
        XCTAssertEqual(
            PersonResolver.resolve("Przygotuj odpowiedź do Oleny", among: DemoFixtures.clients),
            .resolved(DemoFixtures.olenaID)
        )
    }

    func testUnknownNameDoesNotGuess() {
        XCTAssertEqual(
            PersonResolver.resolve("Napisz do Kowalskiego", among: DemoFixtures.clients),
            .unknown
        )
    }

    func testNoPersonMentioned() {
        XCTAssertEqual(PersonResolver.resolve("Co mam dzisiaj?", among: DemoFixtures.clients), .unknown)
    }
}

// MARK: - Kontekst asystenta (§5.2)

final class AssistantContextTests: XCTestCase {

    func testCaseMustBelongToClient() {
        let context = AssistantContext(scope: .legalCase, clientID: DemoFixtures.dmytroID, caseID: DemoFixtures.caseOlenaID)
        let result = AssistantContext.validate(
            context,
            clients: DemoFixtures.clients,
            cases: DemoFixtures.cases,
            threads: DemoFixtures.threads
        )
        XCTAssertEqual(result, .rejected("Sprawa należy do innego klienta."))
    }

    func testThreadMustBelongToClient() {
        let context = AssistantContext(scope: .thread, clientID: DemoFixtures.olenaID, threadID: DemoFixtures.andriiThread)
        let result = AssistantContext.validate(
            context,
            clients: DemoFixtures.clients,
            cases: DemoFixtures.cases,
            threads: DemoFixtures.threads
        )
        XCTAssertEqual(result, .rejected("Wątek należy do innego klienta."))
    }

    func testConsistentContextIsAccepted() {
        let context = AssistantContext.thread(
            DemoFixtures.olenaThread,
            clientID: DemoFixtures.olenaID,
            caseID: DemoFixtures.caseOlenaID,
            threadVersion: Version(3)
        )
        XCTAssertEqual(
            AssistantContext.validate(
                context,
                clients: DemoFixtures.clients,
                cases: DemoFixtures.cases,
                threads: DemoFixtures.threads
            ),
            .accepted
        )
    }

    func testClientScopeRequiresClient() {
        let context = AssistantContext(scope: .client)
        let result = AssistantContext.validate(
            context,
            clients: DemoFixtures.clients,
            cases: DemoFixtures.cases,
            threads: DemoFixtures.threads
        )
        XCTAssertEqual(result, .rejected("Kontekst klienta wymaga wskazania klienta."))
    }
}
