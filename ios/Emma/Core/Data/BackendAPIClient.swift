import Foundation

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
    private let timeout: TimeInterval

    public init(
        baseURL: URL,
        accessToken: @escaping @Sendable () async -> String?,
        session: URLSession = .shared,
        timeout: TimeInterval = 20
    ) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.session = session
        self.timeout = timeout
    }

    // MARK: Odczyt zgodny z kontraktem

    /// `GET /api/mobile/v1/clients?query=&stage=&limit=`.
    func clients(query: String, stage: ClientStage?, limit: Int = Self.defaultPageLimit) async throws -> BackendClientPage {
        var items: [URLQueryItem] = []
        if !query.isEmpty {
            items.append(URLQueryItem(name: "query", value: query))
        }
        if let stage {
            items.append(URLQueryItem(name: "stage", value: Self.stageToken(stage)))
        }
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        return try await get(Endpoint.clients.rawValue, query: items)
    }

    /// `GET /api/mobile/v1/clients/{client_id}` — karta klienta z kontekstem.
    func clientCard(id: ClientID) async throws -> BackendClientCard {
        try await get("\(Endpoint.clients.rawValue)/\(id.rawValue)", query: [])
    }

    /// `GET /api/mobile/v1/cases/{case_id}` — sprawa z zadania i historią.
    func caseDetail(id: CaseID) async throws -> BackendCaseDetail {
        try await get("\(Endpoint.cases.rawValue)/\(id.rawValue)", query: [])
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

    /// `GET /api/mobile/v1/events?from=&through=`.
    func events(in range: DateIntervalFilter) async throws -> [BackendEventDTO] {
        let items = [
            URLQueryItem(name: "from", value: range.from.isoString),
            URLQueryItem(name: "through", value: range.through.isoString)
        ]
        let response: BackendItems<BackendEventDTO> = try await get(Endpoint.events.rawValue, query: items)
        return response.items
    }

    // MARK: Żądanie i odpowiedź

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        let token = await accessToken()
        let request = try makeRequest(path: path, query: query, token: token)
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendRepositoryError.transport("nieprawidłowa odpowiedź serwera")
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
        token: String?
    ) throws -> URLRequest {
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
        return request
    }

    /// Zapis z odpowiedzią JSON. `Idempotency-Key` jest wymagany przez kontrakt,
    /// więc wywołanie bez niego jest błędem programisty, a nie użytkownika.
    private func send<B: Encodable, T: Decodable>(
        _ method: String,
        path: String,
        body: B,
        idempotencyKey: String
    ) async throws -> T {
        let token = await accessToken()
        let encoded: Data
        do {
            encoded = try Self.encoder.encode(body)
        } catch {
            throw BackendRepositoryError.decoding("nie udało się zapisać treści żądania: \(error)")
        }
        let request = try makeRequest(
            path: path,
            method: method,
            body: encoded,
            idempotencyKey: idempotencyKey,
            token: token
        )
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendRepositoryError.transport("nieprawidłowa odpowiedź serwera")
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

    /// Zapis bez treści oczekiwanej w odpowiedzi (204).
    private func sendNoContent(
        _ method: String,
        path: String,
        idempotencyKey: String
    ) async throws {
        let token = await accessToken()
        let request = try makeRequest(
            path: path,
            method: method,
            idempotencyKey: idempotencyKey,
            token: token
        )
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendRepositoryError.transport("nieprawidłowa odpowiedź serwera")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: http, data: data)
        }
    }

    /// Koder tworzymy na każde wywołanie — jak dekoder, żeby nie współdzielić
    /// instancji, która nie jest `Sendable`.
    static var encoder: JSONEncoder { JSONEncoder() }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            // Anulowanie to nasza decyzja, nie awaria sieci — nie zamieniamy jej
            // na błąd transportu, bo zadanie i tak jest już porzucone.
            if error.code == .cancelled { throw CancellationError() }
            throw BackendRepositoryError.transport(error.localizedDescription)
        } catch {
            throw BackendRepositoryError.transport(error.localizedDescription)
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
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id, initials, language, topic, stage, source, briefing, version
        case displayName = "display_name"
        case createdAt = "created_at"
        case incomingMessage = "incoming_message"
        case incomingTranslation = "incoming_translation"
        case incomingTime = "incoming_time"
        case needsReply = "needs_reply"
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

    enum CodingKeys: String, CodingKey {
        case id, number, title, status, summary, version
        case clientID = "client_id"
        case createdAt = "created_at"
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
    let clientID: String
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
