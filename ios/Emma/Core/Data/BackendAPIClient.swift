import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Błędy warstwy backendu
//
// Jeden typ błędu obsługuje i klienta HTTP, i repozytorium, bo ekran nie powinien
// zgadywać, czy „brak danych” wróciło z transportu, czy z mapowania kontraktu.
// Komunikaty są po polsku i mówią wprost, czego backend nie udostępnia — to
// jedyny uczciwy sposób zameldowania brakującej trasy zamiast zwrócenia pustki.

public enum BackendRepositoryError: Error, Equatable, Sendable {
    /// 401. Token nie jest czyszczony po stronie klienta HTTP — odświeżaniem
    /// sesji zajmuje się `AuthStore`, a warstwa danych tylko zgłasza stan.
    case unauthorized
    /// 403. Sesja istnieje, ale należy do innego użytkownika albo innej
    /// instalacji — ponawianie nic nie da, trzeba zakończyć próbę.
    case forbidden(String?)
    case notFound
    /// 409. Konflikt wersji kontekstu albo stanu sesji. `currentVersion` jest
    /// z kontraktu (`current_version`), żeby ekran mógł pokazać stan faktyczny,
    /// zamiast kazać użytkownikowi zgadywać.
    case conflict(currentVersion: Int?, message: String?)
    case server(status: Int, message: String?)
    case transport(String)
    /// Trasa, której kontrakt mobilny jeszcze nie ma. Nazwa operacji mówi, co
    /// dokładnie jest niedostępne, żeby komunikat nie był zagadką.
    case notAvailableInBackend(String)
    case decoding(String)

    public var safeMessage: String {
        switch self {
        case .unauthorized:
            return "Sesja wygasła. Zaloguj się ponownie."
        case .forbidden(let message):
            return message ?? "Ta rozmowa należy do innego urządzenia."
        case .notFound:
            return "Nie znaleziono danych."
        case .conflict(_, let message):
            return message ?? "Dane zmieniły się w międzyczasie — odśwież i spróbuj ponownie."
        case .server(_, let message):
            return message ?? "Backend zwrócił błąd."
        case .transport(let reason):
            return "Błąd połączenia: \(reason)."
        case .notAvailableInBackend(let operation):
            return "Backend nie udostępnia jeszcze: \(operation)."
        case .decoding(let reason):
            return "Nie udało się odczytać danych z backendu: \(reason)."
        }
    }

    /// Ponowienie ma sens tylko dla problemów przejściowych. Brak trasy i brak
    /// uprawnień nie naprawią się same, a powtarzanie ich tylko myli użytkownika.
    public var isRetryable: Bool {
        switch self {
        case .transport, .server:
            return true
        default:
            return false
        }
    }
}

// MARK: - Sesja HTTP bez pamięci podręcznej
//
// `URLSession.shared` korzysta z `URLCache.shared`, który może zapisać odpowiedź
// GET na dysk (`Library/Caches/…/Cache.db`) — także z nazwiskami klientów
// i treścią spraw, jeśli serwer nie wyśle `Cache-Control: no-store`. Dane
// kancelarii mają żyć w pamięci procesu, nie w pliku, który przeżywa
// wylogowanie. Tej sesji używają wszystkie klienty backendu.

public extension URLSession {
    static let emmaAPI: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}

// MARK: - Klient HTTP odczytu danych kancelarii
//
// To wyłącznie transport i dekodowanie JSON-a kontraktu mobilnego. Nie ma tu
// logiki biznesowej ani decyzji „co pokazać”: mapowanie na modele aplikacji
// robi `BackendRepository`, a brakujące trasy zgłasza repozytorium.
//
// Klient jest niezmienną strukturą (`Sendable`), więc wiele równoległych odczytów
// nie wymaga blokad — nie ma współdzielonego stanu mutowalnego.

public struct BackendAPIClient: Sendable {

    /// Trasy kontraktu mobilnego. Trzymamy je w jednym miejscu, żeby zmiana
    /// ścieżki była jedną poprawką, a nie szukaniem stringów po plikach.
    public enum Endpoint: String, Sendable, CaseIterable {
        case clients = "api/mobile/v1/clients"
        case cases = "api/mobile/v1/cases"
        case tasks = "api/mobile/v1/tasks"
        case events = "api/mobile/v1/events"
        /// Prefiks `/api/mobile/v1/voice` jest obowiązkowy — trasa bez niego
        /// nie istnieje i nginx jej nie przepuszcza.
        case voiceSessions = "api/mobile/v1/voice/sessions"
        case voiceConversationToken = "api/mobile/v1/voice/conversation-token"
        case notes = "api/mobile/v1/notes"
        case actions = "api/mobile/v1/actions"
        /// Rozmowy WhatsApp (numer kancelarii podłączony przez Dualhook).
        case threads = "api/mobile/v1/threads"
        /// Treść dokumentu z akt (`GET /files/{file_id}`).
        case files = "api/mobile/v1/files"
    }

    /// Domyślny rozmiar strony z kontraktu (`limit`, maks. 100). Repozytorium
    /// czyta dziś pierwszą stronę i nie twierdzi, że pobrało całość: pole
    /// `has_more` jest zwracane razem ze stroną.
    public static let defaultPageLimit = 30

    private let baseURL: URL
    private let session: URLSession
    /// Token pobieramy asynchronicznie, bo jego źródłem jest sesja żyjąca na
    /// głównym aktorze (`AuthStore`). Synchroniczna lektura z wątku tła byłaby
    /// wyścigiem o dane, a nie optymalizacją (Swift 6: pełna kontrola izolacji).
    private let accessToken: @Sendable () async -> String?
    /// Jednorazowe odnowienie po 401 (FIX C). Gdy `nil` (podglądy, testy
    /// transportu), klient zachowuje się jak wcześniej: 401 jest błędem.
    ///
    /// Kontrakt: 401 → jedno odnowienie → ponowienie żądania z nowym tokenem.
    /// Dopiero nieudane odnowienie (albo drugie 401) jest błędem `unauthorized`
    /// i to `AuthStore` decyduje o zakończeniu sesji. 403 nie odświeża i **nie**
    /// wylogowuje — to brak uprawnień do zasobu, nie wygasła sesja.
    private let refreshToken: (@Sendable () async -> String?)?
    private let timeout: TimeInterval

    public init(
        baseURL: URL,
        accessToken: @escaping @Sendable () async -> String?,
        refreshToken: (@Sendable () async -> String?)? = nil,
        session: URLSession = .emmaAPI,
        timeout: TimeInterval = 20
    ) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.session = session
        self.timeout = timeout
    }

    // MARK: Odczyt zgodny z kontraktem

    /// `GET /api/mobile/v1/clients?query=&stage=&limit=&cursor=`.
    ///
    /// `cursor` to przesunięcie kolejnej strony listy; podajemy je tylko wtedy,
    /// gdy poprzednia odpowiedź powiedziała `has_more`.
    func clients(
        query: String,
        stage: ClientStage?,
        limit: Int = Self.defaultPageLimit,
        cursor: String? = nil
    ) async throws -> BackendClientPage {
        var items: [URLQueryItem] = []
        if !query.isEmpty {
            items.append(URLQueryItem(name: "query", value: query))
        }
        if let stage {
            items.append(URLQueryItem(name: "stage", value: Self.stageToken(stage)))
        }
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        if let cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await get(Endpoint.clients.rawValue, query: items)
    }

    /// `GET /api/mobile/v1/clients/{client_id}` — karta klienta z kontekstem.
    func clientCard(id: ClientID) async throws -> BackendClientCard {
        try await get("\(Endpoint.clients.rawValue)/\(id.rawValue)", query: [])
    }

    /// `DELETE /api/mobile/v1/clients/{client_id}` — usunięcie zgłoszenia.
    ///
    /// `expected_version` jedzie w ciele (tak samo jak przy usunięciu terminu):
    /// bez tego drugie urządzenie mogłoby usunąć coś innego, niż widziało.
    func deleteClient(id: String, expectedVersion: Int, idempotencyKey: String) async throws {
        struct Body: Encodable {
            let expectedVersion: Int

            enum CodingKeys: String, CodingKey {
                case expectedVersion = "expected_version"
            }
        }
        try await sendNoContent(
            "DELETE",
            path: "\(Endpoint.clients.rawValue)/\(id)",
            body: Body(expectedVersion: expectedVersion),
            idempotencyKey: idempotencyKey
        )
    }

    /// `POST /api/mobile/v1/clients` — nowe zgłoszenie (lead) z aplikacji.
    ///
    /// Kontrakt `NewClient` zna tylko `display_name`, `topic`, `language`,
    /// `stage` i `source`. `topic` to w bazie **`leads.message`** — CRM trzyma
    /// jeden wolny tekst zgłoszenia, więc kontekst dopisany przez użytkownika
    /// dokładamy do tej samej treści po stronie repozytorium.
    func createClient(
        displayName: String,
        message: String,
        language: String,
        source: String,
        idempotencyKey: String
    ) async throws -> BackendClientDTO {
        struct Body: Encodable {
            let displayName: String
            let topic: String
            let language: String
            let source: String

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case topic
                case language
                case source
            }
        }
        return try await send(
            "POST",
            path: Endpoint.clients.rawValue,
            body: Body(displayName: displayName, topic: message, language: language, source: source),
            idempotencyKey: idempotencyKey
        )
    }

    /// `PATCH /api/mobile/v1/clients/{client_id}` — zmiana danych kontaktu.
    ///
    /// Trasa obsługuje leady i kartotekę tak samo (`lead-26` / `client-33`).
    /// `stage` przysyłamy tylko wtedy, gdy naprawdę się zmienia: dla leada
    /// backend mapuje go na status, a wejście na `client` **konwertuje
    /// zgłoszenie w kartotekę**. `expected_version` to wersja, którą aplikacja
    /// widziała — backend odrzuci zapis, jeśli ktoś zmienił rekord wcześniej.
    func updateClient(
        id: String,
        displayName: String?,
        stage: String?,
        expectedVersion: Int,
        idempotencyKey: String
    ) async throws -> BackendClientDTO {
        struct Body: Encodable {
            let displayName: String?
            let stage: String?
            let expectedVersion: Int

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case stage
                case expectedVersion = "expected_version"
            }
        }
        return try await send(
            "PATCH",
            path: "\(Endpoint.clients.rawValue)/\(id)",
            body: Body(displayName: displayName, stage: stage, expectedVersion: expectedVersion),
            idempotencyKey: idempotencyKey
        )
    }

    /// `GET /api/mobile/v1/cases/{case_id}` — sprawa z zadania i historią.
    func caseDetail(id: CaseID) async throws -> BackendCaseDetail {
        try await get("\(Endpoint.cases.rawValue)/\(id.rawValue)", query: [])
    }

    /// `GET /api/mobile/v1/cases/{case_id}/files` — akta sprawy.
    func caseDocuments(caseID: CaseID) async throws -> [BackendDocumentDTO] {
        let response: BackendItems<BackendDocumentDTO> = try await get(
            "\(Endpoint.cases.rawValue)/\(caseID.rawValue)/files", query: []
        )
        return response.items
    }

    /// `POST /api/mobile/v1/cases/{case_id}/files` — plik do akt (multipart).
    /// Bez ponawiania: drugi taki sam skan w aktach to bałagan, nie wygoda.
    func uploadCaseDocument(caseID: CaseID, form: MultipartForm) async throws -> [BackendDocumentDTO] {
        let body = form.finished()
        let (data, http) = try await authenticatedRequest { token in
            var request = try self.makeRequest(
                path: "\(Endpoint.cases.rawValue)/\(caseID.rawValue)/files",
                method: "POST",
                token: token
            )
            request.httpBody = body
            request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
            // Skan kilku stron przez słabe LTE trwa dłużej niż zwykły zapis.
            request.timeoutInterval = max(request.timeoutInterval, 120)
            return request
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: http, data: data)
        }
        do {
            return try Self.decoder.decode(BackendItems<BackendDocumentDTO>.self, from: data).items
        } catch {
            throw BackendRepositoryError.decoding("\(error)")
        }
    }

    /// `GET /api/mobile/v1/files/{file_id}` — surowa treść dokumentu.
    func documentData(id: String) async throws -> Data {
        let (data, http) = try await authenticatedRequest { token in
            var request = try self.makeRequest(path: "\(Endpoint.files.rawValue)/\(id)", token: token)
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.timeoutInterval = max(request.timeoutInterval, 120)
            return request
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: http, data: data)
        }
        return data
    }

    /// `GET /api/mobile/v1/tasks/{task_id}`.
    func task(id: TaskID) async throws -> BackendTaskDTO {
        try await get("\(Endpoint.tasks.rawValue)/\(id.rawValue)", query: [])
    }

    /// `GET /api/mobile/v1/events/{event_id}`.
    func event(id: EventID) async throws -> BackendEventDTO {
        try await get("\(Endpoint.events.rawValue)/\(id.rawValue)", query: [])
    }

    /// `POST /api/mobile/v1/cases` — 201 nowa sprawa albo 200 istniejąca.
    func createCase(_ body: BackendCaseCreateBody, idempotencyKey: String) async throws -> BackendLegalCaseDTO {
        try await send("POST", path: Endpoint.cases.rawValue, body: body, idempotencyKey: idempotencyKey)
    }

    /// `PATCH /api/mobile/v1/cases/{case_id}` — nazwa i status.
    func updateCase(id: String, body: BackendCaseUpdateBody, idempotencyKey: String) async throws -> BackendLegalCaseDTO {
        try await send("PATCH", path: "\(Endpoint.cases.rawValue)/\(id)", body: body, idempotencyKey: idempotencyKey)
    }

    /// `GET /api/mobile/v1/cases?status=&client_id=&limit=` — lista spraw.
    func cases(status: CaseStatus?, clientID: ClientID? = nil) async throws -> [BackendLegalCaseDTO] {
        var items: [URLQueryItem] = []
        if let status {
            items.append(URLQueryItem(name: "status", value: Self.caseStatusToken(status)))
        }
        if let clientID {
            items.append(URLQueryItem(name: "client_id", value: clientID.rawValue))
        }
        let response: BackendItems<BackendLegalCaseDTO> = try await get(Endpoint.cases.rawValue, query: items)
        return response.items
    }

    /// Token statusu sprawy w słowniku kontraktu.
    static func caseStatusToken(_ status: CaseStatus) -> String {
        switch status {
        case .inProgress: return "in_progress"
        case .awaitingClient: return "awaiting_client"
        case .closed: return "closed"
        }
    }

    /// `GET /api/mobile/v1/tasks?scope=&client_id=&case_id=&due_on_or_before=`.
    func tasks(filter: TaskFilter) async throws -> [BackendTaskDTO] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "scope", value: Self.scopeToken(filter.scope))
        ]
        if let clientID = filter.clientID {
            items.append(URLQueryItem(name: "client_id", value: clientID.rawValue))
        }
        if let caseID = filter.caseID {
            items.append(URLQueryItem(name: "case_id", value: caseID.rawValue))
        }
        if let due = filter.dueOnOrBefore {
            items.append(URLQueryItem(name: "due_on_or_before", value: due.isoString))
        }
        let response: BackendItems<BackendTaskDTO> = try await get(Endpoint.tasks.rawValue, query: items)
        return response.items
    }

    /// `GET /api/mobile/v1/events?from=&through=[&client_id=]`.
    func events(in range: DateIntervalFilter, clientID: ClientID? = nil) async throws -> [BackendEventDTO] {
        var items = [
            URLQueryItem(name: "from", value: range.from.isoString),
            URLQueryItem(name: "through", value: range.through.isoString)
        ]
        if let clientID {
            items.append(URLQueryItem(name: "client_id", value: clientID.rawValue))
        }
        let response: BackendItems<BackendEventDTO> = try await get(Endpoint.events.rawValue, query: items)
        return response.items
    }

    // MARK: Zapis danych kancelarii
    //
    // Trasy istniały w backendzie od dawna, a repozytorium zgłaszało je jako
    // niedostępne — dlatego „Zatwierdź” i formularze nic nie zapisywały.

    /// `POST /api/mobile/v1/tasks`.
    func createTask(_ body: BackendTaskCreateBody, idempotencyKey: String) async throws -> BackendTaskDTO {
        try await send("POST", path: Endpoint.tasks.rawValue, body: body, idempotencyKey: idempotencyKey)
    }

    /// `PATCH /api/mobile/v1/tasks/{task_id}` — pola `nil` nie są wysyłane.
    func updateTask(id: String, body: BackendTaskUpdateBody, idempotencyKey: String) async throws -> BackendTaskDTO {
        try await send("PATCH", path: "\(Endpoint.tasks.rawValue)/\(id)", body: body, idempotencyKey: idempotencyKey)
    }

    /// `POST /api/mobile/v1/events`.
    func createEvent(_ body: BackendEventCreateBody, idempotencyKey: String) async throws -> BackendEventDTO {
        try await send("POST", path: Endpoint.events.rawValue, body: body, idempotencyKey: idempotencyKey)
    }

    /// `PATCH /api/mobile/v1/events/{event_id}` — stan, dzień, godzina, długość,
    /// a od audytu 23.09.2026 także nazwa, miejsce i rodzaj.
    func updateEvent(id: String, body: BackendEventUpdateBody, idempotencyKey: String) async throws -> BackendEventDTO {
        try await send("PATCH", path: "\(Endpoint.events.rawValue)/\(id)", body: body, idempotencyKey: idempotencyKey)
    }

    /// `DELETE /api/mobile/v1/events/{event_id}` z `expected_version` w ciele.
    func deleteEvent(id: String, expectedVersion: Int, idempotencyKey: String) async throws {
        try await sendNoContent(
            "DELETE",
            path: "\(Endpoint.events.rawValue)/\(id)",
            body: BackendExpectedVersionBody(expectedVersion: expectedVersion),
            idempotencyKey: idempotencyKey
        )
    }

    /// `POST /api/mobile/v1/notes`.
    func createNote(_ body: BackendNoteCreateBody, idempotencyKey: String) async throws -> BackendNoteDTO {
        try await send("POST", path: Endpoint.notes.rawValue, body: body, idempotencyKey: idempotencyKey)
    }

    // MARK: Akcje asystenta (propozycja → zgoda → wykonanie)

    /// `POST /api/mobile/v1/actions` — propozycja; niczego nie wykonuje.
    func prepareAction(_ body: BackendActionPrepareBody, idempotencyKey: String) async throws -> BackendActionDTO {
        try await send("POST", path: Endpoint.actions.rawValue, body: body, idempotencyKey: idempotencyKey)
    }

    /// `PATCH /api/mobile/v1/actions/{id}` — korekta treści; unieważnia zgodę.
    func reviseAction(id: String, text: String, expectedVersion: Int, idempotencyKey: String) async throws -> BackendActionDTO {
        try await send(
            "PATCH",
            path: "\(Endpoint.actions.rawValue)/\(id)",
            body: BackendActionReviseBody(text: text, expectedVersion: expectedVersion),
            idempotencyKey: idempotencyKey
        )
    }

    /// `POST /api/mobile/v1/actions/{id}/confirm`. Pochodzenie zgody jedzie
    /// w nagłówku `X-Emma-Consent` — backend odrzuca zgodę „od modelu”.
    func confirmAction(
        id: String,
        body: BackendActionConfirmBody,
        consent: String,
        idempotencyKey: String
    ) async throws -> BackendActionExecutionDTO {
        try await send(
            "POST",
            path: "\(Endpoint.actions.rawValue)/\(id)/confirm",
            body: body,
            idempotencyKey: idempotencyKey,
            headers: ["X-Emma-Consent": consent]
        )
    }

    /// `POST /api/mobile/v1/actions/{id}/cancel`.
    func cancelAction(id: String, idempotencyKey: String) async throws -> BackendActionDTO {
        try await send(
            "POST",
            path: "\(Endpoint.actions.rawValue)/\(id)/cancel",
            body: BackendEmptyBody(),
            idempotencyKey: idempotencyKey
        )
    }

    /// `GET /api/mobile/v1/actions/{id}/execution`.
    func actionExecution(id: String) async throws -> BackendActionExecutionDTO {
        try await get("\(Endpoint.actions.rawValue)/\(id)/execution", query: [])
    }

    // MARK: Głos (M5)
    //
    // Trasy sesji głosu. `Idempotency-Key` pochodzi od wywołującego (repozytorium),
    // bo to on wie, co jest „tym samym logicznym żądaniem” — tutaj tylko go wysyłamy.

    /// `POST /api/mobile/v1/voice/sessions`. Powtórzenie tego samego `session_id`
    /// zwraca istniejącą sesję, nie zakłada drugiej.
    func createVoiceSession(
        sessionID: VoiceSessionID,
        installationID: String,
        contextVersion: Int,
        idempotencyKey: String
    ) async throws -> BackendVoiceSessionDTO {
        let body = BackendVoiceSessionCreateBody(
            sessionID: sessionID.rawValue,
            installationID: installationID,
            contextVersion: contextVersion
        )
        return try await send(
            "POST",
            path: Endpoint.voiceSessions.rawValue,
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    /// `POST /api/mobile/v1/voice/conversation-token`. Zwraca wyłącznie token
    /// rozmowy — klucz API dostawcy nigdy nie opuszcza backendu.
    func voiceConversationToken(
        sessionID: VoiceSessionID,
        installationID: String,
        contextVersion: Int,
        idempotencyKey: String
    ) async throws -> BackendConversationTokenDTO {
        let body = BackendVoiceConversationTokenBody(
            sessionID: sessionID.rawValue,
            installationID: installationID,
            contextVersion: contextVersion
        )
        return try await send(
            "POST",
            path: Endpoint.voiceConversationToken.rawValue,
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    /// `PATCH /api/mobile/v1/voice/sessions/{id}/context` — wersja może tylko rosnąć.
    func updateVoiceContext(
        sessionID: VoiceSessionID,
        contextVersion: Int,
        idempotencyKey: String
    ) async throws -> BackendVoiceSessionDTO {
        let body = BackendVoiceContextBody(contextVersion: contextVersion)
        return try await send(
            "PATCH",
            path: "\(Endpoint.voiceSessions.rawValue)/\(sessionID.rawValue)/context",
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    /// `GET /api/mobile/v1/voice/sessions/{id}/status`.
    func voiceSessionStatus(sessionID: VoiceSessionID) async throws -> BackendVoiceSessionDTO {
        try await get("\(Endpoint.voiceSessions.rawValue)/\(sessionID.rawValue)/status", query: [])
    }

    /// `DELETE /api/mobile/v1/voice/sessions/{id}` → 204.
    func endVoiceSession(sessionID: VoiceSessionID, idempotencyKey: String) async throws {
        try await sendNoContent(
            "DELETE",
            path: "\(Endpoint.voiceSessions.rawValue)/\(sessionID.rawValue)",
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: Rozmowy WhatsApp

    /// `GET /api/mobile/v1/threads` — rozmowy z licznikami dla zalogowanej osoby.
    /// `includeUnassigned` dokłada rozmowy bez osoby w kartotece (`client_id = null`);
    /// starszy serwer ignoruje parametr i zwraca tylko rozmowy z osobą.
    func threads(includeUnassigned: Bool = false) async throws -> BackendThreadList {
        try await get(
            Endpoint.threads.rawValue,
            query: includeUnassigned ? [URLQueryItem(name: "include_unassigned", value: "1")] : []
        )
    }

    /// `POST /api/mobile/v1/threads/{thread_id}/draft-reply` — szkic odpowiedzi od modelu.
    func draftReply(threadID: ThreadID, idempotencyKey: String) async throws -> BackendDraftReplyDTO {
        try await send(
            "POST",
            path: "\(Endpoint.threads.rawValue)/\(threadID.rawValue)/draft-reply",
            body: BackendEmptyBody(),
            idempotencyKey: idempotencyKey
        )
    }

    /// `POST /api/mobile/v1/assistant/messages` — pytanie do Emmy pisemnie.
    func askAssistant(body: BackendAssistantMessageBody, idempotencyKey: String) async throws -> BackendAssistantReplyDTO {
        try await send("POST", path: "api/mobile/v1/assistant/messages", body: body, idempotencyKey: idempotencyKey)
    }

    /// `GET /api/mobile/v1/voice/usage` — koszt rozmów głosowych w tym miesiącu.
    func voiceUsage() async throws -> BackendVoiceUsageDTO {
        try await get("api/mobile/v1/voice/usage", query: [])
    }

    /// `POST /api/mobile/v1/threads/{thread_id}/lead` — rozmowa bez osoby staje się leadem.
    func createThreadLead(threadID: ThreadID, idempotencyKey: String) async throws -> BackendThreadSummaryDTO {
        try await send(
            "POST",
            path: "\(Endpoint.threads.rawValue)/\(threadID.rawValue)/lead",
            body: BackendEmptyBody(),
            idempotencyKey: idempotencyKey
        )
    }

    /// `GET /api/mobile/v1/threads/{thread_id}/messages?before_sequence=&limit=`.
    /// `before_sequence` może być ≤ 0 — tak numerowana jest historia z telefonu.
    func messages(threadID: ThreadID, beforeSequence: Int?, limit: Int) async throws -> BackendMessagePage {
        var query = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100)))]
        if let beforeSequence {
            query.append(URLQueryItem(name: "before_sequence", value: String(beforeSequence)))
        }
        return try await get("\(Endpoint.threads.rawValue)/\(threadID.rawValue)/messages", query: query)
    }

    /// `POST /api/mobile/v1/threads/{thread_id}/messages` — odpowiedź klientowi.
    /// Wraca 202 z wiadomością; `transport` mówi, czy WhatsApp ją przyjął.
    func sendMessage(
        threadID: ThreadID,
        body: BackendOutgoingMessageBody,
        idempotencyKey: String
    ) async throws -> BackendMessageDTO {
        try await send(
            "POST",
            path: "\(Endpoint.threads.rawValue)/\(threadID.rawValue)/messages",
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    /// `PUT /api/mobile/v1/threads/{thread_id}/read-state` — kursor tylko do przodu.
    /// Kontrakt nie wymaga tu klucza idempotencji (chroni wersja), ale go
    /// wysyłamy, bo wspólna ścieżka zapisu zawsze go dokłada.
    func saveReadState(
        threadID: ThreadID,
        body: BackendReadStateBody,
        idempotencyKey: String
    ) async throws -> BackendThreadUserStateDTO {
        try await send(
            "PUT",
            path: "\(Endpoint.threads.rawValue)/\(threadID.rawValue)/read-state",
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: Żądanie i odpowiedź

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        let (data, http) = try await authenticatedRequest { token in
            try self.makeRequest(path: path, query: query, token: token)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: http, data: data)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            // Nie podmieniamy nieudanego dekodowania na pusty wynik: brak danych
            // i niezgodność kontraktu to dwie różne sytuacje dla użytkownika.
            throw BackendRepositoryError.decoding("\(error)")
        }
    }

    private func makeRequest(
        path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        idempotencyKey: String? = nil,
        headers: [String: String] = [:],
        token: String?
    ) throws -> URLRequest {
        // Identyfikatory w ścieżce bywają niezaufane (np. `case_id` od modelu
        // w narzędziu `app_open_case`). `appendingPathComponent` nie usuwa
        // `..` ani `/`, więc `case-1/../../actions/7/confirm` trafiłby w inną
        // trasę — z tokenem użytkownika. Nieprawidłowy identyfikator = brak rekordu.
        guard Self.isSafePath(path) else {
            throw BackendRepositoryError.notFound
        }
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw BackendRepositoryError.transport("nieprawidłowy adres backendu")
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw BackendRepositoryError.transport("nieprawidłowe zapytanie")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let idempotencyKey, !idempotencyKey.isEmpty {
            // Kontrakt wymaga klucza przy zapisach; bez niego backend odrzuca
            // żądanie (422), więc nie wysyłamy zapisu „na próbę”.
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    /// Każdy segment ścieżki jest niepusty, nie jest `.` ani `..` i składa się
    /// wyłącznie ze znaków spotykanych w identyfikatorach kontraktu
    /// (`client-12`, `lead-7`, UUID sesji głosu).
    static func isSafePath(_ path: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:")
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { segment in
            !segment.isEmpty && segment != "." && segment != ".." && segment.allSatisfy(allowed.contains)
        }
    }

    /// Zapis z odpowiedzią JSON. `Idempotency-Key` jest wymagany przez kontrakt,
    /// więc wywołanie bez niego jest błędem programisty, a nie użytkownika.
    private func send<B: Encodable, T: Decodable>(
        _ method: String,
        path: String,
        body: B,
        idempotencyKey: String,
        headers: [String: String] = [:]
    ) async throws -> T {
        let encoded: Data
        do {
            encoded = try Self.encoder.encode(body)
        } catch {
            throw BackendRepositoryError.decoding("nie udało się zapisać treści żądania: \(error)")
        }
        let (data, http) = try await authenticatedRequest { token in
            try self.makeRequest(
                path: path,
                method: method,
                body: encoded,
                idempotencyKey: idempotencyKey,
                headers: headers,
                token: token
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: http, data: data)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw BackendRepositoryError.decoding("\(error)")
        }
    }

    /// Zapis z ciałem, którego odpowiedź nie niesie treści (204).
    ///
    /// Istnieje osobno od `send(_:path:body:)`, bo tamten **dekoduje** odpowiedź:
    /// przy 204 nie ma czego dekodować, a próba kończyłaby się błędem mimo
    /// udanego zapisu.
    private func sendNoContent<B: Encodable>(
        _ method: String,
        path: String,
        body: B,
        idempotencyKey: String
    ) async throws {
        let encoded: Data
        do {
            encoded = try Self.encoder.encode(body)
        } catch {
            throw BackendRepositoryError.decoding("nie udało się zapisać treści żądania: \(error)")
        }
        let (data, http) = try await authenticatedRequest { token in
            try self.makeRequest(
                path: path,
                method: method,
                body: encoded,
                idempotencyKey: idempotencyKey,
                token: token
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: http, data: data)
        }
    }

    /// Zapis bez treści oczekiwanej w odpowiedzi (204).
    private func sendNoContent(
        _ method: String,
        path: String,
        idempotencyKey: String
    ) async throws {
        let (data, http) = try await authenticatedRequest { token in
            try self.makeRequest(
                path: path,
                method: method,
                idempotencyKey: idempotencyKey,
                token: token
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: http, data: data)
        }
    }

    // MARK: Żądanie z obsługą wygaśnięcia tokenu

    /// Wykonuje żądanie z bieżącym tokenem, a przy 401 **raz** odnawia token
    /// i ponawia. Zwraca surową odpowiedź (także błędną), żeby wołający mógł
    /// zmapować status na właściwy błąd domenowy.
    ///
    /// Świadomie nie ponawiamy przy 403: brak uprawnień do zasobu nie jest
    /// wygasłą sesją i nie może prowadzić do wylogowania.
    private func authenticatedRequest(
        _ make: @Sendable (String?) throws -> URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let token = await accessToken()
        let (data, http) = try await performAndValidate(try make(token))
        guard http.statusCode == 401,
              let refreshToken,
              let refreshed = await refreshToken(),
              !refreshed.isEmpty else {
            return (data, http)
        }
        return try await performAndValidate(try make(refreshed))
    }

    private func performAndValidate(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendRepositoryError.transport("nieprawidłowa odpowiedź serwera")
        }
        return (data, http)
    }

    /// Koder tworzymy na każde wywołanie — jak dekoder, żeby nie współdzielić
    /// instancji, która nie jest `Sendable`.
    static var encoder: JSONEncoder { JSONEncoder() }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where Self.isRetryableRead(request, error: error) {
            // Po powrocie z tła iOS często próbuje najpierw starego połączenia
            // (HTTP/2), które serwer już zamknął — pierwszy odczyt kończy się
            // „The network connection was lost”, drugi przechodzi. Odczyt jest
            // bezpieczny do powtórzenia, więc ponawiamy go raz, po krótkiej
            // przerwie, zamiast pokazywać błąd, który znika po drugim „odśwież”.
            try await Task.sleep(nanoseconds: 350_000_000)
            return try await performOnce(request)
        } catch let error as URLError {
            throw Self.mapTransport(error)
        } catch {
            throw BackendRepositoryError.transport(error.localizedDescription)
        }
    }

    private func performOnce(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw Self.mapTransport(error)
        } catch {
            throw BackendRepositoryError.transport(error.localizedDescription)
        }
    }

    /// Anulowanie to nasza decyzja, nie awaria sieci — nie zamieniamy jej
    /// na błąd transportu, bo zadanie i tak jest już porzucone.
    private static func mapTransport(_ error: URLError) -> Error {
        if error.code == .cancelled { return CancellationError() }
        return BackendRepositoryError.transport(error.localizedDescription)
    }

    /// Czy żądanie wolno powtórzyć po chwilowym błędzie sieci. Tylko odczyt:
    /// zapis ma własny klucz idempotencji i ponawia go użytkownik, świadomie.
    static func isRetryableRead(_ request: URLRequest, error: URLError) -> Bool {
        guard (request.httpMethod ?? "GET").uppercased() == "GET" else { return false }
        switch error.code {
        case .networkConnectionLost, .cannotConnectToHost,
             .notConnectedToInternet, .dnsLookupFailed, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    // MARK: Błędy i dekodowanie

    private struct ErrorBody: Decodable {
        let code: String
        let message: String
    }

    /// Ciało konfliktu wersji (`version_conflict`) niesie `current_version`.
    private struct ErrorVersionBody: Decodable {
        let currentVersion: Int?

        enum CodingKeys: String, CodingKey {
            case currentVersion = "current_version"
        }
    }

    /// Mapowanie odpowiedzi błędu po statusie. Ciało `{code, message}` służy
    /// tylko do pokazania komunikatu; o rodzaju błędu decyduje status, bo to on
    /// jest częścią transportu i nie zależy od wersji kontraktu.
    static func error(from response: HTTPURLResponse, data: Data) -> BackendRepositoryError {
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message
        switch response.statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden(message)
        case 404:
            // Brak rekordu backend zgłasza w JSON (`not_found`). 404 bez takiego
            // ciała (strona HTML) znaczy, że serwer nie ma jeszcze tej trasy —
            // to inna sytuacja niż „nie ma rekordu” i aplikacja może wtedy
            // skorzystać z dawnej drogi (np. szukania rekordu na liście).
            if message == nil, let first = data.first(where: { !($0 == 32 || $0 == 10 || $0 == 13 || $0 == 9) }), first == UInt8(ascii: "<") {
                return .notAvailableInBackend("ta funkcja na serwerze kancelarii (zaktualizuj backend)")
            }
            return .notFound
        case 409:
            // Konflikt wersji: kontrakt dokłada `current_version`, żeby aplikacja
            // mogła pokazać wersję faktyczną, a nie tylko „błąd”.
            let version = (try? JSONDecoder().decode(ErrorVersionBody.self, from: data))?.currentVersion
            return .conflict(currentVersion: version, message: message)
        default:
            return .server(status: response.statusCode, message: message)
        }
    }

    /// Dekoder powstaje na każde wywołanie: dzięki temu nie trzymamy współdzielonej
    /// instancji, która nie jest `Sendable` — w trybie Swift 6 to nie szczegół stylu.
    static var decoder: JSONDecoder { JSONDecoder() }

    // MARK: Tokeny kontraktu (wartości druciane)

    /// Etap klienta jest w aplikacji opisany po polsku, a w kontrakcie tokenem.
    /// Trzymamy oba tłumaczenia obok siebie, żeby nie rozjechały się z dekodowaniem.
    private static func stageToken(_ stage: ClientStage) -> String {
        switch stage {
        case .new: return "new"
        case .inContact: return "in_contact"
        case .client: return "client"
        }
    }

    private static func scopeToken(_ scope: TaskFilter.Scope) -> String {
        switch scope {
        case .open: return "open"
        case .done: return "done"
        case .all: return "all"
        }
    }
}

// MARK: - Kształty JSON-a kontraktu
//
// Typy są wewnętrzne: to nie model aplikacji, tylko wierny obraz odpowiedzi
// backendu. Mapowanie na `Client`, `TaskItem` itd. należy do `BackendRepository`,
// więc warstwy nie przeciekają do siebie.

struct BackendItems<T: Decodable>: Decodable {
    let items: [T]
}

struct BackendClientPage: Decodable {
    let items: [BackendClientDTO]
    let nextCursor: String?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

struct BackendClientDTO: Decodable {
    let id: String
    let displayName: String
    let initials: String
    let language: String
    let topic: String
    let stage: String
    let source: String
    let createdAt: LocalDate
    let briefing: String?
    let incomingMessage: String?
    let incomingTranslation: String?
    let incomingTime: String?
    let needsReply: Bool
    /// Rozszerzenie kontraktu (opcjonalne): dokładna chwila przyjęcia
    /// zgłoszenia, telefon i e-mail. Starszy backend ich nie wysyła — wtedy
    /// aplikacja liczy wiek leada z samej daty i nie proponuje dzwonienia.
    let receivedAt: String?
    let phone: String?
    let email: String?
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id, initials, language, topic, stage, source, briefing, version, phone, email
        case displayName = "display_name"
        case createdAt = "created_at"
        case incomingMessage = "incoming_message"
        case incomingTranslation = "incoming_translation"
        case incomingTime = "incoming_time"
        case needsReply = "needs_reply"
        case receivedAt = "received_at"
    }
}

struct BackendLegalCaseDTO: Decodable {
    let id: String
    let number: String
    let title: String
    let clientID: String
    let status: String
    let summary: String?
    let createdAt: LocalDate
    let version: Int
    /// Rozszerzenie kontraktu (backend 30.09.2026): sygnatura akt i sąd osobno.
    let signature: String?
    let court: String?
    /// Rozszerzenie kontraktu (01.10.2026): profil sprawy i pilnowane daty.
    /// Starszy serwer ich nie wysyła — wtedy wszystkie są `nil`.
    let kind: String?
    let stage: String?
    let clientRole: String?
    let custodyUntil: String?
    let legalStayUntil: String?

    enum CodingKeys: String, CodingKey {
        case id, number, title, status, summary, version, signature, court, kind, stage
        case clientID = "client_id"
        case createdAt = "created_at"
        case clientRole = "client_role"
        case custodyUntil = "custody_until"
        case legalStayUntil = "legal_stay_until"
    }
}

struct BackendTaskDTO: Decodable {
    let id: String
    let title: String
    let clientID: String?
    let caseID: String?
    let dueDate: String?
    let isDone: Bool
    let priority: String
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id, title, priority, version
        case clientID = "client_id"
        case caseID = "case_id"
        case dueDate = "due_date"
        case isDone = "is_done"
    }
}

struct BackendEventDTO: Decodable {
    let id: String
    /// Kontrakt wymaga klienta w terminie, ale baza kancelarii zna też terminy
    /// bez kartoteki (np. konsultację zapisaną z samego zgłoszenia). Pole jest
    /// więc opcjonalne, żeby jeden taki rekord **nie wywracał dekodowania całej
    /// odpowiedzi** — aplikacja pomija taki termin, zamiast gasić ekran.
    let clientID: String?
    let caseID: String?
    let title: String
    let day: LocalDate
    /// `null` przy terminie całodniowym — kontrakt nie niesie wtedy godziny.
    let time: String?
    /// `true` dla terminu całodniowego — wtedy `time` jest `null`.
    let allDay: Bool
    let durationMinutes: Int
    let kind: String
    let status: String
    let place: String?
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id, title, day, time, kind, status, place, version
        case clientID = "client_id"
        case caseID = "case_id"
        case allDay = "all_day"
        case durationMinutes = "duration_minutes"
    }
}

struct BackendNoteDTO: Decodable {
    let id: String
    let clientID: String
    let caseID: String?
    let text: String
    let authorID: String
    /// Pełny znacznik ISO (`2026-09-13T12:00:00.000Z`); aplikacja trzyma samą datę.
    let createdAt: String
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id, text, version
        case clientID = "client_id"
        case caseID = "case_id"
        case authorID = "author_id"
        case createdAt = "created_at"
    }
}

struct BackendActivityDTO: Decodable {
    let id: String
    let text: String
    let clientID: String?
    let caseID: String?
    let createdAt: String
    let authorID: String

    enum CodingKeys: String, CodingKey {
        case id, text
        case clientID = "client_id"
        case caseID = "case_id"
        case createdAt = "created_at"
        case authorID = "author_id"
    }
}

struct BackendClientCard: Decodable {
    let client: BackendClientDTO
    let legalCase: BackendLegalCaseDTO?
    let events: [BackendEventDTO]
    let tasks: [BackendTaskDTO]
    let notes: [BackendNoteDTO]
    let activity: [BackendActivityDTO]

    enum CodingKeys: String, CodingKey {
        case client, events, tasks, notes, activity
        case legalCase = "case"
    }
}

struct BackendCaseDetail: Decodable {
    let legalCase: BackendLegalCaseDTO
    let tasks: [BackendTaskDTO]
    let events: [BackendEventDTO]
    let notes: [BackendNoteDTO]
    let activity: [BackendActivityDTO]

    enum CodingKeys: String, CodingKey {
        case tasks, events, notes, activity
        case legalCase = "case"
    }
}

// MARK: - Kształty JSON-a zapisu

struct BackendEmptyBody: Encodable {}

struct BackendExpectedVersionBody: Encodable {
    let expectedVersion: Int
    enum CodingKeys: String, CodingKey { case expectedVersion = "expected_version" }
}

struct BackendTaskCreateBody: Encodable {
    let title: String
    let dueDate: String
    let priority: String
    let clientID: String?
    let caseID: String?

    enum CodingKeys: String, CodingKey {
        case title, priority
        case dueDate = "due_date"
        case clientID = "client_id"
        case caseID = "case_id"
    }
}

struct BackendTaskUpdateBody: Encodable {
    var expectedVersion: Int
    var title: String?
    var dueDate: String?
    var priority: String?
    var isDone: Bool?
    /// Zmiana klienta: `nil` — bez zmiany, `.some(nil)` — odpięcie (`null`).
    var clientID: String?? = nil

    enum CodingKeys: String, CodingKey {
        case title, priority
        case expectedVersion = "expected_version"
        case dueDate = "due_date"
        case isDone = "is_done"
        case clientID = "client_id"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(expectedVersion, forKey: .expectedVersion)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(isDone, forKey: .isDone)
        if let clientID {
            try container.encode(clientID, forKey: .clientID)
        }
    }
}

struct BackendEventCreateBody: Encodable {
    let title: String
    let day: String
    let time: String
    let durationMinutes: Int
    let kind: String
    /// `nil` — termin bez klienta (pole pomijane w JSON-ie).
    let clientID: String?
    let caseID: String?
    let place: String?

    enum CodingKeys: String, CodingKey {
        case title, day, time, kind, place
        case durationMinutes = "duration_minutes"
        case clientID = "client_id"
        case caseID = "case_id"
    }
}

struct BackendEventUpdateBody: Encodable {
    var expectedVersion: Int
    var status: String?
    var durationMinutes: Int?
    var day: String?
    var time: String?
    var title: String?
    var place: String?
    var kind: String?

    enum CodingKeys: String, CodingKey {
        case status, day, time, title, place, kind
        case expectedVersion = "expected_version"
        case durationMinutes = "duration_minutes"
    }
}

struct BackendCaseCreateBody: Encodable {
    let clientID: String
    let title: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case title, summary
        case clientID = "client_id"
    }
}

struct BackendCaseUpdateBody: Encodable {
    let expectedVersion: Int
    let title: String?
    let status: String?
    /// `nil` — bez zmiany; pusty tekst czyści pole na serwerze.
    var signature: String? = nil
    var court: String? = nil
    /// Profil sprawy: token albo pusty tekst (czyści pole); `nil` — bez zmiany.
    var kind: String? = nil
    var stage: String? = nil
    var clientRole: String? = nil
    /// Data `YYYY-MM-DD` albo pusty tekst (czyści datę); `nil` — bez zmiany.
    var custodyUntil: String? = nil
    var legalStayUntil: String? = nil

    enum CodingKeys: String, CodingKey {
        case title, status, signature, court, kind, stage
        case expectedVersion = "expected_version"
        case clientRole = "client_role"
        case custodyUntil = "custody_until"
        case legalStayUntil = "legal_stay_until"
    }
}

struct BackendNoteCreateBody: Encodable {
    let text: String
    let clientID: String
    let caseID: String?
    let authorID: String

    enum CodingKeys: String, CodingKey {
        case text
        case clientID = "client_id"
        case caseID = "case_id"
        case authorID = "author_id"
    }
}

// MARK: - Kształty JSON-a akcji

struct BackendActionContextBody: Encodable {
    let scope: String
    let version: Int
    let clientID: String?
    let caseID: String?
    let threadID: String?

    enum CodingKeys: String, CodingKey {
        case scope, version
        case clientID = "client_id"
        case caseID = "case_id"
        case threadID = "thread_id"
    }
}

struct BackendActionPrepareBody: Encodable {
    let kind: String
    let text: String
    let origin: String
    let actorUserID: String
    let taskDueDate: String?
    let context: BackendActionContextBody

    enum CodingKeys: String, CodingKey {
        case kind, text, origin, context
        case actorUserID = "actor_user_id"
        case taskDueDate = "task_due_date"
    }
}

struct BackendActionReviseBody: Encodable {
    let text: String
    let expectedVersion: Int
    enum CodingKeys: String, CodingKey {
        case text
        case expectedVersion = "expected_version"
    }
}

struct BackendActionConfirmBody: Encodable {
    let presentationID: String
    let expectedContextVersion: Int
    let voiceSessionID: String?

    enum CodingKeys: String, CodingKey {
        case presentationID = "presentation_id"
        case expectedContextVersion = "expected_context_version"
        case voiceSessionID = "voice_session_id"
    }
}

/// Propozycja akcji z backendu. `context_version` rośnie przy każdej korekcie
/// i pełni rolę wersji propozycji (`expected_version` w `PATCH`).
struct BackendActionDTO: Decodable {
    let id: String
    let kind: String
    let actorUserID: String
    let clientID: String?
    let caseID: String?
    let threadID: String?
    let text: String
    let payloadHash: String
    let contextVersion: Int
    let presentedAt: String
    let expiresAt: String
    let presentationID: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case id, kind, text, state
        case actorUserID = "actor_user_id"
        case clientID = "client_id"
        case caseID = "case_id"
        case threadID = "thread_id"
        case payloadHash = "payload_hash"
        case contextVersion = "context_version"
        case presentedAt = "presented_at"
        case expiresAt = "expires_at"
        case presentationID = "presentation_id"
    }
}

struct BackendActionExecutionDTO: Decodable {
    let actionID: String
    let state: String
    let outboxID: String
    let providerMessageID: String?
    let updatedAt: String
    let failureCode: String?

    enum CodingKeys: String, CodingKey {
        case state
        case actionID = "action_id"
        case outboxID = "outbox_id"
        case providerMessageID = "provider_message_id"
        case updatedAt = "updated_at"
        case failureCode = "failure_code"
    }
}

// MARK: - Kształty JSON-a sesji głosu (M5)

/// Odpowiedź na otwarcie/zmianę/odczyt sesji głosu. `ended_at` jest `null`,
/// dopóki sesja żyje, a `provider_conversation_id` — dopóki nie wydano tokenu.
struct BackendVoiceSessionDTO: Decodable {
    let id: String
    let state: String
    let contextVersion: Int
    let installationID: String
    let startedAt: String
    let endedAt: String?
    let providerConversationID: String?

    enum CodingKeys: String, CodingKey {
        case id, state
        case contextVersion = "context_version"
        case installationID = "installation_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case providerConversationID = "provider_conversation_id"
    }
}

/// Odpowiedź `POST /voice/conversation-token` dla Gemini Live. Live API nie
/// wydaje identyfikatora rozmowy; `expires_at` i `model` są opcjonalne, bo
/// backend może ich nie zwrócić w każdej wersji kontraktu.
struct BackendConversationTokenDTO: Decodable {
    let token: String
    let conversationID: String?
    let contextVersion: Int
    let sessionID: String
    /// Nazwa dostawcy, który wydał token. Musi być `gemini_live`, jeśli pole
    /// jest obecne.
    let provider: String?
    /// Model wskazany przez backend — aplikacja ma go odesłać w `setup`.
    let model: String?
    /// Czas wygaśnięcia **jako tekst ISO-8601**. Świadomie nie `Date`: wspólny
    /// dekoder klienta nie ma strategii dat, a jeden format daty dostawcy nie
    /// może zmieniać dekodowania wszystkich pozostałych odpowiedzi.
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case token
        case conversationID = "conversation_id"
        case contextVersion = "context_version"
        case sessionID = "session_id"
        case provider
        case model
        case expiresAt = "expires_at"
    }
}

struct BackendVoiceSessionCreateBody: Encodable {
    let sessionID: String
    let installationID: String
    let contextVersion: Int

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case installationID = "installation_id"
        case contextVersion = "context_version"
    }
}

struct BackendVoiceConversationTokenBody: Encodable {
    let sessionID: String
    let installationID: String
    let contextVersion: Int

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case installationID = "installation_id"
        case contextVersion = "context_version"
    }
}

struct BackendVoiceContextBody: Encodable {
    let contextVersion: Int

    enum CodingKeys: String, CodingKey {
        case contextVersion = "context_version"
    }
}

// MARK: Rozmowy WhatsApp

struct BackendMessageDTO: Decodable {
    let id: String
    let threadID: String
    let direction: String
    let authorID: String?
    let authorLabel: String?
    let providerMessageID: String?
    let kind: String
    /// Rozszerzenie kontraktu: rodzaj załącznika (image, document, audio…).
    let attachmentType: String?
    /// Rozszerzenie kontraktu (01.10.2026): nazwa pliku załącznika.
    let attachmentName: String?
    let text: String
    let translation: String?
    let sentAt: String
    let sequence: Int
    let transport: String
    let source: String
    /// Rozszerzenie kontraktu: customer, business_app, api, history.
    let origin: String?
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id, direction, kind, text, translation, sequence, transport, source, origin, version
        case threadID = "thread_id"
        case authorID = "author_id"
        case authorLabel = "author_label"
        case providerMessageID = "provider_message_id"
        case attachmentType = "attachment_type"
        case attachmentName = "attachment_name"
        case sentAt = "sent_at"
    }
}

struct BackendThreadSummaryDTO: Decodable {
    let id: String
    /// `nil` tylko dla rozmowy bez osoby (`include_unassigned=1`).
    let clientID: String?
    let clientName: String?
    let preview: BackendMessageDTO?
    let unreadCount: Int
    let isPinned: Bool?
    let highWatermark: Int?
    // Rozszerzenia kontraktu: stan osoby w wątku bez osobnego zapytania.
    let readCursorSequence: Int?
    let manualUnread: Bool?
    let readStateVersion: Int?
    /// Do kiedy WhatsApp pozwala wysłać swobodny tekst (ISO) — `nil`, gdy okno zamknięte.
    let replyWindowUntil: String?
    /// Rozszerzenie 02.10.2026: numer rozmówcy i znacznik rozmowy bez osoby.
    let contactPhone: String?
    let isUnassigned: Bool?

    enum CodingKeys: String, CodingKey {
        case id, preview
        case contactPhone = "contact_phone"
        case isUnassigned = "is_unassigned"
        case clientID = "client_id"
        case clientName = "client_name"
        case unreadCount = "unread_count"
        case isPinned = "is_pinned"
        case highWatermark = "high_watermark"
        case readCursorSequence = "read_cursor_sequence"
        case manualUnread = "manual_unread"
        case readStateVersion = "read_state_version"
        case replyWindowUntil = "reply_window_until"
    }
}

struct BackendAssistantMessageBody: Encodable {
    let message: String
    let conversationID: Int?
    let contextClientID: String?
    let contextName: String?

    enum CodingKeys: String, CodingKey {
        case message
        case conversationID = "conversation_id"
        case contextClientID = "context_client_id"
        case contextName = "context_name"
    }
}

struct BackendAssistantReplyDTO: Decodable {
    let conversationID: Int
    let reply: String

    enum CodingKeys: String, CodingKey {
        case reply
        case conversationID = "conversation_id"
    }
}

struct BackendDraftReplyDTO: Decodable {
    let text: String
    let language: String?
}

struct BackendVoiceUsageDTO: Decodable {
    let monthCostUsd: Double
    let budgetUsd: Double
    let sessions: Int
    let minutes: Int

    enum CodingKeys: String, CodingKey {
        case sessions, minutes
        case monthCostUsd = "month_cost_usd"
        case budgetUsd = "budget_usd"
    }
}

struct BackendThreadList: Decodable {
    let items: [BackendThreadSummaryDTO]
    let unreadTotal: Int

    enum CodingKeys: String, CodingKey {
        case items
        case unreadTotal = "unread_total"
    }
}

struct BackendMessagePage: Decodable {
    let items: [BackendMessageDTO]
    let highWatermark: Int

    enum CodingKeys: String, CodingKey {
        case items
        case highWatermark = "high_watermark"
    }
}

struct BackendThreadUserStateDTO: Decodable {
    let threadID: String
    let userID: String
    let readCursorSequence: Int
    let manualUnread: Bool
    let isPinned: Bool
    let version: Int

    enum CodingKeys: String, CodingKey {
        case version
        case threadID = "thread_id"
        case userID = "user_id"
        case readCursorSequence = "read_cursor_sequence"
        case manualUnread = "manual_unread"
        case isPinned = "is_pinned"
    }
}

struct BackendOutgoingMessageBody: Encodable {
    let text: String
    let authorID: String
    let language: String

    enum CodingKeys: String, CodingKey {
        case text, language
        case authorID = "author_id"
    }
}

struct BackendReadStateBody: Encodable {
    let readCursorSequence: Int
    let manualUnread: Bool
    let isPinned: Bool
    let expectedVersion: Int

    enum CodingKeys: String, CodingKey {
        case readCursorSequence = "read_cursor_sequence"
        case manualUnread = "manual_unread"
        case isPinned = "is_pinned"
        case expectedVersion = "expected_version"
    }
}

/// Dokument z akt sprawy (`MobileDocument`).
struct BackendDocumentDTO: Decodable, Sendable {
    let id: String
    let caseID: String
    let name: String
    let mime: String
    let size: Int
    let folder: String
    let status: String?
    let uploadedAt: String
    let uploadedBy: String?

    enum CodingKeys: String, CodingKey {
        case id, name, mime, size, folder, status
        case caseID = "case_id"
        case uploadedAt = "uploaded_at"
        case uploadedBy = "uploaded_by"
    }
}
