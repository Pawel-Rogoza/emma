import Combine
import Foundation
import SwiftUI

// MARK: - Magazyn ekranu „Klienci”
//
// Jedno wczytanie dla trzech trybów listy (leady, klienci i sprawy): ekran nie składa
// danych z wielu niezależnych tablic, a po każdym zapisie wraca tu przez
// `dataVersion` (§ „STORE + VIEW”).

// `ClientsModel` i reguły liczenia mieszkają w rdzeniu (`ClientsOverview.swift`).

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

            let model = ClientsModel.make(
                clients: clients,
                cases: cases,
                openTasks: openTasks,
                events: events,
                today: today
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
