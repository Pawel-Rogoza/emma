import SwiftUI

// MARK: - Ekran „Klienci”
//
// Port stanów `clients()` i `clientList()` z referencji: jeden ekran, dwa tryby
// (Leady / Sprawy). Tryb mieszka w `AppDependencies`, bo przełącza go także
// pulpit „Dzisiaj” (`selectClients(mode)`), a wyszukiwanie i filtr są lokalne.

struct ClientsScreen: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout

    @StateObject private var store = ClientsStore()
    @State private var search = ""
    /// Domyślnie pokazujemy **nowe** zgłoszenia.
    ///
    /// Leady to rezerwacje konsultacji ze strony — sensem tego ekranu jest
    /// przerobienie świeżych zgłoszeń, a nie przeklikanie całej kartoteki.
    /// Zgłoszenia, których nikt nie ruszył, zostają „nowe" i gromadzą się
    /// (na produkcji 8 z 25), więc widok otwiera się dokładnie na nich.
    @State private var leadFilter: LeadListFilter = .new
    @State private var caseFilter: CaseListFilter = .active
    /// Nazwa leada w trakcie zmiany — `nil` znaczy, że okno jest zamknięte.
    @State private var renaming: Client?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                SegmentedFilter(
                    items: AppDependencies.ClientListMode.allCases,
                    selection: $dependencies.clientMode,
                    title: { $0.rawValue }
                )
                .padding(.top, 18)

                SearchField(text: $search, placeholder: "Szukaj osoby lub tematu")
                    .padding(.top, 15)

                filterChips
                    .padding(.top, 15)
                    .padding(.bottom, 18)

                list
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, EmmaSpacing.contentTop)
            .padding(.bottom, EmmaSpacing.contentBottom)
        }
        .background(EmmaTheme.bg)
        .task(id: dependencies.dataVersion) { await store.load(dependencies) }
        .onChange(of: dependencies.clientMode) { _, _ in
            // `setClientMode` w referencji czyści wyszukiwanie i wraca do pierwszego filtra.
            search = ""
            leadFilter = .new
            caseFilter = .active
        }
        .alert("Zmień nazwę", isPresented: renameBinding) {
            TextField("Imię i nazwisko", text: $renameText)
            Button("Anuluj", role: .cancel) { renaming = nil }
            Button("Zapisz") { commitRename() }
        } message: {
            Text("Nazwa pojawi się na liście i w karcie.")
        }
    }

    // MARK: Zmiana nazwy

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }

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
        Task {
            await dependencies.perform {
                try await dependencies.repository.updateClient(updated, expectedVersion: client.version)
            }
        }
    }

    // MARK: Zmiana etapu

    /// Przeniesienie leada między etapami. Wejście na etap `client` jest
    /// w backendzie **konwersją zgłoszenia w klienta** — dlatego menu pyta
    /// o to wprost, zamiast po cichu zakładać kartotekę.
    private func move(_ client: Client, to stage: ClientStage) {
        guard stage != client.stage else { return }
        var updated = client
        updated.stage = stage
        Task {
            await dependencies.perform {
                try await dependencies.repository.updateClient(updated, expectedVersion: client.version)
            }
        }
    }

    // MARK: Nagłówek

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ScreenHeader(
                kicker: "BAZA KANCELARII",
                title: "Klienci",
            )
            IconButton(systemName: "plus", accessibilityLabel: "Dodaj leada") {
                dependencies.present(.newLead)
            }
        }
    }

    // MARK: Filtry

    @ViewBuilder
    private var filterChips: some View {
        switch (dependencies.clientMode, store.phase) {
        case (.leads, .loaded(let model)):
            // Liczba przy filtrze mówi, ile zgłoszeń naprawdę czeka — bez tego
            // trzeba zgadywać, czy warto przełączyć widok.
            ListFilterChips(
                items: LeadListFilter.allCases,
                selection: $leadFilter,
                title: { $0.rawValue },
                count: { filter in
                    switch filter {
                    case .all: return model.clients.filter { $0.stage != .client }.count
                    case .new: return model.clients.filter { $0.stage == .new }.count
                    case .inContact: return model.clients.filter { $0.stage == .inContact }.count
                    }
                }
            )
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

    // MARK: Lista

    @ViewBuilder
    private var list: some View {
        switch store.phase {
        case .idle, .loading:
            LoadingState("Wczytuję bazę kancelarii…")
        case .failed(let failure):
            LoadFailureView(failure) {
                Task { await store.load(dependencies) }
            }
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
        let rows = filteredLeads(model)
        if rows.isEmpty {
            EmptyState(
                systemImage: "person.crop.circle.badge.plus",
                title: "Brak zgłoszeń w tym widoku",
                message: "Wybierz inny filtr lub dodaj nowy kontakt."
            )
        } else {
            LazyVStack(spacing: EmmaSpacing.cardGap) {
                ForEach(rows) { client in
                    LeadCard(
                        client: client,
                        nextEvent: model.nextLeadEvents[client.id],
                        onOpen: { dependencies.openPerson(client.id) },
                        onSetStage: { stage in move(client, to: stage) },
                        onRename: { beginRename(client) }
                    )
                }
            }
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
        } else {
            LazyVStack(spacing: EmmaSpacing.cardGap) {
                ForEach(rows) { legalCase in
                    CaseCard(
                        legalCase: legalCase,
                        clientName: model.clientNames[legalCase.clientID] ?? "",
                        openTaskCount: model.openTaskCounts[legalCase.id] ?? 0,
                        nextEvent: model.nextCaseEvents[legalCase.id],
                        onOpen: { dependencies.openCase(legalCase.id) }
                    )
                }
            }
        }
    }

    // MARK: Filtrowanie (odpowiada `clientList()`)

    private func filteredLeads(_ model: ClientsModel) -> [Client] {
        let query = normalizedQuery
        return model.clients.filter { client in
            guard client.stage != .client else { return false }
            switch leadFilter {
            case .all:
                break
            case .new:
                guard client.stage == .new else { return false }
            case .inContact:
                guard client.stage == .inContact else { return false }
            }
            return SearchText.matches(query, in: [client.displayName, client.topic])
        }
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
}

// MARK: - Filtry listy

/// Filtr listy leadów. Kolejność i etykiety z referencji.
enum LeadListFilter: String, Hashable, CaseIterable {
    case all = "Wszystkie"
    case new = "Nowe"
    case inContact = "W kontakcie"
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

    init(
        items: [Item],
        selection: Binding<Item>,
        title: @escaping (Item) -> String,
        count: ((Item) -> Int)? = nil
    ) {
        self.items = items
        self._selection = selection
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    selection = item
                } label: {
                    Text(label(item))
                        .font(EmmaTypography.caption(isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? EmmaTheme.secondaryButtonText : EmmaTheme.mutedSoft)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .frame(minHeight: 36)
                        .background(isSelected ? EmmaTheme.surface : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.segmentedInner, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: EmmaRadii.segmentedInner, style: .continuous)
                                .strokeBorder(isSelected ? EmmaTheme.border : Color.clear, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: EmmaSpacing.hitTarget)
                .accessibilityLabel(label(item))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    /// Licznik doklejamy do etykiety, bo filtr ma od razu odpowiadać na pytanie
    /// „ile tam czeka”, a nie tylko zmieniać zawartość listy.
    private func label(_ item: Item) -> String {
        guard let count else { return title(item) }
        return "\(title(item)) \(count(item))"
    }
}

#Preview("Klienci") {
    ClientsScreen()
        .environmentObject(AppDependencies.demo())
}
