import Foundation

// MARK: - Terminy procesowe
//
// Karnista liczy terminy codziennie: 7 dni na zażalenie, 14 na apelację,
// 30 na kasację — i za każdym razem sprawdza, czy ostatni dzień nie wypada
// w sobotę albo święto. Pomyłka o jeden dzień to termin nie do przywrócenia.
// Formularz terminu liczy to sam, a reguła mieszka w rdzeniu, żeby dało się ją
// przetestować bez SwiftUI.
//
// Zasady liczenia (terminy w dniach):
//   • nie wlicza się dnia zdarzenia, od którego biegnie termin
//     (art. 123 § 1 k.p.k., art. 57 § 1 k.p.a., art. 83 § 1 p.p.s.a.),
//   • koniec terminu w sobotę lub dzień ustawowo wolny od pracy przesuwa się
//     na najbliższy dzień, który nie jest ani jednym, ani drugim
//     (art. 123 § 3 k.p.k., art. 57 § 5 k.p.a., art. 83 § 2 p.p.s.a.).
// Niedziela jest dniem ustawowo wolnym, więc też przesuwa termin.
//
// Wynik to podpowiedź do wpisania w kalendarz — decyzję i odczyt pouczenia
// zostawiamy adwokatowi (formularz mówi to wprost).

/// Dni ustawowo wolne od pracy (ustawa z 18 stycznia 1951 r. o dniach wolnych
/// od pracy), z Wigilią wolną od 2025 r.
public enum PolishHolidays {

    public static func isHoliday(_ date: LocalDate) -> Bool {
        if date.weekdayIndexMondayFirst == 6 { return true } // niedziela
        switch (date.month, date.day) {
        case (1, 1), (1, 6), (5, 1), (5, 3), (8, 15), (11, 1), (11, 11), (12, 25), (12, 26):
            return true
        case (12, 24):
            return date.year >= 2025
        default:
            break
        }
        let easter = easterSunday(year: date.year)
        // Poniedziałek Wielkanocny, Zielone Świątki (niedziela), Boże Ciało.
        return date == easter
            || date == easter.adding(days: 1)
            || date == easter.adding(days: 49)
            || date == easter.adding(days: 60)
    }

    /// Nazwa święta do wyjaśnienia przesunięcia („1 listopada to Wszystkich Świętych”).
    public static func name(of date: LocalDate) -> String? {
        switch (date.month, date.day) {
        case (1, 1): return "Nowy Rok"
        case (1, 6): return "Trzech Króli"
        case (5, 1): return "Święto Pracy"
        case (5, 3): return "Święto Konstytucji 3 Maja"
        case (8, 15): return "Wniebowzięcie NMP"
        case (11, 1): return "Wszystkich Świętych"
        case (11, 11): return "Święto Niepodległości"
        case (12, 24) where date.year >= 2025: return "Wigilia"
        case (12, 25), (12, 26): return "Boże Narodzenie"
        default: break
        }
        let easter = easterSunday(year: date.year)
        if date == easter { return "Wielkanoc" }
        if date == easter.adding(days: 1) { return "Poniedziałek Wielkanocny" }
        if date == easter.adding(days: 49) { return "Zielone Świątki" }
        if date == easter.adding(days: 60) { return "Boże Ciało" }
        return nil
    }

    /// Niedziela Wielkanocna (kalendarz gregoriański, algorytm Meeusa/Jonesa/Butchera).
    public static func easterSunday(year: Int) -> LocalDate {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return LocalDate(year: year, month: month, day: day)
    }

    /// Dzień, w którym można skutecznie dokonać czynności: nie sobota
    /// i nie dzień ustawowo wolny od pracy.
    public static func isWorkingDay(_ date: LocalDate) -> Bool {
        date.weekdayIndexMondayFirst != 5 && !isHoliday(date)
    }
}

/// Typowy termin procesowy: w dniach (z przesunięciem z soboty i świąt) albo
/// w godzinach (zatrzymanie — liczone od chwili, bez przesunięć).
public struct DeadlineRule: Identifiable, Hashable, Sendable {

    public enum Span: Hashable, Sendable {
        case days(Int)
        /// Termin miesięczny: koniec w dniu, który datą odpowiada dniowi
        /// zdarzenia, a gdy go nie ma — w ostatnim dniu miesiąca
        /// (art. 123 § 2 k.p.k., art. 57 § 3 k.p.a.).
        case months(Int)
        case hours(Int)
    }

    public let id: String
    /// Krótka nazwa czynności — trafia do nazwy terminu w kalendarzu.
    public let title: String
    public let span: Span
    /// Od czego biegnie termin — pokazywane przy dacie początkowej.
    public let startsFrom: String
    /// Podstawa prawna — do sprawdzenia w pouczeniu.
    public let legalBasis: String

    public init(id: String, title: String, span: Span, startsFrom: String, legalBasis: String) {
        self.id = id
        self.title = title
        self.span = span
        self.startsFrom = startsFrom
        self.legalBasis = legalBasis
    }

    /// Termin godzinowy liczy się od chwili (data i godzina), a nie od dnia.
    public var isHourly: Bool {
        if case .hours = span { return true }
        return false
    }

    /// „14 dni”, „48 h”.
    public var spanText: String {
        switch span {
        case .days(let days): return EmmaPlural.days(days)
        case .months(let months): return EmmaPlural.label(months, "miesiąc", "miesiące", "miesięcy")
        case .hours(let hours): return "\(hours) h"
        }
    }
}

public enum ProceduralDeadlines {

    /// Najczęstsze terminy kancelarii: najpierw karne, potem pobytowe (k.p.a., WSA).
    public static let common: [DeadlineRule] = [
        DeadlineRule(
            id: "kpk-zazalenie", title: "Zażalenie", span: .days(7),
            startsFrom: "od ogłoszenia lub doręczenia postanowienia", legalBasis: "art. 460 k.p.k."
        ),
        DeadlineRule(
            id: "kpk-uzasadnienie", title: "Wniosek o uzasadnienie", span: .days(7),
            startsFrom: "od ogłoszenia wyroku", legalBasis: "art. 422 § 1 k.p.k."
        ),
        DeadlineRule(
            id: "kpk-apelacja", title: "Apelacja", span: .days(14),
            startsFrom: "od doręczenia wyroku z uzasadnieniem", legalBasis: "art. 445 § 1 k.p.k."
        ),
        DeadlineRule(
            id: "kpk-sprzeciw", title: "Sprzeciw od wyroku nakazowego", span: .days(7),
            startsFrom: "od doręczenia wyroku nakazowego", legalBasis: "art. 506 § 1 k.p.k."
        ),
        DeadlineRule(
            id: "kpk-kasacja", title: "Kasacja", span: .days(30),
            startsFrom: "od doręczenia wyroku z uzasadnieniem", legalBasis: "art. 524 § 1 k.p.k."
        ),
        DeadlineRule(
            id: "kpk-zazalenie-areszt", title: "Zażalenie na areszt", span: .days(7),
            startsFrom: "od ogłoszenia lub doręczenia postanowienia o środku zapobiegawczym",
            legalBasis: "art. 252 § 1 i art. 460 k.p.k."
        ),
        DeadlineRule(
            id: "kpk-zazalenie-umorzenie", title: "Zażalenie na umorzenie", span: .days(7),
            startsFrom: "od doręczenia postanowienia o umorzeniu lub odmowie wszczęcia",
            legalBasis: "art. 306 § 1 i art. 460 k.p.k."
        ),
        DeadlineRule(
            id: "kpk-subsydiarny", title: "Subsydiarny akt oskarżenia", span: .months(1),
            startsFrom: "od doręczenia zawiadomienia o ponownym umorzeniu lub odmowie",
            legalBasis: "art. 55 § 1 k.p.k."
        ),
        DeadlineRule(
            id: "kpk-przywrocenie", title: "Wniosek o przywrócenie terminu", span: .days(7),
            startsFrom: "od ustania przeszkody", legalBasis: "art. 126 § 1 k.p.k."
        ),
        DeadlineRule(
            id: "kpk-zatrzymanie-48", title: "Zatrzymanie — wniosek o areszt", span: .hours(48),
            startsFrom: "od chwili zatrzymania; bez wniosku zatrzymanego trzeba zwolnić",
            legalBasis: "art. 248 § 1 k.p.k."
        ),
        DeadlineRule(
            id: "kpk-zatrzymanie-72", title: "Zatrzymanie — koniec 72 h", span: .hours(72),
            startsFrom: "od chwili zatrzymania; bez postanowienia o areszcie trzeba zwolnić",
            legalBasis: "art. 248 § 2 k.p.k."
        ),
        DeadlineRule(
            id: "kpa-odwolanie", title: "Odwołanie od decyzji", span: .days(14),
            startsFrom: "od doręczenia decyzji", legalBasis: "art. 129 § 2 k.p.a."
        ),
        DeadlineRule(
            id: "kpa-zazalenie", title: "Zażalenie na postanowienie (k.p.a.)", span: .days(7),
            startsFrom: "od doręczenia postanowienia", legalBasis: "art. 141 § 2 k.p.a."
        ),
        DeadlineRule(
            id: "ppsa-skarga", title: "Skarga do WSA", span: .days(30),
            startsFrom: "od doręczenia rozstrzygnięcia", legalBasis: "art. 53 § 1 p.p.s.a."
        ),
        DeadlineRule(
            id: "ppsa-skarga-kasacyjna", title: "Skarga kasacyjna do NSA", span: .days(30),
            startsFrom: "od doręczenia wyroku z uzasadnieniem", legalBasis: "art. 177 § 1 p.p.s.a."
        )
    ]

    /// Czynności w kolejności, w jakiej przydają się na danym etapie: najpierw
    /// te, które na nim naprawdę biegną, potem reszta. Bez profilu — lista
    /// ogólna. Nic nie znika: adwokat zawsze może wybrać inną czynność.
    public static func suggested(kind: CaseKind?, stage: CaseStage?) -> [DeadlineRule] {
        let first: [String]
        switch (kind, stage) {
        case (_, .preTrial?):
            first = ["kpk-zatrzymanie-48", "kpk-zatrzymanie-72", "kpk-zazalenie-areszt",
                     "kpk-zazalenie-umorzenie", "kpk-subsydiarny", "kpk-zazalenie"]
        case (_, .firstInstance?) where kind != .enforcement:
            first = ["kpk-uzasadnienie", "kpk-apelacja", "kpk-sprzeciw", "kpk-zazalenie-areszt", "kpk-zazalenie"]
        case (_, .appeal?) where kind != .enforcement:
            first = ["kpk-uzasadnienie", "kpk-kasacja", "kpk-zazalenie-areszt"]
        case (_, .cassation?):
            first = ["kpk-kasacja", "kpk-przywrocenie"]
        case (.enforcement?, _):
            first = ["kpk-zazalenie", "kpk-przywrocenie"]
        case (_, .adminFirst?), (_, .adminAppeal?):
            first = ["kpa-odwolanie", "kpa-zazalenie", "ppsa-skarga"]
        case (_, .adminCourt?):
            first = ["ppsa-skarga", "ppsa-skarga-kasacyjna"]
        case (.residence?, _), (.deportation?, _):
            first = ["kpa-odwolanie", "kpa-zazalenie", "ppsa-skarga", "ppsa-skarga-kasacyjna"]
        case (.criminal?, _):
            first = ["kpk-zazalenie", "kpk-apelacja", "kpk-zatrzymanie-48"]
        default:
            return common
        }
        let leading = first.compactMap { id in common.first { $0.id == id } }
        return leading + common.filter { rule in !first.contains(rule.id) }
    }

    public struct Result: Equatable, Sendable {
        /// Ostatni dzień terminu po przesunięciu — to trafia do kalendarza.
        public let due: LocalDate
        /// Dzień wynikający z samego dodania dni.
        public let nominal: LocalDate
        /// Dlaczego termin się przesunął („sobota”, „Wszystkich Świętych”); `nil` bez przesunięcia.
        public let shiftReason: String?

        public var isShifted: Bool { due != nominal }
    }

    /// Ostatni dzień terminu `days` dni od zdarzenia `from`.
    public static func due(from: LocalDate, days: Int) -> Result {
        // Dnia zdarzenia nie wlicza się: 7 dni od poniedziałku to następny poniedziałek.
        let nominal = from.adding(days: days)
        var due = nominal
        while !PolishHolidays.isWorkingDay(due) {
            due = due.adding(days: 1)
        }
        return Result(due: due, nominal: nominal, shiftReason: due == nominal ? nil : reason(for: nominal))
    }

    /// Ostatni dzień terminu `months` miesięcy od zdarzenia `from`
    /// (31 stycznia + 1 miesiąc → 28/29 lutego), z tym samym przesunięciem
    /// z soboty i dni wolnych co terminy dniowe.
    public static func due(from: LocalDate, months: Int) -> Result {
        let nominal = from.addingMonths(months)
        var due = nominal
        while !PolishHolidays.isWorkingDay(due) {
            due = due.adding(days: 1)
        }
        return Result(due: due, nominal: nominal, shiftReason: due == nominal ? nil : reason(for: nominal))
    }

    /// Ostatni dzień terminu dniowego albo miesięcznego; `nil` dla godzinowego.
    public static func due(from: LocalDate, rule: DeadlineRule) -> Result? {
        switch rule.span {
        case .days(let days): return due(from: from, days: days)
        case .months(let months): return due(from: from, months: months)
        case .hours: return nil
        }
    }

    /// Koniec terminu godzinowego: chwila zatrzymania plus `hours` godzin.
    /// Sobota ani święto nic tu nie zmieniają — zegar biegnie cały czas.
    public static func due(from instant: Date, hours: Int) -> Date {
        instant.addingTimeInterval(TimeInterval(hours) * 3600)
    }

    public static func rule(id: String) -> DeadlineRule? {
        common.first { $0.id == id }
    }

    /// Wyliczenie dla Emmy (`app_compute_deadline`): ta sama arytmetyka co
    /// w formularzu, żeby głos i kalkulator nigdy nie podały dwóch dat.
    public struct Computation: Equatable, Sendable {
        /// `nil`, gdy liczono z samej liczby dni.
        public let rule: DeadlineRule?
        public let from: LocalDate
        public let result: Result
        public let spanText: String
    }

    public enum ComputationError: Error, Equatable, Sendable {
        case unknownRule(String)
        /// Zatrzymanie liczy się w godzinach od chwili — to robi formularz.
        case hourly(DeadlineRule)
        case missingSpan
    }

    /// Reguła z listy albo `days` dni od `from`. Reguła ma pierwszeństwo.
    public static func compute(ruleID: String?, days: Int?, from: LocalDate) -> Swift.Result<Computation, ComputationError> {
        if let ruleID, !ruleID.isEmpty {
            guard let rule = rule(id: ruleID) else { return .failure(.unknownRule(ruleID)) }
            guard let result = due(from: from, rule: rule) else { return .failure(.hourly(rule)) }
            return .success(Computation(rule: rule, from: from, result: result, spanText: rule.spanText))
        }
        guard let days, days > 0, days <= 366 else { return .failure(.missingSpan) }
        return .success(Computation(rule: nil, from: from, result: due(from: from, days: days), spanText: EmmaPlural.days(days)))
    }

    private static func reason(for day: LocalDate) -> String {
        if let holiday = PolishHolidays.name(of: day) { return holiday }
        return day.weekdayIndexMondayFirst == 5 ? "sobota" : "niedziela"
    }
}
