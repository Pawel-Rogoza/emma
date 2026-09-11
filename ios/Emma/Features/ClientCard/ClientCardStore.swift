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
                phase = .failed("Nie znaleziono karty klienta.")
                return
            }

            let window = ClientCardEventWindow.presentation(today: dependencies.today)
            async let legalCaseTask = repository.caseForClient(clientID)
            async let eventsTask = repository.events(in: window, ownerID: nil)
            async let notesTask = repository.notes(clientID: clientID, caseID: nil)
            async let threadsTask = repository.threads()

            let legalCase = try await legalCaseTask
            let events = try await eventsTask
            let notes = try await notesTask
            let threads = try await threadsTask

            phase = .loaded(
                ClientCardModel(
                    client: client,
                    legalCase: legalCase,
                    events: events
                        .filter { $0.clientID == clientID }
                        .sorted { lhs, rhs in
                            if lhs.day != rhs.day { return lhs.day < rhs.day }
                            if lhs.time != rhs.time { return lhs.time < rhs.time }
                            return lhs.id.rawValue < rhs.id.rawValue
                        },
                    notes: notes,
                    threadID: threads.first { $0.clientID == clientID }?.id
                )
            )
        } catch let error as DomainError {
            phase = .failed(error.safeMessage)
        } catch {
            phase = .failed("Nie udało się wczytać karty klienta.")
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
