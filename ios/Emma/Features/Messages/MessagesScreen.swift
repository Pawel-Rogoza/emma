import SwiftUI

// MARK: - Ekran „Rozmowy”
//
// Port `messagesPage()` i `conversationList()`. Filtr nowych wiadomości korzysta
// z tej samej reguły co licznik w wątku (`ReadStatePolicy`), więc liczby nie
// mogą się rozjechać (§3.3).
//
// Przebudowa 02.10.2026 — jak w WhatsAppie: bez kafelków i grup, lista od
// najnowszej wiadomości (przypięte na górze), wiersz z godziną, ptaszkami
// i dyskretnym „Bez odpowiedzi” / „Ponad 24 h bez odpowiedzi”. Poniższy opis
// z 29.09 dotyczy reguł stanu, które zostały (`ConversationInbox`):
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
        /// Rozmowy bez osoby w kartotece (np. z historii WhatsApp Business)
        /// po wyszukiwaniu; `allUnassigned` — pełny zbiór.
        var unassigned: [UnassignedConversation] = []
        var allUnassigned: [UnassignedConversation] = []

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

        /// Rozmowa każdego klienta (przy kilku wątkach — ta, która jest wyżej
        /// na liście) — do znaczników w kartotece.
        var rowsByClient: [ClientID: Row] {
            Dictionary(allRows.map { ($0.client.id, $0) }, uniquingKeysWith: { lhs, rhs in
                lhs.sortKey < rhs.sortKey ? lhs : rhs
            })
        }

        /// Rozmowy z nowymi wiadomościami — najdłużej czekający klient najpierw.
        var unreadRows: [Row] {
            allRows
                .filter { $0.unreadCount > 0 }
                .sorted { ($0.waitingSince ?? .distantFuture) < ($1.waitingSince ?? .distantFuture) }
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
        // Ciche pierwsze wczytanie (z „Dzisiaj” i „Klientów”) nie pokazuje
        // szkieletu ani błędu — tamte ekrany po prostu nie dostaną znaczników.
        if !wasLoaded && !silent { phase = .loading }
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

            // Rozmowy bez osoby nie blokują listy: starszy serwer albo błąd
            // tego jednego zapytania zostawia resztę rozmów na ekranie.
            let unassigned = (try? await repository.unassignedConversations()) ?? []

            // Pełny zbiór zapisujemy osobno, a filtrowanie liczymy z niego — nie z wyniku.
            let allRows = rows
            let model = Model(
                rows: filterAndSort(allRows),
                allRows: allRows,
                searchQuery: searchText,
                filter: filter,
                unassigned: filterUnassigned(unassigned),
                allUnassigned: unassigned
            )
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
                SearchText.matches(query, in: [row.client.displayName, row.preview?.previewText ?? ""])
                    || SearchText.matchesPhone(query, phone: row.client.phone)
            }
            // „Mniejszy” klucz = wyżej na liście (przypięte, potem najnowsze).
            .sorted { $0.sortKey < $1.sortKey }
    }

    /// Rozmowy bez osoby widać przy „Wszystkie” i w wyszukiwaniu — nie są
    /// ani nowe, ani do odpowiedzi w sensie filtrów (to zwykle historia).
    private func filterUnassigned(_ items: [UnassignedConversation]) -> [UnassignedConversation] {
        let query = searchText
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard filter == .all || !trimmed.isEmpty else { return [] }
        return items
            .filter { item in
                SearchText.matches(query, in: [item.name, item.preview?.previewText ?? ""])
                    || SearchText.matchesPhone(query, phone: item.phone)
            }
            .sorted { ($0.preview?.sentAt ?? .distantPast) > ($1.preview?.sentAt ?? .distantPast) }
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
                filter: filter,
                unassigned: filterUnassigned(model.allUnassigned),
                allUnassigned: model.allUnassigned
            )
        )
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
    /// Otwarta rozmowa bez osoby (podgląd historii i „Zrób leada”).
    @State private var openedUnassigned: UnassignedConversation?
    /// Historia z telefonu bywa długa — pokazujemy najpierw kilka rozmów.
    @State private var showsAllUnassigned = false
    private static let unassignedPreviewLimit = 8

    var body: some View {
        List {
            controls
            listContent
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .environment(\.defaultMinListRowHeight, 0)
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
        .sheet(item: $openedUnassigned) { conversation in
            UnassignedConversationSheet(conversation: conversation)
                .environmentObject(dependencies)
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

    // Przebudowa 02.10.2026: kafelki „nowe / czekają / odpisane” dublowały
    // chipy filtra (te same liczby dwa razy nad listą) — zostały chipy.
    @ViewBuilder
    private var controls: some View {
        header
            .emmaListRow(top: EmmaSpacing.contentTop, bottom: 0, horizontal: layout.horizontalPadding)

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
            if model.rows.isEmpty && model.unassigned.isEmpty {
                emptyState(model)
                    .emmaListRow(top: 6, bottom: 0, horizontal: layout.horizontalPadding)
            } else {
                // Jak w WhatsAppie: przypięte na górze, dalej od najnowszej
                // wiadomości. Kto czeka na odpowiedź, mówi sam wiersz.
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { offset, row in
                    conversationRow(row, index: offset)
                }
            }
            unassignedSection(model)
            disclosure(hasThreads: !model.allRows.isEmpty || !model.allUnassigned.isEmpty)
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
        .emmaListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
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
        Button {
            dependencies.present(.conversationOptions(row.thread.id))
        } label: {
            Label("Więcej opcji", systemImage: "ellipsis.circle")
        }
    }

    // MARK: Rozmowy bez osoby

    @ViewBuilder
    private func unassignedSection(_ model: MessagesStore.Model) -> some View {
        if !model.unassigned.isEmpty {
            let searching = !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let visible = showsAllUnassigned || searching
                ? model.unassigned
                : Array(model.unassigned.prefix(Self.unassignedPreviewLimit))
            GroupHeader(
                title: "Bez osoby w kartotece",
                count: model.unassigned.count,
                tone: EmmaTheme.mutedSoft,
                emphasized: false
            )
            .emmaListRow(top: 12, bottom: 2, horizontal: layout.horizontalPadding)

            ForEach(visible) { conversation in
                UnassignedConversationRow(conversation: conversation) {
                    openedUnassigned = conversation
                }
                .emmaListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
            }

            if visible.count < model.unassigned.count {
                Button("Pokaż wszystkie (\(model.unassigned.count))") {
                    withAnimation(EmmaMotion.smooth) { showsAllUnassigned = true }
                }
                .font(EmmaTypography.caption(.medium))
                .foregroundStyle(EmmaTheme.accent)
                .frame(maxWidth: .infinity, minHeight: EmmaSpacing.hitTarget)
                .emmaListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
            }
        }
    }

    // MARK: Czynności

    /// Emma pisze szkic odpowiedzi prosto w polu rozmowy — do sprawdzenia,
    /// nic nie wysyła (wcześniej przez zakładkę Emmy i szablon).
    private func prepareReply(_ row: MessagesStore.Row) {
        EmmaHaptics.tap()
        dependencies.openThreadWithEmmaDraft(row.thread.id)
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
