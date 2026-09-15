import XCTest
@testable import Emma

// MARK: - Repozytorium backendu: mapowanie kontraktu na modele aplikacji
//
// Testy nie używają sieci: `StubURLProtocol` podstawia odpowiedzi HTTP, a my
// sprawdzamy, czy repozytorium czyta prawdę i czy jawnie zgłasza brak trasy.
// Nie ma tu ani jednego przypadku, w którym brak danych zamieniamy na wartość
// domyślną — właśnie dlatego brak terminu jest testowany osobno.

final class BackendRepositoryTests: XCTestCase {

    private var baseURL: URL { URL(string: "https://advokat-varshava.pl")! }

    private func makeRepository(user: User? = User(
        id: UserID("user-1"),
        displayName: "Paweł Rogoża",
        initials: "PR"
    )) -> BackendRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = BackendAPIClient(
            baseURL: baseURL,
            accessToken: { "token-dostepu" },
            session: URLSession(configuration: configuration)
        )
        return BackendRepository(client: client, currentUser: { user })
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: Klienci

    func testClientsListDecodesLeadAndClient() async throws {
        StubURLProtocol.respond(json: Data(Self.clientsJSON.utf8), status: 200)
        let clients = try await makeRepository().clients(matching: "", stage: nil)

        // Identyfikatory przychodzą z prefiksem i są przepisywane dosłownie —
        // repozytorium nie dokleja własnego.
        XCTAssertEqual(clients.map(\.id.rawValue), ["lead-7", "client-12"])
        XCTAssertEqual(clients[0].displayName, "Ihor Bondar")
        XCTAssertEqual(clients[1].displayName, "Olena Kowalenko")
        XCTAssertEqual(clients[0].stage, .new)
        XCTAssertEqual(clients[1].stage, .client)
        XCTAssertEqual(clients[0].source, .webForm)
        XCTAssertEqual(clients[1].source, .whatsApp)
        // Model aplikacji nie ma briefingu opcjonalnego: `null` to pusty tekst.
        XCTAssertEqual(clients[0].briefing, "")
        XCTAssertEqual(clients[1].briefing, "Skrót sprawy")
        XCTAssertEqual(clients[0].language, .uk)
        XCTAssertEqual(clients[1].language, .pl)
        XCTAssertEqual(clients[1].incomingTime, TimeOfDay(hhmm: "11:30"))
        XCTAssertTrue(clients[0].needsReply)
        XCTAssertEqual(clients[1].version, Version(5))
    }

    func testInContactStageAndImportSourceMapToKnownValues() async throws {
        StubURLProtocol.respond(json: Data(Self.importClientJSON.utf8), status: 200)
        let clients = try await makeRepository().clients(matching: "", stage: nil)
        let client = try XCTUnwrap(clients.first)

        XCTAssertEqual(client.stage, .inContact)
        // Świadome uproszczenie: `import` nie ma osobnego przypadku w aplikacji,
        // więc trafia do `.manual` — nie znikamy go i nie tworzymy nowego stanu.
        XCTAssertEqual(client.source, .manual)
    }

    // MARK: Zadania

    func testTaskPriorityAndDueDateMap() async throws {
        StubURLProtocol.respond(json: Data(Self.tasksJSON.utf8), status: 200)
        let tasks = try await makeRepository().tasks(filter: TaskFilter(scope: .open))

        XCTAssertEqual(tasks.count, 1)
        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id.rawValue, "task-3")
        XCTAssertEqual(task.priority, .urgent)
        XCTAssertEqual(task.dueDate, LocalDate(year: 2026, month: 9, day: 14))
        XCTAssertEqual(task.clientID, ClientID("client-12"))
        XCTAssertNil(task.caseID)
    }

    func testTaskWithoutDueDateIsSkipped() async throws {
        StubURLProtocol.respond(json: Data(Self.tasksWithMissingDueDateJSON.utf8), status: 200)
        let tasks = try await makeRepository().tasks(filter: TaskFilter(scope: .all))

        // Zadanie bez terminu (`task-1`) znika z wyniku zamiast dostać datę
        // zastępczą, która w interfejsie wyglądałaby jak „po terminie”.
        XCTAssertEqual(tasks.map(\.id.rawValue), ["task-2"])
    }

    // MARK: Terminy

    func testEventKindStatusAndTimeMapping() async throws {
        StubURLProtocol.respond(json: Data(Self.eventsJSON.utf8), status: 200)
        let events = try await makeRepository().events(in: DateIntervalFilter(
            from: LocalDate(year: 2026, month: 9, day: 1),
            through: LocalDate(year: 2026, month: 9, day: 30)
        ))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].kind, .caseDeadline)
        XCTAssertEqual(events[1].kind, .consultation)
        // Stan bierzemy z kontraktu: `to_confirm` i `confirmed` mają znaczenie,
        // a CRM na razie wysyła zawsze to pierwsze, bo stanu nie prowadzi.
        XCTAssertEqual(events[0].status, .toConfirm)
        XCTAssertEqual(events[1].status, .confirmed)
        // Termin całodniowy (`time: null`, `all_day: true`) nie ma godziny;
        // północ jest brakiem godziny, a prawdę niesie `isAllDay`.
        XCTAssertEqual(events[0].time, TimeOfDay(minutes: 0))
        XCTAssertTrue(events[0].isAllDay)
        XCTAssertFalse(events[1].isAllDay)
        XCTAssertEqual(events[1].time, TimeOfDay(hhmm: "10:00"))
        // Miejsce przychodzi z backendu (`events.location`).
        XCTAssertEqual(events[0].place, "")
        XCTAssertEqual(events[1].place, "Sąd Rejonowy, sala 214")
        XCTAssertEqual(events[0].id.rawValue, "event-1")
    }

    func testCaseListReadsFromBackend() async throws {
        StubURLProtocol.respond(
            // Uwaga: surowy string wieloliniowy w Swift zaczyna treść w nowej
            // linii — JSON w tej samej linii co `"""` dokleja dwa cudzysłowy
            // do danych i parser JSON zgłasza błąd.
            json: Data(#"""
            {"items":[{"id":"case-041","number":"II K 341/26","title":"Zatrzymanie prawa jazdy","client_id":"client-12","status":"in_progress","summary":"","created_at":"2026-09-11","version":3}]}
            """#.utf8),
            status: 200
        )
        let cases = try await makeRepository().cases(status: .inProgress)
        XCTAssertEqual(cases.count, 1)
        XCTAssertEqual(cases[0].id.rawValue, "case-041")
        XCTAssertEqual(cases[0].number, "II K 341/26")
        XCTAssertEqual(cases[0].status, .inProgress)
        XCTAssertEqual(cases[0].version, Version(3))

        // Status trafia do zapytania w słowniku kontraktu.
        let url = try XCTUnwrap(StubURLProtocol.lastRequest?.url?.absoluteString)
        XCTAssertTrue(url.contains("status=in_progress"), "adres bez statusu: \(url)")
        XCTAssertTrue(url.contains("/api/mobile/v1/cases"), "adres bez trasy: \(url)")
    }

    // MARK: Notatki i historia

    func testNoteFullISOBecomesLocalDate() async throws {
        StubURLProtocol.respond(json: Data(Self.cardJSON.utf8), status: 200)
        let notes = try await makeRepository().notes(clientID: ClientID("client-12"), caseID: nil)

        XCTAssertEqual(notes.count, 1)
        let note = try XCTUnwrap(notes.first)
        // Backend wysyła pełny ISO (`2026-09-13T12:00:00.000Z`), a model trzyma dzień.
        XCTAssertEqual(note.createdAt, LocalDate(year: 2026, month: 9, day: 13))
        XCTAssertEqual(note.id.rawValue, "note-9")
    }

    func testActivityFullISOBecomesLocalDate() async throws {
        StubURLProtocol.respond(json: Data(Self.cardJSON.utf8), status: 200)
        let activity = try await makeRepository().activity(clientID: ClientID("client-12"))

        XCTAssertEqual(activity.count, 1)
        let entry = try XCTUnwrap(activity.first)
        XCTAssertEqual(entry.createdAt, LocalDate(year: 2026, month: 9, day: 12))
    }

    // MARK: Brak trasy w backendzie

    func testCreateClientThrowsNotAvailableInBackend() async {
        let repository = makeRepository()
        await assertNotAvailable {
            _ = try await repository.createClient(NewClientDraft(
                displayName: "Nowy",
                topic: "Temat",
                language: .pl,
                context: "",
                createdAt: LocalDate(year: 2026, month: 9, day: 14)
            ))
        }
    }

    func testSingleTaskAndEventReadThrowNotAvailableInBackend() async {
        let repository = makeRepository()
        // Lista spraw ma już trasę (`GET /cases`), ale odczyt pojedynczego
        // zadania i terminu nie ma jej w kontrakcie — dlatego tylko te dwa
        // zgłaszają brak, zamiast zwracać pustkę.
        await assertNotAvailable { _ = try await repository.task(id: TaskID("task-3")) }
        await assertNotAvailable { _ = try await repository.event(id: EventID("event-1")) }
        await assertNotAvailable { _ = try await repository.addNote(NewNoteDraft(
            clientID: ClientID("client-12"),
            caseID: nil,
            text: "Notatka",
            authorID: UserID("user-1"),
            createdAt: LocalDate(year: 2026, month: 9, day: 14)
        )) }
    }

    func testVoiceAndAssistantActionsThrowNotAvailableInBackend() async {
        let repository = makeRepository()
        await assertNotAvailable {
            _ = try await repository.create(CreateVoiceSession(
                userID: UserID("user-1"),
                context: .firm,
                assistantLanguage: .pl,
                installationID: "instalacja-1"
            ))
        }
        await assertNotAvailable { _ = try await repository.prepare(PrepareAction(PrepareActionRequest(
            actionID: ActionID("action-1"),
            kind: .reply,
            actorUserID: UserID("user-1"),
            text: "Treść",
            contextVersion: .initial,
            presentationID: "presentation-1",
            now: Date()
        ))) }
        await assertNotAvailable { _ = try await repository.confirm(ConfirmAction(
            confirmation: ActionEngine.Confirmation(
                actionID: ActionID("action-1"),
                expectedVersion: .initial,
                presentationID: "presentation-1",
                origin: .directUIButton,
                now: Date()
            ),
            idempotencyKey: "idem-1"
        )) }
    }

    // MARK: Rozmowy

    func testMessageReadsAreEmptyButWritesThrow() async throws {
        let repository = makeRepository()
        // Backend naprawdę nie prowadzi jeszcze wątków: pusty wynik to prawda
        // o stanie, a nie atrapa.
        let threads = try await repository.threads()
        let thread = try await repository.thread(id: ThreadID("thread-1"))
        let messages = try await repository.latestMessages(threadID: ThreadID("thread-1"), limit: 10)
        let unread = try await repository.unreadTotal(userID: UserID("user-1"))
        XCTAssertEqual(threads, [])
        XCTAssertNil(thread)
        XCTAssertEqual(messages, [])
        XCTAssertEqual(unread, 0)

        await assertNotAvailable {
            _ = try await repository.appendOutgoing(OutgoingMessageDraft(
                threadID: ThreadID("thread-1"),
                text: "Treść",
                authorID: UserID("user-1"),
                language: .pl,
                sentAt: Date(),
                idempotencyKey: "idem-1"
            ))
        }
    }

    // MARK: Użytkownik

    func testCurrentUserComesFromProvider() async throws {
        let expected = User(id: UserID("user-7"), displayName: "Tomasz Rogoża", initials: "TR")
        let repository = makeRepository(user: expected)
        let user = try await repository.currentUser()
        XCTAssertEqual(user, expected)
    }

    func testCurrentUserWithoutProviderReportsUnauthorized() async {
        let repository = makeRepository(user: nil)
        do {
            _ = try await repository.currentUser()
            XCTFail("Oczekiwano braku sesji")
        } catch let error as BackendRepositoryError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Oczekiwano BackendRepositoryError, a jest \(error)")
        }
    }

    // MARK: Pomocnicze

    private func assertNotAvailable(
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Oczekiwano notAvailableInBackend", file: file, line: line)
        } catch let error as BackendRepositoryError {
            guard case .notAvailableInBackend = error else {
                return XCTFail("Oczekiwano .notAvailableInBackend, a jest \(error)", file: file, line: line)
            }
            XCTAssertTrue(error.safeMessage.hasPrefix("Backend nie udostępnia jeszcze"), file: file, line: line)
        } catch {
            XCTFail("Oczekiwano BackendRepositoryError, a jest \(error)", file: file, line: line)
        }
    }

    // MARK: Dane wejściowe

    private static let clientsJSON = #"""
    {"items":[
      {"id":"lead-7","display_name":"Ihor Bondar","initials":"IB","language":"uk",
       "topic":"Zapytanie o rozwód","stage":"new","source":"web_form","created_at":"2026-09-01",
       "briefing":null,"incoming_message":null,"incoming_translation":null,"incoming_time":null,
       "needs_reply":true,"version":3},
      {"id":"client-12","display_name":"Olena Kowalenko","initials":"OK","language":"pl",
       "topic":"Sprawa spadkowa","stage":"client","source":"whatsapp","created_at":"2026-08-01",
       "briefing":"Skrót sprawy","incoming_message":null,"incoming_translation":null,
       "incoming_time":"11:30","needs_reply":false,"version":5}
    ],"next_cursor":null,"has_more":false}
    """#

    private static let importClientJSON = #"""
    {"items":[
      {"id":"lead-9","display_name":"Zespół","initials":"Z","language":"pl","topic":"Import",
       "stage":"in_contact","source":"import","created_at":"2026-09-02","briefing":null,
       "incoming_message":null,"incoming_translation":null,"incoming_time":null,
       "needs_reply":false,"version":1}
    ],"next_cursor":null,"has_more":false}
    """#

    private static let tasksJSON = #"""
    {"items":[
      {"id":"task-3","title":"Przygotować odpowiedź","client_id":"client-12","case_id":null,
       "owner_id":"user-1","due_date":"2026-09-14","is_done":false,"priority":"urgent","version":2}
    ]}
    """#

    private static let tasksWithMissingDueDateJSON = #"""
    {"items":[
      {"id":"task-1","title":"Bez terminu","client_id":null,"case_id":null,"owner_id":"user-1",
       "due_date":null,"is_done":false,"priority":"normal","version":1},
      {"id":"task-2","title":"Z terminem","client_id":null,"case_id":null,"owner_id":"user-1",
       "due_date":"2026-09-15","is_done":false,"priority":"normal","version":1}
    ]}
    """#

    // Słowniki w tej fiksturze są **kontraktu** (`consultation`/`case_deadline`,
    // `to_confirm`), nie CRM — inaczej test przechodziłby na danych, których
    // backend nie ma prawa wysłać.
    private static let eventsJSON = #"""
    {"items":[
      {"id":"event-1","client_id":"client-12","case_id":null,"title":"Termin na dokumenty",
       "day":"2026-09-14","time":null,"all_day":true,"duration_minutes":0,"kind":"case_deadline",
       "status":"to_confirm","place":null,"version":1},
      {"id":"event-2","client_id":"client-12","case_id":"case-041","title":"Rozprawa",
       "day":"2026-09-15","time":"10:00","all_day":false,"duration_minutes":30,"kind":"consultation",
       "status":"confirmed","place":"Sąd Rejonowy, sala 214","version":1}
    ]}
    """#

    private static let cardJSON = #"""
    {"client":{"id":"client-12","display_name":"Olena Kowalenko","initials":"OK","language":"pl",
      "topic":"Sprawa spadkowa","stage":"client","source":"whatsapp","created_at":"2026-08-01",
      "briefing":null,"incoming_message":null,"incoming_translation":null,"incoming_time":null,
      "needs_reply":false,"version":5},
     "events":[],
     "tasks":[],
     "notes":[{"id":"note-9","client_id":"client-12","case_id":null,"text":"Ustalenia",
       "author_id":"user-1","created_at":"2026-09-13T12:00:00.000Z","version":1}],
     "activity":[{"id":"activity-4","text":"Otwarto sprawę","client_id":"client-12","case_id":null,
       "created_at":"2026-09-12T08:30:00.000Z","author_id":"user-1"}]}
    """#
}
