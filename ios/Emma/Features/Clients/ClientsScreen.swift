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
    @Environment(\.openURL) private var openURL

    /// Magazyn żyje w `AppDependencies`, więc powrót na zakładkę nie mruga
    /// stanem ładowania, a lista od razu pokazuje ostatni stan.
    @ObservedObject var store: ClientsStore
    /// Rozmowy WhatsApp — znaczniki „2 nowe” i „czeka” na kartach kartoteki.
    @ObservedObject var messages: MessagesStore

    @State private var search = ""
    @FocusState private var searchFocused: Bool
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
        .refreshable {
            await store.load(dependencies)
            await messages.load(dependencies, silent: true)
        }
        .task(id: dependencies.dataVersion) { await store.load(dependencies) }
        .task { await messages.load(dependencies, silent: true) }
        .onAppear {
            consumePendingFilter()
            consumePendingSearch()
        }
        .onChange(of: dependencies.pendingLeadFilter) { _, _ in consumePendingFilter() }
        .onChange(of: dependencies.pendingClientSearch) { _, _ in consumePendingSearch() }
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
            .emmaListRow(top: EmmaSpacing.contentTop, bottom: 0, horizontal: layout.horizontalPadding)

        SegmentedFilter(
            items: AppDependencies.ClientListMode.allCases,
            selection: $dependencies.clientMode,
            title: { $0.rawValue }
        )
        .emmaListRow(top: 14, bottom: 0, horizontal: layout.horizontalPadding)

        if case .loaded(let model) = store.phase {
            summaryTiles(model, proxy: proxy)
                .emmaListRow(top: 14, bottom: 0, horizontal: layout.horizontalPadding)
        }

        SearchField(text: $search, placeholder: searchPlaceholder, isFocused: $searchFocused)
            .emmaListRow(top: 14, bottom: 0, horizontal: layout.horizontalPadding)

        filterChips
            .emmaListRow(top: 8, bottom: 6, horizontal: 0)
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
        case .leads: return "Szukaj osoby, tematu lub telefonu"
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
                // Wcześniej ustawiał ten sam filtr co „do obsługi” — teraz
                // przewija prosto do zgłoszeń, które czekają najdłużej.
                PulseTile(
                    value: inbox.waiting.count,
                    label: "czeka ponad dobę",
                    systemImage: "clock",
                    tone: inbox.waiting.isEmpty ? EmmaTheme.accent : EmmaTheme.pillAmberText
                ) { showLeadGroup(inbox.waiting.isEmpty ? nil : LeadGroupID.waiting, proxy: proxy) }
                PulseTile(
                    value: booked,
                    label: EmmaPlural.form(booked, "umówiona konsultacja", "umówione konsultacje", "umówionych konsultacji"),
                    systemImage: "calendar",
                    tone: EmmaTheme.accent
                ) { selectLeadFilter(.all) }
            }
        case .clients:
            let firmCount = model.firmClients.count
            let withCase = model.clientsWithActiveCase.count
            let attention = model.clientsNeedingAttention.count
            HStack(spacing: 8) {
                PulseTile(
                    value: firmCount,
                    label: EmmaPlural.form(firmCount, "klient", "klientów", "klientów"),
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
            let board = model.caseBoard
            let active = board.activeCount
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

    /// Kafelek leadów przewija do grupy, jak kafelki spraw.
    private func showLeadGroup(_ groupID: String?, proxy: ScrollViewProxy) {
        search = ""
        leadFilter = .needsAction
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(groupID ?? Self.topID, anchor: .top)
            }
        }
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
            ListFilterChips(
                items: ClientDirectoryFilter.visible(in: model, selected: clientFilter),
                selection: $clientFilter,
                title: { $0.rawValue },
                count: { $0.count(in: model) },
                attention: { filter in
                    switch filter {
                    case .needsAttention, .stale: return filter.count(in: model) > 0
                    case .all, .withActiveCase: return false
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
                    case .active: return model.caseBoard.activeCount
                    case .closed: return model.closedCases.count
                    }
                }
            )
        case (.leads, _):
            ListFilterChips(items: LeadListFilter.allCases, selection: $leadFilter, title: { $0.rawValue })
        case (.clients, _):
            ListFilterChips(items: ClientDirectoryFilter.primary, selection: $clientFilter, title: { $0.rawValue })
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
                .emmaListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
        case .failed(let failure):
            LoadFailureView(failure) {
                Task { await store.load(dependencies) }
            }
            .emmaListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
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
            .emmaListRow(top: 0, bottom: 0, horizontal: 0)
    }

    // MARK: Leady

    @ViewBuilder
    private func leadsList(_ model: ClientsModel) -> some View {
        let sections = leadSections(model)
        if sections.isEmpty {
            leadsEmptyState
                .emmaListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
        } else {
            ForEach(sections) { section in
                if let title = section.title {
                    GroupHeader(
                        title: title,
                        count: section.clients.count,
                        tone: LeadStatusStyle.tone(section.status),
                        emphasized: section.status == .waiting
                    )
                    .id(section.id)
                    .emmaListRow(top: 12, bottom: 2, horizontal: layout.horizontalPadding)
                }
                ForEach(Array(section.clients.enumerated()), id: \.element.id) { offset, client in
                    leadRow(client, model: model)
                        .emmaAppear(offset)
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
            onDelete: { pendingDelete = client },
            conversation: messages.phase.value?.rowsByClient[client.id],
            onOpenConversation: { dependencies.openThread($0) }
        )
        .emmaListRow(top: 5.5, bottom: 5.5, horizontal: layout.horizontalPadding)
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
            client.stage != .client && Self.personMatches(query, client)
        }
        let inbox = LeadWorkflow.inbox(matching, now: dependencies.now)

        let waiting = LeadSection(id: LeadGroupID.waiting, title: "Czekają ponad dobę", status: .waiting, clients: inbox.waiting)
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
            let firm = model.firmClients
                .filter { Self.personMatches(query, $0) }
                .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
            sections.append(LeadSection(id: "clients", title: "Klienci kancelarii", status: .client, clients: firm))
        }
        return sections.filter { !$0.clients.isEmpty }
    }

    // MARK: Klienci

    @ViewBuilder
    private func clientsList(_ model: ClientsModel) -> some View {
        let rows = model.firmClients.filter { client in
            clientFilter.includes(client.id, in: model) && matchesSearch(client, model)
        }
        let leads = matchingLeads(model)
        let recent = recentClients(model)
        let conversations = messages.phase.value?.rowsByClient ?? [:]
        if search.isEmpty && clientFilter == .all && !recent.isEmpty {
            RecentClientsStrip(clients: recent, horizontalPadding: layout.horizontalPadding) { client in
                dependencies.openPerson(client.id)
            }
            .emmaListRow(top: 6, bottom: 4, horizontal: 0)
        }
        if rows.isEmpty && leads.isEmpty {
            EmptyState(
                systemImage: "person.2",
                title: search.isEmpty ? "Brak klientów w tym widoku" : "Nikogo nie znaleziono",
                message: "Klient pojawia się tu po „Przyjmij sprawę” na karcie zgłoszenia."
            )
            .emmaListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
        } else {
            ForEach(ClientDirectory.sections(rows)) { section in
                GroupHeader(title: section.letter, count: section.clients.count, tone: nil, emphasized: false)
                    .emmaListRow(top: 12, bottom: 2, horizontal: layout.horizontalPadding)
                ForEach(Array(section.clients.enumerated()), id: \.element.id) { offset, client in
                    directoryRow(client, model: model, conversation: conversations[client.id])
                        .emmaAppear(offset)
                }
            }
            // Szukana osoba bywa jeszcze zgłoszeniem — nie każ przełączać trybu.
            if !leads.isEmpty {
                GroupHeader(title: "Zgłoszenia", count: leads.count, tone: EmmaTheme.accent, emphasized: false)
                    .emmaListRow(top: 12, bottom: 2, horizontal: layout.horizontalPadding)
                ForEach(leads) { client in
                    leadRow(client, model: model)
                }
            }
            bottomSpacer
        }
    }

    /// Wiersz kartoteki. Przesunięcia dają dwie rzeczy, które adwokat robi
    /// z listą klientów najczęściej: zadzwonić i umówić termin — bez
    /// otwierania karty i bez szukania menu pod przytrzymaniem.
    private func directoryRow(_ client: Client, model: ClientsModel, conversation: MessagesStore.Row?) -> some View {
        let phoneURL = client.phone.flatMap(ContactLinks.phoneURL)
        let whatsAppURL = client.phone.flatMap(ContactLinks.whatsAppURL)
        return ClientDirectoryCard(
            client: client,
            cases: model.casesByClient[client.id] ?? [],
            nextEvent: model.nextClientEvents[client.id],
            missedEvent: model.missedClientEvents[client.id],
            overdueTaskCount: model.clientOverdueTaskCounts[client.id] ?? 0,
            isStale: model.staleClients.contains(client.id),
            onOpen: { dependencies.openPerson(client.id) },
            conversation: conversation,
            onOpenConversation: { dependencies.openThread($0) }
        )
        .emmaListRow(top: 5, bottom: 5, horizontal: layout.horizontalPadding)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let phoneURL {
                Button {
                    EmmaHaptics.selection()
                    openURL(phoneURL)
                } label: {
                    Label("Zadzwoń", systemImage: "phone.fill")
                }
                .tint(EmmaTheme.pillGreenText)
            }
            if let whatsAppURL {
                Button {
                    openURL(whatsAppURL)
                } label: {
                    Label("WhatsApp", systemImage: "message.fill")
                }
                .tint(EmmaTheme.accent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                dependencies.present(.eventForm(editing: nil, clientID: client.id, caseID: nil, initialDay: nil))
            } label: {
                Label("Termin", systemImage: "calendar.badge.plus")
            }
            .tint(EmmaTheme.pillAmberText)
        }
    }

    /// Klienta można znaleźć po nazwisku, temacie, telefonie, tytule i numerze jego sprawy.
    private func matchesSearch(_ client: Client, _ model: ClientsModel) -> Bool {
        if Self.personMatches(search, client) { return true }
        let cases = model.casesByClient[client.id] ?? []
        return SearchText.matches(search, in: cases.flatMap(\.searchableTexts))
    }

    /// Zgłoszenia pasujące do wyszukiwania w trybie „Klienci”.
    private func matchingLeads(_ model: ClientsModel) -> [Client] {
        guard !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return model.clients
            .filter { $0.stage != .client && Self.personMatches(search, $0) }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    /// Osoba po nazwisku, temacie albo numerze telefonu.
    private static func personMatches(_ query: String, _ client: Client) -> Bool {
        SearchText.matches(query, in: [client.displayName, client.topic])
            || SearchText.matchesPhone(query, phone: client.phone)
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
        switch caseFilter {
        case .active:
            let board = model.caseBoard.filtered { matchesSearch($0, model) }
            if board.isEmpty {
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
                        .emmaListRow(top: 12, bottom: 2, horizontal: layout.horizontalPadding)
                        ForEach(Array(cases.enumerated()), id: \.element.id) { offset, legalCase in
                            caseRow(legalCase, model: model)
                                .emmaAppear(offset)
                        }
                    }
                }
                bottomSpacer
            }
        case .closed:
            // Najnowsze najpierw — do zamkniętej sprawy wraca się zwykle
            // tuż po jej zamknięciu, a nie w porządku alfabetycznym.
            let closed = model.closedCases.filter { matchesSearch($0, model) }
            if closed.isEmpty {
                casesEmptyState
            } else {
                ForEach(Array(closed.enumerated()), id: \.element.id) { offset, legalCase in
                    caseRow(legalCase, model: model)
                        .emmaAppear(offset)
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
            missedEvent: model.missedCaseEvents[legalCase.id],
            onOpen: { dependencies.openCase(legalCase.id) }
        )
        .emmaListRow(top: 5, bottom: 5, horizontal: layout.horizontalPadding)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if legalCase.status.isActive {
                Button {
                    dependencies.present(.eventForm(
                        editing: nil,
                        clientID: legalCase.clientID,
                        caseID: legalCase.id,
                        initialDay: nil
                    ))
                } label: {
                    Label("Termin", systemImage: "calendar.badge.plus")
                }
                .tint(EmmaTheme.pillAmberText)
            }
        }
    }

    private var casesEmptyState: some View {
        EmptyState(
            systemImage: "folder",
            title: search.isEmpty ? "Brak spraw w tym widoku" : "Brak pasujących spraw",
            message: "Zmień filtr lub utwórz sprawę z karty klienta."
        )
        .emmaListRow(top: 0, bottom: 0, horizontal: layout.horizontalPadding)
    }

    private func groupTone(_ group: CaseBoard.Group) -> Color {
        switch group {
        case .attention: return EmmaTheme.pillDangerText
        case .inProgress: return EmmaTheme.pillGreenText
        case .awaitingClient: return EmmaTheme.mutedSoft
        }
    }

    private func matchesSearch(_ legalCase: LegalCase, _ model: ClientsModel) -> Bool {
        let client = model.clientsByID[legalCase.clientID]
        return SearchText.matches(search, in: legalCase.searchableTexts + [client?.displayName ?? ""])
            || SearchText.matchesPhone(search, phone: client?.phone)
    }

    // MARK: Filtr z innego ekranu

    /// Filtr zamówiony z innego ekranu (np. „Wszystkie” na „Dzisiaj”).
    private func consumePendingFilter() {
        guard let filter = dependencies.pendingLeadFilter else { return }
        dependencies.pendingLeadFilter = nil
        search = ""
        leadFilter = filter
    }

    /// Lupa z „Dzisiaj”: pole szukania od razu z klawiaturą.
    private func consumePendingSearch() {
        guard dependencies.pendingClientSearch else { return }
        dependencies.pendingClientSearch = false
        Task { @MainActor in
            // Najpierw przełączenie trybu (czyści wyszukiwanie), potem fokus.
            try? await Task.sleep(nanoseconds: 350_000_000)
            searchFocused = true
        }
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

/// Identyfikatory grup leadów — cel przewijania z kafelków.
private enum LeadGroupID {
    static let waiting = "lead-group-waiting"
}

private struct LeadSection: Identifiable {
    let id: String
    let title: String?
    let status: LeadStatus
    let clients: [Client]
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

/// Filtr kartoteki klientów. „Wymaga uwagi” to przegapiony termin, zaległe
/// zadanie albo termin w ciągu tygodnia (`CaseUrgency`). „Bez ruchu” to aktywna
/// sprawa bez żadnego terminu od miesiąca — chip pojawia się tylko wtedy, gdy
/// ktoś taki jest, żeby nie dokładać opcji, które nic nie pokazują.
enum ClientDirectoryFilter: String, Hashable, CaseIterable {
    case all = "Wszyscy"
    case withActiveCase = "Z aktywną sprawą"
    case needsAttention = "Wymaga uwagi"
    case stale = "Bez ruchu"

    static let primary: [ClientDirectoryFilter] = [.all, .withActiveCase, .needsAttention]

    static func visible(in model: ClientsModel, selected: ClientDirectoryFilter) -> [ClientDirectoryFilter] {
        model.staleClients.isEmpty && selected != .stale ? primary : allCases
    }

    func includes(_ id: ClientID, in model: ClientsModel) -> Bool {
        switch self {
        case .all: return true
        case .withActiveCase: return model.clientsWithActiveCase.contains(id)
        case .needsAttention: return model.clientsNeedingAttention.contains(id)
        case .stale: return model.staleClients.contains(id)
        }
    }

    func count(in model: ClientsModel) -> Int {
        switch self {
        case .all: return model.firmClients.count
        case .withActiveCase: return model.clientsWithActiveCase.count
        case .needsAttention: return model.clientsNeedingAttention.count
        case .stale: return model.staleClients.count
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
    @Namespace private var selectionSpace

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
        .animation(EmmaMotion.snappy, value: selection)
    }

    private func chip(_ item: Item) -> some View {
        let isSelected = item == selection
        let needsAttention = attention?(item) ?? false
        return Button {
            guard selection != item else { return }
            EmmaHaptics.selection()
            // Animacja tylko zaznaczenia (niżej) — lista pod chipami zmienia się od razu.
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
                        .contentTransition(.numericText())
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 36)
            // Zaznaczenie przesuwa się między chipami (jak w segmentach).
            .background {
                if isSelected {
                    Capsule()
                        .fill(EmmaTheme.surface)
                        .overlay { Capsule().strokeBorder(EmmaTheme.border, lineWidth: 1) }
                        .matchedGeometryEffect(id: "chip-selection", in: selectionSpace)
                }
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
    return ClientsScreen(store: dependencies.clientsStore, messages: dependencies.messagesStore)
        .environmentObject(dependencies)
}
