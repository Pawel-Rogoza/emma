import XCTest
@testable import Emma

// MARK: - Etap 5: intencje i pola (F14)
//
// Sprawdzamy reguły na zdaniach z §6 audytu, bo to one są warunkiem akceptacji
// etapu. Ustalenia są deterministyczne: „dziś” to dzień referencyjny demo
// (piątek 11.09.2026), więc daty można porównywać wprost.

final class AssistantIntentTests: XCTestCase {

    /// Piątek 11 września 2026 — dzień referencyjny demo.
    private let friday = LocalDate(year: 2026, month: 9, day: 11)

    private func parse(_ text: String) -> AssistantIntent {
        AssistantIntentParser.parse(text, today: friday)
    }

    // MARK: §6-A — wiadomość do Oleny

    func testReplyIntentCarriesMessageTextAfterZe() {
        let intent = parse("Wyślij Olenie WhatsApp, że spóźnię się 15 minut")
        XCTAssertEqual(intent.kind, .reply)
        XCTAssertEqual(intent.text, "spóźnię się 15 minut")
        XCTAssertEqual(intent.dueDate, nil, "Wiadomość nie ma terminu zadania")
        XCTAssertFalse(intent.isReadOnly)
    }

    /// „Wyślij” samo w sobie jest zgodą; z adresatem i treścią — odpowiedzią.
    func testBareSendIsConfirmationButSendToPersonIsReply() {
        XCTAssertEqual(parse("wyślij").kind, .confirm)
        XCTAssertEqual(parse("Wyślij").kind, .confirm)
        XCTAssertEqual(parse("Wyślij Olenie wiadomość na WhatsApp").kind, .reply)
    }

    func testReplyIntentFromNapiszDo() {
        let intent = parse("Napisz do Oleny, że dokumenty są gotowe")
        XCTAssertEqual(intent.kind, .reply)
        XCTAssertEqual(intent.text, "dokumenty są gotowe")
    }

    // MARK: §6-A krok 5 — poprawka treści

    func testQuantityCorrectionIsNotMistakenForAnHour() {
        let intent = parse("Zmień na 20 minut")
        XCTAssertEqual(intent.kind, .correction)
        XCTAssertEqual(intent.revision?.quantity, 20)
        XCTAssertEqual(intent.revision?.unit, "minut")
        XCTAssertNil(intent.dueTime, "„na 20 minut” to ilość, nie godzina 20:00")
    }

    func testHourCorrectionKeepsHour() {
        let intent = parse("Zmień na 11:30")
        XCTAssertEqual(intent.kind, .correction)
        XCTAssertEqual(intent.revision?.time, TimeOfDay(hhmm: "11:30"))
    }

    func testWordHourCorrection() {
        let intent = parse("Nie, spotkanie jest o jedenastej")
        XCTAssertEqual(intent.kind, .correction)
        XCTAssertEqual(intent.revision?.time, TimeOfDay(hhmm: "11:00"))
    }

    // MARK: §6-C — zadanie z terminem

    func testTaskIntentKeepsDueTimeFromDo() {
        let intent = parse("Dodaj zadanie: wyślij dokumenty Olenie jutro do 14")
        XCTAssertEqual(intent.kind, .task)
        XCTAssertEqual(intent.text, "wyślij dokumenty Olenie jutro do 14")
        XCTAssertEqual(intent.dueDate, friday.adding(days: 1))
        XCTAssertEqual(intent.dueTime, TimeOfDay(hhmm: "14:00"))
    }

    func testTaskIntentWithoutColonDropsKindNoun() {
        let intent = parse("dodaj zadanie wysłać dokumenty")
        XCTAssertEqual(intent.kind, .task)
        XCTAssertEqual(intent.text, "wysłać dokumenty")
    }

    func testTaskIntentFromPrzypomnij() {
        let intent = parse("Przypomnij mi o spotkaniu z Oleną")
        XCTAssertEqual(intent.kind, .task)
    }

    func testTaskIntentTodayWithoutDatePhrase() {
        let intent = parse("Dodaj zadanie: zadzwonić do sądu")
        XCTAssertEqual(intent.kind, .task)
        XCTAssertEqual(intent.text, "zadzwonić do sądu")
        XCTAssertNil(intent.dueDate, "Brak frazy daty to brak terminu, a nie zgadywanie")
    }

    // MARK: §6-C poprawka terminu

    func testDateCorrectionWithWeekday() {
        let intent = parse("Nie, na poniedziałek")
        XCTAssertEqual(intent.kind, .correction)
        XCTAssertEqual(intent.revision?.date, friday.adding(days: 3), "Najbliższy poniedziałek to 14.09")
    }

    /// W poniedziałek „na poniedziałek” znaczy za tydzień, nie „już”.
    func testWeekdayCorrectionOnThatWeekdayMeansNextWeek() {
        let monday = LocalDate(year: 2026, month: 9, day: 14)
        let intent = AssistantIntentParser.parse("Nie, na poniedziałek", today: monday)
        XCTAssertEqual(intent.revision?.date, monday.adding(days: 7))
    }

    // MARK: §6-B — pytania odczytowe

    func testScheduleQuestionIsBriefingAndReadOnly() {
        let intent = parse("Jakie mam terminy na dzisiaj?")
        XCTAssertEqual(intent.kind, .briefing)
        XCTAssertTrue(intent.isReadOnly)
        XCTAssertEqual(intent.dueDate, friday)
    }

    func testTomorrowFollowUpKeepsBriefingKind() {
        let intent = parse("A jutro?")
        XCTAssertEqual(intent.kind, .briefing)
        XCTAssertEqual(intent.dueDate, friday.adding(days: 1))
    }

    func testCaseSummaryFromPrzygotujMnie() {
        let intent = parse("Przygotuj mnie do pierwszego")
        XCTAssertEqual(intent.kind, .caseSummary)
    }

    func testPlanQuestionIsBriefing() {
        XCTAssertEqual(parse("Podsumuj dzisiejszy dzień").kind, .briefing)
        XCTAssertEqual(parse("Co mam w kalendarzu?").kind, .briefing)
    }

    // MARK: Spotkanie (F14)

    func testAddMeetingIsEventNotBriefing() {
        let intent = parse("Dodaj spotkanie z Oleną na jutro o 11")
        XCTAssertEqual(intent.kind, .event, "„Dodaj spotkanie” nie może uruchamiać briefingu")
        XCTAssertEqual(intent.dueDate, friday.adding(days: 1))
        XCTAssertEqual(intent.dueTime, TimeOfDay(hhmm: "11:00"))
        XCTAssertTrue(intent.requiresRecipient)
    }

    func testMeetingWithoutVerbalSchedule() {
        let intent = parse("Zaplanuj spotkanie w sprawie KR/2026/041")
        XCTAssertEqual(intent.kind, .event)
        XCTAssertNil(intent.dueDate)
    }

    // MARK: Notatka i zgoda

    func testNoteIntentAfterColon() {
        let intent = parse("Dodaj notatkę: klient prosi o kontakt w piątek")
        XCTAssertEqual(intent.kind, .note)
        XCTAssertEqual(intent.text, "klient prosi o kontakt w piątek")
    }

    func testConfirmationFormsAreBareOnly() {
        for form in ["tak", "Tak", "wyślij", "zatwierdź", "zapisz", "potwierdzam"] {
            XCTAssertEqual(parse(form).kind, .confirm, "„\(form)” ma być zgodą")
        }
        XCTAssertNotEqual(parse("tak, ale zmień treść").kind, .confirm)
    }

    func testCancelForms() {
        XCTAssertEqual(parse("anuluj").kind, .cancel)
        XCTAssertEqual(parse("nie").kind, .cancel)
        XCTAssertEqual(parse("rezygnuję").kind, .cancel)
    }

    // MARK: Daty i godziny

    func testRelativeDates() {
        XCTAssertEqual(parse("plan na dziś").dueDate, friday)
        XCTAssertEqual(parse("plan na jutro").dueDate, friday.adding(days: 1))
        XCTAssertEqual(parse("plan na pojutrze").dueDate, friday.adding(days: 2))
        XCTAssertEqual(parse("plan na za tydzień").dueDate, friday.adding(days: 7))
    }

    func testAbsoluteDateWithMonthName() {
        XCTAssertEqual(parse("spotkanie 12 września").dueDate, LocalDate(year: 2026, month: 9, day: 12))
        XCTAssertEqual(parse("spotkanie 3 stycznia").dueDate, LocalDate(year: 2027, month: 1, day: 3))
    }

    func testAbsoluteDateWithDots() {
        XCTAssertEqual(parse("spotkanie 12.09").dueDate, LocalDate(year: 2026, month: 9, day: 12))
        XCTAssertEqual(parse("spotkanie 12.09.2027").dueDate, LocalDate(year: 2027, month: 9, day: 12))
    }

    /// Dzień, którego nie ma w kalendarzu, nie jest terminem — wcześniej parser
    /// zwracał `2026-09-31`, który szedł dalej do porównań i do backendu.
    func testNonexistentDatesAreRejected() {
        XCTAssertNil(parse("spotkanie 31 września").dueDate)
        XCTAssertNil(parse("spotkanie 30.02").dueDate)
        // Luty 2027 nie ma 29 dnia — najbliższy istniejący 29 lutego to 2028.
        XCTAssertEqual(parse("spotkanie 29 lutego").dueDate, LocalDate(year: 2028, month: 2, day: 29))
        XCTAssertNil(LocalDate(checkedYear: 2026, month: 2, day: 29))
        XCTAssertEqual(LocalDate(checkedYear: 2028, month: 2, day: 29), LocalDate(year: 2028, month: 2, day: 29))
    }

    func testTimesWithPrepositions() {
        XCTAssertEqual(parse("zadanie na jutro do 14").dueTime, TimeOfDay(hhmm: "14:00"))
        XCTAssertEqual(parse("spotkanie o 11:30").dueTime, TimeOfDay(hhmm: "11:30"))
        XCTAssertNil(parse("zadanie na 20 minut").dueTime)
    }

    // MARK: Nierozpoznane

    func testUnknownTextStaysUnknown() {
        let intent = parse("no i co tam")
        XCTAssertEqual(intent.kind, .unknown)
        XCTAssertTrue(intent.isReadOnly, "Nierozpoznane polecenie nie tworzy akcji")
    }
}
