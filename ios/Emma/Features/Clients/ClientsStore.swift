import Combine
import Foundation
import SwiftUI

// MARK: - Magazyn ekranu „Klienci”
//
// Jedno wczytanie dla trzech trybów listy (leady, klienci i sprawy): ekran nie składa
// danych z wielu niezależnych tablic, a po każdym zapisie wraca tu przez
// `dataVersion` (§ „STORE + VIEW”).

/// Dane list leadów, klientów i spraw wraz z policzonymi zależnościami.
struct ClientsModel: Equatable {
    var clients: [Client]
    var cases: [LegalCase]
    /// Liczba otwartych zadań w sprawie — stopka karty sprawy.
    var openTaskCounts: [CaseID: Int]
    /// Otwarte zadania z terminem przed dziś — sprawa trafia do „Wymaga uwagi”.
    var overdueTaskCounts: [CaseID: Int]
    /// Zaległe zadania klienta (jego własne i w jego sprawach) — kartoteka.
    var clientOverdueTaskCounts: [ClientID: Int]
    /// Najbliższy przyszły, niezakończony termin sprawy.
    var nextCaseEvents: [CaseID: ScheduledEvent]
    /// Najbliższy niezakończony termin leada (referencja: pierwszy z posortowanych).
    var nextLeadEvents: [ClientID: ScheduledEvent]
    /// Najbliższy **przyszły** termin osoby — kartoteka i kafelek konsultacji.
    var nextClientEvents: [ClientID: ScheduledEvent]
    var clientsByID: [ClientID: Client]
    /// Sprawy każdego klienta — kartoteka pokazuje, co u niego prowadzimy.
    var casesByClient: [ClientID: [LegalCase]]
}

@MainActor
final class ClientsStore: ObservableObject {

    @Published private(set) var phase: LoadPhase<ClientsModel> = .idle

    func load(_ dependencies: AppDependencies) async {
        // Ponowne wczytanie po zapisie nie czyści listy — ekran nie mruga stanem ładowania.
        if !phase.hasLoaded { phase = .loading }
        do {
            let repository = dependencies.repository
            let today = dependencies.today
            let window = ClientsEventWindow.presentation(today: today)

            async let clientsTask = repository.clients(matching: "", stage: nil)
            async let casesTask = repository.cases(status: nil)
            async let openTasksTask = repository.tasks(filter: TaskFilter(scope: .open))
            async let eventsTask = repository.events(in: window)

            let clients = try await clientsTask
            let cases = try await casesTask
            let openTasks = try await openTasksTask
            let events = try await eventsTask

            let caseOwners = Dictionary(cases.map { ($0.id, $0.clientID) }, uniquingKeysWith: { first, _ in first })
            var openTaskCounts: [CaseID: Int] = [:]
            var overdueTaskCounts: [CaseID: Int] = [:]
            var clientOverdueTaskCounts: [ClientID: Int] = [:]
            for task in openTasks {
                let isOverdue = task.dueDate.map { $0 < today } ?? false
                if let caseID = task.caseID {
                    openTaskCounts[caseID, default: 0] += 1
                    if isOverdue { overdueTaskCounts[caseID, default: 0] += 1 }
                }
                if isOverdue, let owner = task.clientID ?? task.caseID.flatMap({ caseOwners[$0] }) {
                    clientOverdueTaskCounts[owner, default: 0] += 1
                }
            }

            let activeEvents = events.filter { $0.status != .finished }

            var nextCaseEvents: [CaseID: ScheduledEvent] = [:]
            for legalCase in cases {
                nextCaseEvents[legalCase.id] = earliest(
                    activeEvents.filter { $0.caseID == legalCase.id && $0.day >= today }
                )
            }

            var nextLeadEvents: [ClientID: ScheduledEvent] = [:]
            var nextClientEvents: [ClientID: ScheduledEvent] = [:]
            for client in clients {
                let own = activeEvents.filter { $0.clientID == client.id }
                nextLeadEvents[client.id] = earliest(own)
                nextClientEvents[client.id] = earliest(own.filter { $0.day >= today })
            }

            let model = ClientsModel(
                clients: clients,
                cases: cases,
                openTaskCounts: openTaskCounts,
                overdueTaskCounts: overdueTaskCounts,
                clientOverdueTaskCounts: clientOverdueTaskCounts,
                nextCaseEvents: nextCaseEvents,
                nextLeadEvents: nextLeadEvents,
                nextClientEvents: nextClientEvents,
                clientsByID: Dictionary(clients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                casesByClient: Dictionary(grouping: cases, by: \.clientID)
            )
            // Odświeżenie po zapisie jest animowane: obsłużony lead wysuwa się
            // z listy, zamiast zniknąć skokiem. Pierwsze wczytanie — bez animacji.
            if phase.hasLoaded {
                withAnimation(.easeInOut(duration: 0.28)) { phase = .loaded(model) }
            } else {
                phase = .loaded(model)
            }
            // Plakietka zakładki liczona z tych samych danych co lista.
            dependencies.leadsNeedingAction = clients.filter { $0.stage == .new }.count
        } catch {
            if let message = phase.recordFailure(error, fallback: "Nie udało się wczytać bazy kancelarii.") {
                dependencies.showToast(message)
            }
        }
    }

    /// Najwcześniejszy termin: data, potem godzina, na końcu identyfikator
    /// (deterministyczne rozstrzygnięcie remisu, jak w repozytorium).
    private func earliest(_ events: [ScheduledEvent]) -> ScheduledEvent? {
        events.min { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.id.rawValue < rhs.id.rawValue
        }
    }
}

// MARK: - Okno terminów listy

/// Repozytorium udostępnia terminy wyłącznie zakresem dat (`events(in:)`).
/// Lista potrzebuje **najbliższych** terminów, więc okno zaczyna się tuż przed
/// dziś: backend oddaje najwyżej 200 pozycji od najstarszej, a okno ±3 lata
/// wypełniało limit starymi terminami i przyszłe spotkania znikały z kart.
enum ClientsEventWindow {
    static func presentation(today: LocalDate) -> DateIntervalFilter {
        DateIntervalFilter(from: today.adding(days: -30), through: today.adding(days: 365 * 2))
    }
}
