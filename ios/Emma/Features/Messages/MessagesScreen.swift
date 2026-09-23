import SwiftUI

// MARK: - Ekran „Rozmowy”
//
// Port `messagesPage()` i `conversationList()`. Sortowanie: przypięte najpierw,
// potem po czasie ostatniej wiadomości malejąco. Filtr „Nieprzeczytane” korzysta
// z tej samej reguły co licznik w wątku (`ReadStatePolicy`), więc liczby nie mogą
// się rozjechać (§3.3).
//
// Uczciwość wobec dostawcy: to demo nie jest połączone z WhatsApp i mówi o tym
// wprost w stopce listy oraz w szczegółach wiadomości.

@MainActor
final class MessagesStore: ObservableObject {

    enum Filter: String, CaseIterable, Identifiable, Hashable {
        case all = "Wszystkie"
        case unread = "Nieprzeczytane"
        case pinned = "Przypięte"

        var id: String { rawValue }
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
        let avatarTone: Client.AvatarTone
    }

    struct Model {
        var rows: [Row]
        /// Pełny, nieprzefiltrowany zbiór wierszy. Bez niego czyszczenie wyszukiwania
        /// filtrowało ponownie już przefiltrowaną listę i nie odtwarzało utraconych
        /// pozycji (F11).
        var allRows: [Row]
        var searchQuery: String
        var filter: Filter
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle
    @Published var filter: Filter = .all
    @Published var searchText: String = ""

    func load(_ dependencies: AppDependencies) async {
        // Odświeżenie po zapisie nie zdejmuje listy z ekranu (jak na „Dzisiaj”).
        if !phase.hasLoaded { phase = .loading }
        do {
            let repository = dependencies.repository
            let userID = dependencies.currentUser.id
            let threads = try await repository.threads()
            let states = try await repository.readStates(userID: userID)
            let clients = try await repository.clients(matching: "", stage: nil)

            var rows: [Row] = []
            for (index, thread) in threads.enumerated() {
                guard let client = clients.first(where: { $0.id == thread.clientID }) else { continue }
                let messages = try await repository.latestMessages(threadID: thread.id, limit: 60)
                let state = states.first { $0.threadID == thread.id }
                    ?? ThreadUserState(userID: userID, threadID: thread.id)
                let sorted = MessageOrdering.sorted(messages)
                rows.append(
                    Row(
                        thread: thread,
                        client: client,
                        preview: sorted.last,
                        unreadCount: ReadStatePolicy.unreadCount(in: sorted, state: state),
                        isPinned: state.isPinned,
                        sortKey: MessageOrdering.conversationSortKey(
                            lastMessage: sorted.last,
                            state: state,
                            threadID: thread.id
                        ),
                        hasDraft: !(state.draft?.isEmpty ?? true),
                        // Ton awatara zależy od stabilnej pozycji na liście, nie od identyfikatora.
                        avatarTone: EmmaTheme.avatarTone(forPresentationIndex: index)
                    )
                )
            }

            // Pełny zbiór zapisujemy osobno, a filtrowanie liczymy z niego — nie z wyniku.
            let allRows = rows
            phase = .loaded(
                Model(rows: filterAndSort(allRows), allRows: allRows, searchQuery: searchText, filter: filter)
            )
        } catch {
            phase = .failed(ScreenLoad.failure(for: error, fallback: "Nie udało się wczytać rozmów."))
        }
    }

    private func filterAndSort(_ rows: [Row]) -> [Row] {
        let query = searchText
        return rows
            .filter { row in
                switch filter {
                case .all: return true
                case .unread: return row.unreadCount > 0
                case .pinned: return row.isPinned
                }
            }
            .filter { row in
                // Treść wiadomości też jest przeszukiwana: nazwisko bywa tylko w treści.
                SearchText.matches(query, in: [row.client.displayName, row.preview?.text ?? ""])
            }
            .sorted { $0.sortKey > $1.sortKey }
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

struct MessagesScreen: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout: EmmaLayoutMetrics
    @StateObject private var store = MessagesStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Nowa rozmowa obok tytułu — jak „+” na liście klientów; osobny
                // wiersz na jeden przycisk zabierał wysokość nad listą.
                HStack(alignment: .top, spacing: 10) {
                    ScreenHeader(
                        kicker: "WHATSAPP",
                        title: "Rozmowy"
                    )
                    IconButton(systemName: "square.and.pencil", accessibilityLabel: "Nowa rozmowa") {
                        dependencies.present(.newConversation)
                    }
                }
                .padding(.bottom, 12)

                SearchField(text: $store.searchText, placeholder: "Szukaj osoby lub wiadomości")
                    .padding(.bottom, 10)
                    .onChange(of: store.searchText) { _, _ in
                        Task { await store.applyLocalFilter() }
                    }

                SegmentedFilter(items: MessagesStore.Filter.allCases, selection: $store.filter) { $0.rawValue }
                    .padding(.bottom, 14)
                    .onChange(of: store.filter) { _, _ in
                        // Filtr działa na wczytanych wierszach — bez ponownego
                        // odpytywania wszystkich wątków i bez mrugnięcia listy.
                        EmmaHaptics.selection()
                        Task { await store.applyLocalFilter() }
                    }

                switch store.phase {
                case .idle, .loading:
                    LoadingState("Wczytuję rozmowy…")
                case .failed(let failure):
                    LoadFailureView(failure) {
                        Task { await store.load(dependencies) }
                    }
                case .loaded(let model):
                    if model.rows.isEmpty {
                        emptyState(model)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                                ConversationRow(
                                    thread: row.thread,
                                    client: row.client,
                                    preview: row.preview,
                                    unreadCount: row.unreadCount,
                                    isPinned: row.isPinned,
                                    avatarTone: row.avatarTone,
                                    hasDraft: row.hasDraft
                                ) {
                                    dependencies.openThread(row.thread.id)
                                } onOptions: {
                                    dependencies.present(.conversationOptions(row.thread.id))
                                }
                                if index < model.rows.count - 1 {
                                    Divider().overlay(EmmaTheme.rowSeparator).padding(.leading, 62)
                                }
                            }
                        }
                        .background(EmmaTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                                .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
                        }
                    }

                    Text(disclosureText)
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.mutedSoft)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, EmmaSpacing.contentTop)
            .padding(.bottom, EmmaSpacing.contentBottom)
        }
        .background(EmmaTheme.bg)
        .scrollIndicators(.hidden)
        .refreshable { await store.load(dependencies) }
        .task(id: dependencies.dataVersion) { await store.load(dependencies) }
    }

    /// Stopka mówi prawdę o źródle: w Demo wiadomości są przykładowe, a poza
    /// Demo skrzynka jest pusta, bo numer kancelarii nie jest jeszcze podłączony.
    private var disclosureText: String {
        dependencies.configuration.usesMockServices
            ? "Wiadomości przykładowe · WhatsApp niepołączony"
            : "WhatsApp niepołączony · rozmowy pojawią się po podłączeniu numeru kancelarii"
    }

    @ViewBuilder
    private func emptyState(_ model: MessagesStore.Model) -> some View {
        if !model.searchQuery.isEmpty {
            EmptyState(
                systemImage: "magnifyingglass",
                title: "Brak wyników",
                message: "Spróbuj innego imienia lub fragmentu wiadomości."
            )
        } else if model.filter == .unread {
            EmptyState(
                systemImage: "checkmark.circle",
                title: "Wszystko przeczytane",
                message: "Nowe wiadomości pojawią się tutaj."
            )
        } else if model.filter == .all {
            // Wcześniej pusta skrzynka (np. poza Demo) mówiła „Brak przypiętych
            // rozmów”, bo ta gałąź była domyślna dla każdego filtra.
            EmptyState(
                systemImage: "bubble.left.and.bubble.right",
                title: "Brak rozmów",
                message: "Rozmowy z klientami pojawią się tutaj."
            )
        } else {
            EmptyState(
                systemImage: "pin",
                title: "Brak przypiętych rozmów",
                message: "Przypnij rozmowę w jej menu, aby mieć ją pod ręką."
            )
        }
    }
}

#Preview("Rozmowy") {
    MessagesScreen()
        .environmentObject(AppDependencies.demo())
}
