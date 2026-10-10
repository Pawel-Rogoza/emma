import BackgroundTasks
import Foundation

// MARK: - Odświeżenie w tle
//
// Review 10.10.2026: powiadomienie o nowym leadzie i przypomnienia o terminach
// dodanych w panelu WWW pojawiały się dopiero po otwarciu aplikacji, bo
// planowało je tylko odświeżenie na pierwszym planie.
//
// iOS budzi aplikację co jakiś czas (sam decyduje kiedy — zwykle co kilkanaście
// minut do kilku godzin, zależnie od tego, jak często jest używana). Wtedy:
// nowe leady → powiadomienie, terminy i zadania → przeplanowane przypomnienia.
// Natychmiastowe powiadomienie o leadzie wymagałoby pushy z serwera (APNs).

@MainActor
enum BackgroundRefresh {

    nonisolated static let identifier = "pl.emma.refresh"

    /// Najwcześniej po tylu sekundach od wyjścia z aplikacji.
    static let interval: TimeInterval = 15 * 60

    /// Ustawiane przy starcie; zadanie w tle nie ma innej drogi do zależności.
    static weak var dependencies: AppDependencies?
    /// Czy jest zalogowana sesja (bez niej nie ma czego sprawdzać).
    static var hasSession: () -> Bool = { false }

    /// Rejestracja musi się odbyć przed końcem `didFinishLaunching`.
    nonisolated static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            // System woła nas na własnej kolejce; praca idzie na główny aktor.
            let box = BackgroundTaskBox(task)
            let work = Task { @MainActor in
                schedule()
                let success = await run()
                box.task.setTaskCompleted(success: success)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Kolejne obudzenie — wołane przy wyjściu w tło i w każdym przebiegu.
    static func schedule() {
        guard let dependencies, !dependencies.configuration.usesMockServices, hasSession() else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func run() async -> Bool {
        guard let dependencies, hasSession() else { return false }
        await dependencies.reminders.checkNewLeads(dependencies, notify: true)
        guard !Task.isCancelled else { return false }
        await dependencies.reminders.refresh(dependencies)
        return true
    }
}

/// `BGTask` nie jest `Sendable`, a kończymy go z głównego aktora. System
/// pozwala wołać `setTaskCompleted` z dowolnego wątku.
private final class BackgroundTaskBox: @unchecked Sendable {
    let task: BGTask

    init(_ task: BGTask) {
        self.task = task
    }
}
