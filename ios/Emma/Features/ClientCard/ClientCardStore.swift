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
            guard let client = try await repository.client(id: clientID) else {
                phase = .failed(LoadFailure(message: "Nie znaleziono karty klienta.", isRetryable: false))
                return
            }

            let window = ClientCardEventWindow.presentation(today: dependencies.today)
            async let legalCaseTask = repository.caseForClient(clientID)
            async let eventsTask = repository.events(in: window, clientID: clientID)
            async let notesTask = repository.notes(clientID: clientID, caseID: nil)
            async let threadsTask = repository.threads()

            let legalCase = try await legalCaseTask
            let events = try await eventsTask
            var notes = try await notesTask
            let threads = try await threadsTask

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
