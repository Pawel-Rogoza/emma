import XCTest
@testable import Emma

// MARK: - Spójność danych przykładowych
//
// Powód istnienia tych testów: cały interfejs demo czyta `DemoFixtures`, a błąd
// w danych (wiszące odwołanie, autor notatki spoza kont) objawia się dopiero
// w widoku — na przykład pustym ekranem albo rozmowami bez licznika. Tutaj
// sprawdzamy to bez interfejsu.
//
// Testy wykonują się na Linuksie razem z resztą logiki (§12.2 planu).

final class FixtureIntegrityTests: XCTestCase {

    // MARK: Użytkownicy

    /// Demo ma **jedno** wspólne konto kancelarii — podział na osoby zniknął
    /// razem z właścicielem danych zadania (D-17).
    func testDemoHasSingleSharedAccount() {
        let dataset = DemoFixtures.Dataset()
        XCTAssertEqual(dataset.users.count, 1, "Demo ma mieć jedno wspólne konto kancelarii")
        XCTAssertEqual(dataset.users.first?.id, .kancelaria)
        XCTAssertEqual(dataset.user.id, .kancelaria)
    }

    func testEveryUserHasInitialsAndLanguages() {
        for user in DemoFixtures.users {
            XCTAssertFalse(user.displayName.isEmpty, "Użytkownik bez nazwy: \(user.id.rawValue)")
            XCTAssertFalse(user.initials.isEmpty, "Użytkownik bez inicjałów: \(user.id.rawValue)")
            XCTAssertFalse(
                user.assistantLanguage.displayName.isEmpty,
                "Użytkownik bez języka asystenta: \(user.id.rawValue)"
            )
        }
    }

    // MARK: Odwołania między encjami

    func testCasesReferenceExistingClients() {
        let dataset = DemoFixtures.Dataset()
        let clientIDs = Set(dataset.clients.map(\.id))
        for legalCase in dataset.cases {
            XCTAssertTrue(
                clientIDs.contains(legalCase.clientID),
                "Sprawa \(legalCase.id.rawValue) wskazuje nieistniejącego klienta"
            )
        }
    }

    func testEventsReferenceExistingClientsAndOptionalCases() {
        let dataset = DemoFixtures.Dataset()
        let clientIDs = Set(dataset.clients.map(\.id))
        let caseIDs = Set(dataset.cases.map(\.id))
        for event in dataset.events {
            XCTAssertTrue(
                clientIDs.contains(event.clientID),
                "Termin \(event.id.rawValue) wskazuje nieistniejącego klienta"
            )
            if let caseID = event.caseID {
                XCTAssertTrue(
                    caseIDs.contains(caseID),
                    "Termin \(event.id.rawValue) wskazuje nieistniejącą sprawę"
                )
            }
        }
    }

    func testTasksReferenceExistingClientsAndOptionalCases() {
        let dataset = DemoFixtures.Dataset()
        let clientIDs = Set(dataset.clients.map(\.id))
        let caseIDs = Set(dataset.cases.map(\.id))
        for task in dataset.tasks {
            if let clientID = task.clientID {
                XCTAssertTrue(
                    clientIDs.contains(clientID),
                    "Zadanie \(task.id.rawValue) wskazuje nieistniejącego klienta"
                )
            }
            if let caseID = task.caseID {
                XCTAssertTrue(
                    caseIDs.contains(caseID),
                    "Zadanie \(task.id.rawValue) wskazuje nieistniejącą sprawę"
                )
            }
        }
    }

    func testNotesReferenceExistingClients() {
        let dataset = DemoFixtures.Dataset()
        let clientIDs = Set(dataset.clients.map(\.id))
        let userIDs = Set(dataset.users.map(\.id))
        for note in dataset.notes {
            XCTAssertTrue(
                clientIDs.contains(note.clientID),
                "Notatka \(note.id.rawValue) wskazuje nieistniejącego klienta"
            )
            XCTAssertTrue(
                userIDs.contains(note.authorID),
                "Notatka \(note.id.rawValue) ma autora spoza listy użytkowników"
            )
        }
    }

    // MARK: Rozmowy

    func testThreadsReferenceExistingClients() {
        let dataset = DemoFixtures.Dataset()
        let clientIDs = Set(dataset.clients.map(\.id))
        for thread in dataset.threads {
            XCTAssertTrue(
                clientIDs.contains(thread.clientID),
                "Wątek \(thread.id.rawValue) wskazuje nieistniejącego klienta"
            )
        }
    }

    func testMessagesReferenceExistingThreadsWithUniqueIdentifiers() {
        let dataset = DemoFixtures.Dataset()
        let threadIDs = Set(dataset.threads.map(\.id))
        for message in dataset.messages {
            XCTAssertTrue(
                threadIDs.contains(message.threadID),
                "Wiadomość \(message.id.rawValue) należy do nieistniejącego wątku"
            )
        }
        XCTAssertEqual(
            Set(dataset.messages.map(\.id)).count,
            dataset.messages.count,
            "Identyfikatory wiadomości muszą być unikalne"
        )
    }

    /// Kolejność wiadomości w wątku musi być rozstrzygalna: `sequence` rośnie
    /// i nie powtarza się w obrębie wątku, bo po niej liczy się odczyt.
    func testMessageSequenceIsStrictlyIncreasingPerThread() {
        let dataset = DemoFixtures.Dataset()
        for thread in dataset.threads {
            let sequences = dataset.messages
                .filter { $0.threadID == thread.id }
                .map(\.sequence)
            XCTAssertEqual(
                Set(sequences).count,
                sequences.count,
                "Powtórzony numer wiadomości w wątku \(thread.id.rawValue)"
            )
            XCTAssertEqual(
                sequences,
                sequences.sorted(),
                "Numery wiadomości w wątku \(thread.id.rawValue) nie są rosnące"
            )
        }
    }

    /// Stan odczytu musi istnieć dla konta w każdym wątku — inaczej licznik
    /// nieprzeczytanych nie miałby z czego powstać.
    func testThreadStatesCoverEveryThreadForEveryUser() {
        let dataset = DemoFixtures.Dataset()
        for user in dataset.users {
            for thread in dataset.threads {
                let hasState = dataset.threadStates.contains {
                    $0.userID == user.id && $0.threadID == thread.id
                }
                XCTAssertTrue(
                    hasState,
                    "Brak stanu odczytu dla \(user.id.rawValue) w wątku \(thread.id.rawValue)"
                )
            }
        }
    }

    /// Kursor odczytu nie może wskazywać dalej, niż sięga historia wątku —
    /// inaczej część wiadomości nigdy nie zostałaby pokazana jako nowa.
    func testReadCursorsDoNotExceedThreadHighWatermark() {
        let dataset = DemoFixtures.Dataset()
        for state in dataset.threadStates {
            let highest = dataset.messages
                .filter { $0.threadID == state.threadID }
                .map(\.sequence)
                .max() ?? 0
            XCTAssertLessThanOrEqual(
                state.readCursorSequence,
                highest,
                "Kursor odczytu wyprzedza historię wątku \(state.threadID.rawValue)"
            )
        }
    }

    // MARK: Dzień referencyjny

    /// Historia rozmów w demo nie może zawierać wiadomości z przyszłości wobec
    /// dnia referencyjnego — inaczej lista pokazuje daty, których nie ma w świecie demo.
    func testNoMessageIsDatedAfterReferenceDay() {
        let reference = DemoClock().now()
        for message in DemoFixtures.messages {
            XCTAssertLessThanOrEqual(
                message.sentAt,
                reference,
                "Wiadomość \(message.id.rawValue) jest datowana po dniu referencyjnym"
            )
        }
    }

    func testReferenceDayIsFridayEleventhSeptember2026() {
        let day = DemoClock().today()
        XCTAssertEqual(day.isoString, "2026-09-11")
        // Poniedziałek = 0, więc piątek = 4.
        XCTAssertEqual(day.weekdayIndexMondayFirst, 4)
    }
}
