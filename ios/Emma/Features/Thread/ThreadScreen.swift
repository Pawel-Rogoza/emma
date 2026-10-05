import SwiftUI

// MARK: - Wątek rozmowy
//
// Port `chatPage()`, `chatHeader()` i `chatComposer()`. Zasady, które ten ekran
// respektuje:
//   • wejście w wątek przesuwa kursor odczytu tylko do przodu (`ReadStatePolicy`),
//   • dyktowanie wpisuje tekst do szkicu i **nigdy** nie wysyła,
//   • wysyłka tworzy wiadomość oczekującą z kluczem idempotencji — demo nie udaje,
//     że WhatsApp dostarczył cokolwiek.
//
// Audyt 29.09.2026: szkic zapisywał się przez `dependencies.perform` przy każdej
// literze. `perform` podbija `dataVersion`, więc każda litera przeładowywała
// wątek (szkielet ładowania, utrata klawiatury) i wszystkie zakładki, a poza
// Demo — gdzie backend nie ma jeszcze zapisu szkicu — kończyła się komunikatem
// błędu. Pole było też aktualizowane asynchronicznie, więc szybkie pisanie
// gubiło litery. Teraz: pole zmienia się od razu, szkic zapisuje się po chwili
// ciszy i **bez** ogłaszania zmiany danych, a ponowne wczytanie nie zdejmuje
// wątku z ekranu i nie gubi separatora „Nowe wiadomości”.

@MainActor
final class ThreadStore: ObservableObject {

    struct Model {
        var thread: ConversationThread
        var client: Client
        var legalCase: LegalCase?
        var messages: [Message]
        var firstUnreadID: MessageID?
        var draft: Draft
        var loadEarlierAvailable: Bool
        /// Okno 24 h WhatsApp: po nim zwykła wiadomość zostanie odrzucona.
        var replyWindow: ReplyWindow

        /// Po polsku albo po rosyjsku — wg tego, jak klient pisze (`ReplyLanguage`).
        var replyLanguage: LanguageCode {
            ReplyLanguage.forReply(clientLanguage: client.language, messages: messages)
        }
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle
    @Published private(set) var isDictating = false
    @Published private(set) var dictationNotice: String?
    /// Emma pisze szkic odpowiedzi (model tekstowy na serwerze).
    @Published private(set) var isDraftingWithEmma = false

    private let pageSize = 30
    private var snapshotSequence: Int = 0
    /// Separator „Nowe wiadomości” z pierwszego wczytania — kolejne (po zapisie)
    /// widzą już przesunięty kursor i zgubiłyby go.
    private var initialFirstUnreadID: MessageID?
    private var hasOpened = false
    /// Odłożony zapis szkicu (po chwili bez pisania).
    private var draftSaveTask: Task<Void, Never>?
    private var pendingDraft: Draft?
    private var isSending = false
    private weak var dependencies: AppDependencies?
    private var state: ThreadUserState?
    private var dictationTarget: DictationTarget?
    private var previousDictationHandler: ((DictationTarget, String) -> Void)?
    private var previousFailureHandler: ((DictationFailure) -> Void)?

    func load(_ dependencies: AppDependencies, threadID: ThreadID) async {
        self.dependencies = dependencies
        // Ponowne wczytanie (po zapisie) nie zdejmuje wątku z ekranu.
        if !phase.hasLoaded { phase = .loading }
        // Szkic w drodze zapisujemy przed odczytem — inaczej odczyt przywróciłby starszy.
        await flushDraft()
        do {
            let repository = dependencies.repository
            let userID = dependencies.currentUser.id
            // Stan odczytu i wiadomości nie zależą od osoby — pytamy o nie od
            // razu, równolegle z wątkiem (05.10.2026). Wcześniej siedem zapytań
            // szło po kolei i otwarcie rozmowy trwało sekundę albo dwie.
            async let statesTask = repository.readStates(userID: userID)
            async let messagesTask = repository.latestMessages(threadID: threadID, limit: pageSize)
            let thread: ConversationThread
            let client: Client
            if let known = try await repository.thread(id: threadID) {
                guard let person = try await repository.client(id: known.clientID) else {
                    phase = .failed(ScreenLoad.failure(for: DomainError.notFound(resource: "klient", id: known.clientID.rawValue), fallback: "Nie znaleziono klienta."))
                    return
                }
                thread = known
                client = person
            } else if let contact = try await repository.unassignedConversations().first(where: { $0.threadID == threadID }) {
                // Rozmówca spoza kartoteki — ten sam wątek, ta sama odpowiedź (03.10.2026).
                thread = .whatsAppContact(contact)
                client = .whatsAppContact(contact, createdAt: dependencies.today)
            } else {
                phase = .failed(ScreenLoad.failure(for: DomainError.notFound(resource: "rozmowa", id: threadID.rawValue), fallback: "Nie znaleziono rozmowy."))
                return
            }
            async let caseTask = Self.legalCase(of: client, repository: repository)
            let states = try await statesTask
            var threadState = states.first { $0.threadID == threadID }
                ?? ThreadUserState(userID: userID, threadID: threadID)

            let messages = try await messagesTask
            let sorted = MessageOrdering.sorted(messages)
            snapshotSequence = sorted.map(\.sequence).max() ?? 0

            // Separator „Nowe wiadomości” liczony wobec stanu **sprzed** otwarcia —
            // raz, przy pierwszym wczytaniu tego ekranu.
            if !hasOpened {
                initialFirstUnreadID = ReadStatePolicy.firstUnreadMessageID(in: sorted, state: threadState)
                hasOpened = true
            }
            let firstUnread = initialFirstUnreadID
            // Repozytorium ma już zapisany szkic (flush wyżej) i ewentualny cytat
            // ustawiony z opcji wiadomości; tekst bierzemy z pola, bo mógł się
            // zmienić w trakcie odczytu.
            var draft = threadState.draft ?? Draft(
                threadID: threadID,
                text: "",
                language: ReplyLanguage.forReply(clientLanguage: client.language, messages: sorted)
            )

            // Otwarcie wątku odnotowuje odczyt: kursor nigdy się nie cofa.
            threadState.readCursorSequence = ReadStatePolicy.cursorAfterOpeningThread(
                current: threadState.readCursorSequence,
                snapshotSequenceAtOpen: snapshotSequence
            )
            threadState.manualUnread = false
            state = threadState
            let legalCase = try await caseTask

            // Ostatni odczyt pola — po wszystkich `await`, żeby nie zgubić liter.
            if let localText = phase.value?.draft.text { draft.text = localText }
            phase = .loaded(
                Model(
                    thread: thread,
                    client: client,
                    legalCase: legalCase,
                    messages: sorted,
                    firstUnreadID: firstUnread,
                    draft: draft,
                    loadEarlierAvailable: sorted.count >= pageSize,
                    replyWindow: ReplyWindow.state(
                        sortedMessages: sorted,
                        now: dependencies.clock.now(),
                        isComplete: sorted.count < pageSize
                    )
                )
            )
            // Odczyt zapisujemy, gdy rozmowa jest już na ekranie — to dwa
            // zapytania, na które adwokat nie musi czekać.
            if let saved = try? await repository.saveReadState(threadState) {
                // Szkic w stanie zmienia tylko `flushDraft` — nie nadpisujemy go.
                var merged = saved
                merged.draft = state?.draft ?? saved.draft
                state = merged
            }
            dependencies.refreshUnreadTotal()
            applyPendingDraft(dependencies, threadID: threadID)
            if dependencies.pendingEmmaDraftThreadID == threadID {
                dependencies.pendingEmmaDraftThreadID = nil
                await draftWithEmma(dependencies)
            }
        } catch {
            if let message = phase.recordFailure(error, fallback: "Nie udało się wczytać rozmowy.") {
                dependencies.showToast(message)
            }
        }
    }

    /// Sprawa osoby z kartoteki; rozmówca spoza kartoteki spraw nie ma.
    private nonisolated static func legalCase(
        of client: Client,
        repository: any EmmaRepository
    ) async throws -> LegalCase? {
        guard !client.isWhatsAppContact else { return nil }
        return try await repository.caseForClient(client.id)
    }

    func loadEarlier(_ dependencies: AppDependencies) async {
        guard let model = phase.value, let oldest = model.messages.first?.sequence else { return }
        do {
            let older = try await dependencies.repository.messages(
                threadID: model.thread.id,
                before: oldest,
                limit: pageSize
            )
            // Model czytany na nowo: w trakcie odczytu mogło zmienić się pole szkicu.
            guard var updated = phase.value else { return }
            updated.messages = MessageOrdering.sorted(older + updated.messages)
            updated.loadEarlierAvailable = older.count >= pageSize
            updated.replyWindow = ReplyWindow.state(
                sortedMessages: updated.messages,
                now: dependencies.clock.now(),
                isComplete: !updated.loadEarlierAvailable
            )
            phase = .loaded(updated)
        } catch {
            dictationNotice = ScreenLoad.message(for: error, fallback: "Nie udało się wczytać starszych wiadomości.")
        }
    }

    // MARK: Odświeżanie na żywo

    /// Dociąga najnowsze wiadomości otwartego wątku (co kilkanaście sekund).
    /// Wcześniej odpowiedź klienta pojawiała się dopiero po wyjściu i ponownym
    /// wejściu w rozmowę. Nie pokazuje szkieletu ładowania, nie rusza pola
    /// wiadomości ani separatora „Nowe wiadomości”; błąd sieci po prostu czeka
    /// na następną próbę. Nowa wiadomość przesuwa kursor odczytu — rozmowa
    /// jest otwarta, więc klient jest „przeczytany”.
    func refreshLatest(_ dependencies: AppDependencies) async {
        guard !isSending, let threadID = phase.value?.thread.id else { return }
        guard let fresh = try? await dependencies.repository.latestMessages(threadID: threadID, limit: pageSize) else {
            return
        }
        // Model czytany na nowo — w trakcie odczytu mogło zmienić się pole.
        guard var model = phase.value, !isSending else { return }
        let merged = MessageOrdering.merged(model.messages, with: fresh)
        let window = ReplyWindow.state(
            sortedMessages: merged,
            now: dependencies.clock.now(),
            isComplete: !model.loadEarlierAvailable
        )
        guard merged != model.messages || window != model.replyWindow else { return }
        model.messages = merged
        model.replyWindow = window
        phase = .loaded(model)

        let highest = merged.map(\.sequence).max() ?? 0
        guard highest > snapshotSequence, var threadState = state else { return }
        snapshotSequence = highest
        // Szkic w drodze najpierw — zapis stanu nie może przywrócić starszego.
        await flushDraft()
        threadState = state ?? threadState
        threadState.readCursorSequence = ReadStatePolicy.cursorAfterOpeningThread(
            current: threadState.readCursorSequence,
            snapshotSequenceAtOpen: highest
        )
        threadState.manualUnread = false
        state = (try? await dependencies.repository.saveReadState(threadState)) ?? threadState
        dependencies.refreshUnreadTotal()
    }

    // MARK: Szkic

    /// Zmiana treści z pola — natychmiast w modelu, zapis po 0,6 s ciszy.
    func setDraftText(_ text: String) {
        guard var model = phase.value, model.draft.text != text else { return }
        model.draft.text = text
        model.draft.updatedAt = dependencies?.clock.now() ?? Date()
        phase = .loaded(model)
        scheduleDraftSave(model.draft, delay: 600_000_000)
    }

    /// Szkic od Emmy („napisz Zenonowi, że…”) albo ze skrótu „Odpowiedz”.
    /// Pusty szkic zastępuje; pisany tekst zostaje, a propozycja dochodzi
    /// pod nim — nic, co adwokat zaczął pisać, nie znika.
    func applyPendingDraft(_ dependencies: AppDependencies, threadID: ThreadID) {
        guard let seed = dependencies.pendingThreadDraft, seed.threadID == threadID,
              let model = phase.value else { return }
        dependencies.pendingThreadDraft = nil
        let current = model.draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        setDraftText(current.isEmpty ? seed.text : "\(model.draft.text)\n\n\(seed.text)")
    }

    /// Szkic odpowiedzi od Emmy prosto w polu (02.10.2026). Wcześniej przycisk
    /// przerzucał na zakładkę Emmy, która wstawiała szablon niezwiązany z tym,
    /// o co pytał klient. Teraz model czyta rozmowę na serwerze i pisze po
    /// polsku albo po rosyjsku. Bez modelu (Demo, starszy serwer) — gotowa
    /// odpowiedź „Otrzymaliśmy” w języku klienta. Nic nie wysyła się samo.
    func draftWithEmma(_ dependencies: AppDependencies) async {
        guard !isDraftingWithEmma, let model = phase.value else { return }
        isDraftingWithEmma = true
        defer { isDraftingWithEmma = false }
        let text: String
        do {
            text = try await dependencies.repository.draftReply(threadID: model.thread.id)
        } catch {
            text = QuickReplies.templates(for: model.replyLanguage).last?.text ?? ""
            if !dependencies.configuration.usesMockServices {
                dependencies.showToast(ScreenLoad.message(for: error, fallback: "Emma nie przygotowała szkicu — wstawiłam gotową odpowiedź."))
            }
        }
        guard !text.isEmpty, let current = phase.value else { return }
        EmmaHaptics.success()
        let typed = current.draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        await replaceDraftText(typed.isEmpty ? text : "\(current.draft.text)\n\n\(text)")
    }

    /// Gotowa odpowiedź albo dyktowanie — zapis bez czekania.
    func replaceDraftText(_ text: String) async {
        setDraftText(text)
        await flushDraft()
    }

    func clearQuote(_ dependencies: AppDependencies) async {
        guard var model = phase.value else { return }
        model.draft.quote = nil
        phase = .loaded(model)
        // Zapisujemy szkic zawsze, także pusty: `saveDraft(nil)` nic nie zmienia
        // w repozytorium, więc cytat wracał po najbliższym odświeżeniu.
        scheduleDraftSave(model.draft, delay: 0)
        await flushDraft()
    }

    private func scheduleDraftSave(_ draft: Draft, delay: UInt64) {
        pendingDraft = draft
        draftSaveTask?.cancel()
        guard delay > 0 else { return }
        draftSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.flushDraft()
        }
    }

    /// Zapis szkicu **bez** `dataChanged()`: to stan pola, nie zmiana danych
    /// kancelarii. Błąd zapisu (backend jeszcze nie przyjmuje szkiców) nie może
    /// kończyć się komunikatem przy każdej literze — tekst zostaje w polu.
    func flushDraft() async {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        guard let draft = pendingDraft, let dependencies else { return }
        pendingDraft = nil
        try? await dependencies.repository.saveDraft(draft)
        if var threadState = state {
            threadState.draft = draft
            state = threadState
        }
    }

    // MARK: Wysyłka

    func send(_ dependencies: AppDependencies) async {
        // Podwójne dotknięcie „Wyślij” nie może wysłać dwóch wiadomości
        // (każda próba ma własny klucz idempotencji).
        guard !isSending, var model = phase.value else { return }
        let text = model.draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Po 24 h WhatsApp i tak odrzuci zwykłą wiadomość — nie udajemy wysyłki.
        guard !text.isEmpty, !model.replyWindow.isClosed else { return }
        isSending = true
        defer { isSending = false }

        let client = model.client
        let draft = model.draft
        let key = UUID().uuidString
        // Odłożony zapis nie może przywrócić wysłanego tekstu jako szkicu.
        draftSaveTask?.cancel()
        draftSaveTask = nil
        pendingDraft = nil

        let sent = await dependencies.perform {
            let message = try await dependencies.repository.appendOutgoing(
                OutgoingMessageDraft(
                    threadID: model.thread.id,
                    text: text,
                    quote: draft.quote,
                    authorID: dependencies.currentUser.id,
                    language: model.replyLanguage,
                    sentAt: dependencies.clock.now(),
                    idempotencyKey: key
                )
            )
            // Repozytorium samo czyści szkic nadawcy przy przyjęciu wiadomości.
            // Oznaczenie klienta jako obsłużonego jest dodatkiem: jego błąd
            // (np. konflikt wersji) nie może zgłaszać, że wysyłka się nie udała.
            // Rozmówcy spoza kartoteki nie ma czego oznaczać.
            var updatedClient = client
            if !client.isWhatsAppContact, updatedClient.needsReply || updatedClient.stage == .new {
                updatedClient.needsReply = false
                if updatedClient.stage == .new { updatedClient.stage = .inContact }
                _ = try? await dependencies.repository.updateClient(
                    updatedClient,
                    expectedVersion: client.version
                )
            }
            return message
        }

        guard let sent else { return }
        EmmaHaptics.success()
        // Model czytany na nowo — w trakcie wysyłki mogło przyjść odświeżenie.
        model = phase.value ?? model
        // Odświeżenie mogło już przynieść tę wiadomość — bez dubla w `ForEach`.
        if !model.messages.contains(where: { $0.id == sent.id }) {
            model.messages = MessageOrdering.sorted(model.messages + [sent])
        }
        model.draft = Draft(threadID: model.thread.id, text: "", language: model.replyLanguage)
        phase = .loaded(model)
        if var threadState = state {
            threadState.draft = nil
            state = threadState
        }
        dependencies.refreshUnreadTotal()
    }

    // MARK: Kartoteka

    /// Rozmówca spoza kartoteki trafia do „Nowych” razem z całą rozmową.
    /// Zapis ogłasza zmianę danych, więc wątek wczyta się już z osobą.
    func addToLeads(_ dependencies: AppDependencies) async {
        guard let model = phase.value, model.client.isWhatsAppContact else { return }
        let threadID = model.thread.id
        let created: Void? = await dependencies.perform {
            try await dependencies.repository.createLead(fromThread: threadID)
        }
        guard created != nil else { return }
        EmmaHaptics.success()
        dependencies.showToast("\(model.client.displayName) jest w „Nowych”")
    }

    // MARK: Dyktowanie

    func toggleDictation(_ dependencies: AppDependencies) async {
        if isDictating {
            await dependencies.voice.finishDictation()
            isDictating = false
            return
        }
        guard let model = phase.value else { return }
        let target = DictationTarget.threadDraft(
            threadID: model.thread.id,
            draftVersion: .initial
        )
        dictationTarget = target
        previousDictationHandler = dependencies.voice.onDictationResult
        previousFailureHandler = dependencies.voice.onDictationFailure
        dependencies.voice.onDictationResult = { [weak self] receivedTarget, text in
            guard let self else { return }
            // Wynik trafia do zamrożonego celu, nawet jeśli użytkownik zmienił ekran.
            guard receivedTarget == target else { return }
            Task { @MainActor in
                self.isDictating = false
                await self.appendDictated(text, dependencies: dependencies)
            }
        }
        dependencies.voice.onDictationFailure = { [weak self] failure in
            Task { @MainActor in
                self?.isDictating = false
                self?.dictationNotice = failure.safeMessage
            }
        }
        isDictating = true
        dictationNotice = "Dyktowanie wpisuje tekst do szkicu. Nic nie wyśle się samo."
        await dependencies.voice.startDictation(
            target: target,
            language: model.replyLanguage,
            service: dependencies.makeDictationService()
        )
    }

    private func appendDictated(_ text: String, dependencies: AppDependencies) async {
        guard let model = phase.value else { return }
        let current = model.draft.text
        await replaceDraftText(current.isEmpty ? text : current + " " + text)
    }

    func teardown(_ dependencies: AppDependencies) async {
        // Wyjście z wątku zapisuje to, co zostało w polu.
        await flushDraft()
        dependencies.voice.onDictationResult = previousDictationHandler
        dependencies.voice.onDictationFailure = previousFailureHandler
        if isDictating {
            await dependencies.voice.cancelDictation()
            isDictating = false
        }
    }
}

struct ThreadScreen: View {

    let threadID: ThreadID

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout: EmmaLayoutMetrics
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var store = ThreadStore()
    /// Koniec historii jest na ekranie — nowa wiadomość może przewinąć w dół.
    /// Na starcie `false`: ustawia go dopiero widoczny znacznik końca, więc
    /// otwarcie od pierwszej nowej wiadomości od razu pokazuje „na dół”.
    @State private var isAtBottom = false
    /// Wiadomości, które przyszły, gdy historia była przewinięta w górę.
    @State private var unseenCount = 0
    @State private var showsContactActions = false

    /// Co ile sekund otwarty wątek pyta o nowe wiadomości.
    private static let liveRefreshSeconds: UInt64 = 15

    var body: some View {
        VStack(spacing: 0) {
            switch store.phase {
            case .idle, .loading:
                LoadingState("Wczytuję rozmowę…")
                    .frame(maxHeight: .infinity)
            case .failed(let failure):
                LoadFailureView(failure) {
                    Task { await store.load(dependencies, threadID: threadID) }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            case .loaded(let model):
                header(model)
                contextStrip(model)
                transcript(model)
                composer(model)
            }
        }
        .background(EmmaTheme.chatBackground)
        .navigationBarBackButtonHidden(true)
        .emmaPreservesSwipeBack()
        .task(id: dependencies.dataVersion) { await store.load(dependencies, threadID: threadID) }
        // Rozmowa już otwarta, a Emma podsuwa szkic — bez ponownego wczytania.
        .onChange(of: dependencies.pendingThreadDraft) { _, _ in
            store.applyPendingDraft(dependencies, threadID: threadID)
        }
        // Odpowiedź klienta pojawia się w otwartej rozmowie sama.
        .task(id: threadID) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.liveRefreshSeconds * 1_000_000_000)
                guard !Task.isCancelled, scenePhase == .active else { continue }
                await store.refreshLatest(dependencies)
            }
        }
        .onDisappear {
            Task { await store.teardown(dependencies) }
        }
    }

    // MARK: Nagłówek

    @ViewBuilder
    private func header(_ model: ThreadStore.Model) -> some View {
        HStack(spacing: 6) {
            Button {
                dependencies.back()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(EmmaTheme.ink)
                    .frame(width: EmmaSpacing.hitTarget, height: EmmaSpacing.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wróć do rozmów")

            Button {
                if model.client.isWhatsAppContact {
                    showsContactActions = true
                } else {
                    dependencies.openPerson(model.client.id)
                }
            } label: {
                HStack(spacing: 10) {
                    ChatAvatar(client: model.client, diameter: EmmaMetrics.threadHeaderAvatar)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.client.displayName)
                            .font(EmmaTypography.chatHeader)
                            .foregroundStyle(EmmaTheme.ink)
                        // Numer zamiast języka: od razu widać, z jakiego numeru ktoś pisze
                        // i czy kartoteka przypisała go właściwej osobie (02.10.2026).
                        Text("WhatsApp · \(model.client.phone ?? model.client.language.displayName)")
                            .font(EmmaTypography.caption())
                            .foregroundStyle(EmmaTheme.mutedSoft)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.client.isWhatsAppContact
                ? "Kontakt \(model.client.displayName)"
                : "Karta klienta \(model.client.displayName)")
            .confirmationDialog(model.client.displayName, isPresented: $showsContactActions, titleVisibility: .visible) {
                Button("Dodaj do „Nowych”") {
                    Task { await store.addToLeads(dependencies) }
                }
                if let url = model.client.phone.flatMap(ContactLinks.whatsAppURL) {
                    Button("Otwórz w WhatsApp") { openURL(url) }
                }
                if let url = model.client.phone.flatMap(ContactLinks.phoneURL) {
                    Button("Zadzwoń") { openURL(url) }
                }
                Button("Anuluj", role: .cancel) {}
            } message: {
                Text("Tego numeru nie ma jeszcze w kartotece.")
            }

            Button {
                dependencies.present(.conversationOptions(model.thread.id))
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(EmmaTheme.muted)
                    .frame(width: EmmaSpacing.hitTarget, height: EmmaSpacing.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Opcje rozmowy")
        }
        .padding(.horizontal, layout.threadHorizontalPadding)
        .padding(.vertical, 6)
        .background(EmmaTheme.chatDockBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EmmaTheme.chatHeaderBorder).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func contextStrip(_ model: ThreadStore.Model) -> some View {
        if model.client.isWhatsAppContact {
            contactStrip(model)
        } else {
            caseStrip(model)
        }
    }

    /// Rozmówca spoza kartoteki: rozmowa działa normalnie, a jednym dotknięciem
    /// numer trafia do „Nowych” razem z historią.
    private func contactStrip(_ model: ThreadStore.Model) -> some View {
        Button {
            EmmaHaptics.tap()
            Task { await store.addToLeads(dependencies) }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 13))
                Text("Numeru nie ma w kartotece · Dodaj do „Nowych”")
                    .font(EmmaTypography.caption())
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "plus.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(EmmaTheme.contextStripText)
            .padding(.horizontal, layout.threadHorizontalPadding)
            .frame(minHeight: 38)
            .background(EmmaTheme.contextStripBackground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(EmmaTheme.contextStripBorder).frame(height: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dodaj \(model.client.displayName) do Nowych")
    }

    private func caseStrip(_ model: ThreadStore.Model) -> some View {
        Button {
            if let legalCase = model.legalCase {
                dependencies.openCase(legalCase.id)
            } else {
                dependencies.openPerson(model.client.id)
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                Text(model.legalCase?.title ?? model.client.topic)
                    .font(EmmaTypography.caption())
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(EmmaTheme.contextStripText)
            .padding(.horizontal, layout.threadHorizontalPadding)
            .frame(minHeight: 38)
            .background(EmmaTheme.contextStripBackground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(EmmaTheme.contextStripBorder).frame(height: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Powiązana sprawa: \(model.legalCase?.title ?? model.client.topic)")
    }

    // MARK: Historia

    private static let bottomAnchor = "thread-bottom"

    /// Historia (przebudowa 03.10.2026): wiadomości jednej strony sklejają się
    /// w grupy, tło ma cichy wzór, otwarcie z nowymi zaczyna od pierwszej nowej,
    /// a gdy historia jest przewinięta w górę, nowa wiadomość jej nie szarpie —
    /// pojawia się przycisk „na dół” z licznikiem.
    @ViewBuilder
    private func transcript(_ model: ThreadStore.Model) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.loadEarlierAvailable {
                        Button("Wczytaj starsze wiadomości") {
                            Task { await store.loadEarlier(dependencies) }
                        }
                        .font(EmmaTypography.caption(.medium))
                        .foregroundStyle(EmmaTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: EmmaSpacing.hitTarget)
                        .accessibilityHint("Dociąga wcześniejsze wiadomości z historii")
                    }

                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        let day = AppDependencies.localDate(from: message.sentAt)
                        let previousDay = index > 0
                            ? AppDependencies.localDate(from: model.messages[index - 1].sentAt)
                            : nil
                        let position = ChatLayout.position(at: index, in: model.messages)
                        if day != previousDay {
                            ChatDaySeparator(text: dependencies.dateText.dayLabel(day))
                        }
                        if message.id == model.firstUnreadID {
                            UnreadDivider().id("unread-divider")
                        }
                        MessageBubble(
                            message: message,
                            senderLabel: message.outgoingAuthorLabel,
                            position: position,
                            attachmentActions: attachmentActions(for: message, model: model),
                            onOpenWhatsApp: whatsAppAction(model)
                        ) {
                            // Najpierw zapis pisanego tekstu: arkusz dopisuje cytat
                            // do szkicu z repozytorium i nie może go potem zgubić.
                            Task {
                                await store.flushDraft()
                                dependencies.present(.messageOptions(threadID: model.thread.id, messageID: message.id))
                            }
                        }
                        .padding(.top, position.startsGroup ? 8 : 2)
                        .id(message.id)
                        // Nowa wiadomość wjeżdża od swojej strony (audyt 29.09.2026).
                        .transition(.asymmetric(
                            insertion: .move(edge: message.isOutgoing ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .opacity
                        ))
                    }

                    // Koniec historii: widoczny — jesteśmy na dole.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                        .onAppear {
                            isAtBottom = true
                            unseenCount = 0
                        }
                        .onDisappear { isAtBottom = false }
                }
                .animation(EmmaMotion.smooth, value: model.messages.count)
                .padding(.horizontal, layout.threadHorizontalPadding)
                .padding(.top, 6)
                .padding(.bottom, EmmaSpacing.chatScrollBottomInset)
            }
            .scrollIndicators(.hidden)
            .background(ChatWallpaper())
            .overlay(alignment: .bottomTrailing) {
                if !isAtBottom {
                    JumpToLatestButton(newCount: unseenCount) {
                        EmmaHaptics.tap()
                        withAnimation(EmmaMotion.smooth) {
                            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                        }
                    }
                    .padding(.trailing, layout.threadHorizontalPadding)
                    .padding(.bottom, 6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(EmmaMotion.snappy, value: isAtBottom)
            .onAppear {
                // Z nowymi wiadomościami — od pierwszej nowej, jak w WhatsAppie.
                if model.firstUnreadID != nil {
                    proxy.scrollTo("unread-divider", anchor: .top)
                } else {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
            // Po wysłaniu historia jedzie na dół — wysłana wiadomość nie może
            // wylądować pod klawiaturą. Odpowiedź klienta przewija tylko wtedy,
            // gdy jesteśmy na dole; wyżej czytany fragment zostaje na miejscu.
            .onChange(of: model.messages.last?.id) { _, last in
                guard last != nil, let newest = model.messages.last else { return }
                if isAtBottom || newest.isOutgoing {
                    withAnimation(EmmaMotion.smooth) {
                        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                    }
                } else {
                    unseenCount += 1
                }
            }
        }
    }

    /// Rozmowa w aplikacji WhatsApp (Business) — tam, gdzie Emma nie może:
    /// po 24 h, przy niewysłanej wiadomości i przy treści, której API nie oddaje.
    private func whatsAppAction(_ model: ThreadStore.Model) -> (() -> Void)? {
        guard let url = model.client.phone.flatMap(ContactLinks.whatsAppURL) else { return nil }
        return { openURL(url) }
    }

    // MARK: Pliki od klienta

    /// Zdjęcie wezwania czy PDF postanowienia: do akt jednym dotknięciem,
    /// a termin liczony od dnia, w którym plik przyszedł (doręczenie).
    /// Rozmówca spoza kartoteki nie ma akt — zostaje WhatsApp i Mapy.
    private func attachmentActions(for message: Message, model: ThreadStore.Model) -> AttachmentActions? {
        guard message.kind.isAttachment, !message.isOutgoing else { return nil }
        let day = AppDependencies.localDate(from: message.sentAt)
        let client = model.client
        let caseID = model.legalCase?.id
        var actions = AttachmentActions()
        actions.openInWhatsApp = whatsAppAction(model)
        if message.kind == .location, let place = message.caption, let url = ContactLinks.mapsURL(place) {
            actions.openInMaps = { openURL(url) }
        }
        guard !client.isWhatsAppContact else { return actions }
        if message.kind.mayBeLegalDocument {
            actions.countDeadline = {
                dependencies.pendingEventDraft = EventDraftSeed(deadlineFrom: day)
                dependencies.present(.eventForm(editing: nil, clientID: client.id, caseID: caseID, initialDay: nil))
            }
        }
        actions.addToCase = {
            Task { await addAttachmentNote(message, day: day, client: client, caseID: caseID) }
        }
        return actions
    }

    private func addAttachmentNote(_ message: Message, day: LocalDate, client: Client, caseID: CaseID?) async {
        let text = message.caseNoteText(clientName: client.displayName, dateText: dependencies.dateText.dayTitle(day))
        let outcome = await dependencies.submit(fallback: "Nie udało się dodać notatki.") {
            try await dependencies.repository.addNote(NewNoteDraft(
                clientID: client.id,
                caseID: caseID,
                text: text,
                authorID: dependencies.currentUser.id,
                createdAt: dependencies.today
            ))
        }
        if outcome.value != nil {
            EmmaHaptics.success()
            dependencies.showToast(caseID == nil ? "Dodano do notatek klienta" : "Dodano do akt sprawy")
        } else if let message = outcome.errorMessage {
            dependencies.showToast(message)
        }
    }

    // MARK: Pole wiadomości

    /// „Emma” — szkic odpowiedzi z treści rozmowy (model na serwerze), w języku
    /// odpowiedzi (PL/RU). Podczas pisania kręciołek zamiast iskierki.
    private func emmaDraftChip(_ model: ThreadStore.Model) -> some View {
        Button {
            EmmaHaptics.tap()
            Task { await store.draftWithEmma(dependencies) }
        } label: {
            HStack(spacing: 6) {
                if store.isDraftingWithEmma {
                    ProgressView().controlSize(.mini).tint(EmmaTheme.primaryButtonText)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(store.isDraftingWithEmma ? "Emma pisze…" : "Odpowiedz z Emmą")
                    .font(EmmaTypography.caption(.semibold))
                Text(model.replyLanguage == .ru ? "RU" : "PL")
                    .font(EmmaTypography.caption(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(EmmaTheme.primaryButtonText.opacity(0.18), in: Capsule())
            }
            .foregroundStyle(EmmaTheme.primaryButtonText)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(EmmaTheme.primaryButton, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .frame(minHeight: EmmaSpacing.hitTarget)
        .disabled(store.isDraftingWithEmma)
        .accessibilityLabel(store.isDraftingWithEmma ? "Emma pisze odpowiedź" : "Odpowiedz z Emmą")
        .accessibilityHint(model.replyLanguage == .ru
            ? "Emma przygotuje szkic po rosyjsku z treści rozmowy. Nic nie wysyła."
            : "Emma przygotuje szkic po polsku z treści rozmowy. Nic nie wysyła.")
    }

    @ViewBuilder
    private func composer(_ model: ThreadStore.Model) -> some View {
        VStack(spacing: 8) {
            replyWindowNotice(model)

            if let quote = model.draft.quote {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(EmmaTheme.quoteRule)
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Odpowiedź · \(quote.authorLabel)")
                            .font(EmmaTypography.caption(.semibold))
                            .foregroundStyle(EmmaTheme.quoteRule)
                        Text(quote.text)
                            .font(EmmaTypography.quotedText(quote.text))
                            .foregroundStyle(EmmaTheme.muted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Task { await store.clearQuote(dependencies) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(EmmaTheme.muted)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Anuluj odpowiedź na wiadomość")
                }
                .padding(9)
                .background(EmmaTheme.quoteBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Gotowe odpowiedzi w języku klienta — tylko przy pustym szkicu,
            // żeby nie zasłaniały pisanej wiadomości (audyt 28.09.2026).
            // Emma jest pierwszym chipem (02.10.2026): wcześniej osobny pasek nad
            // chipami robił z dołu ekranu trzy piętra i zabierał miejsce rozmowie.
            if model.draft.text.isEmpty && model.draft.quote == nil && !model.replyWindow.isClosed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        emmaDraftChip(model)
                        ForEach(QuickReplies.templates(for: model.replyLanguage)) { reply in
                            Button {
                                EmmaHaptics.selection()
                                Task { await store.replaceDraftText(reply.text) }
                            } label: {
                                Text(reply.label)
                                    .font(EmmaTypography.caption(.medium))
                                    .foregroundStyle(EmmaTheme.secondaryButtonText)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 32)
                                    .background(EmmaTheme.surface, in: Capsule())
                                    .overlay { Capsule().strokeBorder(EmmaTheme.composerBorder, lineWidth: 1) }
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(EmmaCardButtonStyle())
                            .frame(minHeight: EmmaSpacing.hitTarget)
                            .accessibilityLabel("Wstaw odpowiedź: \(reply.label)")
                            .accessibilityHint("Wstawia gotowy tekst w języku klienta. Nic nie wysyła.")
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Pole jednoliniowe, które rośnie razem z treścią (1–6 linii).
                // Wcześniej `TextEditor` startował od 40 pt i wyglądał jak pusty,
                // wysoki prostokąt, nawet gdy szkic był pusty.
                TextField(
                    "Napisz wiadomość…",
                    text: Binding(
                        get: { model.draft.text },
                        set: { newValue in store.setDraftText(newValue) }
                    ),
                    axis: .vertical
                )
                .lineLimit(1...6)
                .font(EmmaTypography.composerField)
                .foregroundStyle(EmmaTheme.ink)
                .frame(minHeight: 40, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(EmmaTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.composer, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: EmmaRadii.composer, style: .continuous)
                        .strokeBorder(EmmaTheme.composerBorder, lineWidth: 1)
                }
                .accessibilityLabel("Wiadomość do \(model.client.displayName)")

                Button {
                    Task { await store.toggleDictation(dependencies) }
                } label: {
                    Image(systemName: store.isDictating ? "stop.circle.fill" : "mic")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(store.isDictating ? EmmaTheme.dictationAccent : EmmaTheme.secondaryButtonText)
                        .frame(width: EmmaMetrics.composerIconButton, height: EmmaMetrics.composerIconButton)
                        .background(EmmaTheme.surface)
                        .clipShape(Circle())
                        .overlay {
                            Circle().strokeBorder(EmmaTheme.composerBorder, lineWidth: 1)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isDictating ? "Zakończ dyktowanie" : "Podyktuj wiadomość")

                Button {
                    // Lekkie stuknięcie od razu, „sukces” dopiero po przyjęciu
                    // wiadomości (wcześniej wibrował sukces także przy błędzie).
                    EmmaHaptics.tap()
                    Task { await store.send(dependencies) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolEffect(.bounce, value: hasSendableDraft(model))
                        .foregroundStyle(hasSendableDraft(model) ? EmmaTheme.primaryButtonText : EmmaTheme.disabledButtonText)
                        .frame(width: EmmaMetrics.micButtonSize, height: EmmaMetrics.micButtonSize)
                        .background(hasSendableDraft(model) ? EmmaTheme.primaryButton : EmmaTheme.disabledButton)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(EmmaCardButtonStyle())
                .animation(EmmaMotion.snappy, value: hasSendableDraft(model))
                .disabled(!hasSendableDraft(model))
                .accessibilityLabel("Wyślij wiadomość")
            }

            if let notice = store.dictationNotice {
                Text(notice)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, layout.threadHorizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, EmmaSpacing.listBottomInset)
        // Gotowe odpowiedzi i cytat pojawiają się płynnie, a nie skokiem.
        .animation(EmmaMotion.smooth, value: model.draft.text.isEmpty)
        .animation(EmmaMotion.smooth, value: model.draft.quote != nil)
        .animation(EmmaMotion.smooth, value: model.replyWindow)
        .background(EmmaTheme.chatDockBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(EmmaTheme.chatHeaderBorder).frame(height: 0.5)
        }
    }

    private func hasSendableDraft(_ model: ThreadStore.Model) -> Bool {
        !model.replyWindow.isClosed
            && !model.draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Okno 24 h WhatsApp

    /// Po 24 h od ostatniej wiadomości klienta WhatsApp przyjmuje tylko
    /// zatwierdzony szablon. Zamiast odrzuconej wysyłki — jasna informacja
    /// i telefon pod ręką; tekst można dalej przygotować w polu. Ostatnie
    /// 3 godziny okna — spokojne ostrzeżenie z odliczaniem.
    @ViewBuilder
    private func replyWindowNotice(_ model: ThreadStore.Model) -> some View {
        if case .closed(let since) = model.replyWindow {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(EmmaTheme.pillDangerText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(since == nil ? "Klient jeszcze nie pisał na WhatsApp" : "Minęło 24 h od wiadomości klienta")
                        .font(EmmaTypography.caption(.semibold))
                        .foregroundStyle(EmmaTheme.ink)
                    Text("Stąd WhatsApp przyjmie teraz tylko zatwierdzony szablon. Odpisz w aplikacji WhatsApp albo poczekaj, aż klient napisze.")
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // WhatsApp zamiast telefonu (03.10.2026): z aplikacji WhatsApp
                // Business na telefonie kancelarii można odpisać także po 24 h.
                if let open = whatsAppAction(model) {
                    Button {
                        EmmaHaptics.tap()
                        open()
                    } label: {
                        Label("WhatsApp", systemImage: "arrow.up.forward.app")
                            .font(EmmaTypography.caption(.semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(EmmaTheme.chatGreen, in: Capsule())
                            .frame(minHeight: EmmaSpacing.hitTarget)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(EmmaCardButtonStyle())
                    .accessibilityLabel("Otwórz rozmowę z \(model.client.displayName) w WhatsApp")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(EmmaTheme.pillDangerBackground)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous))
            .accessibilityElement(children: .contain)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                let now = dependencies.now
                if model.replyWindow.isClosingSoon(now: now),
                   let left = model.replyWindow.remainingText(now: now) {
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Okno odpowiedzi WhatsApp zamyka się za \(left)")
                            .font(EmmaTypography.caption(.medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(EmmaTheme.pillAmberText)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

#Preview("Wątek") {
    ThreadScreen(threadID: DemoFixtures.olenaThread)
        .environmentObject(AppDependencies.demo())
}
