import SwiftUI

// MARK: - Ekran „Klienci”
//
// Port stanów `clients()` i `clientList()` z referencji: jeden ekran, dwa tryby
// (Leady / Sprawy). Tryb mieszka w `AppDependencies`, bo przełącza go także
// pulpit „Dzisiaj” (`selectClients(mode)`), a wyszukiwanie i filtr są lokalne.
//
// Przebudowa z review 23.09.2026:
//   • leady są kolejką pracy: domyślny widok „Do obsługi” pokazuje najpierw te,
//     które **czekają** (≥ 24 h), potem **nowe** — reguła w `LeadWorkflow`,
//   • zgłoszenie odhacza się przyciskiem na karcie albo przesunięciem w prawo;
//     w lewo są konwersja i usunięcie — z „Cofnij” w komunikacie, bez pytań,
//   • lista stoi na `List`, bo tylko ona daje systemowe przesunięcia z obsługą
//     VoiceOver; wygląd kart pozostaje własny (tło i separatory wyłączone),
//   • pociągnięcie w dół odświeża listę (nowe zgłoszenia ze strony).

struct ClientsScreen: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout

    /// Magazyn żyje w `AppDependencies`, więc powrót na zakładkę nie mruga
    /// stanem ładowania, a lista od razu pokazuje ostatni stan.
    @ObservedObject var store: ClientsStore

    @State private var search = ""
    /// Domyślnie kolejka „Do obsługi” — nowe i oczekujące zgłoszenia.
    @State private var leadFilter: LeadListFilter = .needsAction
    @State private var caseFilter: CaseListFilter = .active
    /// Nazwa leada w trakcie zmiany — `nil` znaczy, że okno jest zamknięte.
    @State private var renaming: Client?
    @State private var renameText = ""
    /// Zgłoszenie czekające na potwierdzenie usunięcia.
    @State private var pendingDelete: Client?
    /// Zgłoszenie czekające na potwierdzenie konwersji w kartotekę.
    @State private var pendingConversion: Client?

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
        .onAppear { consumePendingFilter() }
        .onChange(of: dependencies.pendingLeadFilter) { _, _ in consumePendingFilter() }
        .onChange(of: dependencies.clientMode) { _, _ in
            // `setClientMode` w referencji czyści wyszukiwanie i wraca do pierwszego filtra.
            search = ""
            leadFilter = .needsAction
            caseFilter = .active
        }
        .alert("Zmień nazwę", isPresented: renameBinding) {
            TextField("Imię i nazwisko", text: $renameText)
            Button("Anuluj", role: .cancel) { renaming = nil }
            Button("Zapisz") { commitRename() }
        } message: {
            Text("Nazwa pojawi się na liście i w karcie.")
        }
        .alert("Usunąć zgłoszenie?", isPresented: deleteBinding, presenting: pendingDelete) { _ in
            Button("Anuluj", role: .cancel) { pendingDelete = nil }
            Button("Usuń", role: .destructive) { commitDelete() }
        } message: { client in
            Text("„\(client.displayName)” zniknie z listy zgłoszeń. Zgłoszenie z rezerwacji zwolni też okienko na stronie.")
        }
        .confirmationDialog(
            "Konwertować na klienta?",
            isPresented: conversionBinding,
            titleVisibility: .visible,
            presenting: pendingConversion
        ) { client in
            Button("Konwertuj na klienta") { commitConversion(client) }
            Button("Anuluj", role: .cancel) { pendingConversion = nil }
        } message: { client in
            Text("Dla „\(client.displayName)” powstanie kartoteka klienta. Tego nie cofa się z aplikacji.")
        }
    }

    // MARK: Nagłówek i sterowanie

    @ViewBuilder
    private var controls: some View {
        header
            .clientsListRow(top: EmmaSpacing.contentTop, bottom: 0, horizontal: layout.horizontalPadding)

        SegmentedFilter(
            items: AppDependencies.ClientListMode.allCases,
            selection: $dependencies.clientMode,
            title: { $0.rawValue }
        )
        .clientsListRow(top: 18, bottom: 0, horizontal: layout.horizontalPadding)

        SearchField(text: $search, placeholder: "Szukaj osoby lub tematu")
            .clientsListRow(top: 15, bottom: 0, horizontal: layout.horizontalPadding)

        filterChips
            .clientsListRow(top: 10, bottom: 8, horizontal: 0)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ScreenHeader(
                kicker: "BAZA KANCELARII",
                title: "Klienci"
            )
            IconButton(systemName: "plus", accessibilityLabel: "Dodaj leada") {
                dependencies.present(.newLead)
            }
        }
    }

    /// Chipy filtra w poziomym przewijaniu: pięć filtrów leadów nie mieści się
    /// w jednej linii na 375 pt, a zawijanie rozbijałoby pasek.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            chipRow
                .padding(.horizontal, layout.horizontalPadding)
        }
    }

    @ViewBuilder
    private var chipRow: some View {
        switch (dependencies.clientMode, store.phase) {
        case (.leads, .loaded(let model)):
            leadChips(LeadWorkflow.inbox(model.clients, now: dependencies.now))
        case (.cases, .loaded(let model)):
            ListFilterChips(
                items: CaseListFilter.allCases,
                selection: $caseFilter,
                title: { $0.rawValue },
                count: { filter in
                    switch filter {
                    case .active: return model.cases.filter { $0.status.isActive }.count
                    case .closed: return model.cases.filter { $0.status == .closed }.count
                    }
                }
            )
        case (.leads, _):
            ListFilterChips(items: LeadListFilter.allCases, selection: $leadFilter, title: { $0.rawValue })
        case (.cases, _):
            ListFilterChips(items: CaseListFilter.allCases, selection: $caseFilter, title: { $0.rawValue })
        }
    }

    /// Liczba przy filtrze mówi, ile zgłoszeń naprawdę czeka — bez tego
    /// trzeba zgadywać, czy warto przełączyć widok.
    private func leadChips(_ inbox: LeadInbox) -> some View {
        ListFilterChips(
            items: LeadListFilter.allCases,
            selection: $leadFilter,
            title: { $0.rawValue },
            count: { filter in filter.count(in: inbox) },
            attention: { filter in filter == .waiting && !inbox.waiting.isEmpty }
        )
    }

    // MARK: Lista

    @ViewBuilder
    private var listContent: some View {
        switch store.phase {
        case .idle, .loading:
            LoadingState("Wczytuję bazę kancelarii…")
                .clientsListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
        case .failed(let failure):
            LoadFailureView(failure) {
                Task { await store.load(dependencies) }
            }
            .clientsListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
        case .loaded(let model):
            switch dependencies.clientMode {
            case .leads:
                leadsList(model)
            case .cases:
                casesList(model)
            }
        }
    }

    @ViewBuilder
    private func leadsList(_ model: ClientsModel) -> some View {
        let sections = leadSections(model)
        if sections.isEmpty {
            leadsEmptyState
                .clientsListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
        } else {
            ForEach(sections) { section in
                if let title = section.title {
                    LeadGroupHeader(title: title, count: section.clients.count, status: section.status)
                        .clientsListRow(top: 12, bottom: 2, horizontal: layout.horizontalPadding)
                }
                ForEach(section.clients) { client in
                    leadRow(client, model: model)
                }
            }
            Color.clear
                .frame(height: EmmaSpacing.contentBottom)
                .clientsListRow(top: 0, bottom: 0, horizontal: 0)
        }
    }

    private func leadRow(_ client: Client, model: ClientsModel) -> some View {
        LeadCard(
            client: client,
            nextEvent: model.nextLeadEvents[client.id],
            onOpen: { dependencies.openPerson(client.id) },
            onMarkHandled: { await LeadActions.markHandled(client, dependencies: dependencies) },
            onReopen: { await LeadActions.reopen(client, dependencies: dependencies) },
            onConvert: { pendingConversion = client },
            onRename: { beginRename(client) },
            onDelete: { pendingDelete = client }
        )
        .clientsListRow(top: 5.5, bottom: 5.5, horizontal: layout.horizontalPadding)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if client.stage == .new {
                Button {
                    Task { await LeadActions.markHandled(client, dependencies: dependencies) }
                } label: {
                    Label("Obsłużone", systemImage: "checkmark")
                }
                .tint(EmmaTheme.pillGreenText)
            } else if client.stage == .inContact {
                Button {
                    Task { await LeadActions.reopen(client, dependencies: dependencies) }
                } label: {
                    Label("Do obsługi", systemImage: "arrow.uturn.backward")
                }
                .tint(EmmaTheme.accent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = client
            } label: {
                Label("Usuń", systemImage: "trash")
            }
            Button {
                pendingConversion = client
            } label: {
                Label("Klient", systemImage: "person.crop.circle.badge.checkmark")
            }
            .tint(EmmaTheme.primaryButton)
        }
    }

    @ViewBuilder
    private var leadsEmptyState: some View {
        if leadFilter == .needsAction && normalizedQuery.isEmpty {
            EmptyState(
                systemImage: "checkmark.seal",
                title: "Wszystko obsłużone",
                message: "Nowe zgłoszenia ze strony pojawią się tutaj. Obsłużone znajdziesz w „W kontakcie”."
            )
        } else {
            EmptyState(
                systemImage: "person.crop.circle.badge.plus",
                title: "Brak zgłoszeń w tym widoku",
                message: "Wybierz inny filtr lub dodaj nowy kontakt."
            )
        }
    }

    @ViewBuilder
    private func casesList(_ model: ClientsModel) -> some View {
        let rows = filteredCases(model)
        if rows.isEmpty {
            EmptyState(
                systemImage: "folder",
                title: "Brak pasujących spraw",
                message: "Zmień filtr lub utwórz sprawę z karty klienta."
            )
            .clientsListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
        } else {
            ForEach(rows) { legalCase in
                CaseCard(
                    legalCase: legalCase,
                    clientName: model.clientNames[legalCase.clientID] ?? "",
                    openTaskCount: model.openTaskCounts[legalCase.id] ?? 0,
                    nextEvent: model.nextCaseEvents[legalCase.id],
                    onOpen: { dependencies.openCase(legalCase.id) }
                )
                .clientsListRow(top: 5.5, bottom: 5.5, horizontal: layout.horizontalPadding)
            }
            Color.clear
                .frame(height: EmmaSpacing.contentBottom)
                .clientsListRow(top: 0, bottom: 0, horizontal: 0)
        }
    }

    // MARK: Filtrowanie i grupy

    /// Grupy listy leadów. „Do obsługi” i „Wszystkie” mają nagłówki grup,
    /// pojedyncze filtry — jedną listę bez nagłówka.
    private func leadSections(_ model: ClientsModel) -> [LeadSection] {
        let query = normalizedQuery
        let matching = model.clients.filter { client in
            client.stage != .client && SearchText.matches(query, in: [client.displayName, client.topic])
        }
        let inbox = LeadWorkflow.inbox(matching, now: dependencies.now)

        var sections: [LeadSection] = []
        switch leadFilter {
        case .needsAction:
            sections.append(LeadSection(id: "waiting", title: "Czekają na kontakt", status: .waiting, clients: inbox.waiting))
            sections.append(LeadSection(id: "fresh", title: "Nowe · ostatnie 24 h", status: .fresh, clients: inbox.fresh))
        case .fresh:
            sections.append(LeadSection(id: "fresh", title: nil, status: .fresh, clients: inbox.fresh))
        case .waiting:
            sections.append(LeadSection(id: "waiting", title: nil, status: .waiting, clients: inbox.waiting))
        case .inContact:
            sections.append(LeadSection(id: "contact", title: nil, status: .inContact, clients: inbox.inContact))
        case .all:
            sections.append(LeadSection(id: "waiting", title: "Czekają na kontakt", status: .waiting, clients: inbox.waiting))
            sections.append(LeadSection(id: "fresh", title: "Nowe", status: .fresh, clients: inbox.fresh))
            sections.append(LeadSection(id: "contact", title: "W kontakcie", status: .inContact, clients: inbox.inContact))
        }
        return sections.filter { !$0.clients.isEmpty }
    }

    private func filteredCases(_ model: ClientsModel) -> [LegalCase] {
        let query = normalizedQuery
        return model.cases.filter { legalCase in
            let matchesFilter = caseFilter == .closed
                ? legalCase.status == .closed
                : legalCase.status.isActive
            guard matchesFilter else { return false }
            let name = model.clientNames[legalCase.clientID] ?? ""
            return SearchText.matches(query, in: [legalCase.title, legalCase.number, name])
        }
    }

    /// Zapytanie trafia do `SearchText`, które odpowiada za normalizację.
    private var normalizedQuery: String { search }

    /// Filtr zamówiony z innego ekranu (np. „Wszystkie” na „Dzisiaj”).
    private func consumePendingFilter() {
        guard let filter = dependencies.pendingLeadFilter else { return }
        dependencies.pendingLeadFilter = nil
        search = ""
        leadFilter = filter
    }

    // MARK: Okna potwierdzeń

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var conversionBinding: Binding<Bool> {
        Binding(
            get: { pendingConversion != nil },
            set: { if !$0 { pendingConversion = nil } }
        )
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }

    // MARK: Zmiana nazwy

    private func beginRename(_ client: Client) {
        renameText = client.displayName
        renaming = client
    }

    private func commitRename() {
        guard let client = renaming else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard trimmed.count >= 2, trimmed != client.displayName else { return }

        var updated = client
        updated.displayName = trimmed
        let draft = updated
        Task {
            await dependencies.perform {
                try await dependencies.repository.updateClient(draft, expectedVersion: client.version)
            }
        }
    }

    // MARK: Usuwanie i konwersja

    /// Usunięcie jest nieodwracalne, więc pytamy wprost i pokazujemy, kogo
    /// dotyczy — przy dwóch podobnych zgłoszeniach łatwo skasować nie to.
    private func commitDelete() {
        guard let client = pendingDelete else { return }
        pendingDelete = nil
        Task {
            let deleted = await dependencies.perform { () async throws -> Bool in
                try await dependencies.repository.deleteClient(client, expectedVersion: client.version)
                return true
            }
            if deleted == true {
                dependencies.showToast("Usunięto zgłoszenie: \(client.displayName)")
            }
        }
    }

    /// Wejście na etap `client` jest w backendzie **konwersją zgłoszenia
    /// w klienta** — dlatego pytamy o to wprost, zamiast po cichu zakładać kartotekę.
    private func commitConversion(_ client: Client) {
        pendingConversion = nil
        Task { await LeadActions.convertToClient(client, dependencies: dependencies) }
    }
}

// MARK: - Grupy listy leadów

private struct LeadSection: Identifiable {
    let id: String
    let title: String?
    let status: LeadStatus
    let clients: [Client]
}

/// Nagłówek grupy: „CZEKAJĄ NA KONTAKT · 2” z kropką w kolorze stanu.
private struct LeadGroupHeader: View {
    let title: String
    let count: Int
    let status: LeadStatus

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(LeadStatusStyle.tone(status))
                .frame(width: 7, height: 7)
            Text(title.uppercased())
                .font(EmmaTypography.caption(.semibold))
                .tracking(0.6)
                .foregroundStyle(status == .waiting ? EmmaTheme.pillAmberText : EmmaTheme.mutedSoft)
            Text("\(count)")
                .font(EmmaTypography.caption(.medium))
                .foregroundStyle(EmmaTheme.mutedSoft)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private extension View {
    /// Wiersz listy wyglądający jak zwykły widok: bez tła, separatorów
    /// i systemowych marginesów — karty mają własny wygląd.
    func clientsListRow(top: CGFloat, bottom: CGFloat, horizontal: CGFloat) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// MARK: - Filtry listy

/// Filtr listy leadów. Domyślny jest „Do obsługi” (nowe i oczekujące).
enum LeadListFilter: String, Hashable, CaseIterable {
    case needsAction = "Do obsługi"
    case fresh = "Nowe"
    case waiting = "Oczekujące"
    case inContact = "W kontakcie"
    case all = "Wszystkie"

    func count(in inbox: LeadInbox) -> Int {
        switch self {
        case .needsAction: return inbox.needsAction.count
        case .fresh: return inbox.fresh.count
        case .waiting: return inbox.waiting.count
        case .inContact: return inbox.inContact.count
        case .all: return inbox.needsAction.count + inbox.inContact.count
        }
    }
}

/// Filtr listy spraw. Aktywne to wszystkie poza zamkniętymi (`CaseStatus.isActive`).
enum CaseListFilter: String, Hashable, CaseIterable {
    case active = "Aktywne"
    case closed = "Zamknięte"
}

/// Chipy filtra (`.filter-chips`). Design system nie ma komponentu chipów,
/// dlatego powstaje tutaj — z tokenów, bez literałów kolorów.
/// Wizualna wysokość 36 pt, obszar dotyku rozszerzony do 44 pt (§2.2).
struct ListFilterChips<Item: Hashable>: View {

    private let items: [Item]
    @Binding private var selection: Item
    private let title: (Item) -> String
    private let count: ((Item) -> Int)?
    /// Filtr, który wymaga uwagi (np. „Oczekujące” z niezerową liczbą) —
    /// licznik jest wtedy bursztynowy także bez zaznaczenia.
    private let attention: ((Item) -> Bool)?

    init(
        items: [Item],
        selection: Binding<Item>,
        title: @escaping (Item) -> String,
        count: ((Item) -> Int)? = nil,
        attention: ((Item) -> Bool)? = nil
    ) {
        self.items = items
        self._selection = selection
        self.title = title
        self.count = count
        self.attention = attention
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(items, id: \.self) { item in
                chip(item)
            }
        }
    }

    private func chip(_ item: Item) -> some View {
        let isSelected = item == selection
        let needsAttention = attention?(item) ?? false
        return Button {
            if selection != item {
                EmmaHaptics.selection()
            }
            selection = item
        } label: {
            HStack(spacing: 5) {
                Text(title(item))
                    .font(EmmaTypography.caption(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? EmmaTheme.ink : EmmaTheme.mutedSoft)
                if let count {
                    Text("\(count(item))")
                        .font(EmmaTypography.caption(.semibold))
                        .foregroundStyle(needsAttention ? EmmaTheme.pillAmberText : EmmaTheme.mutedSoft)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 36)
            .background(isSelected ? EmmaTheme.surface : Color.clear)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(isSelected ? EmmaTheme.border : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: EmmaSpacing.hitTarget)
        .accessibilityLabel(label(item))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Licznik doklejamy do etykiety, bo filtr ma od razu odpowiadać na pytanie
    /// „ile tam czeka”, a nie tylko zmieniać zawartość listy.
    private func label(_ item: Item) -> String {
        guard let count else { return title(item) }
        return "\(title(item)) \(count(item))"
    }
}

#Preview("Klienci") {
    let dependencies = AppDependencies.demo()
    return ClientsScreen(store: dependencies.clientsStore)
        .environmentObject(dependencies)
}
