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
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle
    @Published private(set) var isDictating = false
    @Published private(set) var dictationNotice: String?

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
            guard let thread = try await repository.thread(id: threadID) else {
                phase = .failed(ScreenLoad.failure(for: DomainError.notFound(resource: "rozmowa", id: threadID.rawValue), fallback: "Nie znaleziono rozmowy."))
                return
            }
            guard let client = try await repository.client(id: thread.clientID) else {
                phase = .failed(ScreenLoad.failure(for: DomainError.notFound(resource: "klient", id: thread.clientID.rawValue), fallback: "Nie znaleziono klienta."))
                return
            }
            let states = try await repository.readStates(userID: userID)
            var threadState = states.first { $0.threadID == threadID }
                ?? ThreadUserState(userID: userID, threadID: threadID)

            let messages = try await repository.latestMessages(threadID: threadID, limit: pageSize)
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
            var draft = threadState.draft ?? Draft(threadID: threadID, text: "", language: client.language)

            // Otwarcie wątku odnotowuje odczyt: kursor nigdy się nie cofa.
            threadState.readCursorSequence = ReadStatePolicy.cursorAfterOpeningThread(
                current: threadState.readCursorSequence,
                snapshotSequenceAtOpen: snapshotSequence
            )
            threadState.manualUnread = false
            threadState = (try? await repository.saveReadState(threadState)) ?? threadState
            state = threadState
            dependencies.refreshUnreadTotal()
            let legalCase = try await repository.caseForClient(thread.clientID)

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
        } catch {
            if let message = phase.recordFailure(error, fallback: "Nie udało się wczytać rozmowy.") {
                dependencies.showToast(message)
            }
        }
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
                    language: client.language,
                    sentAt: dependencies.clock.now(),
                    idempotencyKey: key
                )
            )
            // Repozytorium samo czyści szkic nadawcy przy przyjęciu wiadomości.
            // Oznaczenie klienta jako obsłużonego jest dodatkiem: jego błąd
            // (np. konflikt wersji) nie może zgłaszać, że wysyłka się nie udała.
            var updatedClient = client
            if updatedClient.needsReply || updatedClient.stage == .new {
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
        // Model czytany na nowo — w trakcie wysyłki mogło przyjść odświeżenie.
        model = phase.value ?? model
        // Odświeżenie mogło już przynieść tę wiadomość — bez dubla w `ForEach`.
        if !model.messages.contains(where: { $0.id == sent.id }) {
            model.messages = MessageOrdering.sorted(model.messages + [sent])
        }
        model.draft = Draft(threadID: model.thread.id, text: "", language: client.language)
        phase = .loaded(model)
        if var threadState = state {
            threadState.draft = nil
            state = threadState
        }
        dependencies.refreshUnreadTotal()
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
            language: model.client.language,
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
                dependencies.openPerson(model.client.id)
            } label: {
                HStack(spacing: 10) {
                    PersonAvatar(
                        initials: model.client.initials,
                        style: .identity(model.client.id),
                        diameter: EmmaMetrics.threadHeaderAvatar
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.client.displayName)
                            .font(EmmaTypography.chatHeader)
                            .foregroundStyle(EmmaTheme.ink)
                        Text("WhatsApp · \(model.client.language.displayName)")
                            .font(EmmaTypography.caption())
                            .foregroundStyle(EmmaTheme.mutedSoft)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Karta klienta \(model.client.displayName)")

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

    @ViewBuilder
    private func transcript(_ model: ThreadStore.Model) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
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
                        if day != previousDay {
                            ChatDaySeparator(text: dependencies.dateText.dayLabel(day))
                        }
                        if message.id == model.firstUnreadID {
                            UnreadDivider().id("unread-divider")
                        }
                        MessageBubble(
                            message: message,
                            senderLabel: message.outgoingAuthorLabel,
                            showsAuthor: true,
                            attachmentActions: attachmentActions(for: message, model: model)
                        ) {
                            // Najpierw zapis pisanego tekstu: arkusz dopisuje cytat
                            // do szkicu z repozytorium i nie może go potem zgubić.
                            Task {
                                await store.flushDraft()
                                dependencies.present(.messageOptions(threadID: model.thread.id, messageID: message.id))
                            }
                        }
                        .id(message.id)
                        // Nowa wiadomość wjeżdża od swojej strony (audyt 29.09.2026).
                        .transition(.asymmetric(
                            insertion: .move(edge: message.isOutgoing ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .animation(EmmaMotion.smooth, value: model.messages.count)
                .padding(.horizontal, layout.threadHorizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, EmmaSpacing.chatScrollBottomInset)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let last = model.messages.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            // Po wysłaniu (i po nowej wiadomości) historia jedzie na dół —
            // wcześniej przewijała się tylko przy otwarciu wątku, więc wysłana
            // wiadomość potrafiła wylądować pod klawiaturą.
            .onChange(of: model.messages.last?.id) { _, last in
                guard let last else { return }
                withAnimation(EmmaMotion.smooth) {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    // MARK: Pliki od klienta

    /// Zdjęcie wezwania czy PDF postanowienia: do akt jednym dotknięciem,
    /// a termin liczony od dnia, w którym plik przyszedł (doręczenie).
    private func attachmentActions(for message: Message, model: ThreadStore.Model) -> AttachmentActions? {
        guard message.kind.isAttachment, !message.isOutgoing else { return nil }
        let day = AppDependencies.localDate(from: message.sentAt)
        let client = model.client
        let caseID = model.legalCase?.id
        var openInWhatsApp: (() -> Void)?
        if let url = client.phone.flatMap(ContactLinks.whatsAppURL) {
            openInWhatsApp = { openURL(url) }
        }
        var countDeadline: (() -> Void)?
        if message.kind.mayBeLegalDocument {
            countDeadline = {
                dependencies.pendingEventDraft = EventDraftSeed(deadlineFrom: day)
                dependencies.present(.eventForm(editing: nil, clientID: client.id, caseID: caseID, initialDay: nil))
            }
        }
        return AttachmentActions(
            openInWhatsApp: openInWhatsApp,
            addToCase: {
                Task { await addAttachmentNote(message, day: day, client: client, caseID: caseID) }
            },
            countDeadline: countDeadline
        )
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

    @ViewBuilder
    private func composer(_ model: ThreadStore.Model) -> some View {
        VStack(spacing: 8) {
            replyWindowNotice(model)

            Button {
                dependencies.openEmma(clientID: model.client.id, action: .reply)
            } label: {
                HStack(spacing: 8) {
                    EmmaOrb(size: .small)
                    Text("Przygotuj z Emmą")
                        .font(EmmaTypography.ui(13, .medium))
                        .foregroundStyle(EmmaTheme.secondaryButtonText)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EmmaTheme.mutedSoft)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(EmmaTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous)
                        .strokeBorder(EmmaTheme.composerBorder, lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Przygotuj odpowiedź z Emmą")

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
            if model.draft.text.isEmpty && model.draft.quote == nil && !model.replyWindow.isClosed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(QuickReplies.templates(for: model.client.language)) { reply in
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
                    EmmaHaptics.success()
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
                    Text("WhatsApp przyjmie teraz tylko zatwierdzony szablon. Zadzwoń albo poczekaj, aż klient napisze.")
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let phoneURL = model.client.phone.flatMap(ContactLinks.phoneURL) {
                    Button {
                        EmmaHaptics.tap()
                        openURL(phoneURL)
                    } label: {
                        Label("Zadzwoń", systemImage: "phone.fill")
                            .font(EmmaTypography.caption(.semibold))
                            .foregroundStyle(EmmaTheme.primaryButtonText)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(EmmaTheme.primaryButton, in: Capsule())
                            .frame(minHeight: EmmaSpacing.hitTarget)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(EmmaCardButtonStyle())
                    .accessibilityLabel("Zadzwoń do \(model.client.displayName)")
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
