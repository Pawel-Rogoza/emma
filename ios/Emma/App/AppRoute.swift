import Foundation

// MARK: - Zakładki i trasy
//
// Pięć zakładek dokładnie jak w referencji (`nav()` w `reference/prototype/app.js`):
// Dzisiaj · Klienci · Emma · Rozmowy · Kalendarz.
//
// Mapowanie podświetlenia zakładki również pochodzi z referencji:
//   karta klienta i sprawa → zakładka Klienci
//   wątek rozmowy          → zakładka Rozmowy
//   lista zadań            → zakładka Dzisiaj

public enum AppTab: String, CaseIterable, Hashable, Identifiable, Sendable {
    case today
    case clients
    case emma
    case messages
    case calendar

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "Dzisiaj"
        case .clients: return "Klienci"
        case .emma: return "Emma"
        case .messages: return "Rozmowy"
        case .calendar: return "Kalendarz"
        }
    }

    public var systemImage: String {
        switch self {
        case .today: return "house"
        case .clients: return "person.2"
        case .emma: return "sparkles"
        case .messages: return "bubble.left.and.bubble.right"
        case .calendar: return "calendar"
        }
    }

    /// Zakładka środkowa ma w referencji własny, ciemny „chip” zamiast zwykłej ikony.
    public var isEmmaChip: Bool { self == .emma }
}

/// Ekrany wypychane na stos nawigacji w obrębie zakładki.
public enum AppRoute: Hashable, Sendable {
    case person(ClientID)
    case legalCase(CaseID)
    case tasks
    case thread(ThreadID)
}

/// Arkusze modalne. Odpowiadają wywołaniom `openSheet(…)` z referencji.
public enum AppSheet: Hashable, Identifiable, Sendable {
    // Wspólne
    case profile
    case resetDemo

    // Klienci i sprawy
    case newLead
    case startCase(ClientID)
    case caseSettings(CaseID)

    // Praca kancelarii
    case note(clientID: ClientID, caseID: CaseID?)
    case taskForm(editing: TaskID?, clientID: ClientID?, caseID: CaseID?)
    case eventForm(editing: EventID?, clientID: ClientID?, caseID: CaseID?, initialDay: LocalDate?)
    case eventDetail(EventID)
    case taskDetail(TaskID)

    // Komunikator
    case newConversation
    case conversationOptions(ThreadID)
    case messageOptions(threadID: ThreadID, messageID: MessageID)

    // Emma
    case emmaContextSelection(action: EmmaQuickAction?)

    public var id: String {
        switch self {
        case .profile: return "profile"
        case .resetDemo: return "reset"
        case .newLead: return "new-lead"
        case .startCase(let clientID): return "start-case-\(clientID.rawValue)"
        case .caseSettings(let caseID): return "case-settings-\(caseID.rawValue)"
        case .note(let clientID, let caseID):
            return "note-\(clientID.rawValue)-\(caseID?.rawValue ?? "none")"
        case .taskForm(let taskID, let clientID, let caseID):
            return "task-\(taskID?.rawValue ?? "new")-\(clientID?.rawValue ?? "none")-\(caseID?.rawValue ?? "none")"
        case .eventForm(let eventID, let clientID, let caseID, let initialDay):
            let day = initialDay?.isoString ?? "none"
            return "event-\(eventID?.rawValue ?? "new")-\(clientID?.rawValue ?? "none")-\(caseID?.rawValue ?? "none")-\(day)"
        case .eventDetail(let eventID): return "event-detail-\(eventID.rawValue)"
        case .taskDetail(let taskID): return "task-detail-\(taskID.rawValue)"
        case .newConversation: return "new-conversation"
        case .conversationOptions(let threadID): return "conversation-options-\(threadID.rawValue)"
        case .messageOptions(let threadID, let messageID):
            return "message-options-\(threadID.rawValue)-\(messageID.rawValue)"
        case .emmaContextSelection(let action): return "emma-context-\(action?.rawValue ?? "none")"
        }
    }
}

/// Skróty Emmy wywoływane z innych ekranów (odpowiadają `assistantExample(action)`).
public enum EmmaQuickAction: String, Hashable, CaseIterable, Sendable {
    case brief
    case reply
    case note
    case task
    case prepareCase

    public var title: String {
        switch self {
        case .brief: return "Podsumuj dzisiejszy dzień."
        case .reply: return "Przygotuj odpowiedź."
        case .note: return "Chcę zapisać notatkę."
        case .task: return "Chcę dodać zadanie."
        case .prepareCase: return "Przygotuj mnie do rozmowy."
        }
    }
}

// MARK: - Stos nawigacji zakładki

/// Osobny stos dla każdej zakładki. Referencja trzyma jedną wspólną historię;
/// w iOS naturalne jest zachowanie stanu każdej zakładki osobno, dlatego
/// powrót do zakładki przywraca jej poprzednią pozycję.
public struct TabNavigation: Equatable, Sendable {
    public var path: [AppRoute] = []

    public mutating func push(_ route: AppRoute) {
        // Ten sam ekran nie jest odkładany dwa razy pod rząd.
        if path.last != route { path.append(route) }
    }

    public mutating func pop() {
        if !path.isEmpty { path.removeLast() }
    }

    public mutating func popToRoot() {
        path.removeAll()
    }

    /// Zastąpienie stosu jedną trasą (używane przy przejściach między zakładkami).
    public mutating func reset(to route: AppRoute? = nil) {
        path = route.map { [$0] } ?? []
    }
}
