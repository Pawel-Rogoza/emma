import Foundation

// MARK: - Powiadomienia o pracy: zadania i nowe leady
//
// Review 10.10.2026: „powiadomienia mają się triggerować, jak wpadnie nowy lead
// albo gdy zbliża się zadanie/termin — przy wiadomościach i mailach nie”.
// Terminy mają już przypomnienia (`EventReminderPlan`); tu są dwa brakujące
// rodzaje. Czysta logika — co i kiedy; system obsługuje `EventReminderScheduler`.

/// Zadanie z terminem: powiadomienie rano w dniu, na który jest zaplanowane.
public enum TaskReminderPlan {

    public struct Item: Equatable, Sendable {
        public let identifier: String
        public let taskID: TaskID
        public let fireAt: Date
        public let title: String
        public let body: String
    }

    public static let identifierPrefix = "emma.task."

    /// Zadanie ma tylko datę — przypominamy o 9:00, jak o terminie całodniowym.
    public static let hour = EventReminderPlan.allDayHour

    /// Część systemowego limitu 64 powiadomień przeznaczona na zadania.
    public static let defaultLimit = 10

    public static func items(
        tasks: [TaskItem],
        clientNames: [ClientID: String],
        now: Date,
        timeZoneIdentifier: String = EmmaTime.referenceTimeZone,
        limit: Int = defaultLimit
    ) -> [Item] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "UTC")!
        let items: [Item] = tasks.compactMap { task in
            guard !task.isDone, let due = task.dueDate else { return nil }
            let components = DateComponents(year: due.year, month: due.month, day: due.day, hour: hour)
            guard let fireAt = calendar.date(from: components), fireAt > now else { return nil }
            var parts = [task.priority == .urgent ? "Pilne zadanie na dziś" : "Zadanie na dziś"]
            if let clientID = task.clientID, let name = clientNames[clientID] {
                parts.append(name)
            }
            return Item(
                identifier: identifierPrefix + task.id.rawValue,
                taskID: task.id,
                fireAt: fireAt,
                title: task.title,
                body: parts.joined(separator: " · ")
            )
        }
        return Array(
            items
                .sorted { $0.fireAt != $1.fireAt ? $0.fireAt < $1.fireAt : $0.identifier < $1.identifier }
                .prefix(limit)
        )
    }
}

/// Nowy lead (np. formularz ze strony): powiadomienie, gdy telefon go zauważy.
///
/// Bez pushy z serwera aplikacja sprawdza leady przy odświeżeniu w tle i po
/// powrocie na pierwszy plan. Zapamiętuje, kogo już widziała — pierwsze
/// sprawdzenie (świeża instalacja, nowe logowanie) tylko zapamiętuje, żeby
/// nie zasypać ekranu blokady całą listą „Nowych”.
public enum LeadAlertPlan {

    public struct Lead: Equatable, Sendable {
        public let id: String
        public let name: String
        public let topic: String

        public init(id: String, name: String, topic: String) {
            self.id = id
            self.name = name
            self.topic = topic
        }
    }

    public struct Item: Equatable, Sendable {
        public let identifier: String
        public let clientID: ClientID
        public let title: String
        public let body: String
    }

    public struct Outcome: Equatable, Sendable {
        public let alerts: [Item]
        /// Zbiór do zapamiętania na następne sprawdzenie.
        public let known: Set<String>
    }

    public static let identifierPrefix = "emma.lead."

    /// Więcej naraz to już nie „nowy lead”, tylko np. import — jedno zbiorcze.
    public static let maxSeparateAlerts = 3

    /// `known == nil` — pierwsze sprawdzenie na tym telefonie.
    public static func check(leads: [Lead], known: Set<String>?) -> Outcome {
        let ids = Set(leads.map(\.id))
        guard let known else { return Outcome(alerts: [], known: ids) }
        let fresh = leads.filter { !known.contains($0.id) }
        // Pamiętamy także dawnych: lead przeniesiony do „W kontakcie” i z powrotem
        // nie powinien dzwonić drugi raz.
        let remembered = known.union(ids)
        guard !fresh.isEmpty else { return Outcome(alerts: [], known: remembered) }
        if fresh.count > maxSeparateAlerts {
            let names = fresh.prefix(3).map(\.name).joined(separator: ", ")
            let item = Item(
                identifier: identifierPrefix + "batch." + fresh.map(\.id).sorted().joined(separator: "."),
                clientID: ClientID(fresh[0].id),
                title: "Nowe leady: \(fresh.count)",
                body: "\(names) i inni"
            )
            return Outcome(alerts: [item], known: remembered)
        }
        let items = fresh.map { lead in
            let topic = lead.topic.trimmingCharacters(in: .whitespacesAndNewlines)
            return Item(
                identifier: identifierPrefix + lead.id,
                clientID: ClientID(lead.id),
                title: "Nowy lead: \(lead.name)",
                body: topic.isEmpty ? "Nowe zgłoszenie w „Nowych”" : topic
            )
        }
        return Outcome(alerts: items, known: remembered)
    }
}
