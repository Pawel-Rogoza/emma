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
    @State private var leadFilter: LeadListFilter = .all
    @State private var caseFilter: CaseListFilter = .active

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
            leadFilter = .all
            caseFilter = .active
        }
    }

    // MARK: Nagłówek

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ScreenHeader(
                kicker: "BAZA KANCELARII",
                title: "Klienci",
                userInitials: dependencies.currentUser.initials,
                onUserTap: { dependencies.present(.profile) }
            )
            IconButton(systemName: "plus", accessibilityLabel: "Dodaj leada") {
                dependencies.present(.newLead)
            }
        }
    }

    // MARK: Filtry

    @ViewBuilder
    private var filterChips: some View {
        switch dependencies.clientMode {
        case .leads:
            ListFilterChips(items: LeadListFilter.allCases, selection: $leadFilter, title: { $0.rawValue })
        case .cases:
            ListFilterChips(items: CaseListFilter.allCases, selection: $caseFilter, title: { $0.rawValue })
        }
    }

    // MARK: Lista

    @ViewBuilder
    private var list: some View {
        switch store.phase {
        case .idle, .loading:
            LoadingState("Wczytuję bazę kancelarii…")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                InlineError(message)
                SecondaryButton("Spróbuj ponownie", systemImage: "arrow.clockwise") {
                    Task { await store.load(dependencies) }
                }
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
                    LeadCard(client: client, nextEvent: model.nextLeadEvents[client.id]) {
                        dependencies.openPerson(client.id)
                    }
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
            guard !query.isEmpty else { return true }
            let haystack = "\(client.displayName) \(client.topic)".lowercased()
            return haystack.contains(query)
        }
    }

    private func filteredCases(_ model: ClientsModel) -> [LegalCase] {
        let query = normalizedQuery
        return model.cases.filter { legalCase in
            let matchesFilter = caseFilter == .closed
                ? legalCase.status == .closed
                : legalCase.status.isActive
            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            let name = model.clientNames[legalCase.clientID] ?? ""
            let haystack = "\(legalCase.title) \(legalCase.number) \(name)".lowercased()
            return haystack.contains(query)
        }
    }

    private var normalizedQuery: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
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

    init(items: [Item], selection: Binding<Item>, title: @escaping (Item) -> String) {
        self.items = items
        self._selection = selection
        self.title = title
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    selection = item
                } label: {
                    Text(title(item))
                        .font(EmmaTypography.ui(11, isSelected ? .medium : .regular))
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
                .accessibilityLabel(title(item))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

#Preview("Klienci") {
    ClientsScreen()
        .environmentObject(AppDependencies.demo())
}
