import XCTest
@testable import Emma

/// Profil sprawy, pilnowane daty (areszt, legalny pobyt) i terminy miesięczne.
final class CaseProfileTests: XCTestCase {

    private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: year, month: month, day: day)
    }

    private func legalCase(
        kind: CaseKind? = .criminal,
        status: CaseStatus = .inProgress,
        custodyUntil: LocalDate? = nil,
        legalStayUntil: LocalDate? = nil
    ) -> LegalCase {
        LegalCase(
            id: CaseID("case-1"), number: "KR/1", title: "Rozbój", clientID: ClientID("client-1"),
            status: status, summary: "", createdAt: day(2026, 9, 1),
            kind: kind, custodyUntil: custodyUntil, legalStayUntil: legalStayUntil
        )
    }

    // MARK: Terminy miesięczne

    func testMonthDeadlineEndsOnSameDateAndShiftsFromSaturday() {
        // 13.10 + 1 miesiąc = 13.11 (piątek) — bez przesunięcia.
        let plain = ProceduralDeadlines.due(from: day(2026, 10, 13), months: 1)
        XCTAssertEqual(plain.due, day(2026, 11, 13))
        XCTAssertFalse(plain.isShifted)
        // 31.01 + 1 miesiąc → ostatni dzień lutego (sobota 28.02) → poniedziałek 2.03.
        let shifted = ProceduralDeadlines.due(from: day(2026, 1, 31), months: 1)
        XCTAssertEqual(shifted.nominal, day(2026, 2, 28))
        XCTAssertEqual(shifted.due, day(2026, 3, 2))
        XCTAssertEqual(shifted.shiftReason, "sobota")
    }

    func testSubsidiaryIndictmentIsAMonthRule() throws {
        let rule = try XCTUnwrap(ProceduralDeadlines.common.first { $0.id == "kpk-subsydiarny" })
        XCTAssertEqual(rule.span, .months(1))
        XCTAssertEqual(rule.spanText, "1 miesiąc")
        XCTAssertEqual(ProceduralDeadlines.due(from: day(2026, 10, 13), rule: rule)?.due, day(2026, 11, 13))
        let hourly = try XCTUnwrap(ProceduralDeadlines.common.first { $0.isHourly })
        XCTAssertNil(ProceduralDeadlines.due(from: day(2026, 10, 13), rule: hourly))
    }

    func testSuggestedRulesFollowTheStageButKeepEverything() {
        let preTrial = ProceduralDeadlines.suggested(kind: .criminal, stage: .preTrial)
        XCTAssertEqual(preTrial.first?.id, "kpk-zatrzymanie-48")
        let trial = ProceduralDeadlines.suggested(kind: .criminal, stage: .firstInstance)
        XCTAssertEqual(trial.prefix(2).map(\.id), ["kpk-uzasadnienie", "kpk-apelacja"])
        let residence = ProceduralDeadlines.suggested(kind: .residence, stage: nil)
        XCTAssertEqual(residence.first?.id, "kpa-odwolanie")
        for list in [preTrial, trial, residence] {
            XCTAssertEqual(Set(list.map(\.id)), Set(ProceduralDeadlines.common.map(\.id)), "Nic nie znika z listy")
            XCTAssertEqual(list.count, ProceduralDeadlines.common.count, "Bez duplikatów")
        }
        XCTAssertEqual(ProceduralDeadlines.suggested(kind: nil, stage: nil), ProceduralDeadlines.common)
    }

    // MARK: Profil

    func testStagesAndRolesDependOnKind() {
        XCTAssertEqual(CaseKind.criminal.stages.first, .preTrial)
        XCTAssertTrue(CaseKind.residence.roles.isEmpty, "Cudzoziemca nie pytamy o rolę procesową")
        XCTAssertEqual(CaseStage.adminFirst.displayName(in: .deportation), "Straż Graniczna")
        XCTAssertEqual(CaseStage.adminFirst.displayName(in: .residence), "Wojewoda")
        XCTAssertEqual(CaseStage.preTrial.signatureLabel, "Sygnatura prokuratury")
    }

    func testRoleFollowsStageUnlessChosenByHand() {
        // Nieustalona rola idzie za etapem.
        XCTAssertEqual(ClientRole.afterStageChange(current: nil, from: nil, to: .preTrial), .suspect)
        // Podejrzany z przygotowawczego staje się oskarżonym po akcie oskarżenia.
        XCTAssertEqual(ClientRole.afterStageChange(current: .suspect, from: .preTrial, to: .firstInstance), .accused)
        // Pokrzywdzony zostaje pokrzywdzonym.
        XCTAssertEqual(ClientRole.afterStageChange(current: .victim, from: .preTrial, to: .firstInstance), .victim)
    }

    func testProfileText() {
        var value = legalCase()
        value.stage = .preTrial
        value.clientRole = .suspect
        XCTAssertEqual(value.profileText, "Karna · Przygotowawcze · Podejrzany")
        XCTAssertNil(legalCase(kind: nil).profileText)
        XCTAssertTrue(value.searchableTexts.contains("Karna"))
    }

    func testClearedAndDroppedFields() {
        let old = legalCase(custodyUntil: day(2026, 11, 1))
        var new = old
        new.custodyUntil = nil
        new.kind = nil
        XCTAssertEqual(CaseProfileField.cleared(from: old, to: new), [.custodyUntil, .kind])
        XCTAssertEqual(CaseProfileField.dropped(sent: old, returned: legalCase(kind: nil)), [.kind, .custodyUntil])
    }

    // MARK: Pilnowane daty

    func testCustodyCountdown() throws {
        let today = day(2026, 10, 1)
        let watch = try XCTUnwrap(CaseWatch.items(for: legalCase(custodyUntil: day(2026, 10, 10)), today: today).first)
        XCTAssertEqual(watch.kind, .custody)
        XCTAssertEqual(watch.daysLeft, 9)
        XCTAssertEqual(watch.severity, .soon)
        XCTAssertEqual(watch.countdownText, "za 9 dni")

        let critical = CaseWatch.items(for: legalCase(custodyUntil: day(2026, 10, 2)), today: today).first
        XCTAssertEqual(critical?.severity, .critical)
        XCTAssertEqual(critical?.countdownText, "kończy się jutro")

        let expired = CaseWatch.items(for: legalCase(custodyUntil: day(2026, 9, 29)), today: today).first
        XCTAssertEqual(expired?.severity, .expired)
        XCTAssertEqual(expired?.countdownText, "minął 2 dni temu")
    }

    func testWatchRespectsKindAndStatus() {
        let today = day(2026, 10, 1)
        // Sprawa karna nie pilnuje pobytu, pobytowa — aresztu.
        XCTAssertTrue(CaseWatch.items(for: legalCase(legalStayUntil: day(2026, 10, 5)), today: today).isEmpty)
        XCTAssertEqual(
            CaseWatch.items(for: legalCase(kind: .residence, legalStayUntil: day(2026, 10, 5)), today: today).map(\.kind),
            [.legalStay]
        )
        // Zamknięta sprawa nie alarmuje.
        XCTAssertTrue(CaseWatch.items(for: legalCase(status: .closed, custodyUntil: day(2026, 10, 5)), today: today).isEmpty)
    }

    func testUpcomingWindow() {
        let today = day(2026, 10, 1)
        let far = legalCase(custodyUntil: day(2026, 12, 1))
        var soon = legalCase(kind: .residence, legalStayUntil: day(2026, 10, 20))
        soon = LegalCase(
            id: CaseID("case-2"), number: soon.number, title: soon.title, clientID: soon.clientID,
            status: soon.status, summary: "", createdAt: soon.createdAt, kind: .residence, legalStayUntil: day(2026, 10, 20)
        )
        let upcoming = CaseWatch.upcoming(cases: [far, soon], today: today)
        XCTAssertEqual(upcoming.map(\.caseID), [CaseID("case-2")], "Areszt za 2 miesiące jeszcze nie na „Dzisiaj”")
    }

    func testWatchRemindersAt830BeforeTheEnd() throws {
        let today = day(2026, 10, 1)
        let watch = try XCTUnwrap(CaseWatch.items(for: legalCase(custodyUntil: day(2026, 10, 10)), today: today).first)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: EmmaTime.referenceTimeZone)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
        let items = CaseWatchReminderPlan.items(
            watches: [watch],
            clientNames: [ClientID("client-1"): "Jan Kowalski"],
            dateText: { $0.isoString },
            now: now
        )
        // 14 dni przed (26.09) już minęło; zostają 7, 3, 1 i 0.
        XCTAssertEqual(items.map(\.identifier), [
            "emma.watch.case-1.custody.7", "emma.watch.case-1.custody.3",
            "emma.watch.case-1.custody.1", "emma.watch.case-1.custody.0"
        ])
        let first = try XCTUnwrap(items.first)
        XCTAssertEqual(first.title, "Areszt — Jan Kowalski")
        XCTAssertTrue(first.body.hasPrefix("Kończy się za 7 dni (2026-10-10)."), first.body)
        let parts = calendar.dateComponents([.day, .hour, .minute], from: first.fireAt)
        XCTAssertEqual([parts.day, parts.hour, parts.minute], [3, 8, 30])
    }
}

/// Pliki od klienta z WhatsApp: etykieta, podgląd na listach i notatka do akt.
final class MessageAttachmentTests: XCTestCase {

    private func message(kind: MessageKind, text: String, name: String? = nil) -> Message {
        Message(
            id: MessageID("m-1"), threadID: ThreadID("t-1"), direction: .incoming, authorID: nil,
            kind: kind, text: text, attachmentName: name,
            sentAt: Date(timeIntervalSince1970: 0), sequence: 1, transport: .delivered, source: .whatsAppInbound
        )
    }

    func testDocumentLabelAndPreview() {
        let document = message(kind: .document, text: "postanowienie.pdf", name: "postanowienie.pdf")
        XCTAssertEqual(document.attachmentLabel, "Dokument · postanowienie.pdf")
        XCTAssertNil(document.caption, "Nazwa pliku w treści to nie podpis")
        XCTAssertEqual(document.previewText, "Dokument · postanowienie.pdf")

        let photo = message(kind: .image, text: "Dostałem to wczoraj")
        XCTAssertEqual(photo.previewText, "Zdjęcie: Dostałem to wczoraj")
        XCTAssertTrue(photo.kind.mayBeLegalDocument)
        XCTAssertFalse(MessageKind.audio.mayBeLegalDocument)

        // Format backendu: etykieta w nawiasie i nazwa pliku albo podpis.
        let fromBackend = message(kind: .document, text: "[Dokument] wyrok.pdf", name: "wyrok.pdf")
        XCTAssertNil(fromBackend.caption)
        XCTAssertEqual(fromBackend.previewText, "Dokument · wyrok.pdf")
        let captioned = message(kind: .image, text: "[Zdjęcie] Wezwanie na jutro")
        XCTAssertEqual(captioned.caption, "Wezwanie na jutro")

        let plain = message(kind: .text, text: "Dzień dobry")
        XCTAssertNil(plain.attachmentLabel)
        XCTAssertEqual(plain.previewText, "Dzień dobry")
    }

    func testCaseNoteText() {
        let photo = message(kind: .image, text: "Wezwanie na przesłuchanie")
        XCTAssertEqual(
            photo.caseNoteText(clientName: "Olena Kowalczuk", dateText: "1 października"),
            "Od: Olena Kowalczuk (WhatsApp, 1 października) — zdjęcie. Podpis: „Wezwanie na przesłuchanie”. Plik w WhatsApp Business."
        )
    }

    func testAttachmentNameIsMapped() throws {
        let json = #"{"id":"m-9","thread_id":"t-1","direction":"incoming","kind":"attachment","attachment_type":"document","attachment_name":"wyrok.pdf","text":"","sent_at":"2026-10-01T08:00:00Z","sequence":3,"transport":"delivered","source":"provider","version":1}"#
        let dto = try JSONDecoder().decode(BackendMessageDTO.self, from: Data(json.utf8))
        let mapped = try BackendRepository.mapMessage(dto)
        XCTAssertEqual(mapped.kind, .document)
        XCTAssertEqual(mapped.attachmentName, "wyrok.pdf")
        XCTAssertEqual(mapped.previewText, "Dokument · wyrok.pdf")
    }
}

/// „Po rozprawie”: ostatni zakończony, niezamknięty termin w sprawie.
final class DebriefTests: XCTestCase {

    private func event(_ id: String, _ time: String, kind: EventKind, status: EventStatus = .confirmed) -> ScheduledEvent {
        ScheduledEvent(
            id: EventID(id), clientID: nil, caseID: nil, title: id,
            day: LocalDate(year: 2026, month: 10, day: 1), time: TimeOfDay(hhmm: time)!,
            durationMinutes: 60, kind: kind, status: status, place: "Sąd"
        )
    }

    func testDebriefPicksLatestUnfinishedHearing() {
        let events = [
            event("rozprawa-rano", "08:00", kind: .caseDeadline),
            event("konsultacja", "10:00", kind: .consultation),
            event("rozprawa-zamknieta", "11:00", kind: .caseDeadline, status: .finished),
            event("popoludnie", "15:00", kind: .caseDeadline)
        ]
        let split = DayAgenda.split(events, now: TimeOfDay(hhmm: "13:00")!)
        XCTAssertEqual(DayAgenda.debrief(split)?.id, EventID("rozprawa-rano"))
        XCTAssertNil(DayAgenda.debrief(DayAgenda.split(events, now: TimeOfDay(hhmm: "08:30")!)), "Rozprawa jeszcze trwa")
    }
}

final class CaseKindGuessTests: XCTestCase {
    func testGuessFromLeadTopic() {
        XCTAssertEqual(CaseKind.guess(from: "Zatrzymanie brata przez policję"), .criminal)
        XCTAssertEqual(CaseKind.guess(from: "Karta pobytu — odmowa wojewody"), .residence)
        XCTAssertEqual(CaseKind.guess(from: "Decyzja o zobowiązaniu do powrotu, pobyt nielegalny"), .deportation)
        XCTAssertEqual(CaseKind.guess(from: "Мого брата затримали"), .criminal)
        XCTAssertEqual(CaseKind.guess(from: "Dozór elektroniczny zamiast więzienia"), .enforcement)
        XCTAssertNil(CaseKind.guess(from: "Sprawa rozwodowa"))
        XCTAssertEqual(CaseKind.guess(from: "Zezwolenie na widzenie, wizyta w areszcie"), .criminal)
    }
}

final class VoiceContextNoteTests: XCTestCase {

    func testCaseOnScreenGivesNumericIDsForCRMTools() {
        let note = AssistantContext.client(ClientID("client-12"), caseID: CaseID("case-7")).liveContextNote
        XCTAssertTrue(note.contains("client_id 12, case_id 7"), note)
        XCTAssertTrue(note.contains("„Ta sprawa”"))
    }

    func testLeadIsNamedAsLead() {
        XCTAssertTrue(AssistantContext.client(ClientID("lead-3")).liveContextNote.contains("lead_id 3"))
    }

    func testFirmContextSaysNothingIsOpen() {
        XCTAssertTrue(AssistantContext.firm.liveContextNote.contains("całej kancelarii"))
    }
}

final class CaseProfileSeedTests: XCTestCase {

    private func legalCase(kind: CaseKind? = nil, stage: CaseStage? = nil, role: ClientRole? = nil) -> LegalCase {
        var value = LegalCase(
            id: CaseID("case-1"), number: "KR/1", title: "Rozbój", clientID: ClientID("client-1"),
            status: .inProgress, summary: "", createdAt: LocalDate(year: 2026, month: 9, day: 1), kind: kind
        )
        value.stage = stage
        value.clientRole = role
        return value
    }

    func testCustodyWithoutKindMakesTheCaseCriminal() {
        // Bez rodzaju formularz nie pokazałby daty aresztu, a zapis by ją zgubił.
        let seed = CaseProfileSeed(caseID: CaseID("case-1"), custodyUntil: LocalDate(year: 2026, month: 12, day: 12))
        let updated = seed.applied(to: legalCase())
        XCTAssertEqual(updated.kind, .criminal)
        XCTAssertEqual(updated.custodyUntil, LocalDate(year: 2026, month: 12, day: 12))
        XCTAssertEqual(seed.changedFields(in: legalCase()), ["kind", "custody_until"])
    }

    func testStageChangeMovesSuspectToAccusedLikeTheForm() {
        let before = legalCase(kind: .criminal, stage: .preTrial, role: .suspect)
        let updated = CaseProfileSeed(caseID: CaseID("case-1"), stage: .firstInstance).applied(to: before)
        XCTAssertEqual(updated.stage, .firstInstance)
        XCTAssertEqual(updated.clientRole, .accused)
    }

    func testValuesOutsideTheKindAreIgnored() {
        // Etap „WSA” i rola „oskarżony” nie istnieją w sprawie pobytowej.
        let before = legalCase(kind: .residence)
        let seed = CaseProfileSeed(caseID: CaseID("case-1"), stage: .appeal, clientRole: .accused)
        XCTAssertEqual(seed.applied(to: before), before)
        XCTAssertTrue(seed.changedFields(in: before).isEmpty)
    }
}
