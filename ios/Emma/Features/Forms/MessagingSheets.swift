import SwiftUI

// MARK: - Arkusze komunikatora
//
// Port `newChat()`, `chatOptions()` i `messageOptions()` z referencji.
// Tożsamość nadawcy jest tu sprawdzana po `authorID` zalogowanego użytkownika,
// a nie po etykiecie tekstowej — etykieta służy tylko do prezentacji.

/// Wybór klienta do nowej rozmowy.
struct NewConversationSheet: View {

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var phase: LoadPhase<[Client]> = .idle
    @State private var threads: [ConversationThread] = []
    @State private var query = ""

    var body: some View {
        SheetScaffold(title: "Nowa rozmowa", onClose: { dependencies.dismissSheet() }) {
            switch phase {
            case .idle, .loading:
                LoadingState("Wczytuję kontakty…")
            case .failed(let failure):
                LoadFailureView(failure) {
                    Task { await load() }
                }
            case .loaded(let clients):
                if clients.isEmpty {
                    EmptyState(
                        systemImage: "person.2",
                        title: "Brak kontaktów",
                        message: "Dane przykładowe nie zawierają jeszcze żadnego klienta."
                    )
                } else {
                    SearchField(text: $query, placeholder: "Szukaj osoby")
                        .padding(.bottom, 10)

                    let matching = clients.filter {
                        SearchText.matches(query, in: [$0.displayName, $0.topic])
                    }
                    if matching.isEmpty {
                        EmptyState(
                            systemImage: "magnifyingglass",
                            title: "Brak wyników",
                            message: "Spróbuj innego imienia lub nazwiska."
                        )
                    } else {
                        ChoiceList(
                            items: matching,
                            title: { $0.displayName },
                            subtitle: { $0.language.displayName }
                        ) { client in
                            open(client)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        if !phase.hasLoaded { phase = .loading }
        do {
            let clients = try await dependencies.repository.clients(matching: "", stage: nil)
            threads = try await dependencies.repository.threads()
            phase = .loaded(clients)
        } catch {
            phase = .failed(ScreenLoad.failure(for: error, fallback: "Nie udało się wczytać kontaktów."))
        }
    }

    private func open(_ client: Client) {
        dependencies.dismissSheet()
        if let thread = threads.first(where: { $0.clientID == client.id }) {
            dependencies.openThread(thread.id)
        } else {
            dependencies.openPerson(client.id)
            dependencies.showToast("Ten kontakt nie ma jeszcze wątku rozmowy w danych przykładowych.")
        }
    }
}

/// Opcje rozmowy: przypięcie, oznaczenie odczytu i przejście do karty klienta.
struct ConversationOptionsSheet: View {

    let threadID: ThreadID

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var phase: LoadPhase<ThreadUserState> = .idle
    @State private var client: Client?
    @State private var unreadCount = 0

    var body: some View {
        SheetScaffold(
            title: client?.displayName ?? "Rozmowa",
            onClose: { dependencies.dismissSheet() }
        ) {
            switch phase {
            case .idle, .loading:
                LoadingState("Wczytuję rozmowę…")
            case .failed(let failure):
                LoadFailureView(failure) {
                    Task { await load() }
                }
            case .loaded(let state):
                ChoiceList(items: [0, 1, 2], title: { index in
                    switch index {
                    case 0: return state.isPinned ? "Odepnij rozmowę" : "Przypnij rozmowę"
                    case 1: return unreadCount > 0 ? "Oznacz jako przeczytaną" : "Oznacz jako nieprzeczytaną"
                    default: return "Karta klienta"
                    }
                }) { index in
                    Task { await perform(index, state: state) }
                }
                .padding(.bottom, 12)

                Text("Status wiadomości jest przykładowy — WhatsApp nie jest jeszcze połączony.")
                    .font(EmmaTypography.ui(11))
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await load() }
    }

    private func load() async {
        if !phase.hasLoaded { phase = .loading }
        do {
            let userID = dependencies.currentUser.id
            let states = try await dependencies.repository.readStates(userID: userID)
            let threadState = states.first { $0.threadID == threadID }
                ?? ThreadUserState(userID: userID, threadID: threadID)
            let messages = try await dependencies.repository.latestMessages(threadID: threadID, limit: 200)
            unreadCount = ReadStatePolicy.unreadCount(in: messages, state: threadState)
            if let thread = try await dependencies.repository.thread(id: threadID) {
                client = try await dependencies.repository.client(id: thread.clientID)
            }
            phase = .loaded(threadState)
        } catch {
            phase = .failed(ScreenLoad.failure(for: error, fallback: "Nie udało się wczytać rozmowy."))
        }
    }

    private func perform(_ index: Int, state: ThreadUserState) async {
        var updated = state
        switch index {
        case 0:
            updated.isPinned.toggle()
            _ = await dependencies.perform {
                try await dependencies.repository.saveThreadPreferences(updated)
            }
        case 1:
            if unreadCount > 0 {
                // Oznaczenie jako przeczytane przesuwa kursor tylko do przodu.
                let messages = (try? await dependencies.repository.latestMessages(threadID: threadID, limit: 200)) ?? []
                let high = messages.map(\.sequence).max() ?? 0
                updated.readCursorSequence = ReadStatePolicy.cursorAfterOpeningThread(
                    current: updated.readCursorSequence,
                    snapshotSequenceAtOpen: high
                )
                updated.manualUnread = false
            } else {
                updated.manualUnread = true
            }
            _ = await dependencies.perform {
                try await dependencies.repository.saveReadState(updated)
            }
            dependencies.refreshUnreadTotal()
        default:
            dependencies.dismissSheet()
            if let client { dependencies.openPerson(client.id) }
            return
        }
        self.phase = .loaded(updated)
        dependencies.refreshUnreadTotal()
    }
}

/// Szczegóły wiadomości i odpowiedź z cytatem.
struct MessageOptionsSheet: View {

    let threadID: ThreadID
    let messageID: MessageID

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var phase: LoadPhase<Message> = .idle
    @State private var clientName: String = Client.unknownDisplayName

    var body: some View {
        SheetScaffold(title: "Wiadomość", onClose: { dependencies.dismissSheet() }) {
            switch phase {
            case .idle, .loading:
                LoadingState("Wczytuję wiadomość…")
            case .failed(let failure):
                LoadFailureView(failure) {
                    Task { await load() }
                }
            case .loaded(let message):
                content(message)
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ message: Message) -> some View {
        Text(message.text)
            .font(EmmaTypography.body(for: message.text, size: 15))
            .foregroundStyle(EmmaTheme.ink)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .padding(.bottom, 12)

        if message.isOutgoing {
            HStack(spacing: 7) {
                ReceiptMark(transport: message.transport)
                Text("\(message.transport.displayName) · \(clockText(message))")
                    .font(EmmaTypography.ui(12))
                    .foregroundStyle(EmmaTheme.muted)
            }
            .padding(.bottom, 6)

            Text("Status przykładowy. WhatsApp nie jest jeszcze połączony.")
                .font(EmmaTypography.ui(11))
                .foregroundStyle(EmmaTheme.mutedSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
        }

        SecondaryButton("Odpowiedz na tę wiadomość", systemImage: "arrowshape.turn.up.left") {
            Task { await quote(message) }
        }
    }

    private func load() async {
        if !phase.hasLoaded { phase = .loading }
        let result = await RecordLoading.phase(
            missingMessage: "Nie znaleziono tej wiadomości. Wątek mógł się zmienić.",
            fallback: "Nie udało się wczytać wiadomości."
        ) {
            let messages = try await dependencies.repository.latestMessages(threadID: threadID, limit: 200)
            return messages.first { $0.id == messageID }
        }
        phase = result
        if case .loaded = result,
           let thread = try? await dependencies.repository.thread(id: threadID),
           let client = try? await dependencies.repository.client(id: thread.clientID) {
            clientName = client.displayName
        }
    }

    /// Cytat zapisujemy w szkicu wątku. Odpowiedź wysyła użytkownik — nigdy automat.
    private func quote(_ message: Message) async {
        let quote = QuotedReference(
            messageID: message.id,
            authorLabel: message.isOutgoing ? Client.firmDisplayName : clientName,
            text: message.text,
            isAvailable: true
        )
        let userID = dependencies.currentUser.id
        let states = (try? await dependencies.repository.readStates(userID: userID)) ?? []
        var state = states.first { $0.threadID == threadID }
            ?? ThreadUserState(userID: userID, threadID: threadID)
        var draft = state.draft ?? Draft(threadID: threadID, text: "", language: .pl)
        draft.quote = quote
        state.draft = draft
        _ = await dependencies.perform {
            try await dependencies.repository.saveDraft(draft)
        }
        dependencies.dismissSheet()
        dependencies.openThread(threadID)
    }

    private func clockText(_ message: Message) -> String {
        dependencies.dateText.clockTime(message.sentAt)
    }
}
