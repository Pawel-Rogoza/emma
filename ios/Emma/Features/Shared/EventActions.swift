import SwiftUI

// MARK: - Czynności na terminie
//
// Audyt 28.09.2026: „Załatwione” powstało osobno w szczegółach terminu i na
// „Dzisiaj”. Jedno miejsce dla wszystkich ekranów (Dzisiaj, Kalendarz, sprawa,
// karta klienta) — jak `LeadActions` dla zgłoszeń. Szybka czynność nie pyta
// „czy na pewno”: wykonuje się od razu i daje „Cofnij”.

@MainActor
enum EventActions {

    /// „Załatwione” ma sens dla terminu, który trwa dziś albo już minął,
    /// i nie został jeszcze zamknięty.
    static func canFinish(_ event: ScheduledEvent, today: LocalDate) -> Bool {
        event.status != .finished && event.day <= today
    }

    /// Zamyka termin. Zwraca komunikat błędu (formularz pokazuje go u siebie)
    /// albo `nil` po udanym zapisie — wtedy komunikat z „Cofnij” daje ta funkcja.
    @discardableResult
    static func finish(_ event: ScheduledEvent, dependencies: AppDependencies) async -> String? {
        var finished = event
        finished.status = .finished
        let outcome = await dependencies.submit(fallback: "Nie udało się zamknąć terminu.") {
            try await dependencies.repository.updateEvent(finished, expectedVersion: event.version)
        }
        switch outcome {
        case .failed(let message):
            return message
        case .saved(let saved):
            EmmaHaptics.success()
            dependencies.reminders.removeReminder(for: event.id)
            dependencies.showToast(
                "Załatwione: \(event.title)",
                action: AppDependencies.ToastAction(title: "Cofnij") {
                    Task { await EventActions.reopen(saved, previous: event.status, dependencies: dependencies) }
                }
            )
            return nil
        }
    }

    /// Cofnięcie „Załatwione” — z wersją, którą oddał zapis.
    private static func reopen(_ event: ScheduledEvent, previous: EventStatus, dependencies: AppDependencies) async {
        var reopened = event
        reopened.status = previous
        let outcome = await dependencies.submit(fallback: "Nie udało się cofnąć.") {
            try await dependencies.repository.updateEvent(reopened, expectedVersion: event.version)
        }
        if let message = outcome.errorMessage {
            dependencies.showToast(message)
        } else {
            EmmaHaptics.tap()
            dependencies.reminders.scheduleRefresh(dependencies)
        }
    }
}

extension View {
    /// Menu terminu pod przytrzymaniem: „Załatwione” (gdy ma sens) i szczegóły.
    func eventContextMenu(
        _ event: ScheduledEvent,
        dependencies: AppDependencies,
        onOpen: @escaping () -> Void
    ) -> some View {
        contextMenu {
            if EventActions.canFinish(event, today: dependencies.today) {
                Button {
                    Task { await EventActions.finish(event, dependencies: dependencies) }
                } label: {
                    Label("Załatwione", systemImage: "checkmark.circle")
                }
            }
            Button {
                onOpen()
            } label: {
                Label("Szczegóły", systemImage: "arrow.up.forward.square")
            }
        }
    }
}

// MARK: - Czynności na zadaniu

/// Przesunięcie i priorytet zadania pod przytrzymaniem wiersza — bez otwierania
/// formularza. Audyt 28.09.2026: „przesuń na jutro” to najczęstsza zmiana
/// zadania w kancelarii, a wymagała trzech dotknięć i formularza.
@MainActor
enum TaskActions {

    static func reschedule(_ task: TaskItem, to day: LocalDate, label: String, dependencies: AppDependencies) async {
        var updated = task
        updated.dueDate = day
        await save(updated, from: task, message: "\(label): \(task.title)", dependencies: dependencies)
    }

    static func togglePriority(_ task: TaskItem, dependencies: AppDependencies) async {
        var updated = task
        updated.priority = task.priority == .urgent ? .normal : .urgent
        let message = updated.priority == .urgent ? "Pilne: \(task.title)" : "Zwykłe: \(task.title)"
        await save(updated, from: task, message: message, dependencies: dependencies)
    }

    private static func save(_ updated: TaskItem, from original: TaskItem, message: String, dependencies: AppDependencies) async {
        let outcome = await dependencies.submit(fallback: "Nie udało się zapisać zadania.") {
            try await dependencies.repository.updateTask(updated, expectedVersion: original.version)
        }
        switch outcome {
        case .failed(let error):
            dependencies.showToast(error)
        case .saved(let saved):
            EmmaHaptics.success()
            dependencies.showToast(
                message,
                action: AppDependencies.ToastAction(title: "Cofnij") {
                    Task {
                        var restored = original
                        restored.version = saved.version
                        _ = await dependencies.submit(fallback: "Nie udało się cofnąć.") {
                            try await dependencies.repository.updateTask(restored, expectedVersion: saved.version)
                        }
                    }
                }
            )
        }
    }
}

extension View {
    /// Menu zadania pod przytrzymaniem: przesunięcie, priorytet, szczegóły.
    func taskContextMenu(
        _ task: TaskItem,
        dependencies: AppDependencies,
        onOpen: @escaping () -> Void
    ) -> some View {
        contextMenu {
            if !task.isDone {
                Button {
                    Task {
                        await TaskActions.reschedule(
                            task, to: dependencies.today.adding(days: 1), label: "Na jutro", dependencies: dependencies
                        )
                    }
                } label: {
                    Label("Przesuń na jutro", systemImage: "arrow.turn.down.right")
                }
                Button {
                    let base = max(task.dueDate ?? dependencies.today, dependencies.today)
                    Task {
                        await TaskActions.reschedule(
                            task, to: base.adding(days: 7), label: "O tydzień", dependencies: dependencies
                        )
                    }
                } label: {
                    Label("Przesuń o tydzień", systemImage: "calendar.badge.clock")
                }
                Button {
                    Task { await TaskActions.togglePriority(task, dependencies: dependencies) }
                } label: {
                    task.priority == .urgent
                        ? Label("Oznacz jako zwykłe", systemImage: "flag.slash")
                        : Label("Oznacz jako pilne", systemImage: "flame")
                }
            }
            Button {
                onOpen()
            } label: {
                Label("Szczegóły", systemImage: "arrow.up.forward.square")
            }
        }
    }
}
