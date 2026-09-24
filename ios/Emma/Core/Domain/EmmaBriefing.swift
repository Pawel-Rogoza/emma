import Foundation

// MARK: - Zdania o dniu i odmiana imion
//
// Te funkcje mieszkały w `TodayScreen.swift`, czyli w warstwie SwiftUI. Skutek: tego
// samego napisu nie dało się użyć w podglądzie na Linuksie (brak SwiftUI) ani
// w teście logiki — więc naturalnym następstwem była druga kopia. Teraz jest jedno
// miejsce, wołane przez ekran „Dzisiaj”, przez eksporter podglądu i przez testy.

public enum EmmaBriefing {

    /// Zdanie o dniu z jawnym rozróżnieniem „pusto” od „nie udało się sprawdzić”.
    ///
    /// `events` i `tasks` są opcjonalne celowo: `nil` znaczy „odczyt się nie powiódł”,
    /// a `[]` znaczy „sprawdzone, naprawdę nic nie ma”. Wcześniej oba przypadki
    /// wyglądały identycznie, więc awaria kalendarza dawała odpowiedź „nie masz
    /// terminów”. To jest dokładnie ten błąd, którego nie wolno pokazać prawnikowi.
    public static func briefing(
        events: [ScheduledEvent]?,
        tasks: [TaskItem]?,
        waitingForReply: [Client],
        clientNames: [ClientID: String]
    ) -> String {
        var lines: [String] = []

        if let events {
            let relevant = events.filter { $0.status != .finished }.sorted { $0.time < $1.time }
            lines.append("Dzisiaj w zespole: \(EmmaPlural.label(relevant.count, "wydarzenie", "wydarzenia", "wydarzeń")).")
            for event in relevant {
                // Termin bez klienta (rozprawa, spotkanie wewnętrzne) to sam tytuł.
                // Stanu „do potwierdzenia” już nie czytamy: CRM go nie prowadzi,
                // więc każdy termin brzmiał jak niepotwierdzony.
                if let clientID = event.clientID {
                    let who = clientNames[clientID] ?? Client.unknownDisplayName
                    lines.append("\(event.time.hhmm): \(who), \(event.title).")
                } else {
                    lines.append("\(event.time.hhmm): \(event.title).")
                }
            }
        } else {
            lines.append("Nie udało się sprawdzić kalendarza. Nie mam pewności, czy dziś są terminy.")
        }

        lines.append("")
        if let tasks {
            if tasks.isEmpty {
                lines.append("Do załatwienia: brak otwartych zadań na dziś.")
            } else {
                let list = tasks.map(\.title).joined(separator: "; ")
                lines.append("Do załatwienia: \(list).")
            }
        } else {
            lines.append("Nie udało się sprawdzić listy zadań. Nie mam pewności, co jest dziś do zrobienia.")
        }

        if waitingForReply.isEmpty {
            lines.append("Wszystkie rozmowy zaopiekowane.")
        } else {
            lines.append("Na odpowiedź czekają: \(waitingForReply.map(\.displayName).joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }
}
