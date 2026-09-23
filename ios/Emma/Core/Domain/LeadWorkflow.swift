import Foundation

// MARK: - Obsługa zgłoszeń (leadów)
//
// Review właściciela z 23.09.2026: na liście „Klienci” każde zgłoszenie było
// „Nowe” bez względu na to, czy przyszło godzinę, czy tydzień temu — bo etap
// z backendu (`new`) nie mówi nic o czasie. Leady, których nikt nie ruszył,
// gromadziły się i nie było widać, które naprawdę czekają.
//
// Reguła jest teraz jedna i mieszka w rdzeniu (testowalna bez SwiftUI):
//
//   • **Nowy**        — etap `new` i mniej niż 24 godziny od przyjęcia,
//   • **Oczekuje**    — etap `new` i co najmniej 24 godziny bez kontaktu,
//   • **W kontakcie** — ktoś się odezwał; w aplikacji to „obsłużone”,
//   • **Klient**      — zgłoszenie skonwertowane w kartotekę.
//
// „Oznacz jako obsłużone” zmienia etap na `in_contact` (to jedyny zapis, który
// backend przyjmuje dla leada), a cofnięcie — z powrotem na `new`.
//
// Chwila przyjęcia: backend podaje dziś wyłącznie datę (`created_at`, bez
// godziny). Gdy przyjdzie dokładny znacznik (`received_at`), liczymy dokładnie.
// Do tego czasu przyjmujemy południe dnia zgłoszenia — to estymator o
// najmniejszym błędzie przy zgłoszeniach rozłożonych w ciągu dnia — i nie
// udajemy precyzji: wiek pokazujemy wtedy w dniach („dziś”, „wczoraj”), a nie
// w godzinach.

/// Stan zgłoszenia z punktu widzenia pracy kancelarii.
public enum LeadStatus: String, Sendable, CaseIterable, Identifiable {
    case fresh
    case waiting
    case inContact
    case client

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fresh: return "Nowy"
        case .waiting: return "Oczekuje"
        case .inContact: return "W kontakcie"
        case .client: return "Klient"
        }
    }

    /// Czy zgłoszenie czeka na ruch kancelarii (trafia do „Do obsługi”).
    public var needsAction: Bool { self == .fresh || self == .waiting }
}

/// Termin konsultacji zarezerwowany przez stronę.
///
/// Zgłoszenia z rezerwacji mają w treści prefiks `Termin: RRRR-MM-DD GG:MM`
/// (backend: `leads.ts`, `booking/request.ts`). Na liście był to surowy tekst
/// na początku tematu, a to najważniejsza informacja: kiedy klient chce rozmawiać.
public struct LeadBooking: Hashable, Sendable {
    public let day: LocalDate
    public let time: TimeOfDay?

    public init(day: LocalDate, time: TimeOfDay?) {
        self.day = day
        self.time = time
    }
}

/// Temat zgłoszenia rozdzielony na termin z rezerwacji i właściwą treść.
public struct LeadTopic: Hashable, Sendable {
    public let booking: LeadBooking?
    public let text: String

    public init(booking: LeadBooking?, text: String) {
        self.booking = booking
        self.text = text
    }

    private static let bookingPrefix = "Termin:"

    /// Rozbiór tematu. Tekst bez rozpoznawalnego prefiksu wraca bez zmian —
    /// parser niczego nie zgaduje i nie obcina treści, której nie rozumie.
    public static func parse(_ raw: String) -> LeadTopic {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(bookingPrefix) else {
            return LeadTopic(booking: nil, text: trimmed)
        }
        var rest = trimmed.dropFirst(bookingPrefix.count).drop(while: { $0.isWhitespace })
        guard let day = LocalDate(iso: String(rest.prefix(10))) else {
            return LeadTopic(booking: nil, text: trimmed)
        }
        rest = rest.dropFirst(10).drop(while: { $0.isWhitespace })

        let timeToken = String(rest.prefix(while: { !$0.isWhitespace }))
        let time = lenientTime(timeToken)
        if time != nil {
            rest = rest.dropFirst(timeToken.count)
        }
        let text = String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
        return LeadTopic(booking: LeadBooking(day: day, time: time), text: text)
    }

    /// Godzina w zapisie `G:MM` albo `GG:MM` (formularz strony bywa niespójny).
    private static func lenientTime(_ token: String) -> TimeOfDay? {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2 else { return nil }
        let rawHour = String(parts[0])
        let hour = rawHour.count == 1 ? "0" + rawHour : rawHour
        return TimeOfDay(hhmm: hour + ":" + String(parts[1]))
    }
}

/// Kolejka zgłoszeń podzielona tak, jak się nad nią pracuje.
public struct LeadInbox: Equatable, Sendable {
    /// Czekają co najmniej dobę — najstarsze najpierw, bo to one uciekają.
    public let waiting: [Client]
    /// Z ostatnich 24 godzin — najnowsze najpierw.
    public let fresh: [Client]
    /// Obsłużone (w kontakcie) — najnowsze najpierw.
    public let inContact: [Client]

    public init(waiting: [Client], fresh: [Client], inContact: [Client]) {
        self.waiting = waiting
        self.fresh = fresh
        self.inContact = inContact
    }

    /// Wszystko, co wymaga ruchu kancelarii, w kolejności pracy.
    public var needsAction: [Client] { waiting + fresh }
}

public enum LeadWorkflow {

    /// Jak długo zgłoszenie jest „nowe”.
    public static let freshWindow: TimeInterval = 24 * 60 * 60

    /// Chwila przyjęcia zgłoszenia i informacja, czy jest dokładna.
    public static func receivedInstant(of client: Client) -> (date: Date, isExact: Bool) {
        if let receivedAt = client.receivedAt {
            return (receivedAt, true)
        }
        return (noon(of: client.createdAt), false)
    }

    public static func status(of client: Client, now: Date) -> LeadStatus {
        switch client.stage {
        case .client:
            return .client
        case .inContact:
            return .inContact
        case .new:
            let age = now.timeIntervalSince(receivedInstant(of: client).date)
            return age < freshWindow ? .fresh : .waiting
        }
    }

    /// Podział listy kontaktów na kolejkę pracy. Kartoteki (`client`) nie
    /// należą do żadnej grupy — to już nie są zgłoszenia.
    public static func inbox(_ clients: [Client], now: Date) -> LeadInbox {
        var waiting: [Client] = []
        var fresh: [Client] = []
        var inContact: [Client] = []
        for client in clients {
            switch status(of: client, now: now) {
            case .waiting: waiting.append(client)
            case .fresh: fresh.append(client)
            case .inContact: inContact.append(client)
            case .client: break
            }
        }
        return LeadInbox(
            waiting: waiting.sorted { isReceived($0, before: $1) },
            fresh: fresh.sorted { isReceived($1, before: $0) },
            inContact: inContact.sorted { isReceived($1, before: $0) }
        )
    }

    /// „12 min temu”, „3 godz. temu”, „2 dni temu”; przy dacie bez godziny —
    /// „dziś” albo „wczoraj”, bo godzin nie znamy.
    public static func receivedAgoText(of client: Client, now: Date, today: LocalDate) -> String {
        let received = receivedInstant(of: client)
        guard received.isExact else {
            let days = max(0, client.createdAt.days(until: today))
            switch days {
            case 0: return "dziś"
            case 1: return "wczoraj"
            default: return "\(EmmaPlural.days(days)) temu"
            }
        }
        let minutes = max(0, Int(now.timeIntervalSince(received.date) / 60))
        if minutes < 1 { return "przed chwilą" }
        if minutes < 60 { return "\(minutes) min temu" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) godz. temu" }
        return "\(EmmaPlural.days(hours / 24)) temu"
    }

    /// Jak długo zgłoszenie czeka: „2 dni”, a przy dacie bez godziny także
    /// „od wczoraj” (wtedy nie wiemy, czy minęła doba co do godziny).
    public static func waitingText(of client: Client, now: Date, today: LocalDate) -> String {
        let received = receivedInstant(of: client)
        if received.isExact {
            let hours = max(0, Int(now.timeIntervalSince(received.date) / 3600))
            return EmmaPlural.days(max(1, hours / 24))
        }
        let days = client.createdAt.days(until: today)
        return days <= 1 ? "od wczoraj" : EmmaPlural.days(days)
    }

    /// Tekst plakietki: „Nowy · 3 godz. temu”, „Oczekuje · 2 dni”, „W kontakcie”.
    public static func badgeText(for client: Client, now: Date, today: LocalDate) -> String {
        let current = status(of: client, now: now)
        switch current {
        case .fresh:
            return "\(current.title) · \(receivedAgoText(of: client, now: now, today: today))"
        case .waiting:
            return "\(current.title) · \(waitingText(of: client, now: now, today: today))"
        case .inContact, .client:
            return current.title
        }
    }

    // MARK: Pomocnicze

    /// Porządek po chwili przyjęcia, a przy remisie po identyfikatorze —
    /// lista nie może „skakać” między odświeżeniami.
    private static func isReceived(_ lhs: Client, before rhs: Client) -> Bool {
        let left = receivedInstant(of: lhs).date
        let right = receivedInstant(of: rhs).date
        if left != right { return left < right }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    /// Południe danego dnia w strefie kancelarii (przybliżenie chwili przyjęcia).
    static func noon(of day: LocalDate) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: EmmaTime.referenceTimeZone) ?? TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = 12
        if let date = calendar.date(from: components) { return date }
        return Date(timeIntervalSince1970: TimeInterval(day.daysSinceEpoch) * 86_400 + 43_200)
    }
}
