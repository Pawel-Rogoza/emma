import Foundation

// MARK: - MockRepository
//
// Jedno źródło danych demo dla wszystkich ekranów (§etap 03: „na jednym MockRepository,
// a nie oddzielnych tablicach w każdym widoku”). Zachowuje reguły domenowe, walidację
// wersji i idempotencję, więc M1 sprawdza te same kontrakty, których użyje live.

public actor MockRepository:
    EmmaRepository,
    DemoFixtureRepository
{

    private var dataset: DemoFixtures.Dataset
    private let clock: Clock
    /// Sztuczne opóźnienie odpowiedzi, aby stany ładowania były widoczne w UI.
    /// W testach ustawiane na 0, co daje w pełni deterministyczne zachowanie.
    private let artificialLatency: TimeInterval
    private var idSequence = 900
    private var actionState = ActionEngine.State()
    private let actionEngine = ActionEngine()
    private var idempotencyIndex: [String: MessageID] = [:]
    private var voiceSessions: [VoiceSessionID: VoiceSessionStatus] = [:]

    public init(
        dataset: DemoFixtures.Dataset = DemoFixtures.dataset(),
        clock: Clock = DemoClock(),
        artificialLatency: TimeInterval = 0
    ) {
        self.dataset = dataset
        self.clock = clock
        self.artificialLatency = artificialLatency
    }

    private func nextID(_ prefix: String) -> String {
        idSequence += 1
        return "\(prefix)-\(idSequence)"
    }

    private func pause() async {
        guard artificialLatency > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(artificialLatency * 1_000_000_000))
    }

    /// Pełny zrzut danych demo — używany przez testy i przez ekran diagnostyczny.
    public func snapshot() -> DemoFixtures.Dataset { dataset }

    public func reset() {
        dataset = DemoFixtures.dataset()
        idSequence = 900
        actionState = ActionEngine.State()
        idempotencyIndex.removeAll()
        voiceSessions.removeAll()
    }

    // MARK: - Użytkownicy

    public func currentUser() async throws -> User {
        // Jedno wspólne konto kancelarii — nie ma już wyboru zalogowanej osoby.
        dataset.user
    }

    public func updatePreferences(_ user: User) async throws -> User {
        guard let index = dataset.users.firstIndex(where: { $0.id == user.id }) else {
            throw DomainError.notFound(resource: "user", id: user.id.rawValue)
        }
        dataset.users[index] = user
        return user
    }

    // MARK: - Klienci

    public func clients(matching query: String, stage: ClientStage?) async throws -> [Client] {
        await pause()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return dataset.clients.filter { client in
            if let stage, client.stage != stage { return false }
            guard !needle.isEmpty else { return true }
            return client.displayName.lowercased().contains(needle)
                || client.topic.lowercased().contains(needle)
        }
    }

    public func client(id: ClientID) async throws -> Client? {
        await pause()
        return dataset.clients.first { $0.id == id }
    }

    public func createClient(_ draft: NewClientDraft) async throws -> Client {
        await pause()
        let name = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw DomainError.validationFailed("Uzupełnij imię i nazwisko.")
        }
        let topic = draft.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else {
            throw DomainError.validationFailed("Uzupełnij temat zgłoszenia.")
        }
        let initials = name
            .split(whereSeparator: { $0 == " " })
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()

        let client = Client(
            id: ClientID(nextID("client")),
            displayName: name,
            initials: initials.isEmpty ? "??" : initials,
            language: draft.language,
            topic: topic,
            stage: .new,
            source: draft.source,
            createdAt: draft.createdAt,
            briefing: draft.context,
            needsReply: false
        )
        dataset.clients.append(client)
        dataset.threads.append(
            ConversationThread(id: DemoFixtures.threadID(for: client.id), clientID: client.id, sequenceHighWatermark: 0)
        )
        for user in dataset.users {
            dataset.threadStates.append(
                ThreadUserState(userID: user.id, threadID: DemoFixtures.threadID(for: client.id))
            )
        }
        appendActivity("Dodano kontakt do kancelarii", clientID: client.id, caseID: nil)
        return client
    }

    public func updateClient(_ client: Client, expectedVersion: Version) async throws -> Client {
        await pause()
        guard let index = dataset.clients.firstIndex(where: { $0.id == client.id }) else {
            throw DomainError.notFound(resource: "client", id: client.id.rawValue)
        }
        let current = dataset.clients[index]
        guard current.version == expectedVersion else {
            throw DomainError.versionConflict(expected: expectedVersion, current: current.version)
        }
        var updated = client
        updated.version = current.version.next()
        dataset.clients[index] = updated
        return updated
    }

    /// Usunięcie zgłoszenia w Demo — te same reguły co backend: tylko lead,
    /// i tylko wtedy, gdy wersja się zgadza.
    public func deleteClient(_ client: Client, expectedVersion: Version) async throws {
        await pause()
        guard client.stage != .client else {
            throw DomainError.validationFailed(
                "Kartoteki nie usuwa się z aplikacji — usunąć można tylko zgłoszenie przed konwersją."
            )
        }
        guard let index = dataset.clients.firstIndex(where: { $0.id == client.id }) else {
            throw DomainError.notFound(resource: "client", id: client.id.rawValue)
        }
        let current = dataset.clients[index]
        guard current.version == expectedVersion else {
            throw DomainError.versionConflict(expected: expectedVersion, current: current.version)
        }
        dataset.clients.remove(at: index)
    }

    // MARK: - Sprawy

    public func cases(status: CaseStatus?) async throws -> [LegalCase] {
        await pause()
        guard let status else { return dataset.cases }
        if status == .closed { return dataset.cases.filter { !$0.status.isActive } }
        return dataset.cases.filter { $0.status.isActive }
    }

    public func legalCase(id: CaseID) async throws -> LegalCase? {
        await pause()
        return dataset.cases.first { $0.id == id }
    }

    /// Jedna aktywna sprawa na klienta. Zwracanie pierwszej pasującej sprawy jest
    /// regułą tego repozytorium demo, nie regułą domenową (§4.3).
    public func caseForClient(_ clientID: ClientID) async throws -> LegalCase? {
        dataset.cases.first { $0.clientID == clientID && $0.status.isActive }
    }

    public func createCase(_ draft: NewCaseDraft) async throws -> LegalCase {
        await pause()
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = draft.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !summary.isEmpty else {
            throw DomainError.validationFailed("Uzupełnij nazwę i zakres sprawy.")
        }
        // Konwersja nie tworzy duplikatu (§etap 03 gate).
        if let existing = dataset.cases.first(where: { $0.clientID == draft.clientID && $0.status.isActive }) {
            return existing
        }
        let nextNumber = (dataset.cases
            .compactMap { Int($0.number.split(separator: "/").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? "") }
            .max() ?? 40) + 1
        let legalCase = LegalCase(
            id: CaseID(nextID("case")),
            number: "KR / 2026 / \(String(format: "%03d", nextNumber))",
            title: title,
            clientID: draft.clientID,
            status: .inProgress,
            summary: summary,
            createdAt: draft.createdAt
        )
        dataset.cases.append(legalCase)

        // Kontakt staje się klientem, a jego luźne notatki, zadania, terminy i historia
        // zostają powiązane z nową sprawą.
        if let index = dataset.clients.firstIndex(where: { $0.id == draft.clientID }) {
            dataset.clients[index].stage = .client
        }
        for index in dataset.notes.indices where dataset.notes[index].clientID == draft.clientID && dataset.notes[index].caseID == nil {
            dataset.notes[index].caseID = legalCase.id
        }
        for index in dataset.tasks.indices where dataset.tasks[index].clientID == draft.clientID && dataset.tasks[index].caseID == nil {
            dataset.tasks[index].caseID = legalCase.id
        }
        for index in dataset.events.indices where dataset.events[index].clientID == draft.clientID && dataset.events[index].caseID == nil {
            dataset.events[index].caseID = legalCase.id
        }
        for index in dataset.activity.indices where dataset.activity[index].clientID == draft.clientID && dataset.activity[index].caseID == nil {
            dataset.activity[index].caseID = legalCase.id
        }
        appendActivity("Rozpoczęto prowadzenie sprawy", clientID: draft.clientID, caseID: legalCase.id)
        return legalCase
    }

    public func updateCase(_ legalCase: LegalCase, expectedVersion: Version) async throws -> LegalCase {
        await pause()
        guard let index = dataset.cases.firstIndex(where: { $0.id == legalCase.id }) else {
            throw DomainError.notFound(resource: "case", id: legalCase.id.rawValue)
        }
        let current = dataset.cases[index]
        guard current.version == expectedVersion else {
            throw DomainError.versionConflict(expected: expectedVersion, current: current.version)
        }
        var updated = legalCase
        updated.version = current.version.next()
        dataset.cases[index] = updated
        appendActivity("Zaktualizowano sprawę: \(updated.status.rawValue)", clientID: updated.clientID, caseID: updated.id)
        return updated
    }

    // MARK: - Zadania

    /// Pojedyncze zadanie po identyfikatorze. Ekran szczegółów nie musi
    /// filtrować całej listy, aby znaleźć jedno zadanie.
    public func task(id: TaskID) async throws -> TaskItem? {
        dataset.tasks.first { $0.id == id }
    }

    public func tasks(filter: TaskFilter) async throws -> [TaskItem] {
        await pause()
        return dataset.tasks
            .filter { task in
                switch filter.scope {
                case .open: if task.isDone { return false }
                case .done: if !task.isDone { return false }
                case .all: break
                }
                if let due = filter.dueOnOrBefore, task.dueDate > due { return false }
                if let clientID = filter.clientID, task.clientID != clientID { return false }
                if let caseID = filter.caseID, task.caseID != caseID { return false }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                if lhs.priority != rhs.priority { return lhs.priority == .urgent }
                return lhs.id.rawValue < rhs.id.rawValue
            }
    }

    public func createTask(_ draft: NewTaskDraft) async throws -> TaskItem {
        await pause()
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw DomainError.validationFailed("Uzupełnij nazwę zadania.")
        }
        // Sprawa musi należeć do wskazanego klienta; inaczej odrzucamy zamiast zgadywać.
        var caseID = draft.caseID
        if caseID == nil, let clientID = draft.clientID {
            caseID = try await caseForClient(clientID)?.id
        }
        if let caseID, let clientID = draft.clientID {
            guard let legalCase = dataset.cases.first(where: { $0.id == caseID }), legalCase.clientID == clientID else {
                throw DomainError.validationFailed("Sprawa nie należy do wybranego klienta.")
            }
        }
        let task = TaskItem(
            id: TaskID(nextID("task")),
            title: title,
            clientID: draft.clientID,
            caseID: caseID,
            dueDate: draft.dueDate,
            isDone: false,
            priority: draft.priority
        )
        dataset.tasks.append(task)
        appendActivity("Dodano zadanie: \(title)", clientID: draft.clientID, caseID: caseID)
        return task
    }

    public func updateTask(_ task: TaskItem, expectedVersion: Version) async throws -> TaskItem {
        await pause()
        guard let index = dataset.tasks.firstIndex(where: { $0.id == task.id }) else {
            throw DomainError.notFound(resource: "task", id: task.id.rawValue)
        }
        let current = dataset.tasks[index]
        guard current.version == expectedVersion else {
            throw DomainError.versionConflict(expected: expectedVersion, current: current.version)
        }
        var updated = task
        updated.version = current.version.next()
        dataset.tasks[index] = updated
        appendActivity(
            "\(updated.isDone ? "Wykonano" : "Zmieniono") zadanie: \(updated.title)",
            clientID: updated.clientID,
            caseID: updated.caseID
        )
        return updated
    }

    public func setDone(taskID: TaskID, isDone: Bool, expectedVersion: Version) async throws -> TaskItem {
        guard let index = dataset.tasks.firstIndex(where: { $0.id == taskID }) else {
            throw DomainError.notFound(resource: "task", id: taskID.rawValue)
        }
        var task = dataset.tasks[index]
        task.isDone = isDone
        return try await updateTask(task, expectedVersion: expectedVersion)
    }

    // MARK: - Terminy

    public func events(in range: DateIntervalFilter) async throws -> [ScheduledEvent] {
        await pause()
        return dataset.events
            .filter { range.contains($0.day) }
            .sorted { lhs, rhs in
                if lhs.day != rhs.day { return lhs.day < rhs.day }
                if lhs.time != rhs.time { return lhs.time < rhs.time }
                return lhs.id.rawValue < rhs.id.rawValue
            }
    }

    public func event(id: EventID) async throws -> ScheduledEvent? {
        await pause()
        return dataset.events.first { $0.id == id }
    }

    public func createEvent(_ draft: NewEventDraft) async throws -> ScheduledEvent {
        await pause()
        try validateEventFields(
            title: draft.title,
            place: draft.place,
            durationMinutes: draft.durationMinutes
        )
        let candidate = ScheduledEvent(
            id: EventID(nextID("event")),
            clientID: draft.clientID,
            caseID: draft.caseID,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            day: draft.day,
            time: draft.time,
            durationMinutes: draft.durationMinutes,
            kind: draft.kind,
            status: draft.status,
            place: draft.place.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let conflict = dataset.events.first(where: { $0.overlaps(with: candidate) }) {
            throw DomainError.validationFailed(
                "W kalendarzu jest już wydarzenie o \(conflict.time.hhmm): \(conflict.title). "
                + "Wybierz inną godzinę."
            )
        }
        dataset.events.append(candidate)
        appendActivity(
            "Dodano termin: \(candidate.title), \(candidate.day.isoString) \(candidate.time.hhmm)",
            clientID: candidate.clientID,
            caseID: candidate.caseID
        )
        return candidate
    }

    public func updateEvent(_ event: ScheduledEvent, expectedVersion: Version) async throws -> ScheduledEvent {
        await pause()
        guard let index = dataset.events.firstIndex(where: { $0.id == event.id }) else {
            throw DomainError.notFound(resource: "event", id: event.id.rawValue)
        }
        let current = dataset.events[index]
        guard current.version == expectedVersion else {
            throw DomainError.versionConflict(expected: expectedVersion, current: current.version)
        }
        try validateEventFields(title: event.title, place: event.place, durationMinutes: event.durationMinutes)
        if let conflict = dataset.events.first(where: { $0.overlaps(with: event) }) {
            throw DomainError.validationFailed(
                "W kalendarzu jest już wydarzenie o \(conflict.time.hhmm): \(conflict.title). "
                + "Wybierz inną godzinę."
            )
        }
        var updated = event
        updated.version = current.version.next()
        dataset.events[index] = updated
        appendActivity(
            "Zmieniono termin: \(updated.title), \(updated.day.isoString) \(updated.time.hhmm)",
            clientID: updated.clientID,
            caseID: updated.caseID
        )
        return updated
    }

    public func deleteEvent(id: EventID, expectedVersion: Version) async throws {
        await pause()
        guard let index = dataset.events.firstIndex(where: { $0.id == id }) else {
            throw DomainError.notFound(resource: "event", id: id.rawValue)
        }
        let removed = dataset.events[index]
        guard removed.version == expectedVersion else {
            throw DomainError.versionConflict(expected: expectedVersion, current: removed.version)
        }
        dataset.events.remove(at: index)
        appendActivity(
            "Usunięto termin: \(removed.title), \(removed.day.isoString) \(removed.time.hhmm)",
            clientID: removed.clientID,
            caseID: removed.caseID
        )
    }

    private func validateEventFields(title: String, place: String, durationMinutes: Int) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainError.validationFailed("Uzupełnij nazwę wydarzenia.")
        }
        guard !place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainError.validationFailed("Uzupełnij miejsce lub formę.")
        }
        guard durationMinutes > 0, durationMinutes <= 8 * 60 else {
            throw DomainError.validationFailed("Czas trwania musi być dodatni.")
        }
    }

    // MARK: - Notatki i historia

    public func notes(clientID: ClientID, caseID: CaseID?) async throws -> [CaseNote] {
        await pause()
        return dataset.notes
            .filter { note in
                guard note.clientID == clientID else { return false }
                if let caseID { return note.caseID == caseID }
                return true
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func addNote(_ draft: NewNoteDraft) async throws -> CaseNote {
        await pause()
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw DomainError.validationFailed("Wpisz lub podyktuj treść notatki.")
        }
        let note = CaseNote(
            id: NoteID(nextID("note")),
            clientID: draft.clientID,
            caseID: draft.caseID,
            text: text,
            authorID: draft.authorID,
            createdAt: draft.createdAt
        )
        dataset.notes.append(note)
        appendActivity("Dodano notatkę z rozmowy", clientID: draft.clientID, caseID: draft.caseID)
        return note
    }

    public func activity(caseID: CaseID) async throws -> [ActivityEvent] {
        await pause()
        return dataset.activity.filter { $0.caseID == caseID }
    }

    public func activity(clientID: ClientID) async throws -> [ActivityEvent] {
        await pause()
        return dataset.activity.filter { $0.clientID == clientID }
    }

    private func appendActivity(_ text: String, clientID: ClientID?, caseID: CaseID?) {
        dataset.activity.insert(
            ActivityEvent(
                id: ActivityID(nextID("activity")),
                text: text,
                clientID: clientID,
                caseID: caseID,
                createdAt: clock.today(),
                authorID: dataset.user.id
            ),
            at: 0
        )
    }

    // MARK: - Rozmowy

    public func threads() async throws -> [ConversationThread] {
        await pause()
        return dataset.threads
    }

    public func thread(id: ThreadID) async throws -> ConversationThread? {
        await pause()
        return dataset.threads.first { $0.id == id }
    }

    /// Paginacja starszej historii: zwraca wiadomości o numerze mniejszym od `before`.
    public func messages(threadID: ThreadID, before sequence: Int?, limit: Int) async throws -> [Message] {
        await pause()
        let all = MessageOrdering.sorted(dataset.messages.filter { $0.threadID == threadID })
        let filtered = sequence.map { boundary in all.filter { $0.sequence < boundary } } ?? all
        return Array(filtered.suffix(limit))
    }

    public func latestMessages(threadID: ThreadID, limit: Int) async throws -> [Message] {
        await pause()
        let all = MessageOrdering.sorted(dataset.messages.filter { $0.threadID == threadID })
        return Array(all.suffix(limit))
    }

    public func appendOutgoing(_ draft: OutgoingMessageDraft) async throws -> Message {
        await pause()
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw DomainError.validationFailed("Wiadomość nie może być pusta.")
        }
        // Idempotencja tworzenia: ten sam klucz zwraca istniejącą wiadomość (§7).
        if let existing = idempotencyIndex[draft.idempotencyKey],
           let message = dataset.messages.first(where: { $0.id == existing }) {
            return message
        }
        guard let threadIndex = dataset.threads.firstIndex(where: { $0.id == draft.threadID }) else {
            throw DomainError.notFound(resource: "thread", id: draft.threadID.rawValue)
        }
        let sequence = dataset.threads[threadIndex].sequenceHighWatermark + 1
        dataset.threads[threadIndex].sequenceHighWatermark = sequence

        let message = Message(
            id: MessageID(nextID("msg")),
            threadID: draft.threadID,
            direction: .outgoing,
            authorID: draft.authorID,
            text: text,
            quote: draft.quote,
            sentAt: draft.sentAt,
            sequence: sequence,
            // Ręcznie zatwierdzona treść trafia do outboxa: „oczekuje”, nie „wysłano”.
            transport: .pending,
            source: draft.source
        )
        dataset.messages.append(message)
        idempotencyIndex[draft.idempotencyKey] = message.id

        let clientID = dataset.threads[threadIndex].clientID
        if let clientIndex = dataset.clients.firstIndex(where: { $0.id == clientID }) {
            dataset.clients[clientIndex].needsReply = false
            if dataset.clients[clientIndex].stage == .new {
                dataset.clients[clientIndex].stage = .inContact
            }
            appendActivity(
                "Przygotowano wiadomość WhatsApp",
                clientID: clientID,
                caseID: try? await caseForClient(clientID)?.id
            )
        }
        // Wysłanie wiadomości czyści szkic tego wątku dla autora.
        markDraftSent(threadID: draft.threadID, authorID: draft.authorID)
        return message
    }

    private func markDraftSent(threadID: ThreadID, authorID: UserID) {
        for index in dataset.threadStates.indices
        where dataset.threadStates[index].threadID == threadID && dataset.threadStates[index].userID == authorID {
            dataset.threadStates[index].draft = nil
        }
    }

    public func saveReadState(_ state: ThreadUserState) async throws -> ThreadUserState {
        await pause()
        guard let index = dataset.threadStates.firstIndex(where: {
            $0.userID == state.userID && $0.threadID == state.threadID
        }) else {
            dataset.threadStates.append(state)
            return state
        }
        var updated = state
        // Kursor nigdy się nie cofa, a `manualUnread` jest osobnym znacznikiem (§3.3 pkt 2).
        updated.readCursorSequence = max(dataset.threadStates[index].readCursorSequence, state.readCursorSequence)
        dataset.threadStates[index] = updated
        return updated
    }

    /// Liczba nieprzeczytanych wiadomości w każdym wątku dla danego użytkownika.
    ///
    /// Liczona przez `ReadStatePolicy`, czyli tę samą regułę, której używa otwarty
    /// wątek — dzięki temu plakietka na zakładce i licznik w wątku nie mogą się
    /// rozjechać (§3.3).
    public func unreadCounts(userID: UserID) async throws -> [ThreadID: Int] {
        let states = try await readStates(userID: userID)
        var result: [ThreadID: Int] = [:]
        for thread in dataset.threads {
            let messages = try await latestMessages(threadID: thread.id, limit: 200)
            let state = states.first { $0.threadID == thread.id }
                ?? ThreadUserState(userID: userID, threadID: thread.id)
            result[thread.id] = ReadStatePolicy.unreadCount(in: messages, state: state)
        }
        return result
    }

    /// Suma nieprzeczytanych wiadomości — plakietka na zakładce „Rozmowy”.
    public func unreadTotal(userID: UserID) async throws -> Int {
        try await unreadCounts(userID: userID).values.reduce(0, +)
    }

    public func readStates(userID: UserID) async throws -> [ThreadUserState] {
        await pause()
        return dataset.threadStates.filter { $0.userID == userID }
    }

    public func saveThreadPreferences(_ state: ThreadUserState) async throws -> ThreadUserState {
        try await saveReadState(state)
    }

    public func saveDraft(_ draft: Draft?) async throws {
        guard let draft else { return }
        for index in dataset.threadStates.indices where dataset.threadStates[index].threadID == draft.threadID {
            dataset.threadStates[index].draft = draft
        }
    }

    /// Status dostawcy może wyłącznie poprawić stan wiadomości (§9.2).
    public func applyProviderStatus(
        providerMessageID: String,
        status: MessageTransport,
        at date: Date
    ) async throws -> Message? {
        await pause()
        guard let index = dataset.messages.firstIndex(where: { $0.providerMessageID == providerMessageID }) else {
            return nil
        }
        var message = dataset.messages[index]
        message.transport = MessageOrdering.applyingStatus(status, to: message.transport)
        message.version = message.version.next()
        dataset.messages[index] = message
        return message
    }

    // MARK: - Sesje voice

    public func create(_ request: CreateVoiceSession) async throws -> VoiceSessionConfiguration {
        await pause()
        let sessionID = VoiceSessionID(nextID("voice-session"))
        let expiresAt = clock.now().addingTimeInterval(30 * 60)
        let status = VoiceSessionStatus(
            sessionID: sessionID,
            isActive: true,
            context: request.context,
            expiresAt: expiresAt
        )
        voiceSessions[sessionID] = status
        return VoiceSessionConfiguration(
            sessionID: sessionID,
            context: request.context,
            assistantLanguage: request.assistantLanguage,
            // W demo poświadczenie jest fikcyjne i lokalne. W live pochodzi z backendu,
            // a klucz dostawcy nigdy nie trafia do aplikacji (§1.8).
            conversationToken: "demo-session-token-\(sessionID.rawValue)",
            transport: request.requestedTransport,
            expiresAt: expiresAt,
            capabilities: .mock
        )
    }

    public func updateContext(_ request: UpdateVoiceContext) async throws -> AssistantContext {
        await pause()
        guard var status = voiceSessions[request.sessionID] else {
            throw DomainError.notFound(resource: "voice-session", id: request.sessionID.rawValue)
        }
        guard status.context.version == request.expectedContextVersion else {
            throw DomainError.versionConflict(expected: request.expectedContextVersion, current: status.context.version)
        }
        let validation = AssistantContext.validate(
            request.context,
            clients: dataset.clients,
            cases: dataset.cases,
            threads: dataset.threads
        )
        if case .rejected(let reason) = validation {
            throw DomainError.validationFailed(reason)
        }
        var updatedContext = request.context
        updatedContext.version = status.context.version.next()
        status.context = updatedContext
        voiceSessions[request.sessionID] = status
        return updatedContext
    }

    public func fetchStatus(sessionID: VoiceSessionID) async throws -> VoiceSessionStatus {
        await pause()
        guard let status = voiceSessions[sessionID] else {
            throw DomainError.notFound(resource: "voice-session", id: sessionID.rawValue)
        }
        return status
    }

    public func end(sessionID: VoiceSessionID) async throws {
        await pause()
        voiceSessions[sessionID]?.isActive = false
    }

    // MARK: - Silnik akcji

    public func prepare(_ request: PrepareAction) async throws -> ActionProposal {
        await pause()
        return actionEngine.prepare(request.request, into: &actionState)
    }

    public func revise(_ request: ReviseAction) async throws -> ActionProposal {
        await pause()
        guard let current = actionState.proposals[request.actionID] else {
            throw ActionEngineError.proposalNotFound
        }
        guard current.version == request.expectedVersion else {
            throw ActionEngineError.versionConflict(expected: request.expectedVersion, current: current.version)
        }
        return try actionEngine.revise(
            actionID: request.actionID,
            newText: request.newText,
            now: request.now,
            into: &actionState
        )
    }

    public func reschedule(_ request: RescheduleAction) async throws -> ActionProposal {
        await pause()
        guard let current = actionState.proposals[request.actionID] else {
            throw ActionEngineError.proposalNotFound
        }
        guard current.version == request.expectedVersion else {
            throw ActionEngineError.versionConflict(expected: request.expectedVersion, current: current.version)
        }
        return try actionEngine.reschedule(
            actionID: request.actionID,
            dueDate: request.dueDate,
            now: request.now,
            into: &actionState
        )
    }

    public func changeContext(_ request: ChangeActionContext) async throws -> ActionProposal {
        await pause()
        guard let current = actionState.proposals[request.actionID] else {
            throw ActionEngineError.proposalNotFound
        }
        guard current.version == request.expectedVersion else {
            throw ActionEngineError.versionConflict(expected: request.expectedVersion, current: current.version)
        }
        return try actionEngine.changeContext(
            actionID: request.actionID,
            clientID: request.clientID,
            caseID: request.caseID,
            threadID: request.threadID,
            now: request.now,
            into: &actionState
        )
    }

    /// Wykonanie idempotentne: to samo potwierdzenie zwraca to samo wykonanie (§8.1).
    public func confirm(_ request: ConfirmAction) async throws -> ActionExecution {
        await pause()
        if let existing = actionState.executions[request.confirmation.actionID],
           existing.proposalVersion == request.confirmation.expectedVersion {
            return existing
        }
        do {
            return try actionEngine.confirm(
                request.confirmation,
                outboxID: "outbox-\(request.idempotencyKey)",
                into: &actionState
            )
        } catch ActionEngineError.duplicateExecution {
            if let existing = actionState.executions[request.confirmation.actionID] { return existing }
            throw ActionEngineError.duplicateExecution
        }
    }

    public func cancel(_ request: CancelAction) async throws -> ActionExecution {
        await pause()
        let proposal = try actionEngine.cancel(actionID: request.actionID, now: request.now, into: &actionState)
        // Anulowanie propozycji nie tworzy wykonania; zwracamy stan istniejącego
        // wykonania albo jawnie „failed” z powodem, bez wysyłki.
        if let existing = actionState.executions[proposal.id] { return existing }
        return ActionExecution(
            actionID: proposal.id,
            proposalVersion: proposal.version,
            state: .failed,
            outboxID: "outbox-cancelled-\(proposal.id.rawValue)",
            updatedAt: request.now,
            lastErrorCode: "cancelled_before_dispatch"
        )
    }

    public func status(actionID: ActionID) async throws -> ActionExecution {
        await pause()
        guard let execution = actionState.executions[actionID] else {
            throw DomainError.notFound(resource: "action", id: actionID.rawValue)
        }
        return execution
    }

    /// Symulacja zdarzenia dostawcy dla akcji: outbox → accepted.
    /// W demo jawnie oznaczamy, że potwierdzenie pochodzi z symulacji.
    public func simulateProviderAccepted(actionID: ActionID, at date: Date) {
        _ = actionEngine.applyExecutionState(
            actionID: actionID,
            state: .accepted,
            now: date,
            into: &actionState
        )
    }

    public func simulateProviderUnknown(actionID: ActionID, at date: Date) {
        _ = actionEngine.applyExecutionState(
            actionID: actionID,
            state: .unknown,
            now: date,
            into: &actionState
        )
    }
}
