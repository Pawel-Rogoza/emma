import Foundation

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
    /// Bieżący użytkownik pochodzi z zewnątrz (sesja mobilna), a nie z danych
    /// kancelarii. Gdy go nie ma, repozytorium to zgłasza — nie podstawia konta.
    private let currentUserProvider: @Sendable () async -> User?

    public init(
        baseURL: URL,
        accessTokenProvider: @escaping @Sendable () async -> String?,
        currentUser: @escaping @Sendable () async -> User?,
        session: URLSession = .shared,
        timeout: TimeInterval = 20
    ) {
        self.api = BackendAPIClient(
            baseURL: baseURL,
            accessToken: accessTokenProvider,
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

    public func clients(matching query: String, stage: ClientStage?) async throws -> [Client] {
        let page = try await api.clients(query: query, stage: stage)
        return try page.items.map(Self.mapClient)
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

    public func createClient(_ draft: NewClientDraft) async throws -> Client {
        throw notAvailable("tworzenie klienta (POST /clients)")
    }

    public func updateClient(_ client: Client, expectedVersion: Version) async throws -> Client {
        throw notAvailable("zmiana danych klienta (PATCH /clients/{client_id})")
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

    public func createCase(_ draft: NewCaseDraft) async throws -> LegalCase {
        throw notAvailable("rozpoczęcie sprawy (POST /cases)")
    }

    public func updateCase(_ legalCase: LegalCase, expectedVersion: Version) async throws -> LegalCase {
        throw notAvailable("zmiana sprawy (PATCH /cases/{case_id})")
    }

    // MARK: TaskRepository

    public func task(id: TaskID) async throws -> TaskItem? {
        // Kontrakt nie ma trasy pojedynczego zadania. Szczegół jest w karcie
        // klienta lub sprawy, ale to inny zasób niż zapytanie po identyfikatorze.
        throw notAvailable("odczyt zadania po identyfikatorze")
    }

    public func tasks(filter: TaskFilter) async throws -> [TaskItem] {
        let rows = try await api.tasks(filter: filter)
        return try rows.compactMap(Self.mapTask)
    }

    public func createTask(_ draft: NewTaskDraft) async throws -> TaskItem {
        throw notAvailable("tworzenie zadania (POST /tasks)")
    }

    public func updateTask(_ task: TaskItem, expectedVersion: Version) async throws -> TaskItem {
        throw notAvailable("zmiana zadania (PATCH /tasks/{task_id})")
    }

    public func setDone(taskID: TaskID, isDone: Bool, expectedVersion: Version) async throws -> TaskItem {
        throw notAvailable("odhaczenie zadania (PATCH /tasks/{task_id})")
    }

    // MARK: AgendaRepository

    public func events(in range: DateIntervalFilter) async throws -> [ScheduledEvent] {
        let rows = try await api.events(in: range)
        return try rows.map(Self.mapEvent)
    }

    public func event(id: EventID) async throws -> ScheduledEvent? {
        throw notAvailable("odczyt terminu po identyfikatorze")
    }

    public func createEvent(_ draft: NewEventDraft) async throws -> ScheduledEvent {
        throw notAvailable("tworzenie terminu (POST /events)")
    }

    public func updateEvent(_ event: ScheduledEvent, expectedVersion: Version) async throws -> ScheduledEvent {
        throw notAvailable("zmiana terminu (PATCH /events/{event_id})")
    }

    public func deleteEvent(id: EventID, expectedVersion: Version) async throws {
        throw notAvailable("usunięcie terminu (DELETE /events/{event_id})")
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
        throw notAvailable("dodanie notatki (POST /notes)")
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
    // Backend naprawdę nie prowadzi jeszcze wątków, więc odczyty zwracają pusty
    // wynik. To prawda o stanie, nie atrapa — udawany wątek byłby danymi wymyślonymi.
    // Zapisy rzucają, bo nie ma gdzie ich zapisać.

    public func threads() async throws -> [ConversationThread] { [] }

    public func thread(id: ThreadID) async throws -> ConversationThread? { nil }

    public func messages(threadID: ThreadID, before sequence: Int?, limit: Int) async throws -> [Message] { [] }

    public func latestMessages(threadID: ThreadID, limit: Int) async throws -> [Message] { [] }

    public func appendOutgoing(_ draft: OutgoingMessageDraft) async throws -> Message {
        throw notAvailable("wysyłka wiadomości (POST /threads/{thread_id}/messages)")
    }

    public func saveReadState(_ state: ThreadUserState) async throws -> ThreadUserState {
        throw notAvailable("zapis kursora odczytu (PUT /threads/{thread_id}/read-state)")
    }

    public func readStates(userID: UserID) async throws -> [ThreadUserState] { [] }

    public func saveThreadPreferences(_ state: ThreadUserState) async throws -> ThreadUserState {
        throw notAvailable("zapis preferencji wątku")
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

    public func unreadTotal(userID: UserID) async throws -> Int { 0 }

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

    public func prepare(_ request: PrepareAction) async throws -> ActionProposal {
        throw notAvailable("przygotowanie akcji asystenta (M5)")
    }

    public func revise(_ request: ReviseAction) async throws -> ActionProposal {
        throw notAvailable("korekta akcji asystenta (M5)")
    }

    public func reschedule(_ request: RescheduleAction) async throws -> ActionProposal {
        throw notAvailable("zmiana terminu akcji asystenta (M5)")
    }

    public func changeContext(_ request: ChangeActionContext) async throws -> ActionProposal {
        throw notAvailable("zmiana kontekstu akcji asystenta (M5)")
    }

    public func confirm(_ request: ConfirmAction) async throws -> ActionExecution {
        throw notAvailable("potwierdzenie akcji asystenta (M5)")
    }

    public func cancel(_ request: CancelAction) async throws -> ActionExecution {
        throw notAvailable("anulowanie akcji asystenta (M5)")
    }

    public func status(actionID: ActionID) async throws -> ActionExecution {
        throw notAvailable("odczyt wykonania akcji asystenta (M5)")
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
            version: Version(dto.version)
        )
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
            version: Version(dto.version)
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
        let rawDue = dto.dueDate?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawDue, !rawDue.isEmpty else {
            // Kontrakt nie wysyła zadań bez terminu. Gdyby jednak przyszło puste
            // `due_date`, pomijamy wiersz: data zastępcza pokazałaby w interfejsie
            // „po terminie”, czyli nieprawdę.
            return nil
        }
        guard let dueDate = LocalDate(iso: rawDue) else {
            throw BackendRepositoryError.decoding("nieznana data zadania: \(rawDue)")
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

    static func mapEvent(_ dto: BackendEventDTO) throws -> ScheduledEvent {
        ScheduledEvent(
            id: EventID(dto.id),
            clientID: ClientID(dto.clientID),
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

    /// Backend wysyła pełny znacznik ISO (`2026-09-13T12:00:00.000Z`), a model
    /// aplikacji trzyma sam dzień. Bierzemy pierwsze 10 znaków, bo godzina
    /// i strefa nie mają reprezentacji w `LocalDate`.
    static func mapLocalDate(fromISO raw: String) throws -> LocalDate {
        let day = String(raw.prefix(10))
        guard let value = LocalDate(iso: day) else {
            throw BackendRepositoryError.decoding("nieznana data ISO: \(raw)")
        }
        return value
    }

    static func mapTime(_ raw: String?) throws -> TimeOfDay? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let value = TimeOfDay(hhmm: raw) else {
            throw BackendRepositoryError.decoding("nieznana godzina: \(raw)")
        }
        return value
    }
}
