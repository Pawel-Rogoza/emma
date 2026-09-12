import Foundation

// MARK: - Deterministyczne dane demonstracyjne
//
// Wartości przeniesione z zatwierdzonego prototypu (`app.js`, stała `initial`).
// Wszystkie dane są fikcyjne. Data przykładowa: 11 września 2026.

public enum DemoFixtures {

    public static let referenceDay = LocalDate(year: 2026, month: 9, day: 11)
    public static let weekStart = LocalDate(year: 2026, month: 9, day: 7)

    // MARK: Użytkownicy

    public static let tomasz = User(
        id: .tomasz,
        displayName: "Tomasz Rogoża",
        initials: "TR",
        interfaceLanguage: .pl,
        assistantLanguage: .ru
    )

    public static let pawel = User(
        id: .pawel,
        displayName: "Paweł Rogoża",
        initials: "PR",
        interfaceLanguage: .pl,
        assistantLanguage: .ru
    )

    public static let users: [User] = [tomasz, pawel]

    // MARK: Klienci

    public static let olenaID = ClientID("client-olena")
    public static let andriiID = ClientID("client-andrii")
    public static let mariaID = ClientID("client-maria")
    public static let dmytroID = ClientID("client-dmytro")

    public static let olena = Client(
        id: olenaID,
        displayName: "Olena Kovalenko",
        initials: "OK",
        language: .uk,
        topic: "Wezwanie na przesłuchanie",
        stage: .client,
        source: .webForm,
        createdAt: LocalDate(year: 2026, month: 9, day: 9),
        briefing: "Klientka otrzymała wezwanie na przesłuchanie. Chce omówić dokumenty i przygotować się do spotkania.",
        incomingMessage: "Дякую, надішлю документи до зустрічі.",
        incomingTranslation: "Dziękuję, prześlę dokumenty przed spotkaniem.",
        incomingTime: TimeOfDay(hhmm: "09:15"),
        needsReply: false
    )

    public static let andrii = Client(
        id: andriiID,
        displayName: "Andrii Melnyk",
        initials: "AM",
        language: .uk,
        topic: "Zatrzymanie osoby bliskiej",
        stage: .new,
        source: .webForm,
        createdAt: referenceDay,
        briefing: "Prośba o pilny kontakt w sprawie zatrzymania brata. Informacje o miejscu zatrzymania do ustalenia podczas rozmowy.",
        incomingMessage: "Доброго дня, мого брата затримали. Чи можете допомогти?",
        incomingTranslation: "Dzień dobry, zatrzymano mojego brata. Czy może Pan pomóc?",
        incomingTime: TimeOfDay(hhmm: "09:29"),
        needsReply: true
    )

    public static let maria = Client(
        id: mariaID,
        displayName: "Maria Sokołowa",
        initials: "MS",
        language: .ru,
        topic: "Konsultacja prawna",
        stage: .new,
        source: .webForm,
        createdAt: referenceDay,
        briefing: "Klientka umówiła konsultację przez stronę. Preferuje rozmowę po rosyjsku i kontakt przez WhatsApp.",
        incomingMessage: "Здравствуйте! Можно провести консультацию на русском?",
        incomingTranslation: "Dzień dobry! Czy konsultacja może odbyć się po rosyjsku?",
        incomingTime: TimeOfDay(hhmm: "09:03"),
        needsReply: true
    )

    public static let dmytro = Client(
        id: dmytroID,
        displayName: "Dmytro Bondarenko",
        initials: "DB",
        language: .pl,
        topic: "Omówienie dokumentów",
        stage: .client,
        source: .referral,
        createdAt: LocalDate(year: 2026, month: 9, day: 7),
        briefing: "Klient przekazał dokumenty do omówienia podczas konsultacji. Kolejne działania do ustalenia po spotkaniu.",
        incomingMessage: "Dziękuję, przesłałem komplet dokumentów. Do zobaczenia o 12:00.",
        incomingTranslation: nil,
        incomingTime: TimeOfDay(hhmm: "08:42"),
        needsReply: false
    )

    public static let clients: [Client] = [olena, andrii, maria, dmytro]

    // MARK: Sprawy

    public static let caseOlenaID = CaseID("case-041")
    public static let caseDmytroID = CaseID("case-038")

    public static let caseOlena = LegalCase(
        id: caseOlenaID,
        number: "KR / 2026 / 041",
        title: "Przygotowanie do przesłuchania",
        clientID: olenaID,
        status: .inProgress,
        summary: "Zapoznanie się z wezwaniem i konsultacja przed przesłuchaniem.",
        createdAt: LocalDate(year: 2026, month: 9, day: 9)
    )

    public static let caseDmytro = LegalCase(
        id: caseDmytroID,
        number: "KR / 2026 / 038",
        title: "Analiza dokumentów klienta",
        clientID: dmytroID,
        status: .awaitingClient,
        summary: "Weryfikacja przekazanych dokumentów i ustalenie dalszego zakresu prowadzenia sprawy.",
        createdAt: LocalDate(year: 2026, month: 9, day: 7)
    )

    public static let cases: [LegalCase] = [caseOlena, caseDmytro]

    // MARK: Terminy

    public static let eventOlenaID = EventID("event-12")
    public static let eventDmytroID = EventID("event-13")
    public static let eventAndriiID = EventID("event-14")
    public static let eventMariaID = EventID("event-15")
    public static let eventHearingID = EventID("event-16")

    public static let events: [ScheduledEvent] = [
        ScheduledEvent(
            id: eventOlenaID,
            clientID: olenaID,
            caseID: caseOlenaID,
            title: "Konsultacja z Oleną",
            day: referenceDay,
            time: TimeOfDay(hhmm: "10:30")!,
            durationMinutes: 30,
            kind: .consultation,
            status: .confirmed,
            place: "Online"
        ),
        ScheduledEvent(
            id: eventDmytroID,
            clientID: dmytroID,
            caseID: caseDmytroID,
            title: "Omówienie dokumentów",
            day: referenceDay,
            time: TimeOfDay(hhmm: "12:00")!,
            durationMinutes: 30,
            kind: .consultation,
            status: .confirmed,
            place: "Kancelaria"
        ),
        ScheduledEvent(
            id: eventAndriiID,
            clientID: andriiID,
            caseID: nil,
            title: "Pierwsza konsultacja",
            day: referenceDay,
            time: TimeOfDay(hhmm: "14:00")!,
            durationMinutes: 30,
            kind: .consultation,
            status: .toConfirm,
            place: "Telefon"
        ),
        ScheduledEvent(
            id: eventMariaID,
            clientID: mariaID,
            caseID: nil,
            title: "Pierwsza konsultacja",
            day: LocalDate(year: 2026, month: 9, day: 12),
            time: TimeOfDay(hhmm: "11:00")!,
            durationMinutes: 60,
            kind: .consultation,
            status: .toConfirm,
            place: "Online"
        ),
        ScheduledEvent(
            id: eventHearingID,
            clientID: olenaID,
            caseID: caseOlenaID,
            title: "Przesłuchanie klientki",
            day: LocalDate(year: 2026, month: 9, day: 15),
            time: TimeOfDay(hhmm: "09:00")!,
            durationMinutes: 60,
            kind: .caseDeadline,
            status: .confirmed,
            place: "Warszawa · miejsce do sprawdzenia"
        )
    ]

    // MARK: Zadania

    public static let taskCallbackID = TaskID("task-17")
    public static let taskSummonsID = TaskID("task-18")
    public static let taskNoteID = TaskID("task-19")

    public static let tasks: [TaskItem] = [
        TaskItem(
            id: taskCallbackID,
            title: "Oddzwonić w sprawie zatrzymania",
            clientID: andriiID,
            caseID: nil,
            dueDate: referenceDay,
            isDone: false,
            priority: .urgent
        ),
        TaskItem(
            id: taskSummonsID,
            title: "Zapoznać się z wezwaniem",
            clientID: olenaID,
            caseID: caseOlenaID,
            dueDate: referenceDay,
            isDone: false,
            priority: .normal
        ),
        TaskItem(
            id: taskNoteID,
            title: "Uzupełnić notatkę po konsultacji",
            clientID: dmytroID,
            caseID: caseDmytroID,
            dueDate: referenceDay,
            isDone: false,
            priority: .normal
        )
    ]

    // MARK: Notatki i historia

    public static let notes: [CaseNote] = [
        CaseNote(
            id: NoteID("note-1"),
            clientID: olenaID,
            caseID: caseOlenaID,
            text: "Klientka potwierdziła język ukraiński. Na konsultacji sprawdzić kompletność przekazanych dokumentów.",
            authorID: .tomasz,
            createdAt: LocalDate(year: 2026, month: 9, day: 10)
        ),
        CaseNote(
            id: NoteID("note-2"),
            clientID: dmytroID,
            caseID: caseDmytroID,
            text: "Dokumenty otrzymane. Do omówienia podczas konsultacji w piątek.",
            authorID: .pawel,
            createdAt: LocalDate(year: 2026, month: 9, day: 10)
        )
    ]

    public static let activity: [ActivityEvent] = [
        ActivityEvent(
            id: ActivityID("activity-1"),
            text: "Konsultacja potwierdzona na 10:30",
            clientID: olenaID,
            caseID: caseOlenaID,
            createdAt: referenceDay,
            authorID: .tomasz
        ),
        ActivityEvent(
            id: ActivityID("activity-2"),
            text: "Dodano notatkę do sprawy",
            clientID: dmytroID,
            caseID: caseDmytroID,
            createdAt: LocalDate(year: 2026, month: 9, day: 10),
            authorID: .pawel
        )
    ]

    // MARK: Wątki i wiadomości
    //
    // W prototypie wątek jest jeden na osobę; w domenie produkcyjnej wątek jest
    // osobnym zasobem z własnym identyfikatorem.

    public static func threadID(for clientID: ClientID) -> ThreadID {
        ThreadID("thread-\(clientID.rawValue)")
    }

    public static let olenaThread = threadID(for: olenaID)
    public static let andriiThread = threadID(for: andriiID)
    public static let mariaThread = threadID(for: mariaID)
    public static let dmytroThread = threadID(for: dmytroID)

    /// Zegary wiadomości demo. Sekwencje rosną monotonicznie w obrębie wątku.
    private static func instant(_ day: LocalDate, _ hhmm: String) -> Date {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        let parts = hhmm.split(separator: ":")
        components.hour = Int(parts[0])
        components.minute = Int(parts[1])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: EmmaTime.referenceTimeZone) ?? .gmt
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    public static let threads: [ConversationThread] = [
        ConversationThread(id: olenaThread, clientID: olenaID, sequenceHighWatermark: 2),
        // Andrii ma dwie wiadomości nieprzeczytane dla obu adwokatów.
        ConversationThread(id: andriiThread, clientID: andriiID, sequenceHighWatermark: 2),
        ConversationThread(id: mariaThread, clientID: mariaID, sequenceHighWatermark: 1),
        ConversationThread(id: dmytroThread, clientID: dmytroID, sequenceHighWatermark: 2)
    ]

    public static let messages: [Message] = [
        // Olena: wiadomość klientki + odpowiedź Tomasza (odczytana przez klienta)
        Message(
            id: MessageID("msg-olena-1"),
            threadID: olenaThread,
            direction: .incoming,
            authorID: nil,
            authorLabel: "Olena Kovalenko",
            providerMessageID: "wamid.demo.olena.1",
            text: "Дякую, надішлю документи до зустрічі.",
            translation: "Dziękuję, prześlę dokumenty przed spotkaniem.",
            sentAt: instant(referenceDay, "09:15"),
            sequence: 1,
            transport: .delivered,
            source: .demoFixture
        ),
        Message(
            id: MessageID("msg-olena-2"),
            threadID: olenaThread,
            direction: .outgoing,
            authorID: .tomasz,
            providerMessageID: "wamid.demo.olena.2",
            text: "Дякую. До зустрічі о 10:30.",
            sentAt: instant(referenceDay, "09:18"),
            sequence: 2,
            transport: .read,
            source: .demoFixture
        ),

        // Andrii: dwie wiadomości nieprzeczytane
        Message(
            id: MessageID("msg-andrii-1"),
            threadID: andriiThread,
            direction: .incoming,
            authorID: nil,
            authorLabel: "Andrii Melnyk",
            providerMessageID: "wamid.demo.andrii.1",
            text: "Доброго дня, мого брата затримали. Чи можете допомогти?",
            translation: "Dzień dobry, zatrzymano mojego brata. Czy może Pan pomóc?",
            sentAt: instant(referenceDay, "09:29"),
            sequence: 1,
            transport: .delivered,
            source: .demoFixture
        ),
        Message(
            id: MessageID("msg-andrii-2"),
            threadID: andriiThread,
            direction: .incoming,
            authorID: nil,
            authorLabel: "Andrii Melnyk",
            providerMessageID: "wamid.demo.andrii.2",
            text: "Можу зараз говорити по телефону.",
            translation: "Mogę teraz porozmawiać przez telefon.",
            sentAt: instant(referenceDay, "09:31"),
            sequence: 2,
            transport: .delivered,
            source: .demoFixture
        ),

        // Maria: jedna nieprzeczytana wiadomość
        Message(
            id: MessageID("msg-maria-1"),
            threadID: mariaThread,
            direction: .incoming,
            authorID: nil,
            authorLabel: "Maria Sokołowa",
            providerMessageID: "wamid.demo.maria.1",
            text: "Здравствуйте! Можно провести консультацию на русском?",
            translation: "Dzień dobry! Czy konsultacja może odbyć się po rosyjsku?",
            sentAt: instant(referenceDay, "09:03"),
            sequence: 1,
            transport: .delivered,
            source: .demoFixture
        ),

        // Dmytro: przeczytane przez obu
        Message(
            id: MessageID("msg-dmytro-1"),
            threadID: dmytroThread,
            direction: .incoming,
            authorID: nil,
            authorLabel: "Dmytro Bondarenko",
            providerMessageID: "wamid.demo.dmytro.1",
            text: "Dziękuję, przesłałem komplet dokumentów. Do zobaczenia o 12:00.",
            sentAt: instant(referenceDay, "08:42"),
            sequence: 1,
            transport: .delivered,
            source: .demoFixture
        ),
        Message(
            id: MessageID("msg-dmytro-2"),
            threadID: dmytroThread,
            direction: .outgoing,
            authorID: .pawel,
            providerMessageID: "wamid.demo.dmytro.2",
            text: "Dziękuję, do zobaczenia w kancelarii.",
            sentAt: instant(referenceDay, "08:45"),
            sequence: 2,
            transport: .delivered,
            source: .demoFixture
        ),

        // Przykład echa z Business App przy koegzystencji: nadawca nieznany wśród braci.
        Message(
            id: MessageID("msg-dmytro-3"),
            threadID: dmytroThread,
            direction: .outgoing,
            authorID: nil,
            authorLabel: "WhatsApp Business",
            providerMessageID: "wamid.demo.dmytro.echo.1",
            text: "Potwierdzam, dokumenty są kompletne.",
            sentAt: instant(referenceDay, "09:40"),
            sequence: 3,
            transport: .sent,
            source: .whatsAppBusinessEcho
        )
    ]

    /// Kursory startowe: wszystko przed tą datą jest przeczytane.
    /// Andrii i Maria mają nieprzeczytane wiadomości dla obu adwokatów.
    /// Stan odczytu jest **niezależny dla każdego prawnika** (§3.3):
    /// odczyt jednego nie zmienia licznika drugiego, a kursor nigdy się nie cofa.
    ///
    /// Paweł odpowiedział już Andriiowi, Tomasz jeszcze nie — dlatego liczniki
    /// nieprzeczytanych są różne (Tomasz 3, Paweł 1) i widać, że są liczone osobno.
    /// Ten sam zestaw danych obsługuje oba profile.
    public static let threadStates: [ThreadUserState] = {
        var states: [ThreadUserState] = []
        for user in users {
            let isPawel = user.id == UserID.pawel
            states.append(ThreadUserState(userID: user.id, threadID: olenaThread, readCursorSequence: 2))
            // Dwie wiadomości Andriia: Paweł ma je za sobą, Tomasz nie.
            states.append(
                ThreadUserState(
                    userID: user.id,
                    threadID: andriiThread,
                    readCursorSequence: isPawel ? 2 : 0
                )
            )
            states.append(ThreadUserState(userID: user.id, threadID: mariaThread, readCursorSequence: 0))
            states.append(ThreadUserState(userID: user.id, threadID: dmytroThread, readCursorSequence: 3))
        }
        return states
    }()

    // MARK: Akcje demonstracyjne

    public static let contextVersion = Version(4)

    public static let replyProposal = ActionProposal(
        id: ActionID("action-reply-olena"),
        kind: .reply,
        actorUserID: .tomasz,
        clientID: olenaID,
        caseID: caseOlenaID,
        threadID: olenaThread,
        text: "Доброго дня! Бачу нашу консультацію о 10:30. Зустріч підтверджена. Будь ласка, надішліть документи перед розмовою.",
        payloadHash: ActionEngine.payloadHash(
            kind: .reply,
            text: "Доброго дня! Бачу нашу консультацію о 10:30. Зустріч підтверджена. Будь ласка, надішліть документи перед розмовою.",
            clientID: olenaID,
            caseID: caseOlenaID,
            threadID: olenaThread
        ),
        contextVersion: contextVersion,
        threadVersion: Version(3),
        presentedAt: Date(timeIntervalSince1970: 1_789_100_000),
        expiresAt: Date(timeIntervalSince1970: 1_789_100_900),
        presentationID: "presentation-reply-olena-1"
    )

    /// Wersja po korekcie godziny — inny hash i identyfikator prezentacji.
    public static let revisedReplyProposal: ActionProposal = {
        var proposal = replyProposal
        let text = "Доброго дня! Бачу нашу консультацію об 11:00. Зустріч підтверджена. Будь ласка, надішліть документи перед розмовою."
        proposal.text = text
        proposal.version = Version(2)
        proposal.payloadHash = ActionEngine.payloadHash(
            kind: .reply,
            text: text,
            clientID: olenaID,
            caseID: caseOlenaID,
            threadID: olenaThread
        )
        proposal.presentationID = "presentation-reply-olena-1#r2"
        return proposal
    }()

    /// Propozycja w języku rosyjskim dla klientki rosyjskojęzycznej.
    public static let replyProposalRussian = ActionProposal(
        id: ActionID("action-reply-maria"),
        kind: .reply,
        actorUserID: .tomasz,
        clientID: mariaID,
        caseID: nil,
        threadID: mariaThread,
        text: "Здравствуйте! Да, консультацию можно провести на русском языке. Вижу Вашу запись на 12 сентября в 11:00. Время ещё ожидает подтверждения.",
        payloadHash: ActionEngine.payloadHash(
            kind: .reply,
            text: "Здравствуйте! Да, консультацию можно провести на русском языке. Вижу Вашу запись на 12 сентября в 11:00. Время ещё ожидает подтверждения.",
            clientID: mariaID,
            caseID: nil,
            threadID: mariaThread
        ),
        contextVersion: contextVersion,
        threadVersion: Version(1),
        presentedAt: Date(timeIntervalSince1970: 1_789_100_000),
        expiresAt: Date(timeIntervalSince1970: 1_789_100_900),
        presentationID: "presentation-reply-maria-1"
    )

    public static let queuedExecution = ActionExecution(
        actionID: replyProposal.id,
        proposalVersion: replyProposal.version,
        state: .queued,
        outboxID: "outbox-demo-1",
        updatedAt: Date(timeIntervalSince1970: 1_789_100_000)
    )

    // MARK: Zestaw danych dla repozytorium demo

    public struct Dataset: Sendable {
        public var users: [User]
        public var clients: [Client]
        public var cases: [LegalCase]
        public var events: [ScheduledEvent]
        public var tasks: [TaskItem]
        public var notes: [CaseNote]
        public var activity: [ActivityEvent]
        public var threads: [ConversationThread]
        public var messages: [Message]
        public var threadStates: [ThreadUserState]
        public var currentUserID: UserID

        /// Użytkownik, na którego patrzy demo.
        ///
        /// Kancelaria ma dwóch prawników, a `currentUserID` wskazuje, kto jest zalogowany.
        /// Brak pasującego użytkownika oznacza błąd w danych przykładowych, a nie stan,
        /// który interfejs miałby obsłużyć — dlatego kończymy głośno, zamiast po cichu
        /// pokazywać losową osobę (np. pokazanie cudzych rozmów jako własnych).
        public var user: User {
            if let match = users.first(where: { $0.id == currentUserID }) {
                return match
            }
            preconditionFailure(
                "DemoFixtures: brak użytkownika o identyfikatorze \(currentUserID.rawValue) "
                + "przy \(users.count) użytkownikach w zestawie danych"
            )
        }

        public init(
            users: [User] = DemoFixtures.users,
            clients: [Client] = DemoFixtures.clients,
            cases: [LegalCase] = DemoFixtures.cases,
            events: [ScheduledEvent] = DemoFixtures.events,
            tasks: [TaskItem] = DemoFixtures.tasks,
            notes: [CaseNote] = DemoFixtures.notes,
            activity: [ActivityEvent] = DemoFixtures.activity,
            threads: [ConversationThread] = DemoFixtures.threads,
            messages: [Message] = DemoFixtures.messages,
            threadStates: [ThreadUserState] = DemoFixtures.threadStates,
            currentUserID: UserID = UserID.tomasz
        ) {
            self.users = users
            self.clients = clients
            self.cases = cases
            self.events = events
            self.tasks = tasks
            self.notes = notes
            self.activity = activity
            self.threads = threads
            self.messages = messages
            self.threadStates = threadStates
            self.currentUserID = currentUserID
        }
    }

    public static func dataset() -> Dataset { Dataset() }

    /// Zwiększony zestaw wiadomości do testu paginacji (etap 05: 50–100 wiadomości).
    public static func longThreadMessageCount(_ count: Int = 80) -> [Message] {
        var result: [Message] = []
        for index in 0..<count {
            let isIncoming = index % 3 != 2
            let sequence = index + 1
            let minute = index % 60
            let hour = 8 + (index / 60)
            result.append(
                Message(
                    id: MessageID("msg-long-\(sequence)"),
                    threadID: olenaThread,
                    direction: isIncoming ? .incoming : .outgoing,
                    authorID: isIncoming ? nil : .tomasz,
                    authorLabel: isIncoming ? "Olena Kovalenko" : nil,
                    providerMessageID: "wamid.demo.long.\(sequence)",
                    text: isIncoming
                        ? "Повідомлення \(sequence): прошу уточнити деталі справи та надіслати документи."
                        : "Wiadomość \(sequence): potwierdzam, przygotuję odpowiedź.",
                    translation: isIncoming
                        ? "Wiadomość \(sequence): proszę o doprecyzowanie szczegółów sprawy i przesłanie dokumentów."
                        : nil,
                    sentAt: instant(referenceDay, String(format: "%02d:%02d", min(hour, 23), minute)),
                    sequence: sequence,
                    transport: isIncoming ? .delivered : .read,
                    source: .demoFixture
                )
            )
        }
        return result
    }
}
