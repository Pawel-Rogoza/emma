import AppIntents

// MARK: - Skróty Siri, Spotlight i przycisku czynności
//
// Redesign 0.22.0: Emma poza aplikacją. Te same trzy wejścia co szybkie akcje
// z ikony (`HomeScreenQuickActions`) — rozmowa z Emmą, nowy termin, nowe
// zadanie — są dostępne z Siri („Rozmawiaj z Emmą”), Spotlight, aplikacji
// Skróty, przycisku czynności i Centrum sterowania (przez Skróty).
//
// Intencja tylko odkłada czynność w `HomeScreenQuickActions.pending`; powłoka
// wykonuje ją po odblokowaniu (Face ID), więc skrót nie omija blokady.

struct TalkToEmmaIntent: AppIntent {
    static let title: LocalizedStringResource = "Rozmawiaj z Emmą"
    static let description = IntentDescription("Otwiera Emmę i zaczyna rozmowę głosową.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        HomeScreenQuickActions.shared.pending = .talkToEmma
        return .result()
    }
}

struct NewEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Nowy termin"
    static let description = IntentDescription("Otwiera formularz nowego terminu w Emmie.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        HomeScreenQuickActions.shared.pending = .newEvent
        return .result()
    }
}

struct NewTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Nowe zadanie"
    static let description = IntentDescription("Otwiera formularz nowego zadania w Emmie.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        HomeScreenQuickActions.shared.pending = .newTask
        return .result()
    }
}

struct EmmaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TalkToEmmaIntent(),
            phrases: [
                "Rozmawiaj z \(.applicationName)",
                "Porozmawiaj z \(.applicationName)",
                "Zapytaj \(.applicationName)"
            ],
            shortTitle: "Rozmawiaj z Emmą",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: NewEventIntent(),
            phrases: [
                "Nowy termin w \(.applicationName)",
                "Dodaj termin w \(.applicationName)"
            ],
            shortTitle: "Nowy termin",
            systemImageName: "calendar.badge.plus"
        )
        AppShortcut(
            intent: NewTaskIntent(),
            phrases: [
                "Nowe zadanie w \(.applicationName)",
                "Dodaj zadanie w \(.applicationName)"
            ],
            shortTitle: "Nowe zadanie",
            systemImageName: "checklist"
        )
    }
}
