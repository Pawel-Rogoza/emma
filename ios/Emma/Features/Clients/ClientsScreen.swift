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
//   • review 24.09.2026: „Nowe” i „Oczekujące” to jedna kolejka „Do obsługi”
//     (oczekujące wyróżnia bursztynowa plakietka), obok „W kontakcie” i „Wszystkie”,
//   • zgłoszenie przenosi się do „W kontakcie” przyciskiem na karcie albo
//     przesunięciem w prawo; w lewo jest usunięcie. Osobnej „konwersji na
//     klienta” już nie ma — kartoteka powstaje przy „Przyjmij sprawę”,
//   • lista stoi na `List`, bo tylko ona daje systemowe przesunięcia z obsługą
//     VoiceOver; wygląd kart pozostaje własny (tło i separatory wyłączone),
//   • pociągnięcie w dół odświeża listę (nowe zgłoszenia ze strony).
//
// Review 27.09.2026 („wszystko się zlewa, nie odróżnisz jednego od drugiego”):
//   • trzy tryby: Leady · Klienci · Sprawy — kartoteka klientów kancelarii
//     wcześniej była osiągalna tylko przez wyszukiwanie,
//   • nad listą trzy kafelki podsumowania (jak puls dnia na „Dzisiaj”);
//     dotknięcie ustawia filtr albo przewija do grupy,
//   • każda osoba ma stały kolor awatara i plakietkę języka (D-34),
//   • sprawy w grupach „Wymaga uwagi” → „W toku” → „Czekamy na klienta”,
//     z plakietką „dziś / jutro / za 5 dni” zamiast stałego „W toku”,
//   • leady do obsługi rozdzielone na „Czekają ponad dobę” i „Nowe”,
//   • wyszukiwanie obejmuje też numery i tytuły spraw.

struct ClientsScreen: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout

    /// Magazyn żyje w `AppDependencies`, więc powrót na zakładkę nie mruga
    /// stanem ładowania, a lista od razu pokazuje ostatni stan.
    @ObservedObject var store: ClientsStore

    @State private var search = ""
    /// Domyślnie kolejka „Do obsługi” — nowe i oczekujące zgłoszenia.
    @State private var leadFilter: LeadListFilter = .needsAction
    @State private var clientFilter: ClientDirectoryFilter = .all
    @State private var caseFilter: CaseListFilter = .active
    /// Nazwa leada w trakcie zmiany — `nil` znaczy, że okno jest zamknięte.
    @State private var renaming: Client?
    @State private var renameText = ""
    /// Zgłoszenie czekające na potwierdzenie usunięcia.
    @State private var pendingDelete: Client?

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
        .onAppear { consumePendingFilter() }
        .onChange(of: dependencies.pendingLeadFilter) { _, _ in consumePendingFilter() }
        .onChange(of: dependencies.clientMode) { _, _ in
            // `setClientMode` w referencji czyści wyszukiwanie i wraca do pierwszego filtra.
            search = ""
            leadFilter = .needsAction
            clientFilter = .all
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
    }

    // MARK: Nagłówek i sterowanie

    @ViewBuilder
    private func controls(_ proxy: ScrollViewProxy) -> some View {
        header
            .id(Self.topID)
            .clientsListRow(top: EmmaSpacing.contentTop, bottom: 0, horizontal: layout.horizontalPadding)

        SegmentedFilter(
            items: AppDependencies.ClientListMode.allCases,
            selection: $dependencies.clientMode,
            title: { $0.rawValue }
        )
        .clientsListRow(top: 14, bottom: 0, horizontal: layout.horizontalPadding)

        if case .loaded(let model) = store.phase {
            summaryTiles(model, proxy: proxy)
                .clientsListRow(top: 14, bottom: 0, horizontal: layout.horizontalPadding)
        }

        SearchField(text: $search, placeholder: searchPlaceholder)
            .clientsListRow(top: 14, bottom: 0, horizontal: layout.horizontalPadding)

        filterChips
            .clientsListRow(top: 8, bottom: 6, horizontal: 0)
    }

    /// Sam tytuł, bez podpisu „BAZA KANCELARII” — kafelki pod spodem mówią więcej,
    /// a pierwsza karta wchodzi wyżej.
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Klienci")
                .font(EmmaTypography.welcome)
                .tracking(-0.9)
                .foregroundStyle(EmmaTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(systemName: "plus", accessibilityLabel: "Dodaj leada") {
                dependencies.present(.newLead)
            }
        }
    }

    private var searchPlaceholder: String {
        switch dependencies.clientMode {
        case .leads: return "Szukaj osoby lub tematu"
        case .clients: return "Szukaj klienta, sprawy lub numeru"
        case .cases: return "Szukaj sprawy, numeru lub klienta"
        }
    }

    // MARK: Kafelki podsumowania

    @ViewBuilder
    private func summaryTiles(_ model: ClientsModel, proxy: ScrollViewProxy) -> some View {
        switch dependencies.clientMode {
        case .leads:
            let inbox = LeadWorkflow.inbox(model.clients, now: dependencies.now)
            let booked = (inbox.needsAction + inbox.inContact).filter { model.nextClientEvents[$0.id] != nil }.count
            HStack(spacing: 8) {
                PulseTile(
                    value: inbox.needsAction.count,
                    label: "do obsługi",
                    systemImage: "tray.full",
                    tone: EmmaTheme.accent
                ) { selectLeadFilter(.needsAction) }
                PulseTile(
                    value: inbox.waiting.count,
                    label: "czeka ponad dobę",
                    systemImage: "clock",
                    tone: inbox.waiting.isEmpty ? EmmaTheme.accent : EmmaTheme.pillAmberText
                ) { selectLeadFilter(.needsAction) }
                PulseTile(
                    value: booked,
                    label: EmmaPlural.form(booked, "umówiona konsultacja", "umówione konsultacje", "umówionych konsultacji"),
                    systemImage: "calendar",
                    tone: EmmaTheme.accent
                ) { selectLeadFilter(.all) }
            }
        case .clients:
            let firm = firmClients(model)
            let withCase = firm.filter { hasActiveCase($0, model) }.count
            let attention = firm.filter { needsAttention($0, model) }.count
            HStack(spacing: 8) {
                PulseTile(
                    value: firm.count,
                    label: EmmaPlural.form(firm.count, "klient", "klientów", "klientów"),
                    systemImage: "person.2",
                    tone: EmmaTheme.accent
                ) { selectClientFilter(.all) }
                PulseTile(
                    value: withCase,
                    label: "z aktywną sprawą",
                    systemImage: "folder",
                    tone: EmmaTheme.accent
                ) { selectClientFilter(.withActiveCase) }
                PulseTile(
                    value: attention,
                    label: "wymaga uwagi",
                    systemImage: "exclamationmark.circle",
                    tone: attention > 0 ? EmmaTheme.pillDangerText : EmmaTheme.accent
                ) { selectClientFilter(.needsAttention) }
            }
        case .cases:
            let board = caseBoard(model.cases, model: model)
            let active = board.attention.count + board.inProgress.count + board.awaitingClient.count
            HStack(spacing: 8) {
                PulseTile(
                    value: active,
                    label: EmmaPlural.form(active, "aktywna sprawa", "aktywne sprawy", "aktywnych spraw"),
                    systemImage: "folder",
                    tone: EmmaTheme.accent
                ) { showCaseGroup(nil, proxy: proxy) }
                PulseTile(
                    value: board.attention.count,
                    label: "wymaga uwagi",
                    systemImage: "exclamationmark.circle",
                    tone: board.attention.isEmpty ? EmmaTheme.accent : EmmaTheme.pillDangerText
                ) { showCaseGroup(.attention, proxy: proxy) }
                PulseTile(
                    value: board.awaitingClient.count,
                    label: "czeka na klienta",
                    systemImage: "hourglass",
                    tone: EmmaTheme.accent
                ) { showCaseGroup(.awaitingClient, proxy: proxy) }
            }
        }
    }

    private func selectLeadFilter(_ filter: LeadListFilter) {
        search = ""
        leadFilter = filter
    }

    private func selectClientFilter(_ filter: ClientDirectoryFilter) {
        search = ""
        clientFilter = filter
    }

    /// Kafelek spraw nie zmienia zawartości listy, tylko przewija do grupy —
    /// wszystkie aktywne sprawy zostają widoczne.
    private func showCaseGroup(_ group: CaseBoard.Group?, proxy: ScrollViewProxy) {
        search = ""
        caseFilter = .active
        Task { @MainActor in
            // Najpierw lista musi przebudować się po zmianie filtra.
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(group.map(Self.groupID) ?? Self.topID, anchor: .top)
            }
        }
    }

    private static let topID = "clients-top"

    private static func groupID(_ group: CaseBoard.Group) -> String {
        "case-group-\(group)"
    }

    // MARK: Filtry

    /// Chipy filtra w poziomym przewijaniu: na 375 pt nie zawsze mieszczą się
    /// w jednej linii, a zawijanie rozbijałoby pasek.
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
        case (.clients, .loaded(let model)):
            let firm = firmClients(model)
            ListFilterChips(
                items: ClientDirectoryFilter.allCases,
                selection: $clientFilter,
                title: { $0.rawValue },
                count: { filter in firm.filter { matches(filter, $0, model) }.count },
                attention: { filter in
                    filter == .needsAttention && firm.contains { needsAttention($0, model) }
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
        case (.clients, _):
            ListFilterChips(items: ClientDirectoryFilter.allCases, selection: $clientFilter, title: { $0.rawValue })
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
            attention: { filter in filter == .needsAction && !inbox.waiting.isEmpty }
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
            case .clients:
                clientsList(model)
            case .cases:
                casesList(model)
            }
        }
    }

    private var bottomSpacer: some View {
        Color.clear
            .frame(height: EmmaSpacing.contentBottom)
            .clientsListRow(top: 0, bottom: 0, horizontal: 0)
    }

    // MARK: Leady

    @ViewBuilder
    private func leadsList(_ model: ClientsModel) -> some View {
        let sections = leadSections(model)
        if sections.isEmpty {
            leadsEmptyState
                .clientsListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
        } else {
            ForEach(sections) { section in
                if let title = section.title {
                    GroupHeader(
                        title: title,
                        count: section.clients.count,
                        tone: LeadStatusStyle.tone(section.status),
                        emphasized: section.status == .waiting
                    )
                    .clientsListRow(top: 12, bottom: 2, horizontal: layout.horizontalPadding)
                }
                ForEach(section.clients) { client in
                    leadRow(client, model: model)
                }
            }
            bottomSpacer
        }
    }

    private func leadRow(_ client: Client, model: ClientsModel) -> some View {
        LeadCard(
            client: client,
            nextEvent: model.nextLeadEvents[client.id],
            onOpen: { dependencies.openPerson(client.id) },
            onMarkHandled: { await LeadActions.markInContact(client, dependencies: dependencies) },
            onReopen: { await LeadActions.reopen(client, dependencies: dependencies) },
            onRename: { beginRename(client) },
            onDelete: { pendingDelete = client }
        )
        .clientsListRow(top: 5.5, bottom: 5.5, horizontal: layout.horizontalPadding)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if client.stage == .new {
                Button {
                    Task { await LeadActions.markInContact(client, dependencies: dependencies) }
                } label: {
                    Label("W kontakcie", systemImage: "checkmark")
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
            // Kartoteki nie usuwa się z aplikacji.
            if client.stage != .client {
                Button(role: .destructive) {
                    pendingDelete = client
                } label: {
                    Label("Usuń", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var leadsEmptyState: some View {
        if leadFilter == .needsAction && search.isEmpty {
            EmptyState(
                systemImage: "checkmark.seal",
                title: "Wszystko obsłużone",
                message: "Nowe zgłoszenia ze strony pojawią się tutaj. Te, z którymi już rozmawiasz, są w „W kontakcie”."
            )
        } else {
            EmptyState(
                systemImage: "person.crop.circle.badge.plus",
                title: search.isEmpty ? "Brak zgłoszeń w tym widoku" : "Nikogo nie znaleziono",
                message: "Wybierz inny filtr lub dodaj nowy kontakt."
            )
        }
    }

    /// Grupy listy leadów. Kolejka „Do obsługi” dzieli się na zgłoszenia, które
    /// czekają ponad dobę, i nowe — wcześniej jedna lista wyróżniała je tylko
    /// kolorem plakietki. Wyszukiwanie przeszukuje wszystko, także kartotekę.
    private func leadSections(_ model: ClientsModel) -> [LeadSection] {
        let query = search
        let matching = model.clients.filter { client in
            client.stage != .client && SearchText.matches(query, in: [client.displayName, client.topic])
        }
        let inbox = LeadWorkflow.inbox(matching, now: dependencies.now)

        let waiting = LeadSection(id: "waiting", title: "Czekają ponad dobę", status: .waiting, clients: inbox.waiting)
        let fresh = LeadSection(id: "fresh", title: "Nowe", status: .fresh, clients: inbox.fresh)
        let contact = LeadSection(id: "contact", title: "W kontakcie", status: .inContact, clients: inbox.inContact)

        var sections: [LeadSection] = []
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter: LeadListFilter = trimmedQuery.isEmpty ? leadFilter : .all
        switch filter {
        case .needsAction:
            sections = [waiting, fresh]
        case .inContact:
            sections = [LeadSection(id: "contact", title: nil, status: .inContact, clients: inbox.inContact)]
        case .all:
            sections = [waiting, fresh, contact]
        }
        if !trimmedQuery.isEmpty {
            let firm = model.clients
                .filter { $0.stage == .client && SearchText.matches(query, in: [$0.displayName, $0.topic]) }
                .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
            sections.append(LeadSection(id: "clients", title: "Klienci kancelarii", status: .client, clients: firm))
        }
        return sections.filter { !$0.clients.isEmpty }
    }

    // MARK: Klienci

    @ViewBuilder
    private func clientsList(_ model: ClientsModel) -> some View {
        let rows = firmClients(model).filter { client in
            matches(clientFilter, client, model) && matchesSearch(client, model)
        }
        let recent = recentClients(model)
        if search.isEmpty && clientFilter == .all && !recent.isEmpty {
            RecentClientsStrip(clients: recent, horizontalPadding: layout.horizontalPadding) { client in
                dependencies.openPerson(client.id)
            }
            .clientsListRow(top: 6, bottom: 4, horizontal: 0)
        }
        if rows.isEmpty {
            EmptyState(
                systemImage: "person.2",
                title: search.isEmpty ? "Brak klientów w tym widoku" : "Nikogo nie znaleziono",
                message: "Klient pojawia się tu po „Przyjmij sprawę” na karcie zgłoszenia."
            )
            .clientsListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
        } else {
            ForEach(ClientDirectory.sections(rows)) { section in
                GroupHeader(title: section.letter, count: section.clients.count, tone: nil, emphasized: false)
                    .clientsListRow(top: 12, bottom: 2, horizontal: layout.horizontalPadding)
                ForEach(section.clients) { client in
                    ClientDirectoryCard(
                        client: client,
                        cases: model.casesByClient[client.id] ?? [],
                        nextEvent: model.nextClientEvents[client.id],
                        overdueTaskCount: model.clientOverdueTaskCounts[client.id] ?? 0,
                        onOpen: { dependencies.openPerson(client.id) }
                    )
                    .clientsListRow(top: 5, bottom: 5, horizontal: layout.horizontalPadding)
                }
            }
            bottomSpacer
        }
    }

    private func firmClients(_ model: ClientsModel) -> [Client] {
        model.clients.filter { $0.stage == .client }
    }

    private func hasActiveCase(_ client: Client, _ model: ClientsModel) -> Bool {
        (model.casesByClient[client.id] ?? []).contains { $0.status.isActive }
    }

    /// Klient „wymaga uwagi”, gdy ma zaległe zadanie albo termin w ciągu tygodnia
    /// — ta sama miara co przy sprawach (`CaseUrgency`).
    private func needsAttention(_ client: Client, _ model: ClientsModel) -> Bool {
        CaseUrgency(
            nextEvent: model.nextClientEvents[client.id]?.day,
            overdueTasks: model.clientOverdueTaskCounts[client.id] ?? 0,
            today: dependencies.today
        ).needsAttention
    }

    private func matches(_ filter: ClientDirectoryFilter, _ client: Client, _ model: ClientsModel) -> Bool {
        switch filter {
        case .all: return true
        case .withActiveCase: return hasActiveCase(client, model)
        case .needsAttention: return needsAttention(client, model)
        }
    }

    /// Klienta można znaleźć po nazwisku, temacie, tytule i numerze jego sprawy.
    private func matchesSearch(_ client: Client, _ model: ClientsModel) -> Bool {
        let cases = model.casesByClient[client.id] ?? []
        let parts = [client.displayName, client.topic] + cases.flatMap { [$0.title, $0.number] }
        return SearchText.matches(search, in: parts)
    }

    /// Ostatnio otwierane osoby, o ile są klientami kancelarii (leady mają swoją kolejkę).
    private func recentClients(_ model: ClientsModel) -> [Client] {
        dependencies.recentClients.ids.compactMap { id in
            model.clientsByID[id].flatMap { $0.stage == .client ? $0 : nil }
        }
    }

    // MARK: Sprawy

    @ViewBuilder
    private func casesList(_ model: ClientsModel) -> some View {
        let matching = model.cases.filter { matchesSearch($0, model) }
        switch caseFilter {
        case .active:
            let board = caseBoard(matching, model: model)
            if board.attention.isEmpty && board.inProgress.isEmpty && board.awaitingClient.isEmpty {
                casesEmptyState
            } else {
                ForEach(CaseBoard.Group.allCases, id: \.self) { group in
                    let cases = board.cases(in: group)
                    if !cases.isEmpty {
                        GroupHeader(
                            title: group.rawValue,
                            count: cases.count,
                            tone: groupTone(group),
                            emphasized: group == .attention
                        )
                        .id(Self.groupID(group))
                        .clientsListRow(top: 12, bottom: 2, horizontal: layout.horizontalPadding)
                        ForEach(cases) { legalCase in
                            caseRow(legalCase, model: model)
                        }
                    }
                }
                bottomSpacer
            }
        case .closed:
            let closed = matching
                .filter { $0.status == .closed }
                .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            if closed.isEmpty {
                casesEmptyState
            } else {
                ForEach(closed) { legalCase in
                    caseRow(legalCase, model: model)
                }
                bottomSpacer
            }
        }
    }

    private func caseRow(_ legalCase: LegalCase, model: ClientsModel) -> some View {
        CaseCard(
            legalCase: legalCase,
            client: model.clientsByID[legalCase.clientID],
            openTaskCount: model.openTaskCounts[legalCase.id] ?? 0,
            overdueTaskCount: model.overdueTaskCounts[legalCase.id] ?? 0,
            nextEvent: model.nextCaseEvents[legalCase.id],
            onOpen: { dependencies.openCase(legalCase.id) }
        )
        .clientsListRow(top: 5, bottom: 5, horizontal: layout.horizontalPadding)
    }

    private var casesEmptyState: some View {
        EmptyState(
            systemImage: "folder",
            title: search.isEmpty ? "Brak spraw w tym widoku" : "Brak pasujących spraw",
            message: "Zmień filtr lub utwórz sprawę z karty klienta."
        )
        .clientsListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
    }

    private func caseBoard(_ cases: [LegalCase], model: ClientsModel) -> CaseBoard {
        CaseBoard.make(
            cases,
            nextEvents: model.nextCaseEvents,
            overdueTasks: model.overdueTaskCounts,
            today: dependencies.today
        )
    }

    private func groupTone(_ group: CaseBoard.Group) -> Color {
        switch group {
        case .attention: return EmmaTheme.pillDangerText
        case .inProgress: return EmmaTheme.pillGreenText
        case .awaitingClient: return EmmaTheme.mutedSoft
        }
    }

    private func matchesSearch(_ legalCase: LegalCase, _ model: ClientsModel) -> Bool {
        let name = model.clientsByID[legalCase.clientID]?.displayName ?? ""
        return SearchText.matches(search, in: [legalCase.title, legalCase.number, name])
    }

    // MARK: Filtr z innego ekranu

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

    // MARK: Usuwanie

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
}

// MARK: - Grupy listy

private struct LeadSection: Identifiable {
    let id: String
    let title: String?
    let status: LeadStatus
    let clients: [Client]
}

/// Nagłówek grupy: „● CZEKAJĄ PONAD DOBĘ · 2”. Kropka w kolorze stanu;
/// grupa wymagająca działania ma tytuł w tym samym kolorze.
private struct GroupHeader: View {
    let title: String
    let count: Int
    /// `nil` — nagłówek bez kropki (litera kartoteki).
    let tone: Color?
    let emphasized: Bool

    var body: some View {
        HStack(spacing: 7) {
            if let tone {
                Circle()
                    .fill(tone)
                    .frame(width: 7, height: 7)
            }
            Text(title.uppercased())
                .font(EmmaTypography.caption(.semibold))
                .tracking(0.6)
                .foregroundStyle(emphasized ? (tone ?? EmmaTheme.mutedSoft) : EmmaTheme.mutedSoft)
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

/// Filtr listy leadów. Domyślny jest „Do obsługi” (nowe i oczekujące razem).
enum LeadListFilter: String, Hashable, CaseIterable {
    case needsAction = "Do obsługi"
    case inContact = "W kontakcie"
    case all = "Wszystkie"

    func count(in inbox: LeadInbox) -> Int {
        switch self {
        case .needsAction: return inbox.needsAction.count
        case .inContact: return inbox.inContact.count
        case .all: return inbox.needsAction.count + inbox.inContact.count
        }
    }
}

/// Filtr kartoteki klientów. „Wymaga uwagi” to zaległe zadanie albo termin
/// w ciągu tygodnia (`CaseUrgency`).
enum ClientDirectoryFilter: String, Hashable, CaseIterable {
    case all = "Wszyscy"
    case withActiveCase = "Z aktywną sprawą"
    case needsAttention = "Wymaga uwagi"
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
