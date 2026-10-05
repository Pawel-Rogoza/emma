import Combine
import Foundation

// MARK: - Magazyn karty klienta
//
// Port `personPage()` z referencji: klient, jego sprawa (jeśli istnieje),
// terminy, notatki oraz wątek WhatsApp. Jedno wczytanie dla całej karty.

/// Dane karty klienta.
struct ClientCardModel: Equatable {
    var client: Client
    var legalCase: LegalCase?
    /// Wszystkie sprawy klienta, aktywne najpierw. Audyt 28.09.2026: karta
    /// pokazywała jedną sprawę, a klient karnisty często ma kilka postępowań.
    var cases: [LegalCase] = []
    /// Terminy klienta posortowane rosnąco (jak `sortEvents` w referencji).
    var events: [ScheduledEvent]
    var notes: [CaseNote]
    /// Wątek rozmowy klienta — odnaleziony w repozytorium, nie sklejany z identyfikatora.
    var threadID: ThreadID?
}

@MainActor
final class ClientCardStore: ObservableObject {

    @Published private(set) var phase: LoadPhase<ClientCardModel> = .idle

    func load(_ dependencies: AppDependencies, clientID: ClientID) async {
        // Odświeżenie po zapisie zachowuje dotychczasową treść karty.
        if !phase.hasLoaded { phase = .loading }
        do {
            let repository = dependencies.repository
            let window = ClientCardEventWindow.presentation(today: dependencies.today)
            // Wszystkie odczyty idą od razu, razem z osobą (05.10.2026) —
            // wcześniej reszta czekała, aż wróci karta klienta.
            async let clientTask = repository.client(id: clientID)
            async let legalCaseTask = repository.caseForClient(clientID)
            async let eventsTask = repository.events(in: window, clientID: clientID)
            async let notesTask = repository.notes(clientID: clientID, caseID: nil)
            async let threadsTask = repository.threads()
            async let allCasesTask = repository.cases(status: nil)

            guard let client = try await clientTask else {
                phase = .failed(LoadFailure(message: "Nie znaleziono karty klienta.", isRetryable: false))
                return
            }
            let legalCase = try await legalCaseTask
            let events = try await eventsTask
            var notes = try await notesTask
            let threads = try await threadsTask
            // Lista spraw jest dodatkiem — jej brak nie blokuje karty.
            var cases = ((try? await allCasesTask) ?? []).filter { $0.clientID == clientID }
            if let legalCase, !cases.contains(where: { $0.id == legalCase.id }) {
                cases.append(legalCase)
            }
            cases.sort { lhs, rhs in
                if lhs.status.isActive != rhs.status.isActive { return lhs.status.isActive }
                if lhs.createdAt != rhs.createdAt { return rhs.createdAt < lhs.createdAt }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }

            // Notatka dodana z karty klienta, który ma sprawę, trafia do sprawy.
            // Karta czytała wyłącznie notatki kartoteki, więc zapisana notatka
            // „znikała” — review 24.09.2026: „zapisywanie notatek nie działa”.
            // Karta pokazuje teraz notatki klienta i jego sprawy razem.
            if let legalCase {
                let caseNotes = (try? await repository.notes(clientID: clientID, caseID: legalCase.id)) ?? []
                let known = Set(notes.map(\.id))
                notes += caseNotes.filter { !known.contains($0.id) }
            }

            phase = .loaded(
                ClientCardModel(
                    client: client,
                    legalCase: legalCase,
                    cases: cases,
                    events: events
                        .sorted { lhs, rhs in
                            if lhs.day != rhs.day { return lhs.day < rhs.day }
                            if lhs.time != rhs.time { return lhs.time < rhs.time }
                            return lhs.id.rawValue < rhs.id.rawValue
                        },
                    notes: notes.sorted { lhs, rhs in
                        lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : lhs.id.rawValue > rhs.id.rawValue
                    },
                    threadID: threads.first { $0.clientID == clientID }?.id
                )
            )
        } catch {
            if let message = phase.recordFailure(error, fallback: "Nie udało się wczytać karty klienta.") {
                dependencies.showToast(message)
            }
        }
    }
}

// MARK: - Okno terminów karty

/// Repozytorium filtruje terminy zakresem dat, a karta pokazuje wszystkie terminy
/// klienta (`sortEvents(data.events.filter(e=>e.personId===p.id))`), dlatego
/// pobieramy szerokie okno prezentacji wokół dnia referencyjnego.
enum ClientCardEventWindow {
    static func presentation(today: LocalDate) -> DateIntervalFilter {
        DateIntervalFilter(from: today.adding(days: -365 * 3), through: today.adding(days: 365 * 3))
    }
}
