import SwiftUI

// MARK: - Wątek rozmowy
//
// Port `chatPage()`, `chatHeader()` i `chatComposer()`. Zasady, które ten ekran
// respektuje:
//   • wejście w wątek przesuwa kursor odczytu tylko do przodu (`ReadStatePolicy`),
//   • dyktowanie wpisuje tekst do szkicu i **nigdy** nie wysyła,
//   • wysyłka tworzy wiadomość oczekującą z kluczem idempotencji — demo nie udaje,
//     że WhatsApp dostarczył cokolwiek.

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
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle
    @Published private(set) var isDictating = false
    @Published private(set) var dictationNotice: String?

    private let pageSize = 30
    private var snapshotSequence: Int = 0
    private var state: ThreadUserState?
    private var dictationTarget: DictationTarget?
    private var previousDictationHandler: ((DictationTarget, String) -> Void)?
    private var previousFailureHandler: ((DictationFailure) -> Void)?

    func load(_ dependencies: AppDependencies, threadID: ThreadID) async {
        phase = .loading
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

            // Separator „Nowe wiadomości” liczony wobec stanu **sprzed** otwarcia.
            let firstUnread = ReadStatePolicy.firstUnreadMessageID(in: sorted, state: threadState)

            // Otwarcie wątku odnotowuje odczyt: kursor nigdy się nie cofa.
            threadState.readCursorSequence = ReadStatePolicy.cursorAfterOpeningThread(
                current: threadState.readCursorSequence,
                snapshotSequenceAtOpen: snapshotSequence
            )
            threadState.manualUnread = false
            threadState = (try? await repository.saveReadState(threadState)) ?? threadState
            state = threadState
            dependencies.refreshUnreadTotal()

            phase = .loaded(
                Model(
                    thread: thread,
                    client: client,
                    legalCase: try await repository.caseForClient(thread.clientID),
                    messages: sorted,
                    firstUnreadID: firstUnread,
                    draft: threadState.draft ?? Draft(threadID: threadID, text: "", language: client.language),
                    loadEarlierAvailable: sorted.count >= pageSize
                )
            )
        } catch {
            phase = .failed(ScreenLoad.failure(for: error, fallback: "Nie udało się wczytać rozmowy."))
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
            var updated = model
            updated.messages = MessageOrdering.sorted(older + model.messages)
            updated.loadEarlierAvailable = older.count >= pageSize
            phase = .loaded(updated)
        } catch {
            dictationNotice = ScreenLoad.message(for: error, fallback: "Nie udało się wczytać starszych wiadomości.")
        }
    }

    // MARK: Szkic

    func updateDraft(_ text: String, dependencies: AppDependencies) async {
        guard var model = phase.value, let threadState = state else { return }
        var draft = model.draft
        draft.text = text
        draft.updatedAt = dependencies.clock.now()
        model.draft = draft
        phase = .loaded(model)
        _ = await dependencies.perform { try await dependencies.repository.saveDraft(draft) }
        _ = threadState
    }

    func clearQuote(_ dependencies: AppDependencies) async {
        guard var model = phase.value, var threadState = state else { return }
        var draft = model.draft
        draft.quote = nil
        model.draft = draft
        phase = .loaded(model)
        threadState.draft = draft.isEmpty ? nil : draft
        _ = await dependencies.perform { try await dependencies.repository.saveDraft(threadState.draft) }
        state = threadState
    }

    func setQuote(_ quote: QuotedReference, dependencies: AppDependencies) async {
        guard var model = phase.value, var threadState = state else { return }
        var draft = model.draft
        draft.quote = quote
        model.draft = draft
        phase = .loaded(model)
        threadState.draft = draft
        _ = await dependencies.perform { try await dependencies.repository.saveDraft(draft) }
        state = threadState
    }

    // MARK: Wysyłka

    func send(_ dependencies: AppDependencies) async {
        guard var model = phase.value else { return }
        let text = model.draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let client = model.client
        let draft = model.draft
        let key = UUID().uuidString

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
            var updatedClient = client
            if updatedClient.needsReply || updatedClient.stage == .new {
                updatedClient.needsReply = false
                if updatedClient.stage == .new { updatedClient.stage = .inContact }
                _ = try await dependencies.repository.updateClient(
                    updatedClient,
                    expectedVersion: client.version
                )
            }
            return message
        }

        guard let sent else { return }
        model.messages = MessageOrdering.sorted(model.messages + [sent])
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
        guard var model = phase.value else { return }
        var draft = model.draft
        draft.text = draft.text.isEmpty ? text : draft.text + " " + text
        model.draft = draft
        phase = .loaded(model)
        if var threadState = state {
            threadState.draft = draft
            state = threadState
            _ = await dependencies.perform { try await dependencies.repository.saveDraft(draft) }
        }
    }

    func teardown(_ dependencies: AppDependencies) async {
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
    @StateObject private var store = ThreadStore()

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
                        style: .person,
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
                            showsAuthor: true
                        ) {
                            dependencies.present(.messageOptions(threadID: model.thread.id, messageID: message.id))
                        }
                        .id(message.id)
                    }
                }
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
        }
    }

    // MARK: Pole wiadomości

    @ViewBuilder
    private func composer(_ model: ThreadStore.Model) -> some View {
        VStack(spacing: 8) {
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

            HStack(alignment: .bottom, spacing: 8) {
                // Pole jednoliniowe, które rośnie razem z treścią (1–6 linii).
                // Wcześniej `TextEditor` startował od 40 pt i wyglądał jak pusty,
                // wysoki prostokąt, nawet gdy szkic był pusty.
                TextField(
                    "Napisz wiadomość…",
                    text: Binding(
                        get: { model.draft.text },
                        set: { newValue in Task { await store.updateDraft(newValue, dependencies: dependencies) } }
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
                    Task { await store.send(dependencies) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(hasSendableDraft(model) ? EmmaTheme.primaryButtonText : EmmaTheme.disabledButtonText)
                        .frame(width: EmmaMetrics.micButtonSize, height: EmmaMetrics.micButtonSize)
                        .background(hasSendableDraft(model) ? EmmaTheme.primaryButton : EmmaTheme.disabledButton)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
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
        .background(EmmaTheme.chatDockBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(EmmaTheme.chatHeaderBorder).frame(height: 0.5)
        }
    }

    private func hasSendableDraft(_ model: ThreadStore.Model) -> Bool {
        !model.draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview("Wątek") {
    ThreadScreen(threadID: DemoFixtures.olenaThread)
        .environmentObject(AppDependencies.demo())
}
