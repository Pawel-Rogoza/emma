import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Repozytorium danych czytające z prawdziwego backendu
//
// Adapter produkcyjny spełniający `EmmaRepository`: ekrany nadal pracują na
// wąskich kontraktach domenowych, a tu rozstrzyga się, co da się odczytać
// z kontraktu mobilnego, a czego backend jeszcze nie udostępnia.
//
// Zasada, która rządzi całym plikiem: **nie ma danych wymyślonych**. Odczyt bez
// trasy w kontrakcie rzuca `notAvailableInBackend`, a nie zwraca pustki udającej
// „sprawdzone, nic nie ma”. Wyjątkiem są rozmowy: backend naprawdę nie prowadzi
// jeszcze wątków, więc pusty wynik jest prawdą o stanie, nie atrapą.
//
// Typ jest niezmienną strukturą (`Sendable`), więc nie potrzebuje blokad —
// nie ma współdzielonego stanu mutowalnego.

public struct BackendRepository: EmmaRepository, Sendable {

    private let api: BackendAPIClient
    /// Górny limit stron przy domykaniu stronicowania listy kontaktów.
    /// Dziesięć stron po 30 pozycji to 300 kontaktów — więcej niż kancelaria
    /// ma dzisiaj, a jednocześnie granica, która nie pozwala zapętlić się
    /// w nieskończoność, gdyby serwer zwracał sprzeczne `has_more`.
    private static let maxClientPages = 10

    /// Klucz idempotencji dla pojedynczego zamiaru zapisu.
    ///
    /// Jedno dotknięcie użytkownika = jedno żądanie, więc klucz powstaje raz
    /// na operację. Backend wymaga go zawsze i dzięki niemu powtórzone żądanie
    /// (np. ponowienie po zerwaniu) nie wykona zapisu drugi raz.
    static func newIdempotencyKey() -> String {
        UUID().uuidString.lowercased()
    }

    /// Bieżący użytkownik pochodzi z zewnątrz (sesja mobilna), a nie z danych
    /// kancelarii. Gdy go nie ma, repozytorium to zgłasza — nie podstawia konta.
    private let currentUserProvider: @Sendable () async -> User?

    public init(
        baseURL: URL,
        accessTokenProvider: @escaping @Sendable () async -> String?,
        tokenRefresher: (@Sendable () async -> String?)? = nil,
        currentUser: @escaping @Sendable () async -> User?,
        session: URLSession = .emmaAPI,
        timeout: TimeInterval = 20
    ) {
        self.api = BackendAPIClient(
            baseURL: baseURL,
            accessToken: accessTokenProvider,
            refreshToken: tokenRefresher,
            session: session,
            timeout: timeout
        )
        self.currentUserProvider = currentUser
    }

    /// Inicjalizacja dla testów i dla miejsc, które składają klienta HTTP same.
    public init(client: BackendAPIClient, currentUser: @escaping @Sendable () async -> User?) {
        self.api = client
        self.currentUserProvider = currentUser
    }

    /// Jedno miejsce, w którym powstaje błąd brakującej trasy. Nazwa operacji
    /// mówi użytkownikowi, czego dokładnie backend nie ma.
    private func notAvailable(_ operation: String) -> BackendRepositoryError {
        .notAvailableInBackend(operation)
    }

    // MARK: ClientRepository

    /// Lista kontaktów. Pobiera **wszystkie strony**, a nie tylko pierwszą.
    ///
    /// Wcześniej brana była pierwsza strona i reszta po cichu ginęła: serwer
    /// oddawał `has_more: true`, a ekran pokazywał 30 z 37 pozycji (na produkcji
    /// brakowało 7 klientów). Stronicowanie domykamy tutaj, żeby każdy ekran —
    /// lista klientów, dzień, zadania, formularze — dostał pełny zbiór.
    public func clients(matching query: String, stage: ClientStage?) async throws -> [Client] {
        var collected: [BackendClientDTO] = []
        var cursor: String?
        var pages = 0
        repeat {
            let page = try await api.clients(query: query, stage: stage, cursor: cursor)
            collected.append(contentsOf: page.items)
            // Zabezpieczenie: gdyby serwer powiedział `has_more` bez kursora,
            // kończymy, zamiast zapętlić się w nieskończoność.
            cursor = page.hasMore ? page.nextCursor : nil
            pages += 1
        } while cursor != nil && pages < Self.maxClientPages
        // Kursor jest przesunięciem: gdy między stronami dojdzie nowy lead, ten
        // sam kontakt wraca na kolejnej stronie. Duplikat identyfikatora
        // wywracał ekrany budujące słowniki po `id`, więc zostawiamy pierwszy.
        var seen = Set<String>()
        let unique = collected.filter { seen.insert($0.id).inserted }
        return try unique.map(Self.mapClient)
    }

    public func client(id: ClientID) async throws -> Client? {
        do {
            let card = try await api.clientCard(id: id)
            return try Self.mapClient(card.client)
        } catch BackendRepositoryError.notFound {
            // Protokół zwraca opcjonalny typ, więc brak klienta jest poprawnym
            // wynikiem, a nie awarią. Inne błędy (np. transport) lecą dalej.
            return nil
        }
    }

    /// Nowe zgłoszenie z aplikacji (`POST /clients`).
    ///
    /// Zakłada **leada**, nie kartotekę: backend domyślnie nadaje etap `new`,
    /// a konwersja na klienta jest osobną, świadomą decyzją (etap `client`).
    public func createClient(_ draft: NewClientDraft) async throws -> Client {
        let dto = try await api.createClient(
            displayName: draft.displayName,
            message: Self.leadMessage(topic: draft.topic, context: draft.context),
            language: draft.language.rawValue,
            source: try Self.sourceToken(draft.source),
            idempotencyKey: Self.newIdempotencyKey()
        )
        return try Self.mapClient(dto)
    }

    /// CRM trzyma w leadzie **jeden** wolny tekst zgłoszenia (`leads.message`,
    /// widoczny i przeszukiwalny w panelu). Formularz pyta o temat i kontekst
    /// osobno, więc kontekst dokładamy jako drugi akapit — bez tego to, co
    /// użytkownik napisał, przepadłoby po cichu.
    static func leadMessage(topic: String, context: String) -> String {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return topic }
        return "\(topic)\n\n\(trimmed)"
    }

    /// Źródło zgłoszenia w słowniku kontraktu.
    ///
    /// `ClientSource.referral` („Polecenie”) nie ma odpowiednika w kontrakcie,
    /// więc **nie** sprowadzamy go do `manual` (to byłoby kłamstwo w bazie) —
    /// zgłaszamy brak trasy tak samo, jak przy brakujących endpointach.
    static func sourceToken(_ source: ClientSource) throws -> String {
        switch source {
        case .manual: return "manual"
        case .webForm: return "web_form"
        case .whatsApp: return "whatsapp"
        case .referral:
            throw BackendRepositoryError.notAvailableInBackend(
                "źródło „Polecenie” (POST /clients)"
            )
        }
    }

    /// Zmiana danych kontaktu (`PATCH /clients/{client_id}`).
    ///
    /// Wysyłamy tylko pola, które faktycznie różnią się od stanu z serwera:
    /// nazwę, a gdy etap się zmienił — także etap (wejście na `client`
    /// konwertuje zgłoszenie w kartotekę po stronie backendu). Puste różnice
    /// nie lecą w ogóle, żeby zmiana nazwy nie ruszała statusu.
    public func updateClient(_ client: Client, expectedVersion: Version) async throws -> Client {
        let original = try await currentClient(client.id)
        let name = client.displayName != original.displayName ? client.displayName : nil
        let stage = client.stage != original.stage ? Self.stageToken(client.stage) : nil

        // Sama wersja różnicy nie czyni: bez zmiany pól nie ma czego zapisywać,
        // więc zwracamy stan z serwera, zamiast wysyłać pusty zapis.
        guard name != nil || stage != nil else { return original }

        let dto: BackendClientDTO
        do {
            dto = try await api.updateClient(
                id: client.id.rawValue,
                displayName: name,
                stage: stage,
                expectedVersion: expectedVersion.value,
                idempotencyKey: Self.newIdempotencyKey()
            )
        } catch let error as BackendRepositoryError {
            throw Self.writeError(error, expectedVersion: expectedVersion)
        }
        return try Self.mapClient(dto)
    }

    /// Usunięcie **zgłoszenia** (`DELETE /clients/{client_id}`).
    ///
    /// Backend przyjmuje tu wyłącznie leada. Kartoteki nie usuwamy także
    /// dlatego, że w aplikacji jest to nieodwracalne, a panel kancelarii ma
    /// wobec niej własne zasady (sprawy, terminy, dokumenty).
    public func deleteClient(_ client: Client, expectedVersion: Version) async throws {
        guard client.stage != .client else {
            throw DomainError.validationFailed(
                "Kartoteki nie usuwa się z aplikacji — usunąć można tylko zgłoszenie przed konwersją."
            )
        }
        do {
            try await api.deleteClient(
                id: client.id.rawValue,
                expectedVersion: expectedVersion.value,
                idempotencyKey: Self.newIdempotencyKey()
            )
        } catch let error as BackendRepositoryError {
            throw Self.writeError(error, expectedVersion: expectedVersion)
        }
    }

    /// Wspólne tłumaczenie błędu zapisu.
    ///
    /// `BackendRepositoryError` nie jest `DomainError`, więc bez tego ekran
    /// pokazałby bezradne „Nie udało się wykonać operacji.” — a przy konflikcie
    /// wersji użytkownik wie, co zrobić: odświeżyć i powtórzyć.
    private static func writeError(
        _ error: BackendRepositoryError,
        expectedVersion: Version
    ) -> Error {
        if case .conflict(let current, _) = error {
            return DomainError.versionConflict(
                expected: expectedVersion,
                current: current.map(Version.init) ?? expectedVersion.next()
            )
        }
        return error
    }

    static func priorityToken(_ priority: TaskPriority) -> String {
        switch priority {
        case .normal: return "normal"
        case .urgent: return "urgent"
        }
    }

    static func eventKindToken(_ kind: EventKind) -> String {
        switch kind {
        case .consultation: return "consultation"
        case .caseDeadline: return "case_deadline"
        }
    }

    static func eventStatusToken(_ status: EventStatus) -> String {
        switch status {
        case .toConfirm: return "to_confirm"
        case .confirmed: return "confirmed"
        case .finished: return "finished"
        }
    }

    /// Etap kontaktu w słowniku kontraktu (`new` / `in_contact` / `client`).
    static func stageToken(_ stage: ClientStage) -> String {
        switch stage {
        case .new: return "new"
        case .inContact: return "in_contact"
        case .client: return "client"
        }
    }

    /// Kontakt w kształcie aplikacji — potrzebny, by porównać, co się zmieniło.
    private func currentClient(_ id: ClientID) async throws -> Client {
        guard let card = try await client(id: id) else {
            throw BackendRepositoryError.notFound
        }
        return card
    }

    // MARK: CaseRepository

    public func cases(status: CaseStatus?) async throws -> [LegalCase] {
        let rows = try await api.cases(status: status)
        return try rows.map(Self.mapLegalCase)
    }

    public func legalCase(id: CaseID) async throws -> LegalCase? {
        do {
            let detail = try await api.caseDetail(id: id)
            return try Self.mapLegalCase(detail.legalCase)
        } catch BackendRepositoryError.notFound {
            return nil
        }
    }

    public func caseForClient(_ clientID: ClientID) async throws -> LegalCase? {
        do {
            let card = try await api.clientCard(id: clientID)
            return try Self.mapLegalCaseIfPresent(card.legalCase)
        } catch BackendRepositoryError.notFound {
            return nil
        }
    }

    /// `POST /cases`. Zakres sprawy backend zapisuje jako notatkę sprawy
    /// (panel nie ma takiego pola); zgłoszenie jest przy tym konwertowane.
    public func createCase(_ draft: NewCaseDraft) async throws -> LegalCase {
        let dto = try await api.createCase(
            BackendCaseCreateBody(clientID: draft.clientID.rawValue, title: draft.title, summary: draft.summary),
            idempotencyKey: Self.newIdempotencyKey()
        )
        return try Self.mapLegalCase(dto)
    }

    /// `PATCH /cases/{id}` — nazwa, status, sygnatura akt, sąd i profil sprawy. Zakresu backend nie prowadzi,
    /// więc go nie wysyłamy (formularz poza Demo go nie pokazuje).
    public func updateCase(_ legalCase: LegalCase, expectedVersion: Version, clearing: Set<CaseProfileField>) async throws -> LegalCase {
        // Pusty tekst czyści pole na serwerze (jak przy sygnaturze).
        func value(_ field: CaseProfileField, _ current: String?) -> String? {
            clearing.contains(field) ? "" : current
        }
        do {
            let dto = try await api.updateCase(
                id: legalCase.id.rawValue,
                body: BackendCaseUpdateBody(
                    expectedVersion: expectedVersion.value,
                    title: legalCase.title,
                    status: BackendAPIClient.caseStatusToken(legalCase.status),
                    signature: legalCase.courtSignature?.trimmingCharacters(in: .whitespacesAndNewlines),
                    court: legalCase.court?.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: value(.kind, legalCase.kind?.rawValue),
                    stage: value(.stage, legalCase.stage?.rawValue),
                    clientRole: value(.clientRole, legalCase.clientRole?.rawValue),
                    custodyUntil: value(.custodyUntil, legalCase.custodyUntil?.isoString),
                    legalStayUntil: value(.legalStayUntil, legalCase.legalStayUntil?.isoString)
                ),
                idempotencyKey: Self.newIdempotencyKey()
            )
            return try Self.mapLegalCase(dto)
        } catch let error as BackendRepositoryError {
            throw Self.writeError(error, expectedVersion: expectedVersion)
        }
    }

    // MARK: TaskRepository

    /// `GET /tasks/{id}`. Starszy backend tej trasy nie ma (404 bez JSON) —
    /// wtedy szukamy zadania na liście: najpierw otwartych, potem wszystkich.
    ///
    /// Do 0.2.0 ta metoda rzucała „niedostępne”: na TestFlight szczegół zadania
    /// kończył się błędem, a „Edytuj” zakładało duplikat zamiast zmienić zadanie.
    public func task(id: TaskID) async throws -> TaskItem? {
        do {
            return try Self.mapTask(try await api.task(id: id))
        } catch BackendRepositoryError.notFound {
            return nil
        } catch BackendRepositoryError.notAvailableInBackend {
            for scope in [TaskFilter.Scope.open, .all] {
                if let match = try await tasks(filter: TaskFilter(scope: scope)).first(where: { $0.id == id }) {
                    return match
                }
            }
            return nil
        }
    }

    public func tasks(filter: TaskFilter) async throws -> [TaskItem] {
        let rows = try await api.tasks(filter: filter)
        return try rows.compactMap(Self.mapTask)
    }

    public func createTask(_ draft: NewTaskDraft) async throws -> TaskItem {
        let dto = try await api.createTask(
            BackendTaskCreateBody(
                title: draft.title,
                dueDate: draft.dueDate.isoString,
                priority: Self.priorityToken(draft.priority),
                clientID: draft.clientID?.rawValue,
                caseID: draft.caseID?.rawValue
            ),
            idempotencyKey: Self.newIdempotencyKey()
        )
        return try Self.requireTask(dto)
    }

    public func updateTask(_ task: TaskItem, expectedVersion: Version) async throws -> TaskItem {
        let saved = try await patchTask(
            id: task.id,
            body: BackendTaskUpdateBody(
                expectedVersion: expectedVersion.value,
                title: task.title,
                dueDate: task.dueDate?.isoString,
                priority: Self.priorityToken(task.priority),
                isDone: task.isDone,
                clientID: .some(task.clientID?.rawValue)
            ),
            expectedVersion: expectedVersion
        )
        // Starszy backend nie przyjmuje `client_id` i po cichu go pomija —
        // wtedy mówimy wprost, zamiast pokazać „zapisano” bez tej zmiany.
        if saved.clientID != task.clientID {
            throw notAvailable("przeniesienie zadania do innego klienta — pozostałe zmiany zapisano; klienta zmień w panelu")
        }
        return saved
    }

    public func setDone(taskID: TaskID, isDone: Bool, expectedVersion: Version) async throws -> TaskItem {
        try await patchTask(
            id: taskID,
            body: BackendTaskUpdateBody(expectedVersion: expectedVersion.value, isDone: isDone),
            expectedVersion: expectedVersion
        )
    }

    private func patchTask(id: TaskID, body: BackendTaskUpdateBody, expectedVersion: Version) async throws -> TaskItem {
        do {
            let dto = try await api.updateTask(id: id.rawValue, body: body, idempotencyKey: Self.newIdempotencyKey())
            return try Self.requireTask(dto)
        } catch let error as BackendRepositoryError {
            throw Self.writeError(error, expectedVersion: expectedVersion)
        }
    }

    private static func requireTask(_ dto: BackendTaskDTO) throws -> TaskItem {
        guard let task = try mapTask(dto) else {
            throw BackendRepositoryError.decoding("zadanie bez terminu w odpowiedzi zapisu")
        }
        return task
    }

    // MARK: AgendaRepository

    public func events(in range: DateIntervalFilter) async throws -> [ScheduledEvent] {
        let rows = try await api.events(in: range)
        // Termin bez klienta jest pełnoprawnym terminem kancelarii (rozprawa,
        // spotkanie wewnętrzne) — kalendarz i przypomnienia muszą go widzieć.
        return try rows.compactMap(Self.mapEvent)
    }

    /// Terminy klienta filtrowane przez serwer (`client_id`). `GET /events`
    /// oddaje najwyżej 200 pozycji od najstarszej, więc filtr w aplikacji na
    /// liście wszystkich terminów gubił przyszłe spotkania w karcie klienta.
    public func events(in range: DateIntervalFilter, clientID: ClientID) async throws -> [ScheduledEvent] {
        let rows = try await api.events(in: range, clientID: clientID)
        return try rows.compactMap(Self.mapEvent).filter { $0.clientID == clientID }
    }

    /// `GET /events/{id}`. Starszy backend tej trasy nie ma — wtedy szukamy
    /// terminu w oknach dat (lista oddaje najwyżej 200 pozycji od najstarszej):
    /// najpierw wokół dziś, potem dalsza przeszłość i dalsza przyszłość.
    public func event(id: EventID) async throws -> ScheduledEvent? {
        do {
            return try Self.mapEvent(try await api.event(id: id))
        } catch BackendRepositoryError.notFound {
            return nil
        } catch BackendRepositoryError.notAvailableInBackend {
            let today = Self.todayInFirmTimeZone()
            let windows = [
                DateIntervalFilter(from: today.adding(days: -14), through: today.adding(days: 120)),
                DateIntervalFilter(from: today.adding(days: -400), through: today.adding(days: -15)),
                DateIntervalFilter(from: today.adding(days: 121), through: today.adding(days: 1_100))
            ]
            for window in windows {
                if let match = try await events(in: window).first(where: { $0.id == id }) {
                    return match
                }
            }
            return nil
        }
    }

    /// Dzień bieżący w strefie kancelarii. Repozytorium backendu działa tylko
    /// poza Demo, więc zegar systemowy jest tu właściwym źródłem „dziś”.
    static func todayInFirmTimeZone(now: Date = Date()) -> LocalDate {
        localDate(of: now)
    }

    public func createEvent(_ draft: NewEventDraft) async throws -> ScheduledEvent {
        let dto = try await api.createEvent(
            BackendEventCreateBody(
                title: draft.title,
                day: draft.day.isoString,
                time: draft.time.hhmm,
                durationMinutes: draft.durationMinutes,
                kind: Self.eventKindToken(draft.kind),
                clientID: draft.clientID?.rawValue,
                caseID: draft.caseID?.rawValue,
                place: draft.place.isEmpty ? nil : draft.place
            ),
            idempotencyKey: Self.newIdempotencyKey()
        )
        return try Self.requireEvent(dto)
    }

    /// Trasa `PATCH /events` zmienia stan, dzień, godzinę i długość. Tytułu
    /// i miejsca nie zmienia — gdy tylko to się różni, mówimy to wprost.
    public func updateEvent(_ event: ScheduledEvent, expectedVersion: Version) async throws -> ScheduledEvent {
        let body = BackendEventUpdateBody(
            expectedVersion: expectedVersion.value,
            status: Self.eventStatusToken(event.status),
            durationMinutes: event.durationMinutes,
            day: event.day.isoString,
            time: event.isAllDay ? nil : event.time.hhmm,
            title: event.title,
            place: event.place,
            kind: Self.eventKindToken(event.kind)
        )
        let saved: ScheduledEvent
        do {
            let dto = try await api.updateEvent(id: event.id.rawValue, body: body, idempotencyKey: Self.newIdempotencyKey())
            saved = try Self.requireEvent(dto)
        } catch let error as BackendRepositoryError {
            throw Self.writeError(error, expectedVersion: expectedVersion)
        }
        // Starszy backend przyjmował tylko stan, dzień, godzinę i długość, a resztę
        // pomijał po cichu. Rozjazd w odpowiedzi to sygnał, że zmiana nie weszła.
        if saved.title != event.title || saved.place != event.place || saved.kind != event.kind {
            throw notAvailable("zmiana nazwy, rodzaju i miejsca terminu — termin zapisano bez nich; zmień je w panelu")
        }
        // Trasa edycji nie przyjmuje klienta — zmiana klienta nie może udawać zapisu.
        if saved.clientID != event.clientID {
            throw notAvailable("zmiana klienta terminu — pozostałe zmiany zapisano; klienta zmień w panelu")
        }
        return saved
    }

    public func deleteEvent(id: EventID, expectedVersion: Version) async throws {
        do {
            try await api.deleteEvent(
                id: id.rawValue,
                expectedVersion: expectedVersion.value,
                idempotencyKey: Self.newIdempotencyKey()
            )
        } catch let error as BackendRepositoryError {
            throw Self.writeError(error, expectedVersion: expectedVersion)
        }
    }

    private static func requireEvent(_ dto: BackendEventDTO) throws -> ScheduledEvent {
        guard let event = try mapEvent(dto) else {
            throw BackendRepositoryError.decoding("termin bez klienta w odpowiedzi zapisu")
        }
        return event
    }

    // MARK: NoteRepository

    public func notes(clientID: ClientID, caseID: CaseID?) async throws -> [CaseNote] {
        // Notatki są częścią karty klienta i szczegółu sprawy — to jedyne trasy,
        // które je niosą, więc nie tworzymy osobnego zapytania „po notatki”.
        if let caseID {
            let detail = try await api.caseDetail(id: caseID)
            return try detail.notes.map(Self.mapNote)
        }
        let card = try await api.clientCard(id: clientID)
        return try card.notes.map(Self.mapNote)
    }

    public func addNote(_ draft: NewNoteDraft) async throws -> CaseNote {
        let dto = try await api.createNote(
            BackendNoteCreateBody(
                text: draft.text,
                clientID: draft.clientID.rawValue,
                caseID: draft.caseID?.rawValue,
                authorID: draft.authorID.rawValue
            ),
            idempotencyKey: Self.newIdempotencyKey()
        )
        return try Self.mapNote(dto)
    }

    // MARK: ActivityRepository

    public func activity(caseID: CaseID) async throws -> [ActivityEvent] {
        let detail = try await api.caseDetail(id: caseID)
        return try detail.activity.map(Self.mapActivity)
    }

    public func activity(clientID: ClientID) async throws -> [ActivityEvent] {
        let card = try await api.clientCard(id: clientID)
        return try card.activity.map(Self.mapActivity)
    }

    // MARK: MessagingRepository
    //
    // Rozmowy WhatsApp z backendu (numer kancelarii podłączony przez Dualhook).
    // Stan osoby w wątku (kursor, przypięcie) przychodzi razem z listą rozmów,
    // więc `readStates` nie wymaga osobnej trasy. Repozytorium jest bezstanowe:
    // wersję stanu do zapisu bierze ze świeżej listy, a nie z pamięci podręcznej,
    // która mogłaby być nieaktualna po zmianie na drugim urządzeniu.

    public func threads() async throws -> [ConversationThread] {
        try await threadList()?.items.compactMap(Self.mapThread) ?? []
    }

    public func unassignedConversations() async throws -> [UnassignedConversation] {
        let list: BackendThreadList
        do {
            list = try await api.threads(includeUnassigned: true)
        } catch BackendRepositoryError.notAvailableInBackend {
            return []
        }
        return try list.items.compactMap { dto in
            guard dto.clientID == nil else { return nil }
            let phone = dto.contactPhone ?? ""
            return UnassignedConversation(
                threadID: ThreadID(dto.id),
                name: dto.clientName ?? phone,
                phone: phone,
                preview: try dto.preview.map(Self.mapMessage)
            )
        }
    }

    public func createLead(fromThread threadID: ThreadID) async throws {
        _ = try await api.createThreadLead(threadID: threadID, idempotencyKey: Self.newIdempotencyKey())
    }

    /// Lista rozmów albo `nil`, gdy serwer kancelarii nie ma jeszcze tras
    /// `/threads` (starszy backend: 404 ze stroną HTML). Wtedy rozmów po prostu
    /// nie ma — ekran pokazuje stan pusty zamiast błędu, a karta klienta,
    /// która też czyta rozmowy, nadal się otwiera.
    private func threadList() async throws -> BackendThreadList? {
        do {
            return try await api.threads()
        } catch BackendRepositoryError.notAvailableInBackend {
            return nil
        }
    }

    public func thread(id: ThreadID) async throws -> ConversationThread? {
        try await threads().first { $0.id == id }
    }

    public func messages(threadID: ThreadID, before sequence: Int?, limit: Int) async throws -> [Message] {
        try await api.messages(threadID: threadID, beforeSequence: sequence, limit: limit)
            .items.map(Self.mapMessage)
    }

    public func latestMessages(threadID: ThreadID, limit: Int) async throws -> [Message] {
        try await api.messages(threadID: threadID, beforeSequence: nil, limit: limit)
            .items.map(Self.mapMessage)
    }

    public func appendOutgoing(_ draft: OutgoingMessageDraft) async throws -> Message {
        let dto = try await api.sendMessage(
            threadID: draft.threadID,
            body: BackendOutgoingMessageBody(
                text: draft.text,
                authorID: draft.authorID.rawValue,
                language: draft.language.rawValue
            ),
            // Klucz z wersji roboczej, nie nowy: ponowienie tego samego zamiaru
            // nie może wysłać klientowi drugiej wiadomości.
            idempotencyKey: draft.idempotencyKey
        )
        return try Self.mapMessage(dto)
    }

    public func saveReadState(_ state: ThreadUserState) async throws -> ThreadUserState {
        try await writeThreadState(state)
    }

    public func readStates(userID: UserID) async throws -> [ThreadUserState] {
        try await threadList()?.items.map { Self.mapUserState($0, userID: userID) } ?? []
    }

    public func saveThreadPreferences(_ state: ThreadUserState) async throws -> ThreadUserState {
        try await writeThreadState(state)
    }

    /// Zapis stanu osoby w wątku z wersją z serwera. Kursor nigdy nie jest
    /// cofany: gdy serwer zna już dalszy, zostawiamy serwerowy (backend i tak
    /// odrzuca cofnięcie). Konflikt wersji (drugie urządzenie) ponawiamy raz,
    /// na świeżym stanie.
    private func writeThreadState(_ state: ThreadUserState, retryOnConflict: Bool = true) async throws -> ThreadUserState {
        guard let summary = try await api.threads().items.first(where: { $0.id == state.threadID.rawValue }) else {
            throw BackendRepositoryError.notFound
        }
        let body = BackendReadStateBody(
            readCursorSequence: max(state.readCursorSequence, summary.readCursorSequence ?? 0),
            manualUnread: state.manualUnread,
            isPinned: state.isPinned,
            expectedVersion: summary.readStateVersion ?? Version.initial.value
        )
        do {
            let saved = try await api.saveReadState(
                threadID: state.threadID,
                body: body,
                idempotencyKey: Self.newIdempotencyKey()
            )
            var result = state
            result.readCursorSequence = saved.readCursorSequence
            result.manualUnread = saved.manualUnread
            result.isPinned = saved.isPinned
            return result
        } catch BackendRepositoryError.conflict where retryOnConflict {
            return try await writeThreadState(state, retryOnConflict: false)
        }
    }

    public func saveDraft(_ draft: Draft?) async throws {
        throw notAvailable("zapis szkicu wiadomości")
    }

    public func applyProviderStatus(
        providerMessageID: String,
        status: MessageTransport,
        at date: Date
    ) async throws -> Message? {
        throw notAvailable("status wiadomości od dostawcy")
    }

    public func unreadTotal(userID: UserID) async throws -> Int {
        try await threadList()?.unreadTotal ?? 0
    }

    // MARK: Mapowanie rozmów

    /// `nil` dla rozmowy bez osoby — tych nie ma na liście klientów.
    static func mapThread(_ dto: BackendThreadSummaryDTO) -> ConversationThread? {
        guard let clientID = dto.clientID else { return nil }
        return ConversationThread(
            id: ThreadID(dto.id),
            clientID: ClientID(clientID),
            sequenceHighWatermark: dto.highWatermark ?? 0
        )
    }

    static func mapUserState(_ dto: BackendThreadSummaryDTO, userID: UserID) -> ThreadUserState {
        ThreadUserState(
            userID: userID,
            threadID: ThreadID(dto.id),
            readCursorSequence: dto.readCursorSequence ?? 0,
            manualUnread: dto.manualUnread ?? false,
            isPinned: dto.isPinned ?? false
        )
    }

    static func mapMessage(_ dto: BackendMessageDTO) throws -> Message {
        guard let sentAt = MobileAuthClient.parseISO8601(dto.sentAt) else {
            throw BackendRepositoryError.decoding("nieprawidłowy czas wiadomości: \(dto.sentAt)")
        }
        let direction: MessageDirection = dto.direction == "outgoing" ? .outgoing : .incoming
        return Message(
            id: MessageID(dto.id),
            threadID: ThreadID(dto.threadID),
            direction: direction,
            authorID: dto.authorID.map { UserID($0) },
            authorLabel: dto.authorLabel,
            providerMessageID: dto.providerMessageID,
            kind: mapMessageKind(dto.kind, attachmentType: dto.attachmentType),
            text: dto.text,
            attachmentName: dto.attachmentName,
            translation: dto.translation,
            sentAt: sentAt,
            sequence: dto.sequence,
            transport: mapTransport(dto.transport),
            source: mapMessageSource(origin: dto.origin, source: dto.source, direction: direction),
            version: Version(dto.version)
        )
    }

    static func mapMessageKind(_ kind: String, attachmentType: String?) -> MessageKind {
        switch kind {
        case "system":
            return .system
        case "attachment":
            switch attachmentType {
            case "image": return .image
            case "video": return .video
            case "audio": return .audio
            case "sticker": return .sticker
            case "location": return .location
            default: return .document
            }
        default:
            return .text
        }
    }

    /// Tokeny transportu z kontraktu (`snake_case`) → stan w aplikacji.
    /// Nieznany token to brak wiedzy, a nie sukces — stąd `.unknown`.
    static func mapTransport(_ raw: String) -> MessageTransport {
        switch raw {
        case "local_draft": return .localDraft
        case "pending": return .pending
        case "sending": return .sending
        case "accepted": return .accepted
        case "sent": return .sent
        case "delivered": return .delivered
        case "read": return .read
        case "failed": return .failed
        default: return .unknown
        }
    }

    /// Pochodzenie wiadomości. Echo z aplikacji WhatsApp Business (telefon
    /// kancelarii) ma własne źródło, bo nie ma znanego autora w Emmie.
    static func mapMessageSource(origin: String?, source: String, direction: MessageDirection) -> MessageSource {
        switch origin {
        case "customer":
            return .whatsAppInbound
        case "business_app":
            return .whatsAppBusinessEcho
        case "history":
            return direction == .incoming ? .whatsAppInbound : .whatsAppBusinessEcho
        default:
            if source == "app" { return .app }
            if source == "voice_action" { return .appVoice }
            return direction == .incoming ? .whatsAppInbound : .whatsAppBusinessEcho
        }
    }

    // MARK: UserRepository

    public func currentUser() async throws -> User {
        guard let user = await currentUserProvider() else {
            // Brak zalogowanego użytkownika to brak sesji, a nie „użytkownik domyślny”.
            throw BackendRepositoryError.unauthorized
        }
        return user
    }

    public func updatePreferences(_ user: User) async throws -> User {
        throw notAvailable("zmiana preferencji użytkownika")
    }

    // MARK: VoiceSessionRepository (M4)

    public func create(_ request: CreateVoiceSession) async throws -> VoiceSessionConfiguration {
        throw notAvailable("tworzenie sesji głosowej (M4)")
    }

    public func updateContext(_ request: UpdateVoiceContext) async throws -> AssistantContext {
        throw notAvailable("aktualizacja kontekstu Emmy (M4)")
    }

    public func fetchStatus(sessionID: VoiceSessionID) async throws -> VoiceSessionStatus {
        throw notAvailable("odczyt stanu sesji głosowej (M4)")
    }

    public func end(sessionID: VoiceSessionID) async throws {
        throw notAvailable("zakończenie sesji głosowej (M4)")
    }

    // MARK: AssistantActionRepository (M5)

    //
    // Kontrakt `/actions`: propozycja → zgoda (nagłówek `X-Emma-Consent`) →
    // wykonanie. Termin zadania i odbiorcę propozycji backend zmienia wyłącznie
    // przez nową propozycję, więc `reschedule`/`changeContext` przygotowują ją
    // od nowa i anulują poprzednią — zgoda na starą treść nie przechodzi.

    public func prepare(_ request: PrepareAction) async throws -> ActionProposal {
        let prepared = request.request
        let dto = try await api.prepareAction(
            BackendActionPrepareBody(
                kind: prepared.kind.rawValue,
                text: prepared.text,
                origin: prepared.sessionID == nil ? "ui" : "voice",
                actorUserID: prepared.actorUserID.rawValue,
                taskDueDate: prepared.kind == .task ? prepared.taskDueDate?.isoString : nil,
                context: BackendActionContextBody(
                    scope: Self.actionScope(clientID: prepared.clientID, caseID: prepared.caseID, threadID: prepared.threadID),
                    version: max(prepared.contextVersion.value, 1),
                    clientID: prepared.clientID?.rawValue,
                    caseID: prepared.caseID?.rawValue,
                    threadID: prepared.threadID?.rawValue
                )
            ),
            idempotencyKey: Self.newIdempotencyKey()
        )
        return try Self.mapProposal(dto, sessionID: prepared.sessionID, taskDueDate: prepared.taskDueDate)
    }

    public func revise(_ request: ReviseAction) async throws -> ActionProposal {
        do {
            let dto = try await api.reviseAction(
                id: request.actionID.rawValue,
                text: request.newText,
                expectedVersion: request.expectedVersion.value,
                idempotencyKey: Self.newIdempotencyKey()
            )
            return try Self.mapProposal(dto, sessionID: nil, taskDueDate: nil)
        } catch let error as BackendRepositoryError {
            throw Self.writeError(error, expectedVersion: request.expectedVersion)
        }
    }

    public func reschedule(_ request: RescheduleAction) async throws -> ActionProposal {
        throw notAvailable("zmiana terminu w przygotowanej propozycji — anuluj ją i poproś o nową z właściwą datą")
    }

    public func changeContext(_ request: ChangeActionContext) async throws -> ActionProposal {
        throw notAvailable("zmiana odbiorcy w przygotowanej propozycji — anuluj ją i poproś o nową dla właściwej osoby")
    }

    public func confirm(_ request: ConfirmAction) async throws -> ActionExecution {
        let confirmation = request.confirmation
        let consent: String
        switch confirmation.origin {
        case .directUIButton: consent = "direct_ui_button"
        case .authenticatedVoiceTurn: consent = "authenticated_voice_turn"
        case .languageModelArgument:
            // Zgoda „od modelu” nie istnieje. Nie wysyłamy nawet żądania.
            throw DomainError.validationFailed("Zgodę daje użytkownik przyciskiem, nie model językowy.")
        }
        do {
            let dto = try await api.confirmAction(
                id: confirmation.actionID.rawValue,
                body: BackendActionConfirmBody(
                    presentationID: confirmation.presentationID,
                    expectedContextVersion: confirmation.expectedVersion.value,
                    voiceSessionID: nil
                ),
                consent: consent,
                idempotencyKey: request.idempotencyKey
            )
            return Self.mapExecution(dto, proposalVersion: confirmation.expectedVersion)
        } catch let error as BackendRepositoryError {
            throw Self.writeError(error, expectedVersion: confirmation.expectedVersion)
        }
    }

    public func cancel(_ request: CancelAction) async throws -> ActionExecution {
        let dto = try await api.cancelAction(id: request.actionID.rawValue, idempotencyKey: Self.newIdempotencyKey())
        // Anulowanie nie ma wykonania; kontrakt protokołu wymaga go jednak jako
        // wyniku, więc zwracamy stan „nieudane” bez identyfikatora kolejki.
        return ActionExecution(
            actionID: ActionID(dto.id),
            proposalVersion: Version(dto.contextVersion),
            state: .failed,
            outboxID: "",
            updatedAt: MobileAuthClient.parseISO8601(dto.presentedAt) ?? Date(),
            lastErrorCode: "cancelled"
        )
    }

    public func status(actionID: ActionID) async throws -> ActionExecution {
        let dto = try await api.actionExecution(id: actionID.rawValue)
        return Self.mapExecution(dto, proposalVersion: .initial)
    }

    static func actionScope(clientID: ClientID?, caseID: CaseID?, threadID: ThreadID?) -> String {
        if threadID != nil { return "thread" }
        if caseID != nil { return "legal_case" }
        if clientID != nil { return "client" }
        return "firm"
    }

    static func mapProposal(
        _ dto: BackendActionDTO,
        sessionID: VoiceSessionID?,
        taskDueDate: LocalDate?
    ) throws -> ActionProposal {
        guard let kind = ActionKind(rawValue: dto.kind) else {
            throw BackendRepositoryError.decoding("nieznany rodzaj akcji: \(dto.kind)")
        }
        guard let presentedAt = MobileAuthClient.parseISO8601(dto.presentedAt),
              let expiresAt = MobileAuthClient.parseISO8601(dto.expiresAt) else {
            throw BackendRepositoryError.decoding("nieznany format czasu propozycji")
        }
        let state: ProposalState
        switch dto.state {
        case "proposed", "revised": state = .proposed
        case "confirmed": state = .confirmed
        case "cancelled": state = .rejected
        case "expired": state = .expired
        default: throw BackendRepositoryError.decoding("nieznany stan propozycji: \(dto.state)")
        }
        return ActionProposal(
            id: ActionID(dto.id),
            kind: kind,
            version: Version(dto.contextVersion),
            actorUserID: UserID(dto.actorUserID),
            sessionID: sessionID,
            clientID: dto.clientID.map { ClientID($0) },
            caseID: dto.caseID.map { CaseID($0) },
            threadID: dto.threadID.map { ThreadID($0) },
            text: dto.text,
            payloadHash: dto.payloadHash,
            contextVersion: Version(dto.contextVersion),
            presentedAt: presentedAt,
            expiresAt: expiresAt,
            presentationID: dto.presentationID,
            state: state,
            taskDueDate: taskDueDate
        )
    }

    static func mapExecution(_ dto: BackendActionExecutionDTO, proposalVersion: Version) -> ActionExecution {
        ActionExecution(
            actionID: ActionID(dto.actionID),
            proposalVersion: proposalVersion,
            // Stan spoza słownika to niepewność, nie sukces.
            state: ExecutionState(rawValue: dto.state) ?? .unknown,
            outboxID: dto.outboxID,
            providerMessageID: dto.providerMessageID,
            updatedAt: MobileAuthClient.parseISO8601(dto.updatedAt) ?? Date(),
            lastErrorCode: dto.failureCode
        )
    }
}

// MARK: - Mapowanie kontraktu na modele aplikacji
//
// Mapowania są statyczne i rzucają błąd przy wartości spoza kontraktu. Cicha
// wartość domyślna byłaby tu najgorszym wyborem: użytkownik zobaczyłby etap
// „Nowy” albo priorytet „Zwykłe” dla danych, których wcale tak nie opisano.

extension BackendRepository {

    static func mapClient(_ dto: BackendClientDTO) throws -> Client {
        Client(
            id: ClientID(dto.id),
            displayName: dto.displayName,
            initials: dto.initials,
            // Kontrakt dopuszcza wartości, których `LanguageCode` nie zna;
            // wtedy zostaje polski jako język kancelarii, a nie pusty kod.
            language: LanguageCode(lenient: dto.language) ?? .pl,
            topic: dto.topic,
            stage: try mapStage(dto.stage),
            source: try mapSource(dto.source),
            createdAt: dto.createdAt,
            // Model aplikacji nie ma opcjonalnego briefingu, więc `null` to pusty
            // tekst — brak treści, a nie brak pola.
            briefing: dto.briefing ?? "",
            incomingMessage: dto.incomingMessage,
            incomingTranslation: dto.incomingTranslation,
            incomingTime: try mapTime(dto.incomingTime),
            needsReply: dto.needsReply,
            // Znacznik spoza formatu ISO nie zatrzymuje listy: zgłoszenie
            // zostaje, a wiek liczymy wtedy z samej daty (`LeadWorkflow`).
            receivedAt: dto.receivedAt.flatMap(MobileAuthClient.parseISO8601),
            phone: nonEmpty(dto.phone),
            email: nonEmpty(dto.email),
            version: Version(dto.version)
        )
    }

    /// Pusty napis z backendu to brak danych, nie „numer” do wybrania.
    static func nonEmpty(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func mapStage(_ raw: String) throws -> ClientStage {
        switch raw {
        case "new": return .new
        case "in_contact": return .inContact
        case "client": return .client
        default: throw BackendRepositoryError.decoding("nieznany etap klienta: \(raw)")
        }
    }

    static func mapSource(_ raw: String) throws -> ClientSource {
        switch raw {
        case "web_form": return .webForm
        case "whatsapp": return .whatsApp
        case "manual": return .manual
        // Świadome uproszczenie: kontrakt zna `import`, którego aplikacja nie
        // rozróżnia — nie ma osobnego przypadku, więc sprowadzamy go do `.manual`.
        case "import": return .manual
        default: throw BackendRepositoryError.decoding("nieznane źródło klienta: \(raw)")
        }
    }

    static func mapLegalCase(_ dto: BackendLegalCaseDTO) throws -> LegalCase {
        LegalCase(
            id: CaseID(dto.id),
            number: dto.number,
            title: dto.title,
            clientID: ClientID(dto.clientID),
            status: try mapCaseStatus(dto.status),
            summary: dto.summary ?? "",
            createdAt: dto.createdAt,
            version: Version(dto.version),
            courtSignature: dto.signature,
            court: dto.court,
            // Nieznany token (nowszy serwer) to brak wiedzy, nie błąd sprawy.
            kind: dto.kind.flatMap(CaseKind.init(rawValue:)),
            stage: dto.stage.flatMap(CaseStage.init(rawValue:)),
            clientRole: dto.clientRole.flatMap(ClientRole.init(rawValue:)),
            custodyUntil: dto.custodyUntil.flatMap(LocalDate.init(iso:)),
            legalStayUntil: dto.legalStayUntil.flatMap(LocalDate.init(iso:))
        )
    }

    static func mapLegalCaseIfPresent(_ dto: BackendLegalCaseDTO?) throws -> LegalCase? {
        guard let dto else { return nil }
        return try mapLegalCase(dto)
    }

    static func mapCaseStatus(_ raw: String) throws -> CaseStatus {
        switch raw {
        case "in_progress": return .inProgress
        case "awaiting_client": return .awaitingClient
        case "closed": return .closed
        default: throw BackendRepositoryError.decoding("nieznany status sprawy: \(raw)")
        }
    }

    static func mapTask(_ dto: BackendTaskDTO) throws -> TaskItem? {
        // Panel kancelarii dopuszcza zadania bez terminu (na produkcji 3 z 10).
        // Wcześniej takie zadanie znikało z aplikacji; teraz trafia do grupy
        // „Bez terminu” — bez daty zastępczej, która udawałaby „po terminie”.
        let rawDue = dto.dueDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dueDate: LocalDate?
        if rawDue.isEmpty {
            dueDate = nil
        } else {
            guard let parsed = LocalDate(iso: rawDue) else {
                throw BackendRepositoryError.decoding("nieznana data zadania: \(rawDue)")
            }
            dueDate = parsed
        }
        return TaskItem(
            id: TaskID(dto.id),
            title: dto.title,
            clientID: dto.clientID.map { ClientID($0) },
            caseID: dto.caseID.map { CaseID($0) },
            dueDate: dueDate,
            isDone: dto.isDone,
            priority: try mapPriority(dto.priority),
            version: Version(dto.version)
        )
    }

    static func mapPriority(_ raw: String) throws -> TaskPriority {
        switch raw {
        case "urgent": return .urgent
        case "normal": return .normal
        default: throw BackendRepositoryError.decoding("nieznany priorytet zadania: \(raw)")
        }
    }

    /// Termin z backendu. `nil` znaczy „terminu nie da się przypisać do klienta”
    /// — kontrakt wymaga `client_id`, ale baza kancelarii dopuszcza terminy bez
    /// kartoteki. Zwracamy wtedy `nil` zamiast rzucać, bo jeden taki termin nie
    /// jest powodem, by gasnąć cały ekran.
    static func mapEvent(_ dto: BackendEventDTO) throws -> ScheduledEvent? {
        let clientID = dto.clientID.flatMap { $0.isEmpty ? nil : ClientID($0) }
        return ScheduledEvent(
            id: EventID(dto.id),
            clientID: clientID,
            caseID: dto.caseID.map { CaseID($0) },
            title: dto.title,
            day: dto.day,
            time: try mapEventTime(dto.time),
            durationMinutes: dto.durationMinutes,
            kind: try mapEventKind(dto.kind),
            status: try mapEventStatus(dto.status),
            place: dto.place ?? "",
            isAllDay: dto.allDay,
            version: Version(dto.version)
        )
    }

    static func mapEventTime(_ raw: String?) throws -> TimeOfDay {
        guard let raw, !raw.isEmpty else {
            // Termin całodniowy nie ma godziny. Model aplikacji nie zna jeszcze
            // terminu bez godziny, więc zostaje północ **jako brak godziny**,
            // a prawdę niesie `isAllDay`. Ograniczenie: dopóki widoki nie
            // obsłużą `isAllDay`, taki termin pokaże się z godziną 00:00.
            return TimeOfDay(minutes: 0)!
        }
        guard let value = TimeOfDay(hhmm: raw) else {
            throw BackendRepositoryError.decoding("nieznana godzina terminu: \(raw)")
        }
        return value
    }

    /// Słownik **kontraktu**, nie CRM: `consultation` / `case_deadline`.
    /// Backend mapuje swoje cztery rodzaje na te dwie wartości, więc aplikacja
    /// nie musi znać `hearing` ani `meeting`.
    static func mapEventKind(_ raw: String) throws -> EventKind {
        switch raw {
        case "case_deadline": return .caseDeadline
        case "consultation": return .consultation
        default: throw BackendRepositoryError.decoding("nieznany rodzaj terminu: \(raw)")
        }
    }

    /// Stan terminu: CRM go nie prowadzi i wysyła `to_confirm`, ale gdy panel
    /// zacznie zapisywać stan, aplikacja odczyta go bez zmiany.
    static func mapEventStatus(_ raw: String) throws -> EventStatus {
        switch raw {
        case "to_confirm": return .toConfirm
        case "confirmed": return .confirmed
        case "finished": return .finished
        default: throw BackendRepositoryError.decoding("nieznany status terminu: \(raw)")
        }
    }

    static func mapNote(_ dto: BackendNoteDTO) throws -> CaseNote {
        CaseNote(
            id: NoteID(dto.id),
            clientID: ClientID(dto.clientID),
            caseID: dto.caseID.map { CaseID($0) },
            text: dto.text,
            authorID: UserID(dto.authorID),
            createdAt: try mapLocalDate(fromISO: dto.createdAt),
            version: Version(dto.version)
        )
    }

    static func mapActivity(_ dto: BackendActivityDTO) throws -> ActivityEvent {
        ActivityEvent(
            id: ActivityID(dto.id),
            text: dto.text,
            clientID: dto.clientID.map { ClientID($0) },
            caseID: dto.caseID.map { CaseID($0) },
            createdAt: try mapLocalDate(fromISO: dto.createdAt),
            authorID: UserID(dto.authorID)
        )
    }

    /// Backend wysyła pełny znacznik ISO w UTC (`2026-09-13T12:00:00.000Z`),
    /// a model aplikacji trzyma sam dzień **w strefie kancelarii**.
    ///
    /// Samo obcięcie do 10 znaków brało dzień UTC: notatka zapisana w Warszawie
    /// 13 września o 0:30 (22:30Z dnia poprzedniego) pokazywała się jako 12
    /// września. Pełny znacznik przeliczamy więc na `Europe/Warsaw`; sama data
    /// (`YYYY-MM-DD`) jest już dniem lokalnym i nie wymaga przeliczenia.
    static func mapLocalDate(fromISO raw: String) throws -> LocalDate {
        if raw.count > 10, let instant = MobileAuthClient.parseISO8601(raw) {
            return localDate(of: instant)
        }
        guard let value = LocalDate(iso: String(raw.prefix(10))) else {
            throw BackendRepositoryError.decoding("nieznana data ISO: \(raw)")
        }
        return value
    }

    private static func localDate(of instant: Date) -> LocalDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: EmmaTime.referenceTimeZone) ?? .gmt
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        return LocalDate(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    static func mapTime(_ raw: String?) throws -> TimeOfDay? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let value = TimeOfDay(hhmm: raw) else {
            throw BackendRepositoryError.decoding("nieznana godzina: \(raw)")
        }
        return value
    }
}

// MARK: - Akta sprawy

extension BackendRepository: CaseDocumentsRepository {

    public func caseDocuments(caseID: CaseID) async throws -> [CaseDocument] {
        try await api.caseDocuments(caseID: caseID).map(Self.document(from:))
    }

    public func uploadCaseDocument(
        caseID: CaseID,
        fileName: String,
        mime: String,
        data: Data,
        folder: CaseDocumentFolder
    ) async throws -> CaseDocument {
        var form = MultipartForm()
        form.addField("folder", folder.rawValue)
        form.addFile("files", fileName: fileName, mime: mime, data: data)
        guard let saved = try await api.uploadCaseDocument(caseID: caseID, form: form).first else {
            throw BackendRepositoryError.decoding("serwer nie odesłał zapisanego dokumentu")
        }
        return try Self.document(from: saved)
    }

    public func documentData(id: String) async throws -> Data {
        try await api.documentData(id: id)
    }

    static func document(from dto: BackendDocumentDTO) throws -> CaseDocument {
        guard let uploadedAt = MobileAuthClient.parseISO8601(dto.uploadedAt) else {
            throw BackendRepositoryError.decoding("nieprawidłowa data dokumentu: \(dto.uploadedAt)")
        }
        return CaseDocument(
            id: dto.id,
            caseID: CaseID(dto.caseID),
            name: dto.name,
            mime: dto.mime,
            size: dto.size,
            folder: dto.folder,
            status: dto.status,
            uploadedAt: uploadedAt,
            uploadedBy: dto.uploadedBy
        )
    }
}

