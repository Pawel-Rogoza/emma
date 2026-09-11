import Combine
import Foundation

// MARK: - Magazyn ekranu „Klienci”
//
// Jedno wczytanie dla obu trybów listy (leady i sprawy): ekran nie składa
// danych z wielu niezależnych tablic, a po każdym zapisie wraca tu przez
// `dataVersion` (§ „STORE + VIEW”).

/// Dane listy leadów i spraw wraz z policzonymi zależnościami.
struct ClientsModel: Equatable {
    var clients: [Client]
    var cases: [LegalCase]
    /// Liczba otwartych zadań w sprawie — stopka karty sprawy.
    var openTaskCounts: [CaseID: Int]
    /// Najbliższy przyszły, niezakończony termin sprawy.
    var nextCaseEvents: [CaseID: ScheduledEvent]
    /// Najbliższy niezakończony termin leada (referencja: pierwszy z posortowanych).
    var nextLeadEvents: [ClientID: ScheduledEvent]
    var clientNames: [ClientID: String]
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
            async let eventsTask = repository.events(in: window, ownerID: nil)

            let clients = try await clientsTask
            let cases = try await casesTask
            let openTasks = try await openTasksTask
            let events = try await eventsTask

            var openTaskCounts: [CaseID: Int] = [:]
            for task in openTasks {
                guard let caseID = task.caseID else { continue }
                openTaskCounts[caseID, default: 0] += 1
            }

            let activeEvents = events.filter { $0.status != .finished }

            var nextCaseEvents: [CaseID: ScheduledEvent] = [:]
            for legalCase in cases {
                nextCaseEvents[legalCase.id] = earliest(
                    activeEvents.filter { $0.caseID == legalCase.id && $0.day >= today }
                )
            }

            var nextLeadEvents: [ClientID: ScheduledEvent] = [:]
            for client in clients {
                nextLeadEvents[client.id] = earliest(activeEvents.filter { $0.clientID == client.id })
            }

            phase = .loaded(
                ClientsModel(
                    clients: clients,
                    cases: cases,
                    openTaskCounts: openTaskCounts,
                    nextCaseEvents: nextCaseEvents,
                    nextLeadEvents: nextLeadEvents,
                    clientNames: Dictionary(clients.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
                )
            )
        } catch let error as DomainError {
            phase = .failed(error.safeMessage)
        } catch {
            phase = .failed("Nie udało się wczytać bazy kancelarii.")
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

/// Repozytorium udostępnia terminy wyłącznie zakresem dat (`events(in:ownerID:)`),
/// dlatego lista pobiera szerokie okno prezentacji wokół dnia referencyjnego
/// zamiast zgadywać pojedyncze dni. Kolumna godzin z referencji nie występuje.
enum ClientsEventWindow {
    static func presentation(today: LocalDate) -> DateIntervalFilter {
        DateIntervalFilter(from: today.adding(days: -365 * 3), through: today.adding(days: 365 * 3))
    }
}
