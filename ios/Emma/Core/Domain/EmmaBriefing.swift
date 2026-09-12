import Foundation

// MARK: - Zdania o dniu i odmiana imion
//
// Te funkcje mieszkały w `TodayScreen.swift`, czyli w warstwie SwiftUI. Skutek: tego
// samego napisu nie dało się użyć w podglądzie na Linuksie (brak SwiftUI) ani
// w teście logiki — więc naturalnym następstwem była druga kopia. Teraz jest jedno
// miejsce, wołane przez ekran „Dzisiaj”, przez eksporter podglądu i przez testy.

public enum EmmaBriefing {

    public static func vocative(_ name: String) -> String {
        guard let first = name.split(separator: " ").first.map(String.init) else { return name }
        switch first {
        case "Tomasz": return "Tomaszu"
        case "Paweł": return "Pawle"
        default: return first
        }
    }

    public static func briefing(
        events: [ScheduledEvent],
        tasks: [TaskItem],
        waitingForReply: [Client],
        clientNames: [ClientID: String]
    ) -> String {
        let relevant = events.filter { $0.status != .finished }.sorted { $0.time < $1.time }
        var lines: [String] = []
        lines.append("Dzisiaj w zespole: \(EmmaPlural.label(relevant.count, "wydarzenie", "wydarzenia", "wydarzeń")).")
        for event in relevant {
            let who = clientNames[event.clientID] ?? Client.unknownDisplayName
            var line = "\(event.time.hhmm): \(who), \(event.title)."
            if event.status == .toConfirm { line += " Termin czeka na potwierdzenie." }
            lines.append(line)
        }
        lines.append("")
        if tasks.isEmpty {
            lines.append("Do załatwienia: brak otwartych zadań na dziś.")
        } else {
            let list = tasks.map(\.title).joined(separator: "; ")
            lines.append("Do załatwienia: \(list).")
        }
        if waitingForReply.isEmpty {
            lines.append("Wszystkie rozmowy zaopiekowane.")
        } else {
            lines.append("Na odpowiedź czekają: \(waitingForReply.map(\.displayName).joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }
}
