import Foundation

// MARK: - Podział dnia na najbliższy termin, dalsze i minione
//
// Etap 3 audytu UX: „Dzisiaj” ma pokazać **najbliższy termin** jako osobną,
// wyróżnioną pozycję, a nie pierwszy wiersz płaskiej listy. Minione terminy mają
// trafić do zwijanej sekcji, żeby nie spychały zadań poza pierwszy widok.
//
// Reguła w rdzeniu: sortowanie i podział to logika, nie rysowanie. Dzięki temu
// da się ją sprawdzić bez SwiftUI i jest jedno miejsce, które decyduje, co znaczy
// „najbliższy”.

public enum DayAgenda {

    public struct Split: Equatable, Sendable {
        /// Pierwszy termin, który się jeszcze nie zakończył (może trwać).
        public let next: ScheduledEvent?
        /// Pozostałe terminy przed nami, w kolejności godzin.
        public let upcoming: [ScheduledEvent]
        /// Terminy zakończone, w kolejności godzin.
        public let past: [ScheduledEvent]

        public init(next: ScheduledEvent?, upcoming: [ScheduledEvent], past: [ScheduledEvent]) {
            self.next = next
            self.upcoming = upcoming
            self.past = past
        }
    }

    /// Dzieli terminy **jednego dnia** względem bieżącej godziny.
    ///
    /// Zakłada, że wejście dotyczy jednego dnia — tak używa tego ekran „Dzisiaj”.
    /// Termin trwający (`isHappening`) jest nadal najbliższy, a nie miniony.
    public static func split(_ events: [ScheduledEvent], now: TimeOfDay) -> Split {
        let ordered = events.sorted { $0.time < $1.time }
        let remaining = ordered.filter { !$0.hasPassed(at: now) }
        let past = ordered.filter { $0.hasPassed(at: now) }
        return Split(next: remaining.first, upcoming: Array(remaining.dropFirst()), past: past)
    }

    /// „Po rozprawie”: ostatni dzisiejszy termin w sprawie, który już się
    /// skończył, a nikt go nie zamknął. Po wyjściu z sądu adwokat ma trzy
    /// rzeczy do zrobienia — notatka, kolejny termin, zamknięcie — i chce je
    /// zrobić od razu, zanim szczegóły wylecą z głowy.
    public static func debrief(_ split: Split) -> ScheduledEvent? {
        split.past.last { $0.kind == .caseDeadline && $0.status != .finished }
    }
}
