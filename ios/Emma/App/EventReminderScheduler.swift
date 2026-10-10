import Foundation
import UserNotifications

// MARK: - Planowanie przypomnień w systemie
//
// Adapter `EventReminderPlan` → `UNUserNotificationCenter`. Plan (co i kiedy)
// jest w rdzeniu i ma testy; tu jest tylko rozmowa z systemem:
//
//   • zgoda na powiadomienia — pytamy dopiero wtedy, gdy użytkownik ustawia
//     przypomnienie przy terminie (kontekst prośby jest wtedy oczywisty),
//   • odświeżenie — terminy na najbliższe 45 dni z repozytorium, stare
//     powiadomienia terminów zdjęte, nowe zaplanowane. Wołane po każdym
//     zapisie (z opóźnieniem, żeby seria zapisów dała jedno odświeżenie)
//     i po powrocie aplikacji na pierwszy plan,
//   • dotknięcie powiadomienia otwiera szczegóły terminu.
//
// W Demo i w testach interfejsu przypomnienia są wyłączone: zegar Demo stoi
// na 11 września 2026, a systemowa prośba o zgodę zasłaniałaby testy.

@MainActor
final class EventReminderScheduler {

    let preferences = ReminderPreferences()
    private let isEnabled: Bool
    private var refreshTask: Task<Void, Never>?

    /// Ile dni naprzód planujemy (limit 48 powiadomień i tak obcina resztę).
    static let horizonDays = 45

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// Zgoda na powiadomienia. Zwraca, czy przypomnienia mogą się pojawić.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        guard isEnabled else { return false }
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    static let promptDismissedKey = "emma.notifications.promptDismissed"

    /// Czy pokazać na „Dzisiaj” kartę „Włącz poranny skrót”: tylko poza Demo,
    /// gdy system jeszcze nie pytał i użytkownik jej nie zamknął.
    func shouldOfferPermission() async -> Bool {
        guard isEnabled, !UserDefaults.standard.bool(forKey: Self.promptDismissedKey) else { return false }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined
    }

    func dismissPermissionOffer() {
        UserDefaults.standard.set(true, forKey: Self.promptDismissedKey)
    }

    /// Czy użytkownik odmówił zgody (formularz mówi wtedy, gdzie ją włączyć).
    func isDenied() async -> Bool {
        guard isEnabled else { return false }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Odświeżenie z opóźnieniem — kilka zapisów pod rząd daje jedno zapytanie.
    func scheduleRefresh(_ dependencies: AppDependencies) {
        guard isEnabled else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self, weak dependencies] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self, let dependencies else { return }
            await self.refresh(dependencies)
        }
    }

    func refresh(_ dependencies: AppDependencies) async {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }

        let today = dependencies.today
        let range = DateIntervalFilter(from: today, through: today.adding(days: Self.horizonDays))
        // Błąd odczytu zostawia dotychczasowe powiadomienia — lepiej przypomnieć
        // o terminie sprzed chwili niż zdjąć wszystkie przez brak sieci.
        guard let events = try? await dependencies.repository.events(in: range) else { return }
        let clients = (try? await dependencies.repository.clients(matching: "", stage: nil)) ?? []
        let names = Dictionary(clients.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let preferences = self.preferences
        let items = EventReminderPlan.items(
            events: events,
            clientNames: names,
            offset: { preferences.offset(for: $0.id) },
            now: dependencies.now,
            limit: Self.eventLimit
        )

        // Zadania z terminem: rano w dniu zadania (10.10.2026).
        let openTasks = (try? await dependencies.repository.tasks(filter: TaskFilter(scope: .open))) ?? []
        let taskItems = TaskReminderPlan.items(tasks: openTasks, clientNames: names, now: dependencies.now)

        // Poranny skrót (8:00): terminy dnia i niezamknięte terminy po czasie.
        let past = (try? await dependencies.repository.events(
            in: DateIntervalFilter(from: today.adding(days: -CaseUrgency.missedLookbackDays), through: today.adding(days: -1))
        )) ?? []
        let missed = past.filter { $0.kind == .caseDeadline && $0.status != .finished }.count
        let mornings = MorningBrief.items(events: events, missedDeadlines: missed, today: today, now: dependencies.now)

        // Areszt i legalny pobyt: tylko daty z najbliższych 30 dni, żeby kilka
        // spraw nie wyczerpało systemowego limitu 64 powiadomień.
        let cases = (try? await dependencies.repository.cases(status: nil)) ?? []
        let watches = cases
            .flatMap { CaseWatch.items(for: $0, today: today) }
            .filter { $0.daysLeft >= 0 && $0.daysLeft <= CaseWatch.showOnTodayDays }
        let dateText = dependencies.dateText
        let watchItems = CaseWatchReminderPlan.items(
            watches: watches,
            clientNames: names,
            dateText: { dateText.dayTitle($0) },
            now: dependencies.now
        ).prefix(12)

        let pending = await center.pendingNotificationRequests()
        let ours = pending
            .map(\.identifier)
            .filter(Self.isOurs)
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for item in watchItems {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.userInfo = [Self.caseIDKey: item.caseID.rawValue]
            let components = Calendar(identifier: .gregorian).dateComponents(
                [.timeZone, .year, .month, .day, .hour, .minute, .second],
                from: item.fireAt
            )
            try? await center.add(UNNotificationRequest(
                identifier: item.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        }

        for item in taskItems {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.userInfo = [Self.taskIDKey: item.taskID.rawValue]
            let components = Calendar(identifier: .gregorian).dateComponents(
                [.timeZone, .year, .month, .day, .hour, .minute, .second],
                from: item.fireAt
            )
            try? await center.add(UNNotificationRequest(
                identifier: item.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        }

        for morning in mornings {
            let content = UNMutableNotificationContent()
            content.title = morning.title
            content.body = morning.body
            content.sound = .default
            // Ze strefą: wyzwalacz bez niej trzyma „godzinę na zegarze”, więc po
            // zmianie strefy telefonu przypomnienie przesuwałoby się o różnicę.
            let components = Calendar(identifier: .gregorian).dateComponents(
                [.timeZone, .year, .month, .day, .hour, .minute, .second],
                from: morning.fireAt
            )
            try? await center.add(UNNotificationRequest(
                identifier: morning.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        }

        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.userInfo = [Self.eventIDKey: item.eventID.rawValue]
            // Ze strefą: wyzwalacz bez niej trzyma „godzinę na zegarze”, więc po
            // zmianie strefy telefonu przypomnienie przesuwałoby się o różnicę.
            let components = Calendar(identifier: .gregorian).dateComponents(
                [.timeZone, .year, .month, .day, .hour, .minute, .second],
                from: item.fireAt
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(
                UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
            )
        }
    }

    // MARK: Nowe leady

    static let knownLeadsKey = "emma.notifications.knownLeads"

    /// Sprawdza „Nowych” i powiadamia o tych, których telefon jeszcze nie
    /// widział. `notify: false` (aplikacja na ekranie) tylko zapamiętuje —
    /// lead i tak widać wtedy na „Dzisiaj”.
    func checkNewLeads(_ dependencies: AppDependencies, notify: Bool) async {
        guard isEnabled else { return }
        guard let leads = try? await dependencies.repository.clients(matching: "", stage: .new) else { return }
        let stored = UserDefaults.standard.array(forKey: Self.knownLeadsKey) as? [String]
        let outcome = LeadAlertPlan.check(
            leads: leads.map { LeadAlertPlan.Lead(id: $0.id.rawValue, name: $0.displayName, topic: $0.topic) },
            known: stored.map(Set.init)
        )
        UserDefaults.standard.set(Array(outcome.known), forKey: Self.knownLeadsKey)
        guard notify, !outcome.alerts.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }
        for alert in outcome.alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            content.userInfo = alert.identifier.hasPrefix(LeadAlertPlan.identifierPrefix + "batch.")
                ? [Self.leadsKey: true]
                : [Self.clientIDKey: alert.clientID.rawValue]
            // Bez wyzwalacza — od razu.
            try? await center.add(UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil))
        }
    }

    /// Koniec sesji. Przypomnienia i poranny skrót niosą nazwy klientów
    /// i terminów, więc nie mogą przeżyć wylogowania — pojawiałyby się na
    /// ekranie blokady telefonu osobie, która nie ma już dostępu do danych.
    func removeAll() async {
        refreshTask?.cancel()
        refreshTask = nil
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter(Self.isOurs)
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter(Self.isOurs)
        center.removeDeliveredNotifications(withIdentifiers: delivered)
        // Następne konto zaczyna od zera — bez powiadomień o cudzych leadach.
        UserDefaults.standard.removeObject(forKey: Self.knownLeadsKey)
    }

    /// Zdjęcie przypomnienia usuniętego terminu od razu, bez czekania na odświeżenie.
    func removeReminder(for eventID: EventID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [EventReminderPlan.identifierPrefix + eventID.rawValue]
        )
        preferences.removeOffset(for: eventID)
    }

    nonisolated static let eventIDKey = "eventID"
    nonisolated static let caseIDKey = "caseID"
    nonisolated static let taskIDKey = "taskID"
    nonisolated static let clientIDKey = "clientID"
    nonisolated static let leadsKey = "leads"

    /// Terminy dzielą limit 64 powiadomień z zadaniami (10), sprawami (12)
    /// i porannym skrótem — stąd mniej niż `EventReminderPlan.defaultLimit`.
    static let eventLimit = 38

    /// Powiadomienia Emmy (terminy, poranny skrót, areszt i pobyt) — sprzątanie
    /// nie rusza niczego innego.
    nonisolated static func isOurs(_ identifier: String) -> Bool {
        [
            EventReminderPlan.identifierPrefix,
            MorningBrief.identifierPrefix,
            CaseWatchReminderPlan.identifierPrefix,
            TaskReminderPlan.identifierPrefix,
            LeadAlertPlan.identifierPrefix,
        ]
            .contains { identifier.hasPrefix($0) }
    }
}

// MARK: - Dotknięcie powiadomienia

/// Delegat centrum powiadomień: baner także przy otwartej aplikacji,
/// a dotknięcie przypomnienia otwiera szczegóły terminu.
final class EventNotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    @MainActor weak var dependencies: AppDependencies?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        // Zadanie — otwiera jego szczegóły.
        if let taskRaw = info[EventReminderScheduler.taskIDKey] as? String {
            await MainActor.run { dependencies?.present(.taskDetail(TaskID(taskRaw))) }
            return
        }
        // Nowy lead — otwiera kartę osoby; kilka naraz — listę klientów.
        if let clientRaw = info[EventReminderScheduler.clientIDKey] as? String {
            await MainActor.run {
                dependencies?.go(to: .clients, resetStack: true)
                dependencies?.openPerson(ClientID(clientRaw))
            }
            return
        }
        if info[EventReminderScheduler.leadsKey] != nil {
            await MainActor.run { dependencies?.go(to: .clients, resetStack: true) }
            return
        }
        // Areszt / legalny pobyt — otwiera sprawę.
        if let caseRaw = response.notification.request.content.userInfo[EventReminderScheduler.caseIDKey] as? String {
            await MainActor.run { dependencies?.openCase(CaseID(caseRaw)) }
            return
        }
        guard let raw = response.notification.request.content.userInfo[EventReminderScheduler.eventIDKey] as? String else {
            // Poranny skrót nie wskazuje terminu — otwiera „Dzisiaj”.
            if response.notification.request.identifier.hasPrefix(MorningBrief.identifierPrefix) {
                await MainActor.run { dependencies?.go(to: .today, resetStack: true) }
            }
            return
        }
        await MainActor.run {
            dependencies?.present(.eventDetail(EventID(raw)))
        }
    }
}
