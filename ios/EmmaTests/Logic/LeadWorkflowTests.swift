import XCTest
@testable import Emma

// MARK: - Obsługa zgłoszeń: „nowy” przez 24 godziny, potem „oczekuje”
//
// Review właściciela z 23.09.2026: leady wisiały jako „Nowe” bez końca. Reguła
// jest w rdzeniu (`LeadWorkflow`), więc testujemy ją tutaj, bez SwiftUI.

final class LeadWorkflowTests: XCTestCase {

    private static let warsaw = TimeZone(identifier: "Europe/Warsaw")!

    private func instant(_ iso: String, _ hhmm: String) -> Date {
        let day = LocalDate(iso: iso)!
        let time = TimeOfDay(hhmm: hhmm)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.warsaw
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        return calendar.date(from: components)!
    }

    private func lead(
        _ id: String,
        stage: ClientStage = .new,
        source: ClientSource = .webForm,
        created: String,
        receivedAt: Date? = nil,
        topic: String = "Temat",
        consultation: ConsultationRequest? = nil
    ) -> Client {
        Client(
            id: ClientID(id),
            displayName: "Osoba \(id)",
            initials: "OS",
            language: .pl,
            topic: topic,
            stage: stage,
            source: source,
            createdAt: LocalDate(iso: created)!,
            briefing: "",
            receivedAt: receivedAt,
            consultation: consultation
        )
    }

    // MARK: Bez rozmów WhatsApp (review 04.10.2026)

    func testInboxSkipsWhatsAppConversations() {
        let now = instant("2026-10-04", "10:00")
        let clients = [
            lead("lead-web", created: "2026-10-04", receivedAt: instant("2026-10-04", "09:00")),
            lead("lead-whatsapp", source: .whatsApp, created: "2026-10-04", receivedAt: instant("2026-10-04", "09:10")),
            lead("lead-manual", source: .manual, created: "2026-10-04", receivedAt: instant("2026-10-04", "09:20")),
            lead("lead-whatsapp-contact", stage: .inContact, source: .whatsApp, created: "2026-10-01"),
            lead("lead-web-contact", stage: .inContact, created: "2026-10-01")
        ]

        let inbox = LeadWorkflow.inbox(clients, now: now)

        // Ręcznie dodany lead zostaje — „+” na liście nie może tworzyć niewidocznych wpisów.
        XCTAssertEqual(inbox.fresh.map(\.id.rawValue), ["lead-manual", "lead-web"])
        XCTAssertEqual(inbox.inContact.map(\.id.rawValue), ["lead-web-contact"])
        XCTAssertEqual(LeadWorkflow.needsActionCount(clients), 2, "Plakietka nie liczy rozmów WhatsApp")
        XCTAssertFalse(LeadWorkflow.isLead(lead("client-1", stage: .client, created: "2026-01-01")))
    }

    func testBookingPrefersReservationDataOverTopicPrefix() {
        let reserved = lead(
            "lead-booking",
            created: "2026-10-04",
            topic: "Termin: 2026-10-08 10:00 Wiza",
            consultation: ConsultationRequest(
                minutes: 60,
                priceGrosze: 49_000,
                day: LocalDate(iso: "2026-10-09")!,
                time: TimeOfDay(hhmm: "14:00")
            )
        )
        XCTAssertEqual(
            LeadWorkflow.booking(of: reserved),
            LeadBooking(day: LocalDate(iso: "2026-10-09")!, time: TimeOfDay(hhmm: "14:00"))
        )
        XCTAssertEqual(reserved.consultation?.variantText, "60 min · 490 zł")

        // Starszy serwer: termin tylko w treści zgłoszenia.
        let legacy = lead("lead-legacy", created: "2026-10-04", topic: "Termin: 2026-10-08 10:00 Wiza")
        XCTAssertEqual(LeadWorkflow.booking(of: legacy)?.day, LocalDate(iso: "2026-10-08"))
    }

    func testConsultationSummarySaysHowLongAndWhen() {
        let dateText = DateTextFormatter(today: LocalDate(iso: "2026-10-08")!)
        let reserved = lead(
            "lead-booking",
            created: "2026-10-04",
            consultation: ConsultationRequest(
                minutes: 60,
                priceGrosze: 49_000,
                day: LocalDate(iso: "2026-10-09")!,
                time: TimeOfDay(hhmm: "14:00")
            )
        )
        let summary = LeadWorkflow.consultation(of: reserved)
        XCTAssertEqual(summary?.variantText, "60 min · 490 zł")
        XCTAssertEqual(summary?.whenText(dateText), "Jutro, 9 października · 14:00")
        XCTAssertEqual(summary?.compactText(dateText), "Konsultacja 60 min · Jutro 14:00")
        XCTAssertEqual(summary?.compactText(dateText, withPrice: true), "Konsultacja 60 min · 490 zł · Jutro 14:00")
        XCTAssertEqual(summary?.timing(today: LocalDate(iso: "2026-10-08")!), .tomorrow)
        XCTAssertEqual(summary?.timing(today: LocalDate(iso: "2026-10-10")!), .past)

        // Bez terminu: wariant z ceną, żeby linia mówiła „ile”.
        let noDate = ConsultationSummary(minutes: 30, priceGrosze: 29_000, day: nil, time: nil)
        XCTAssertEqual(noDate.compactText(dateText), "Konsultacja 30 min · 290 zł")
        XCTAssertNil(noDate.whenText(dateText))

        // Zgłoszenie bez rezerwacji nie udaje konsultacji.
        XCTAssertNil(LeadWorkflow.consultation(of: lead("lead-plain", created: "2026-10-04", topic: "Wiza")))
    }

    func testConsultationPriceText() {
        XCTAssertEqual(ConsultationRequest.priceText(29_000), "290 zł")
        XCTAssertEqual(ConsultationRequest.priceText(29_050), "290,50 zł")
        XCTAssertEqual(ConsultationRequest.priceText(29_005), "290,05 zł")
        XCTAssertNil(ConsultationRequest(minutes: nil, priceGrosze: nil, day: nil, time: nil).variantText)
        XCTAssertEqual(ConsultationRequest(minutes: 30, priceGrosze: nil, day: nil, time: nil).variantText, "30 min")
    }

    func testWhatsAppLinkCarriesReplyTextWithEncodedPlus() {
        let url = ContactLinks.whatsAppURL("+48 600 100 200", text: "BLIK na +48 579 910 709 & dzięki")
        XCTAssertEqual(
            url?.absoluteString,
            "https://wa.me/48600100200?text=BLIK%20na%20%2B48%20579%20910%20709%20%26%20dzi%C4%99ki"
        )
        XCTAssertNil(ContactLinks.whatsAppURL("abc", text: "x"))
    }

    // MARK: Status

    func testExactTimestampSwitchesToWaitingAfterTwentyFourHours() {
        let received = instant("2026-09-22", "14:00")
        let client = lead("lead-1", created: "2026-09-22", receivedAt: received)

        XCTAssertEqual(LeadWorkflow.status(of: client, now: instant("2026-09-23", "13:59")), .fresh)
        XCTAssertEqual(LeadWorkflow.status(of: client, now: instant("2026-09-23", "14:00")), .waiting)
    }

    func testDateOnlyLeadIsFreshUntilNoonOfNextDay() {
        // Bez godziny przyjmujemy południe dnia zgłoszenia.
        let client = lead("lead-2", created: "2026-09-22")

        XCTAssertEqual(LeadWorkflow.status(of: client, now: instant("2026-09-22", "08:00")), .fresh)
        XCTAssertEqual(LeadWorkflow.status(of: client, now: instant("2026-09-23", "11:59")), .fresh)
        XCTAssertEqual(LeadWorkflow.status(of: client, now: instant("2026-09-23", "12:00")), .waiting)
    }

    func testStageDecidesForContactedLeadsAndClients() {
        let now = instant("2026-09-30", "10:00")
        XCTAssertEqual(LeadWorkflow.status(of: lead("a", stage: .inContact, created: "2026-09-01"), now: now), .inContact)
        XCTAssertEqual(LeadWorkflow.status(of: lead("b", stage: .client, created: "2026-09-01"), now: now), .client)
        XCTAssertFalse(LeadStatus.inContact.needsAction)
        XCTAssertTrue(LeadStatus.waiting.needsAction)
        XCTAssertTrue(LeadStatus.fresh.needsAction)
    }

    // MARK: Kolejka

    func testInboxOrdersWaitingOldestFirstAndFreshNewestFirst() {
        let now = instant("2026-09-23", "10:00")
        let clients = [
            lead("lead-old", created: "2026-09-18"),
            lead("lead-older", created: "2026-09-15"),
            lead("lead-fresh-early", created: "2026-09-23", receivedAt: instant("2026-09-23", "07:00")),
            lead("lead-fresh-late", created: "2026-09-23", receivedAt: instant("2026-09-23", "09:30")),
            lead("lead-contacted", stage: .inContact, created: "2026-09-20"),
            lead("client-1", stage: .client, created: "2026-01-01")
        ]

        let inbox = LeadWorkflow.inbox(clients, now: now)

        XCTAssertEqual(inbox.waiting.map(\.id.rawValue), ["lead-older", "lead-old"])
        XCTAssertEqual(inbox.fresh.map(\.id.rawValue), ["lead-fresh-late", "lead-fresh-early"])
        XCTAssertEqual(inbox.inContact.map(\.id.rawValue), ["lead-contacted"])
        XCTAssertEqual(inbox.needsAction.count, 4, "Kartoteka i obsłużone nie są do obsługi")
    }

    // MARK: Teksty

    func testBadgeTextUsesHoursOnlyWhenTimeIsKnown() {
        let now = instant("2026-09-23", "10:00")
        let today = LocalDate(iso: "2026-09-23")!

        let exact = lead("e", created: "2026-09-23", receivedAt: instant("2026-09-23", "07:00"))
        XCTAssertEqual(LeadWorkflow.badgeText(for: exact, now: now, today: today), "Nowy · 3 godz. temu")

        let minutes = lead("m", created: "2026-09-23", receivedAt: instant("2026-09-23", "09:48"))
        XCTAssertEqual(LeadWorkflow.receivedAgoText(of: minutes, now: now, today: today), "12 min temu")

        let justNow = lead("j", created: "2026-09-23", receivedAt: now)
        XCTAssertEqual(LeadWorkflow.receivedAgoText(of: justNow, now: now, today: today), "przed chwilą")

        let dateOnly = lead("d", created: "2026-09-23")
        XCTAssertEqual(LeadWorkflow.badgeText(for: dateOnly, now: now, today: today), "Nowy · dziś")

        let yesterday = lead("y", created: "2026-09-22")
        XCTAssertEqual(LeadWorkflow.badgeText(for: yesterday, now: now, today: today), "Nowy · wczoraj")
    }

    func testWaitingTextCountsDaysWithPolishPlural() {
        let today = LocalDate(iso: "2026-09-23")!
        let now = instant("2026-09-23", "15:00")

        XCTAssertEqual(
            LeadWorkflow.badgeText(for: lead("a", created: "2026-09-22"), now: now, today: today),
            "Oczekuje · od wczoraj"
        )
        XCTAssertEqual(
            LeadWorkflow.badgeText(for: lead("b", created: "2026-09-18"), now: now, today: today),
            "Oczekuje · 5 dni"
        )
        let exact = lead("c", created: "2026-09-21", receivedAt: instant("2026-09-21", "14:00"))
        XCTAssertEqual(LeadWorkflow.waitingText(of: exact, now: now, today: today), "2 dni")
        let oneDay = lead("d", created: "2026-09-22", receivedAt: instant("2026-09-22", "09:00"))
        XCTAssertEqual(LeadWorkflow.waitingText(of: oneDay, now: now, today: today), "1 dzień")
        XCTAssertEqual(
            LeadWorkflow.receivedAgoText(of: lead("e", created: "2026-09-19"), now: now, today: today),
            "4 dni temu"
        )
        XCTAssertEqual(LeadWorkflow.badgeText(for: lead("f", stage: .inContact, created: "2026-09-01"), now: now, today: today), "W kontakcie")
        XCTAssertEqual(EmmaPlural.leads(1), "1 zgłoszenie")
        XCTAssertEqual(EmmaPlural.leads(3), "3 zgłoszenia")
        XCTAssertEqual(EmmaPlural.leads(12), "12 zgłoszeń")
    }

    // MARK: Temat z rezerwacji

    func testBookingPrefixIsSeparatedFromTopic() {
        let topic = LeadTopic.parse("Termin: 2026-09-15 20:00 Hello, I need urgent assistance")
        XCTAssertEqual(topic.booking, LeadBooking(day: LocalDate(iso: "2026-09-15")!, time: TimeOfDay(hhmm: "20:00")))
        XCTAssertEqual(topic.text, "Hello, I need urgent assistance")
    }

    func testBookingPrefixAcceptsSingleDigitHourAndNewlines() {
        let topic = LeadTopic.parse("Termin: 2026-09-15 9:30\n\nOpis sprawy")
        XCTAssertEqual(topic.booking?.time, TimeOfDay(hhmm: "09:30"))
        XCTAssertEqual(topic.text, "Opis sprawy")
    }

    func testTopicWithoutBookingIsUntouched() {
        XCTAssertEqual(LeadTopic.parse("  Zatrzymanie osoby bliskiej "), LeadTopic(booking: nil, text: "Zatrzymanie osoby bliskiej"))
        // Nieczytelna data: tekst zostaje w całości, parser niczego nie ucina.
        XCTAssertEqual(LeadTopic.parse("Termin: jutro rano").text, "Termin: jutro rano")
        XCTAssertNil(LeadTopic.parse("Termin: jutro rano").booking)
        // Termin bez godziny (urwany skrót tematu) nadal daje dzień.
        let cut = LeadTopic.parse("Termin: 2026-09-15 20:0…")
        XCTAssertEqual(cut.booking?.day, LocalDate(iso: "2026-09-15"))
        XCTAssertNil(cut.booking?.time)
        XCTAssertEqual(cut.text, "20:0…")
    }

    // MARK: Linki kontaktowe

    func testPhoneNumbersNormalizeToInternationalDigits() {
        XCTAssertEqual(ContactLinks.internationalDigits("600 100 200"), "48600100200")
        XCTAssertEqual(ContactLinks.internationalDigits("+48 600-100-200"), "48600100200")
        XCTAssertEqual(ContactLinks.internationalDigits("0048 600 100 200"), "48600100200")
        XCTAssertEqual(ContactLinks.internationalDigits("+380 67 123 4567"), "380671234567")
        XCTAssertNil(ContactLinks.internationalDigits("brak"))
        XCTAssertNil(ContactLinks.internationalDigits("123"))

        XCTAssertEqual(ContactLinks.phoneURL("600 100 200")?.absoluteString, "tel:+48600100200")
        XCTAssertEqual(ContactLinks.whatsAppURL("600 100 200")?.absoluteString, "https://wa.me/48600100200")
        XCTAssertEqual(ContactLinks.mailURL(" anna@example.com ")?.absoluteString, "mailto:anna@example.com")
        XCTAssertNil(ContactLinks.mailURL("anna example.com"))
        XCTAssertEqual(ContactLinks.mailURL("jan.o'neil+kancelaria@sub.example.pl")?.absoluteString, "mailto:jan.o'neil+kancelaria@sub.example.pl")
        // Adres z formularza strony nie może dopisać ukrytych odbiorców ani treści.
        XCTAssertNil(ContactLinks.mailURL("anna@example.com?bcc=obcy@evil.test&body=x"))
        XCTAssertNil(ContactLinks.mailURL("anna@example.com,obcy@evil.test"))
        // Odpowiedź na mail: temat „Re: …” zakodowany ściśle, bez doklejania drugiego „Re:”.
        XCTAssertEqual(
            ContactLinks.mailReplyURL("anna@example.com", subject: "Karta pobytu & termin")?.absoluteString,
            "mailto:anna@example.com?subject=Re%3A%20Karta%20pobytu%20%26%20termin"
        )
        XCTAssertEqual(
            ContactLinks.mailReplyURL("anna@example.com", subject: "RE: x")?.absoluteString,
            "mailto:anna@example.com?subject=RE%3A%20x"
        )
        XCTAssertEqual(ContactLinks.mailReplyURL("anna@example.com", subject: nil)?.absoluteString, "mailto:anna@example.com")
        XCTAssertNil(ContactLinks.mailReplyURL("anna@example.com?bcc=x@y.z", subject: "x"))
        XCTAssertNil(ContactLinks.mailURL("anna@example.com%0Abcc:obcy@evil.test"))
        XCTAssertNil(ContactLinks.mailURL("anna@@example.com"))
        XCTAssertNil(ContactLinks.mailURL("anna@localhost"))
    }

    func testDemoLeadsCarryExactReceivedTime() {
        let now = DemoClock().now()
        XCTAssertEqual(LeadWorkflow.status(of: DemoFixtures.andrii, now: now), .fresh)
        XCTAssertEqual(LeadWorkflow.receivedInstant(of: DemoFixtures.andrii).isExact, true)
        XCTAssertEqual(DemoFixtures.andrii.phone, "+48 600 100 200")
        XCTAssertNotNil(DemoFixtures.maria.email)
    }

    // MARK: Nawigacja do miejsca terminu

    func testMapsLinkSkipsPlacesYouDoNotDriveTo() {
        XCTAssertNil(ContactLinks.mapsURL(""))
        XCTAssertNil(ContactLinks.mapsURL("Kancelaria"))
        XCTAssertNil(ContactLinks.mapsURL("Online"))
        XCTAssertNil(ContactLinks.mapsURL("telefonicznie"))
    }

    func testMapsLinkDropsCourtroomFromQuery() throws {
        let url = try XCTUnwrap(ContactLinks.mapsURL("Sąd Rejonowy dla Warszawy-Mokotowa, sala 214"))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "q" }?.value
        XCTAssertEqual(query, "Sąd Rejonowy dla Warszawy-Mokotowa")
        XCTAssertEqual(url.host, "maps.apple.com")
        XCTAssertNotNil(ContactLinks.mapsURL("Sąd"), "Samo „Sąd” to nadal miejsce do wyszukania")
    }
}
