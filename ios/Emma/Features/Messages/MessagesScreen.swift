import SwiftUI

// MARK: - Ekran „Rozmowy”
//
// Port `messagesPage()` i `conversationList()`. Filtr nowych wiadomości korzysta
// z tej samej reguły co licznik w wątku (`ReadStatePolicy`), więc liczby nie
// mogą się rozjechać (§3.3).
//
// Przebudowa 29.09.2026 — ten sam język co „Dzisiaj” i „Klienci”:
//   • nad listą trzy kafelki: nowe wiadomości, rozmowy do odpowiedzi i odpisane;
//     dotknięcie ustawia filtr albo przewija do grupy,
//   • lista odpowiada na pytanie **czyj jest ruch** (`ConversationInbox`):
//     „Nowe wiadomości” → „Do odpowiedzi” → „Odpisane”, przypięte na górze,
//   • wiersz to karta: stały kolor osoby, język, linijka stanu („Do odpowiedzi ·
//     czeka 7 min”, „Odpisano · odczytane”) i podgląd,
//   • przesunięcia: w prawo — przeczytane/nieprzeczytane, w lewo — przypnij
//     i odpowiedź przygotowana przez Emmę; to samo pod przytrzymaniem,
//   • poprawione sortowanie: `ConversationSortKey` jest „mniejszy” dla wątku,
//     który ma być wyżej, a lista sortowała malejąco — przypięte lądowały na dole.
//
// Uczciwość wobec dostawcy: to demo nie jest połączone z WhatsApp i mówi o tym
// wprost w stopce listy oraz w szczegółach wiadomości. Po podłączeniu numeru
// kancelarii wiersze przyjdą z backendu — ekran nie zakłada niczego o źródle.

@MainActor
final class MessagesStore: ObservableObject {

    enum Filter: String, CaseIterable, Identifiable, Hashable {
        case all = "Wszystkie"
        case unread = "Nowe"
        case needsReply = "Do odpowiedzi"
        case pinned = "Przypięte"

        var id: String { rawValue }

        func includes(_ row: Row) -> Bool {
            switch self {
            case .all: return true
            case .unread: return row.status == .unread
            case .needsReply: return row.status.needsReply
            case .pinned: return row.isPinned
            }
        }

        /// „Przypięte” pokazujemy dopiero, gdy coś jest przypięte — pusty chip
        /// to opcja, która niczego nie pokazuje (jak „Bez ruchu” w kartotece).
        static func visible(in model: Model) -> [Filter] {
            let hasPinned = model.allRows.contains { $0.isPinned }
            return hasPinned || model.filter == .pinned ? allCases : [.all, .unread, .needsReply]
        }
    }

    struct Row: Identifiable {
        var id: ThreadID { thread.id }
        let thread: ConversationThread
        let client: Client
        let preview: Message?
        let unreadCount: Int
        let isPinned: Bool
        /// Klucz porządkowania trzymany razem z wierszem: przypięcie, czas i remis
        /// rozstrzygane w jednym miejscu, bez powtarzania reguły w widoku.
        let sortKey: MessageOrdering.ConversationSortKey
        let hasDraft: Bool
        /// Czyj jest ruch — wspólna reguła kafelków, chipów i grup.
        let status: ConversationStatus
        /// Od kiedy klient czeka na odpowiedź (`nil`, gdy ostatnie słowo nasze).
        let waitingSince: Date?
        /// Stan odczytu — przesunięcia zapisują go bez otwierania wątku.
        let state: ThreadUserState
        /// Najwyższy znany numer wiadomości (snapshot do „Oznacz jako przeczytaną”).
        let highestSequence: Int
        /// Okno 24 h WhatsApp — ostrzeżenie na karcie, zanim wysyłka zostanie odrzucona.
        let replyWindow: ReplyWindow
    }

    struct Model {
        var rows: [Row]
        /// Pełny, nieprzefiltrowany zbiór wierszy. Bez niego czyszczenie wyszukiwania
        /// filtrowało ponownie już przefiltrowaną listę i nie odtwarzało utraconych
        /// pozycji (F11).
        var allRows: [Row]
        var searchQuery: String
        var filter: Filter

        func count(_ filter: Filter) -> Int {
            allRows.filter(filter.includes).count
        }

        /// Liczba nowych wiadomości (nie rozmów) — jak licznik na zakładce.
        var unreadMessages: Int {
            allRows.reduce(0) { $0 + $1.unreadCount }
        }

        var repliedCount: Int {
            allRows.filter { !$0.status.needsReply }.count
        }
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle
    @Published var filter: Filter = .all
    @Published var searchText: String = ""

    /// Ile ostatnich wiadomości wątku czytamy na liście (stan, czekanie, okno 24 h).
    private static let messagesPerThread = 60

    /// `silent` — odświeżenie w tle (co pół minuty): błąd sieci nie pokazuje
    /// komunikatu ani ekranu błędu, lista zostaje taka, jaka była.
    func load(_ dependencies: AppDependencies, silent: Bool = false) async {
        // Odświeżenie po zapisie nie zdejmuje listy z ekranu (jak na „Dzisiaj”).
        let wasLoaded = phase.hasLoaded
        if silent && !wasLoaded { return }
        if !wasLoaded { phase = .loading }
        do {
            let repository = dependencies.repository
            let userID = dependencies.currentUser.id
            let now = dependencies.clock.now()
            async let threadsTask = repository.threads()
            async let statesTask = repository.readStates(userID: userID)
            async let clientsTask = repository.clients(matching: "", stage: nil)
            let threads = try await threadsTask
            let states = try await statesTask
            let clients = try await clientsTask
            let clientsByID = Dictionary(clients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            // Wiadomości wątków pobieramy równolegle. Po kolei — przy prawdziwym
            // WhatsApp i kilkudziesięciu rozmowach — lista wczytywała się
            // kilka sekund, bo każdy wątek to osobne zapytanie do serwera.
            let visible = threads.filter { clientsByID[$0.clientID] != nil }
            let limit = Self.messagesPerThread
            let messagesByThread = try await withThrowingTaskGroup(of: (ThreadID, [Message]).self) { group in
                for thread in visible {
                    group.addTask {
                        (thread.id, try await repository.latestMessages(threadID: thread.id, limit: limit))
                    }
                }
                var result: [ThreadID: [Message]] = [:]
                for try await (threadID, messages) in group {
                    result[threadID] = messages
                }
                return result
            }

            var rows: [Row] = []
            for thread in visible {
                guard let client = clientsByID[thread.clientID] else { continue }
                let messages = messagesByThread[thread.id] ?? []
                let state = states.first { $0.threadID == thread.id }
                    ?? ThreadUserState(userID: userID, threadID: thread.id)
                let sorted = MessageOrdering.sorted(messages)
                let unread = ReadStatePolicy.unreadCount(in: sorted, state: state)
                rows.append(
                    Row(
                        thread: thread,
                        client: client,
                        preview: sorted.last,
                        unreadCount: unread,
                        isPinned: state.isPinned,
                        sortKey: MessageOrdering.conversationSortKey(
                            lastMessage: sorted.last,
                            state: state,
                            threadID: thread.id
                        ),
                        hasDraft: !(state.draft?.isEmpty ?? true),
                        status: ConversationInbox.status(lastMessage: sorted.last, unreadCount: unread),
                        waitingSince: ConversationInbox.waitingSince(sorted),
                        state: state,
                        highestSequence: sorted.last?.sequence ?? 0,
                        replyWindow: ReplyWindow.state(
                            sortedMessages: sorted,
                            now: now,
                            isComplete: sorted.count < limit
                        )
                    )
                )
            }

            // Pełny zbiór zapisujemy osobno, a filtrowanie liczymy z niego — nie z wyniku.
            let allRows = rows
            let model = Model(rows: filterAndSort(allRows), allRows: allRows, searchQuery: searchText, filter: filter)
            if wasLoaded {
                // Zmiana stanu (przeczytane, przypięte) przenosi kartę między
                // grupami płynnie, zamiast przeskoczyć.
                withAnimation(EmmaMotion.smooth) { phase = .loaded(model) }
            } else {
                phase = .loaded(model)
            }
        } catch {
            guard !silent else { return }
            if let message = phase.recordFailure(error, fallback: "Nie udało się wczytać rozmów.") {
                dependencies.showToast(message)
            }
        }
    }

    private func filterAndSort(_ rows: [Row]) -> [Row] {
        let query = searchText
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Wyszukiwanie przeszukuje wszystko — jak w kartotece klientów.
        let activeFilter: Filter = trimmed.isEmpty ? filter : .all
        return rows
            .filter(activeFilter.includes)
            .filter { row in
                // Treść wiadomości też jest przeszukiwana: nazwisko bywa tylko w treści.
                SearchText.matches(query, in: [row.client.displayName, row.preview?.text ?? ""])
                    || SearchText.matchesPhone(query, phone: row.client.phone)
            }
            // „Mniejszy” klucz = wyżej na liście (przypięte, potem najnowsze).
            .sorted { $0.sortKey < $1.sortKey }
    }

    /// Ponowne filtrowanie bez odpytywania repozytorium — używane przy zmianie
    /// filtra i wpisywaniu tekstu. Liczone jest z pełnego zbioru `allRows`, więc
    /// wyczyszczenie zapytania przywraca całą listę (F11).
    func applyLocalFilter() async {
        guard let model = phase.value else { return }
        phase = .loaded(
            Model(
                rows: filterAndSort(model.allRows),
                allRows: model.allRows,
                searchQuery: searchText,
                filter: filter
            )
        )
    }
}

// MARK: - Grupy listy

/// Grupa listy rozmów: przypięte na górze, potem według tego, czyj jest ruch.
enum ConversationGroup: String, CaseIterable, Identifiable {
    case pinned
    case unread
    case awaitingReply
    case replied

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pinned: return "Przypięte"
        case .unread: return "Nowe wiadomości"
        case .awaitingReply: return "Do odpowiedzi"
        case .replied: return "Odpisane"
        }
    }

    var tone: Color {
        switch self {
        case .pinned: return EmmaTheme.mutedSoft
        case .unread: return EmmaTheme.unreadBadge
        case .awaitingReply: return EmmaTheme.pillAmberText
        case .replied: return EmmaTheme.pillGreenText
        }
    }

    /// Grupy, które wymagają działania, mają tytuł w kolorze stanu.
    var isEmphasized: Bool { self == .unread || self == .awaitingReply }

    /// Cel przewijania z kafelków.
    var anchorID: String { "conversation-group-\(rawValue)" }

    static func of(_ row: MessagesStore.Row) -> ConversationGroup {
        if row.isPinned { return .pinned }
        switch row.status {
        case .unread: return .unread
        case .awaitingReply: return .awaitingReply
        case .replied, .seen, .empty: return .replied
        }
    }
}

private struct ConversationSection: Identifiable {
    let group: ConversationGroup
    let rows: [MessagesStore.Row]
    /// Pozycja pierwszego wiersza na całej liście — do kaskadowego wejścia kart.
    let startIndex: Int

    var id: String { group.rawValue }

    static func make(_ rows: [MessagesStore.Row]) -> [ConversationSection] {
        var sections: [ConversationSection] = []
        var index = 0
        for group in ConversationGroup.allCases {
            let members = rows.filter { ConversationGroup.of($0) == group }
            guard !members.isEmpty else { continue }
            sections.append(ConversationSection(group: group, rows: members, startIndex: index))
            index += members.count
        }
        return sections
    }
}

// MARK: - Ekran

struct MessagesScreen: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout: EmmaLayoutMetrics
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    /// Magazyn żyje w `AppDependencies` — powrót na zakładkę pokazuje od razu
    /// ostatni stan i zachowuje filtr.
    @ObservedObject var store: MessagesStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            List {
                controls(proxy)
                listContent
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .environment(\.defaultMinListRowHeight, 0)
        }
        .background(EmmaTheme.bg)
        .refreshable { await store.load(dependencies) }
        .task(id: dependencies.dataVersion) { await store.load(dependencies) }
        // Nowe wiadomości WhatsApp przychodzą bez naszego udziału — lista
        // odświeża się sama co 30 s, póki jest na ekranie i aplikacja aktywna.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, scenePhase == .active else { continue }
                await store.load(dependencies, silent: true)
                dependencies.refreshUnreadTotal()
            }
        }
        .onChange(of: store.searchText) { _, _ in
            Task { await store.applyLocalFilter() }
        }
        .onChange(of: store.filter) { _, _ in
            // Filtr działa na wczytanych wierszach — bez ponownego odpytywania
            // wszystkich wątków i bez mrugnięcia listy (wibrację daje chip).
            Task { await store.applyLocalFilter() }
        }
    }

    // MARK: Nagłówek i sterowanie

    @ViewBuilder
    private func controls(_ proxy: ScrollViewProxy) -> some View {
        header
            .id(Self.topID)
            .emmaListRow(top: EmmaSpacing.contentTop, bottom: 0, horizontal: layout.horizontalPadding)

        if case .loaded(let model) = store.phase {
            summaryTiles(model, proxy: proxy)
                .emmaListRow(top: 14, bottom: 0, horizontal: layout.horizontalPadding)
        }

        SearchField(text: $store.searchText, placeholder: "Szukaj osoby lub wiadomości", isFocused: $searchFocused)
            .emmaListRow(top: 14, bottom: 0, horizontal: layout.horizontalPadding)

        filterChips
            .emmaListRow(top: 8, bottom: 6, horizontal: 0)
    }

    /// Sam tytuł i „nowa rozmowa” — jak „Klienci” z „+”.
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Rozmowy")
                .font(EmmaTypography.welcome)
                .tracking(-0.9)
                .foregroundStyle(EmmaTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(systemName: "square.and.pencil", accessibilityLabel: "Nowa rozmowa") {
                dependencies.present(.newConversation)
            }
        }
    }

    // MARK: Kafelki

    private func summaryTiles(_ model: MessagesStore.Model, proxy: ScrollViewProxy) -> some View {
        let unreadMessages = model.unreadMessages
        let needsReply = model.count(.needsReply)
        let replied = model.repliedCount
        return HStack(spacing: 8) {
            PulseTile(
                value: unreadMessages,
                label: EmmaPlural.form(unreadMessages, "nowa wiadomość", "nowe wiadomości", "nowych wiadomości"),
                systemImage: "envelope.badge",
                tone: EmmaTheme.unreadBadge
            ) { select(.unread) }
            PulseTile(
                value: needsReply,
                label: EmmaPlural.form(needsReply, "czeka na odpowiedź", "czekają na odpowiedź", "czeka na odpowiedź"),
                systemImage: "arrowshape.turn.up.left",
                tone: needsReply > 0 ? EmmaTheme.pillAmberText : EmmaTheme.accent
            ) { select(.needsReply) }
            PulseTile(
                value: replied,
                label: EmmaPlural.form(replied, "odpisana", "odpisane", "odpisanych"),
                systemImage: "checkmark.message",
                tone: EmmaTheme.pillGreenText
            ) { showGroup(.replied, proxy: proxy) }
        }
    }

    private func select(_ filter: MessagesStore.Filter) {
        store.searchText = ""
        store.filter = filter
    }

    /// Kafelek „odpisane” nie zawęża listy, tylko przewija do grupy.
    private func showGroup(_ group: ConversationGroup, proxy: ScrollViewProxy) {
        store.searchText = ""
        store.filter = .all
        Task { @MainActor in
            // Najpierw lista musi przebudować się po zmianie filtra.
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(group.anchorID, anchor: .top)
            }
        }
    }

    private static let topID = "messages-top"

    // MARK: Filtry

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            chipRow
                .padding(.horizontal, layout.horizontalPadding)
        }
    }

    @ViewBuilder
    private var chipRow: some View {
        if case .loaded(let model) = store.phase {
            ListFilterChips(
                items: MessagesStore.Filter.visible(in: model),
                selection: $store.filter,
                title: { $0.rawValue },
                count: { model.count($0) },
                attention: { filter in filter == .needsReply && model.count(.needsReply) > 0 }
            )
        } else {
            ListFilterChips(
                items: [.all, .unread, .needsReply],
                selection: $store.filter,
                title: { $0.rawValue }
            )
        }
    }

    // MARK: Lista

    @ViewBuilder
    private var listContent: some View {
        switch store.phase {
        case .idle, .loading:
            LoadingState("Wczytuję rozmowy…")
                .emmaListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
        case .failed(let failure):
            LoadFailureView(failure) {
                Task { await store.load(dependencies) }
            }
            .emmaListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
        case .loaded(let model):
            if model.rows.isEmpty {
                emptyState(model)
                    .emmaListRow(top: 6, bottom: 0, horizontal: layout.horizontalPadding)
            } else {
                ForEach(ConversationSection.make(model.rows)) { section in
                    GroupHeader(
                        title: section.group.title,
                        count: section.rows.count,
                        tone: section.group.tone,
                        emphasized: section.group.isEmphasized
                    )
                    .id(section.group.anchorID)
                    .emmaListRow(top: 12, bottom: 2, horizontal: layout.horizontalPadding)

                    ForEach(Array(section.rows.enumerated()), id: \.element.id) { offset, row in
                        conversationRow(row, index: section.startIndex + offset)
                    }
                }
            }
            disclosure(hasThreads: !model.allRows.isEmpty)
                .emmaListRow(top: 12, bottom: EmmaSpacing.contentBottom, horizontal: layout.horizontalPadding)
        }
    }

    private func conversationRow(_ row: MessagesStore.Row, index: Int) -> some View {
        ConversationRow(
            thread: row.thread,
            client: row.client,
            preview: row.preview,
            unreadCount: row.unreadCount,
            isPinned: row.isPinned,
            hasDraft: row.hasDraft,
            status: row.status,
            waitingSince: row.waitingSince,
            replyWindow: row.replyWindow
        ) {
            dependencies.openThread(row.thread.id)
        } onOptions: {
            dependencies.present(.conversationOptions(row.thread.id))
        }
        .contextMenu { rowMenu(row) }
        .emmaAppear(index)
        .emmaListRow(top: 5, bottom: 5, horizontal: layout.horizontalPadding)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await toggleRead(row) }
            } label: {
                if row.unreadCount > 0 {
                    Label("Przeczytane", systemImage: "envelope.open")
                } else {
                    Label("Oznacz jako nową", systemImage: "envelope.badge")
                }
            }
            .tint(EmmaTheme.unreadBadge)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                Task { await togglePin(row) }
            } label: {
                Label(row.isPinned ? "Odepnij" : "Przypnij", systemImage: row.isPinned ? "pin.slash" : "pin")
            }
            .tint(EmmaTheme.pillAmberText)
            Button {
                prepareReply(row)
            } label: {
                Label("Emma", systemImage: "sparkles")
            }
            .tint(EmmaTheme.primaryButton)
        }
    }

    @ViewBuilder
    private func rowMenu(_ row: MessagesStore.Row) -> some View {
        Button {
            prepareReply(row)
        } label: {
            Label("Przygotuj odpowiedź z Emmą", systemImage: "sparkles")
        }
        Button {
            Task { await toggleRead(row) }
        } label: {
            if row.unreadCount > 0 {
                Label("Oznacz jako przeczytaną", systemImage: "envelope.open")
            } else {
                Label("Oznacz jako nową", systemImage: "envelope.badge")
            }
        }
        Button {
            Task { await togglePin(row) }
        } label: {
            Label(row.isPinned ? "Odepnij rozmowę" : "Przypnij rozmowę", systemImage: row.isPinned ? "pin.slash" : "pin")
        }
        if let phoneURL = row.client.phone.flatMap(ContactLinks.phoneURL) {
            Button {
                openURL(phoneURL)
            } label: {
                Label("Zadzwoń", systemImage: "phone")
            }
        }
        Button {
            dependencies.openPerson(row.client.id)
        } label: {
            Label("Karta klienta", systemImage: "person")
        }
    }

    // MARK: Czynności

    /// Emma przygotowuje odpowiedź w języku klienta — do sprawdzenia, nic nie wysyła.
    private func prepareReply(_ row: MessagesStore.Row) {
        EmmaHaptics.tap()
        dependencies.openEmma(clientID: row.client.id, action: .reply, startVoice: false)
    }

    /// Ta sama reguła co w opcjach rozmowy: odczyt przesuwa kursor tylko do
    /// przodu, „nowa” to osobny znacznik, a nie fałszywa wiadomość (§3.3).
    private func toggleRead(_ row: MessagesStore.Row) async {
        var updated = await freshState(row)
        if row.unreadCount > 0 {
            updated.readCursorSequence = ReadStatePolicy.cursorAfterOpeningThread(
                current: updated.readCursorSequence,
                snapshotSequenceAtOpen: row.highestSequence
            )
            updated.manualUnread = false
        } else {
            updated.manualUnread = true
        }
        EmmaHaptics.selection()
        let state = updated
        _ = await dependencies.perform {
            try await dependencies.repository.saveReadState(state)
        }
    }

    private func togglePin(_ row: MessagesStore.Row) async {
        var updated = await freshState(row)
        updated.isPinned.toggle()
        EmmaHaptics.selection()
        let state = updated
        _ = await dependencies.perform {
            try await dependencies.repository.saveThreadPreferences(state)
        }
    }

    /// Stan wątku prosto z repozytorium. `saveReadState` zapisuje cały stan,
    /// także szkic — stan z chwili wczytania listy mógłby przywrócić starszy
    /// szkic, jeśli w międzyczasie ktoś pisał w wątku.
    private func freshState(_ row: MessagesStore.Row) async -> ThreadUserState {
        let states = (try? await dependencies.repository.readStates(userID: dependencies.currentUser.id)) ?? []
        return states.first { $0.threadID == row.thread.id } ?? row.state
    }

    // MARK: Stopka i stany puste

    /// Stopka mówi prawdę o źródle: w Demo wiadomości są przykładowe, a poza
    /// Demo — czy rozmowy WhatsApp kancelarii już płyną z serwera.
    private func disclosure(hasThreads: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EmmaTheme.mutedSoft)
                .padding(.top, 1)
            Text(disclosureText(hasThreads: hasThreads))
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.mutedSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous)
                .strokeBorder(EmmaTheme.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .accessibilityElement(children: .combine)
    }

    private func disclosureText(hasThreads: Bool) -> String {
        if dependencies.configuration.usesMockServices {
            return "Wiadomości przykładowe · WhatsApp niepołączony"
        }
        // Pusta lista nie odróżnia „niepodłączony” od „nikt jeszcze nie napisał”,
        // więc mówimy ostrożnie, zamiast ogłaszać brak połączenia.
        return hasThreads
            ? "WhatsApp kancelarii · statusy dostarczenia pochodzą z WhatsApp"
            : "Rozmowy WhatsApp pojawią się tu, gdy numer kancelarii jest podłączony i klient napisze"
    }

    @ViewBuilder
    private func emptyState(_ model: MessagesStore.Model) -> some View {
        if !model.searchQuery.isEmpty {
            EmptyState(
                systemImage: "magnifyingglass",
                title: "Brak wyników",
                message: "Spróbuj innego imienia, numeru lub fragmentu wiadomości."
            )
        } else {
            switch model.filter {
            case .unread:
                EmptyState(
                    systemImage: "checkmark.circle",
                    title: "Wszystko przeczytane",
                    message: "Nowe wiadomości pojawią się tutaj."
                )
            case .needsReply:
                EmptyState(
                    systemImage: "checkmark.seal",
                    title: "Nikt nie czeka",
                    message: "Na każdą wiadomość jest już odpowiedź."
                )
            case .pinned:
                EmptyState(
                    systemImage: "pin",
                    title: "Brak przypiętych rozmów",
                    message: "Przesuń rozmowę w lewo i przypnij ją, aby mieć ją pod ręką."
                )
            case .all:
                // Wcześniej pusta skrzynka (np. poza Demo) mówiła „Brak przypiętych
                // rozmów”, bo ta gałąź była domyślna dla każdego filtra.
                EmptyState(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "Brak rozmów",
                    message: "Rozmowy z klientami pojawią się tutaj."
                )
            }
        }
    }
}

#Preview("Rozmowy") {
    let dependencies = AppDependencies.demo()
    return MessagesScreen(store: dependencies.messagesStore)
        .environmentObject(dependencies)
}
