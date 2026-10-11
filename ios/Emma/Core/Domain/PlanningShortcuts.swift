import Foundation

// MARK: - Skróty planowania: daty, godziny i opis wybranego dnia
//
// Review 11.10.2026: „formularz ma być przejrzysty i prosty w użyciu, a zadania
// i terminy mają super działać i być w kalendarzu”. Formularze zadania
// i terminu dzielą jedną logikę skrótów — czystą i testowaną, żeby „W poniedziałek” w obu
// znaczyło ten sam dzień, a opis pod datą mówił to samo co kalendarz.

public enum PlanningShortcuts {

    /// Szybki wybór dnia („Jutro”, „W poniedziałek”, „Za tydzień”).
    public struct Day: Hashable, Sendable {
        public let title: String
        public let date: LocalDate
    }

    /// Skróty dnia: dziś, jutro, pojutrze, najbliższy poniedziałek, za tydzień
    /// i za dwa tygodnie. Poniedziałek tylko wtedy, gdy nie pokrywa się z innym
    /// skrótem (w sobotę to „pojutrze”, w poniedziałek — „za tydzień”).
    public static func days(today: LocalDate) -> [Day] {
        let toMonday = 7 - today.weekdayIndexMondayFirst
        var result = [
            Day(title: "Dziś", date: today),
            Day(title: "Jutro", date: today.adding(days: 1)),
            Day(title: "Pojutrze", date: today.adding(days: 2))
        ]
        if (3..<7).contains(toMonday) {
            result.append(Day(title: "W poniedziałek", date: today.adding(days: toMonday)))
        }
        result.append(Day(title: "Za tydzień", date: today.adding(days: 7)))
        result.append(Day(title: "Za 2 tyg.", date: today.adding(days: 14)))
        return result
    }

    /// Typowe godziny spotkań i rozpraw w kancelarii.
    public static let times: [TimeOfDay] = [9, 10, 11, 12, 14, 16].compactMap { TimeOfDay(minutes: $0 * 60) }

    /// „dziś”, „jutro”, „za 3 dni”, „za 2 tygodnie”, „wczoraj”, „5 dni temu”.
    public static func relative(_ date: LocalDate, today: LocalDate) -> String {
        let distance = today.days(until: date)
        switch distance {
        case 0: return "dziś"
        case 1: return "jutro"
        case 2: return "pojutrze"
        case -1: return "wczoraj"
        case let days where days < 0:
            return "\(EmmaPlural.days(-days)) temu"
        case 7: return "za tydzień"
        case let days where days % 7 == 0 && days <= 28:
            return "za " + EmmaPlural.label(days / 7, "tydzień", "tygodnie", "tygodni")
        default:
            return "za \(EmmaPlural.days(distance))"
        }
    }

    /// Ostrzeżenie pod datą: dzień wolny albo data w przeszłości. `nil` — w porządku.
    public static func warning(for date: LocalDate, today: LocalDate) -> String? {
        if date < today { return "Ta data już minęła." }
        if let holiday = PolishHolidays.name(of: date) { return "To dzień wolny: \(holiday)." }
        switch date.weekdayIndexMondayFirst {
        case 5: return "To sobota."
        case 6: return "To niedziela."
        default: return nil
        }
    }
}
