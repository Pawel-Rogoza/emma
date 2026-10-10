import SwiftUI

// MARK: - Ekran główny „Dzisiaj”
//
// Etap 3 audytu UX (F08): pełna scena Emmy, slogan i dwa wejścia zajmowały
// większość górnej części ekranu, więc zadania nie mieściły się w pierwszym
// widoku nawet na dużym telefonie. Kolejność jest teraz taka jak w §4 audytu:
//
//   1. nagłówek dnia (powitanie według pory), portret Emmy i wejście do profilu,
//   2. leady do obsługi — najpierw czekające, potem nowe, z odhaczeniem w wierszu,
//   3. najbliższy termin z akcją „Przygotuj mnie” i linkami do klienta i sprawy,
//   4. zadania z liczbą otwartych i zaległych oraz wejściem „Wszystkie zadania”,
//   5. dopiero dalej pozostałe terminy dnia, a minione w zwijanej sekcji.
//
// Review 24.09.2026: ekran „wyglądał nudno, z dużą ilością nieużywanej
// przestrzeni”, a sekcja leadów znikała, gdy ich nie było. Teraz:
//   • pod nagłówkiem trzy kafelki pulsu dnia (leady do obsługi, terminy dziś,
//     zadania) — każdy prowadzi do swojej listy,
//   • sekcja „Nowe leady” jest zawsze; bez leadów mówi wprost „brak nowych”,
//   • „Najbliższy termin” sięga dalej niż dziś (14 dni) — wolny dzień nie
//     zostawia pustej karty,
//   • pasek tygodnia pokazuje, ile terminów jest w najbliższych 7 dniach.
//
// Review 23.09.2026: leady do obsługi trafiły na ekran główny. Żeby najbliższy
// termin i wejście do zadań nadal mieściły się w pierwszym widoku (F08),
// kompaktowa karta Emmy (~110 pt) zamieniła się w portret w nagłówku: dotknięcie
// zaczyna rozmowę głosową, przytrzymanie daje „Napisz do Emmy”. Pełna scena Emmy
// została w zakładce „Emma”. Odstępstwa od referencji `home()` opisuje
// DESIGN_DEVIATIONS.md (D-15, D-24, D-31).

@MainActor
final class TodayStore: ObservableObject {

    struct Model {
        var today: LocalDate
        /// Terminy dzisiejsze.
        var events: [ScheduledEvent]
        /// Terminy od jutra przez najbliższe dwa tygodnie.
        var upcomingEvents: [ScheduledEvent]
        var tasks: [TaskItem]
        var clientNames: [ClientID: String]
        var caseNumbers: [CaseID: String]
        /// Wszystkie kontakty — z nich liczona jest kolejka leadów do obsługi.
        var clients: [Client]
        /// Niezakończone terminy w sprawach z ostatnich 30 dni, które już minęły —
        /// najdawniejsze najpierw. Audyt 28.09.2026: przegapiony termin procesowy
        /// to dla adwokata najgorsza wiadomość dnia, a ekran go nie pokazywał.
        var missedDeadlines: [ScheduledEvent] = []
        /// Areszt i legalny pobyt kończące się w ciągu 30 dni (albo świeżo
        /// minione) — najbliższe najpierw.
        var watches: [CaseWatch] = []
        var caseTitles: [CaseID: String] = [:]
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle

    /// Jak daleko naprzód sięga „Najbliższy termin” i pasek tygodnia.
    static let horizonDays = 14

    func load(_ dependencies: AppDependencies) async {
        // Ponowne wczytanie po zapisie nie mruga stanem ładowania.
        if !phase.hasLoaded { phase = .loading }
        let today = dependencies.today
        let repository = dependencies.repository
        do {
            async let clientsTask = repository.clients(matching: "", stage: nil)
            async let casesTask = repository.cases(status: nil)
            async let eventsTask = repository.events(
                in: DateIntervalFilter(from: today, through: today.adding(days: Self.horizonDays))
            )
            async let tasksTask = repository.tasks(
                filter: TaskFilter(scope: .open, dueOnOrBefore: today)
            )
            async let pastTask = repository.events(
                in: DateIntervalFilter(
                    from: today.adding(days: -CaseUrgency.missedLookbackDays),
                    through: today.adding(days: -1)
                )
            )

            let clients = try await clientsTask
            let cases = try await casesTask
            let events = try await eventsTask
            let tasks = try await tasksTask
            // Brak przeszłych terminów nie może zablokować całego dnia.
            let past = (try? await pastTask) ?? []
            let missed = past
                .filter { $0.kind == .caseDeadline && $0.status != .finished && $0.day < today }
                .sorted { $0.day != $1.day ? $0.day < $1.day : $0.time < $1.time }

            let active = events.filter { $0.status != .finished || $0.day == today }
            let model = Model(
                    today: today,
                    events: active.filter { $0.day == today }.sorted { $0.time < $1.time },
                    upcomingEvents: active
                        .filter { $0.day > today }
                        .sorted { $0.day != $1.day ? $0.day < $1.day : $0.time < $1.time },
                    tasks: tasks.sorted(by: TaskItem.isOrderedByDueDate),
                    clientNames: Dictionary(
                        clients.map { ($0.id, $0.displayName) },
                        uniquingKeysWith: { first, _ in first }
                    ),
                    // Numery spraw potrzebne do linku „sprawa” przy najbliższym
                    // terminie — wiersz terminu sam nie zna repozytorium.
                    caseNumbers: Dictionary(
                        cases.map { ($0.id, $0.number) },
                        uniquingKeysWith: { first, _ in first }
                    ),
                    clients: clients,
                    missedDeadlines: missed,
                    watches: CaseWatch.upcoming(cases: cases, today: today),
                    caseTitles: Dictionary(
                        cases.map { ($0.id, $0.title) },
                        uniquingKeysWith: { first, _ in first }
                    )
                )
            // Odświeżenie po zapisie (np. obsłużony lead) jest animowane.
            if phase.hasLoaded {
                withAnimation(.easeInOut(duration: 0.28)) { phase = .loaded(model) }
            } else {
                phase = .loaded(model)
            }
            dependencies.leadsNeedingAction = LeadWorkflow.needsActionCount(clients)
            dependencies.spotlight.update(cases: cases, clients: clients)
        } catch {
            if let message = phase.recordFailure(error, fallback: "Nie udało się wczytać dnia.") {
                dependencies.showToast(message)
            }
        }
    }
}

struct TodayScreen: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout: EmmaLayoutMetrics
    @Environment(\.openURL) private var openURL
    /// Magazyn żyje w `AppDependencies` — powrót na zakładkę pokazuje od razu
    /// ostatni stan dnia zamiast „Przygotowuję dzień…”.
    @ObservedObject var store: TodayStore
    /// Rozmowy WhatsApp — karta „Napisali” z imionami i początkiem wiadomości.
    @ObservedObject var messages: MessagesStore
    /// Termin czekający na potwierdzenie usunięcia. Usunięcie jest nieodwracalne
    /// (demo nie ma kosza), więc pytamy — ale dopiero po wybraniu z menu.
    @State private var eventPendingDeletion: ScheduledEvent?
    /// Minione terminy są domyślnie zwinięte: to zapis dnia, nie plan na teraz.
    @State private var showsPastEvents = false
    /// Karta „Włącz poranny skrót” — gdy system jeszcze nie pytał o powiadomienia.
    @State private var offersNotifications = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch store.phase {
                case .idle, .loading:
                    LoadingState("Przygotowuję dzień…")
                case .failed(let failure):
                    LoadFailureView(failure) {
                        Task { await store.load(dependencies) }
                    }
                case .loaded(let model):
                    loaded(model)
                }
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, EmmaSpacing.contentTop)
            .padding(.bottom, EmmaSpacing.contentBottom)
        }
        .background(EmmaTheme.bg)
        .scrollIndicators(.hidden)
        .refreshable {
            await store.load(dependencies)
            await messages.load(dependencies, silent: true)
        }
        .task(id: dependencies.dataVersion) { await store.load(dependencies) }
        // Przy każdym wejściu na „Dzisiaj” — przeczytana w międzyczasie rozmowa
        // znika z „Napisali”, a nowa się pojawia.
        .task { await messages.load(dependencies, silent: true) }
        .task { offersNotifications = await dependencies.reminders.shouldOfferPermission() }
        .confirmationDialog(
            "Usunąć termin?",
            isPresented: Binding(
                get: { eventPendingDeletion != nil },
                set: { if !$0 { eventPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: eventPendingDeletion
        ) { event in
            Button("Usuń termin", role: .destructive) {
                Task { await deleteEvent(event) }
            }
            Button("Wróć", role: .cancel) { eventPendingDeletion = nil }
        } message: { event in
            Text("„\(event.title)” o \(event.time.hhmm) zniknie z kalendarza.")
        }
    }

    /// „Załatwione” z menu wiersza — wspólna czynność (`EventActions`), z „Cofnij”.
    private func finishEvent(_ event: ScheduledEvent) async {
        if let message = await EventActions.finish(event, dependencies: dependencies) {
            dependencies.showToast(message)
        }
    }

    private func deleteEvent(_ event: ScheduledEvent) async {
        await dependencies.perform {
            try await dependencies.repository.deleteEvent(
                id: event.id,
                expectedVersion: event.version
            )
        }
        eventPendingDeletion = nil
    }

    @ViewBuilder
    private func loaded(_ model: TodayStore.Model) -> some View {
        let agenda = DayAgenda.split(model.events, now: TimeOfDay.at(dependencies.clock.now()))
        let inbox = LeadWorkflow.inbox(model.clients, now: dependencies.now)

        header(model, inbox: inbox)
            .emmaAppear(0)

        // Redesign 0.22.0 — trzy poziomy zamiast jedenastu równych kart:
        //   1. „Następne” — jeden bohater z odliczaniem,
        //   2. „Wymaga Ciebie” — jedna kolejka: po terminie, leady, napisali, zadania,
        //   3. „Później dziś” — zwarta lista godzin.
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Następne", actionTitle: "Dodaj", compact: true) {
                dependencies.present(.eventForm(editing: nil, clientID: nil, caseID: nil, initialDay: nil))
            }
            nextEventCard(agenda.next ?? model.upcomingEvents.first, model: model)
        }
        .emmaAppear(1)

        // Po rozprawie — pod bohaterem, żeby nie spychać go z pierwszego widoku.
        if let hearing = DayAgenda.debrief(agenda) {
            debriefCard(hearing, model: model)
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        // Pusta kolejka znika — „nic nie goni” mówi już zdanie pod powitaniem.
        if attentionCount(model, inbox: inbox) > 0 {
            VStack(alignment: .leading, spacing: 0) {
                attentionSection(model, inbox: inbox)
            }
            .emmaAppear(2)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        // Areszt albo koniec legalnego pobytu — liczniki dni pod kolejką.
        ForEach(model.watches) { watch in
            CaseWatchCard(watch: watch, subtitle: watchSubtitle(watch, model: model)) {
                dependencies.openCase(watch.caseID)
            }
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .emmaAppear(3)
        }

        if !agenda.upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Później dziś", actionTitle: "Kalendarz", compact: true) {
                    dependencies.go(to: .calendar)
                }
                eventsCard(agenda.upcoming)
            }
            .emmaAppear(4)
        }

        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Zadania", actionTitle: "Wszystkie zadania", compact: true) {
                dependencies.openTasks()
            }
            tasksSection(model)
        }
        .emmaAppear(5)

        if offersNotifications {
            notificationsOffer
                .padding(.top, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if !agenda.past.isEmpty {
            pastEventsSection(agenda.past)
        }
    }

    // MARK: Wymaga Ciebie

    /// Jedna kolejka rzeczy do zrobienia, od najpilniejszej: terminy po terminie
    /// (czerwone), leady do obsługi, osoby, które napisały, i zadania na dziś.
    /// Każdy wiersz ma ikonę w kolorze stanu — to, co pilne, widać bez czytania.
    @ViewBuilder
    private func attentionSection(_ model: TodayStore.Model, inbox: LeadInbox) -> some View {
        let missed = Array(model.missedDeadlines.prefix(3))
        let leads = Array(inbox.needsAction.prefix(Self.leadsPreviewLimit))
        let writers = Array((messages.phase.value?.unreadWhatsAppRows ?? []).prefix(3))
        let pendingUnread = messages.phase.value == nil ? dependencies.unreadTotal : 0
        let summary = TaskGrouping.summary(model.tasks, today: model.today)
        let count = attentionCount(model, inbox: inbox)

        SectionHeader(count > 0 ? "Wymaga Ciebie · \(count)" : "Wymaga Ciebie", compact: true)

        // Kreski są **nad** wierszem (oprócz pierwszego) — kolejka może się
        // skończyć na dowolnej grupie, a karta nie ma pustej kreski na dole.
        let showsMoreMissed = model.missedDeadlines.count > missed.count
        let showsMoreLeads = inbox.needsAction.count > leads.count
        let moreWriters = (messages.phase.value?.unreadWhatsAppRows.count ?? 0) - writers.count
        let beforeLeads = !missed.isEmpty
        let beforeWriters = beforeLeads || !leads.isEmpty || showsMoreLeads
        let beforeTasks = beforeWriters || !writers.isEmpty || moreWriters > 0 || pendingUnread > 0

        SurfaceCard(padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
            VStack(alignment: .leading, spacing: 0) {
                if !missed.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(missed.enumerated()), id: \.element.id) { index, event in
                            if index > 0 { attentionDivider }
                            Button {
                                dependencies.present(.eventDetail(event.id))
                            } label: {
                                HStack(spacing: 0) {
                                    AttentionIcon(systemName: "exclamationmark", tint: EmmaTheme.critical)
                                        .padding(.leading, 14)
                                    missedRow(event, model: model)
                                }
                            }
                            .buttonStyle(EmmaCardButtonStyle())
                            .contextMenu { missedMenu(event) }
                        }
                        if showsMoreMissed {
                            attentionDivider
                            Button {
                                dependencies.clientMode = .cases
                                dependencies.go(to: .clients, resetStack: true)
                            } label: {
                                Text("Wszystkie po terminie · \(model.missedDeadlines.count)")
                                    .font(EmmaTypography.caption(.semibold))
                                    .foregroundStyle(EmmaTheme.critical)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("today-missed-deadlines")
                }

                ForEach(Array(leads.enumerated()), id: \.element.id) { index, client in
                    if beforeLeads || index > 0 { attentionDivider }
                    LeadInboxRow(
                        client: client,
                        onOpen: { dependencies.openPerson(client.id) },
                        onMarkHandled: { await LeadActions.markInContact(client, dependencies: dependencies) }
                    )
                }
                if showsMoreLeads {
                    if beforeLeads || !leads.isEmpty { attentionDivider }
                    attentionLink("Wszystkie leady do obsługi · \(inbox.needsAction.count)") {
                        dependencies.openLeads(filter: .needsAction)
                    }
                }

                ForEach(Array(writers.enumerated()), id: \.element.id) { index, row in
                    if beforeWriters || index > 0 { attentionDivider }
                    writerRow(row)
                }
                if moreWriters > 0 {
                    if beforeWriters || !writers.isEmpty { attentionDivider }
                    attentionLink("Jeszcze \(moreWriters) · wszystkie nowe") {
                        openUnreadConversations()
                    }
                } else if pendingUnread > 0 {
                    if beforeWriters { attentionDivider }
                    attentionLink(EmmaPlural.unreadConversations(pendingUnread)) {
                        openUnreadConversations()
                    }
                }

                if summary.open > 0 {
                    if beforeTasks { attentionDivider }
                    tasksAttentionRow(summary)
                }
            }
        }
        .animation(EmmaMotion.smooth, value: writers.map(\.id))
    }

    /// Ile pozycji czeka w „Wymaga Ciebie”. Zadania liczą się jako jedna
    /// pozycja i tylko wtedy, gdy coś jest otwarte.
    private func attentionCount(_ model: TodayStore.Model, inbox: LeadInbox) -> Int {
        let pendingUnread = messages.phase.value == nil ? dependencies.unreadTotal : 0
        let summary = TaskGrouping.summary(model.tasks, today: model.today)
        return model.missedDeadlines.count + inbox.needsAction.count
            + (messages.phase.value?.unreadWhatsAppRows.count ?? (pendingUnread > 0 ? 1 : 0))
            + (summary.open > 0 ? 1 : 0)
    }

    private var attentionDivider: some View {
        Divider().overlay(EmmaTheme.rowSeparator).padding(.leading, 58)
    }

    private func attentionLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            EmmaHaptics.tap()
            action()
        } label: {
            Text(title)
                .font(EmmaTypography.caption(.semibold))
                .foregroundStyle(EmmaTheme.accent)
                .frame(maxWidth: .infinity, minHeight: EmmaSpacing.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Ostatni wiersz kolejki — zadania na dziś. Bez otwartych zadań go nie ma
    /// (właściciel: „Zadania na dziś zrobione” to szum na ekranie głównym).
    private func tasksAttentionRow(_ summary: TaskGrouping.Summary) -> some View {
        Button {
            EmmaHaptics.tap()
            dependencies.openTasks()
        } label: {
            HStack(spacing: 12) {
                AttentionIcon(
                    systemName: "checklist",
                    tint: summary.hasOverdue ? EmmaTheme.warning : EmmaTheme.accent
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zadania na dziś · \(summary.open)")
                        .font(EmmaTypography.ui(15, .semibold))
                        .foregroundStyle(EmmaTheme.ink)
                    if summary.hasOverdue {
                        Text("\(summary.overdue) po terminie")
                            .font(EmmaTypography.caption(.medium))
                            .foregroundStyle(EmmaTheme.warning)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EmmaTheme.mutedSoft)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pulse-tasks")
    }

    @ViewBuilder
    private func missedMenu(_ event: ScheduledEvent) -> some View {
        Button {
            Task { await finishEvent(event) }
        } label: {
            Label("Załatwione", systemImage: "checkmark.circle")
        }
        if let caseID = event.caseID {
            Button {
                dependencies.openCase(caseID)
            } label: {
                Label("Otwórz sprawę", systemImage: "folder")
            }
        }
        if let clientID = event.clientID {
            Button {
                dependencies.openPerson(clientID)
            } label: {
                Label("Karta klienta", systemImage: "person")
            }
        }
    }

    // MARK: Nagłówek dnia

    /// Powitanie według pory dnia w strefie kancelarii.
    private var greeting: String {
        let hour = TimeOfDay.at(dependencies.clock.now()).hour
        let base: String
        switch hour {
        case 5..<18: base = "Dzień dobry"
        default: base = "Dobry wieczór"
        }
        // „Dzień dobry, Tomasz” — imię z sesji, bez tytułu („Mec.”, „adw.”).
        let titles: Set<String> = ["mec.", "mecenas", "adw.", "adwokat", "r.pr.", "radca"]
        let words = dependencies.currentUser.displayName.split(separator: " ").map(String.init)
        // Konto kancelarii („Kancelaria Rogoża”) to nie osoba — samo powitanie.
        guard words.first?.lowercased() != "kancelaria" else { return base }
        let firstName = words.first { !titles.contains($0.lowercased()) }
        guard let firstName, firstName.count >= 2, firstName.count <= 14 else { return base }
        return "\(base), \(firstName)"
    }

    /// „Jan Kowalski · Rozbój” pod tytułem karty aresztu.
    private func watchSubtitle(_ watch: CaseWatch, model: TodayStore.Model) -> String {
        [model.clientNames[watch.clientID], model.caseTitles[watch.caseID]]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Nagłówek dnia: data, powitanie, portret Emmy i profil kancelarii.
    ///
    /// Portret jest wejściem do rozmowy — ta sama czynność, co dawny przycisk
    /// mikrofonu w karcie Emmy, ale bez zabierania wysokości pod leady i terminy.
    /// Jedno zdanie o dniu pod powitaniem: co jest dziś do zrobienia, zanim
    /// wzrok zejdzie do kafelków. Pusty dzień też jest informacją.
    private func daySummary(_ model: TodayStore.Model, inbox: LeadInbox) -> String {
        let summary = TaskGrouping.summary(model.tasks, today: model.today)
        var parts: [String] = []
        if !model.missedDeadlines.isEmpty {
            parts.append("\(model.missedDeadlines.count) po terminie")
        }
        // „Areszt Kowalskiego za 5 dni” zasługuje na zdanie o dniu tylko w ostatnim tygodniu.
        for watch in model.watches where watch.severity >= .critical {
            let name = model.clientNames[watch.clientID] ?? Client.unknownDisplayName
            parts.append("\(watch.kind.displayName.lowercased()): \(name) \(watch.countdownText)")
        }
        if !model.events.isEmpty {
            parts.append(EmmaPlural.label(model.events.count, "termin", "terminy", "terminów"))
        }
        if !inbox.needsAction.isEmpty {
            let count = inbox.needsAction.count
            parts.append(EmmaPlural.leads(count) + " " + EmmaPlural.form(count, "czeka", "czekają", "czeka"))
        }
        if summary.hasOverdue {
            parts.append(EmmaPlural.overdueTasks(summary.overdue))
        }
        if dependencies.unreadTotal > 0 {
            parts.append(EmmaPlural.unreadConversations(dependencies.unreadTotal))
        }
        return parts.isEmpty ? "Spokojny dzień — nic nie goni." : parts.joined(separator: " · ")
    }

    private func header(_ model: TodayStore.Model, inbox: LeadInbox) -> some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 5) {
                Text(dependencies.dateText.headline(for: model.today))
                    .font(EmmaTypography.kicker)
                    .tracking(1.5)
                    .foregroundStyle(EmmaTheme.mutedSoft)
                Text(greeting)
                    .font(EmmaTypography.welcome)
                    .tracking(-0.9)
                    .foregroundStyle(EmmaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(daySummary(model, inbox: inbox))
                    .font(EmmaTypography.caption(.medium))
                    .foregroundStyle(model.missedDeadlines.isEmpty ? EmmaTheme.muted : EmmaTheme.pillDangerText)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("today-summary")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Szukanie klienta, sprawy albo numeru telefonu jednym dotknięciem
            // (audyt 28.09.2026) — bez przechodzenia przez zakładkę i tryby.
            Button {
                EmmaHaptics.tap()
                dependencies.openClientSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .frame(width: EmmaSpacing.hitTarget, height: EmmaSpacing.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Szukaj klienta, sprawy lub telefonu")

            emmaHeaderButton

            Button {
                dependencies.present(.profile)
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .frame(width: EmmaSpacing.hitTarget, height: EmmaSpacing.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profil kancelarii")
        }
        .padding(.bottom, 4)
    }

    /// Portret Emmy z plakietką mikrofonu: dotknięcie — rozmowa głosowa,
    /// przytrzymanie — rozmowa albo pisanie do Emmy.
    private var emmaHeaderButton: some View {
        Button {
            EmmaHaptics.tap()
            dependencies.openEmma(clientID: nil, startVoice: true)
        } label: {
            EmmaOrb(
                size: .card,
                // `voiceState` jest publikowany — stan koordynatora czytany
                // wprost nie odświeżał portretu, gdy Emma zaczynała mówić.
                isActive: dependencies.voiceState.isPlaybackActive,
                state: dependencies.voiceState.turn
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(EmmaTheme.primaryButtonText)
                    .frame(width: 18, height: 18)
                    .background(EmmaTheme.primaryButton, in: Circle())
                    .overlay { Circle().strokeBorder(EmmaTheme.bg, lineWidth: 2) }
                    .offset(x: 3, y: 3)
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .contextMenu {
            Button {
                dependencies.openEmma(clientID: nil, startVoice: true)
            } label: {
                Label("Porozmawiaj z Emmą", systemImage: "mic")
            }
            Button {
                dependencies.openEmma(clientID: nil, startVoice: false)
            } label: {
                Label("Napisz do Emmy", systemImage: "keyboard")
            }
            Button {
                dependencies.openEmma(clientID: nil, action: .brief, startVoice: false)
            } label: {
                Label("Podsumuj mój dzień", systemImage: "sparkles")
            }
        }
        .accessibilityLabel("Porozmawiaj z Emmą")
        .accessibilityHint("Zaczyna rozmowę głosową. Przytrzymaj, aby napisać do Emmy.")
    }

    // MARK: Po rozprawie

    /// „Jak poszło?” — notatka, kolejny termin i „Załatwione” jednym dotknięciem.
    private func debriefCard(_ event: ScheduledEvent, model: TodayStore.Model) -> some View {
        let clientName = event.clientID.flatMap { model.clientNames[$0] }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EmmaTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(EmmaTheme.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Jak poszło?")
                        .font(EmmaTypography.ui(14, .semibold))
                        .foregroundStyle(EmmaTheme.ink)
                    Text([event.title, event.time.hhmm].joined(separator: " · "))
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.muted)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                if let clientID = event.clientID {
                    debriefButton("Notatka", systemImage: "square.and.pencil") {
                        dependencies.present(.note(clientID: clientID, caseID: event.caseID))
                    }
                }
                debriefButton("Kolejny termin", systemImage: "calendar.badge.plus") {
                    dependencies.present(.eventForm(editing: nil, clientID: event.clientID, caseID: event.caseID, initialDay: nil))
                }
                debriefButton("Załatwione", systemImage: "checkmark") {
                    // Ta sama ścieżka co menu wiersza — z komunikatem błędu,
                    // który wcześniej tu przepadał (termin „nie znikał” bez słowa).
                    Task { await finishEvent(event) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EmmaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
        }
        .emmaCardShadow()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Po terminie \(event.title)\(clientName.map { ", \($0)" } ?? "")")
    }

    private func debriefButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            EmmaHaptics.tap()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(EmmaTypography.caption(.semibold))
                .foregroundStyle(EmmaTheme.secondaryButtonText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(EmmaTheme.secondaryButton, in: RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(EmmaCardButtonStyle())
    }

    // MARK: Nowe wiadomości

    /// Klient napisał na WhatsApp — pasek nad planem dnia, jedno dotknięcie
    /// otwiera Rozmowy z filtrem „Nowe”. Bez niego wiadomość było widać tylko
    /// po liczniku na zakładce.
    private func openUnreadConversations() {
        EmmaHaptics.tap()
        messages.showUnread(in: .whatsApp)
        dependencies.go(to: .messages)
    }

    private func writerRow(_ row: MessagesStore.Row) -> some View {
        let preview = row.preview?.previewText ?? ""
        return Button {
            EmmaHaptics.tap()
            dependencies.openThread(row.thread.id)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                ChatAvatar(client: row.client, diameter: 38)
                    .overlay(alignment: .topTrailing) {
                        UnreadBadge(count: row.unreadCount, compact: true)
                            .offset(x: 5, y: -4)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.client.displayName)
                            .font(EmmaTypography.ui(14, .semibold))
                            .foregroundStyle(EmmaTheme.ink)
                            .lineLimit(1)
                        LanguageBadge(language: row.client.language)
                        Spacer(minLength: 4)
                        if let since = row.waitingSince {
                            Text("czeka \(ConversationInbox.waitingText(since: since, now: dependencies.now))")
                                .font(EmmaTypography.caption(.medium))
                                .foregroundStyle(
                                    ConversationInbox.isWaitingLong(since: since, now: dependencies.now)
                                        ? EmmaTheme.pillAmberText : EmmaTheme.mutedSoft
                                )
                                .fixedSize()
                        }
                    }
                    Text(preview)
                        .font(EmmaTypography.body(for: preview, size: 13))
                        .foregroundStyle(EmmaTheme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Otwiera rozmowę")
    }

    // MARK: Zgoda na powiadomienia

    /// Jedno zdanie, dwa przyciski. Bez zgody nie ma porannego skrótu ani
    /// przypomnień o rozprawach — a system pyta tylko raz, więc pytamy w porę.
    private var notificationsOffer: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(EmmaTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(EmmaTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Poranny skrót i przypomnienia")
                            .font(EmmaTypography.ui(15, .semibold))
                            .foregroundStyle(EmmaTheme.ink)
                        Text("O 8:00 powiem, co dziś w kalendarzu i co jest po terminie. Przypomnę też przed rozprawą.")
                            .font(EmmaTypography.caption())
                            .foregroundStyle(EmmaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 10) {
                    PrimaryButton("Włącz", systemImage: "bell") {
                        Task {
                            _ = await dependencies.reminders.requestAuthorizationIfNeeded()
                            dependencies.reminders.scheduleRefresh(dependencies)
                            withAnimation(EmmaMotion.smooth) { offersNotifications = false }
                        }
                    }
                    SecondaryButton("Nie teraz") {
                        dependencies.reminders.dismissPermissionOffer()
                        withAnimation(EmmaMotion.smooth) { offersNotifications = false }
                    }
                }
            }
        }
        .accessibilityIdentifier("today-notifications-offer")
    }

    // MARK: Po terminie

    private func missedRow(_ event: ScheduledEvent, model: TodayStore.Model) -> some View {
        let urgency = CaseUrgency(nextEvent: nil, missedEvent: event.day, overdueTasks: 0, today: model.today)
        let meta = [
            event.caseID.flatMap { model.caseNumbers[$0] },
            event.clientID.flatMap { model.clientNames[$0] }
        ].compactMap { $0 }.joined(separator: " · ")
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(EmmaTypography.ui(14, .semibold))
                    .foregroundStyle(EmmaTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                // Kiedy minął — pod tytułem, na czerwono; plakietka z boku
                // zabierała tytułowi połowę szerokości.
                HStack(spacing: 6) {
                    if let countdown = urgency.countdownText {
                        Text(countdown.prefix(1).uppercased() + countdown.dropFirst())
                            .font(EmmaTypography.caption(.semibold))
                            .foregroundStyle(EmmaTheme.pillDangerText)
                    }
                    if !meta.isEmpty {
                        Text("· \(meta)")
                            .font(EmmaTypography.caption())
                            .foregroundStyle(EmmaTheme.muted)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EmmaTheme.pillDangerText.opacity(0.6))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Otwiera termin. Przytrzymaj, aby oznaczyć jako załatwiony albo przejść do sprawy.")
    }

    private static let leadsPreviewLimit = 3

    // MARK: Następne (bohater)

    @ViewBuilder
    private func nextEventCard(_ event: ScheduledEvent?, model: TodayStore.Model) -> some View {
        if let event {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // Bohater ekranu (0.22.0): godzina czytelna z odległości.
                        Text(event.isAllDay ? "Cały dzień" : event.time.hhmm)
                            .font(EmmaTypography.heading(32))
                            .monospacedDigit()
                            .foregroundStyle(EmmaTheme.ink)
                        if event.day != model.today {
                            Text(dependencies.dateText.dayLabel(event.day))
                                .font(EmmaTypography.ui(14, .semibold))
                                .foregroundStyle(EmmaTheme.accent)
                        }
                        // „za 45 min” / „teraz” — odświeżane co minutę.
                        TimelineView(.periodic(from: .now, by: 60)) { _ in
                            if let countdown = event.countdownText(
                                now: TimeOfDay.at(dependencies.clock.now()),
                                today: model.today
                            ) {
                                StatusPill(countdown, kind: countdown == "teraz" ? .green : .neutral)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        Spacer(minLength: 8)
                        Label(event.kind.displayTitle, systemImage: event.kind.systemImage)
                            .font(EmmaTypography.caption(.medium))
                            .foregroundStyle(EmmaTheme.mutedSoft)
                            .lineLimit(1)
                    }

                    Text(event.title)
                        .font(EmmaTypography.meetingTitle)
                        .foregroundStyle(EmmaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if !event.place.isEmpty {
                        // Rozprawa w sądzie — „Prowadź” otwiera nawigację w Mapach.
                        if let mapsURL = ContactLinks.mapsURL(event.place) {
                            Button {
                                EmmaHaptics.tap()
                                openURL(mapsURL)
                            } label: {
                                HStack(spacing: 6) {
                                    Label(event.place, systemImage: "mappin.and.ellipse")
                                        .font(EmmaTypography.caption())
                                        .foregroundStyle(EmmaTheme.muted)
                                        .lineLimit(1)
                                    Text("Prowadź")
                                        .font(EmmaTypography.caption(.semibold))
                                        .foregroundStyle(EmmaTheme.accent)
                                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(EmmaTheme.accent)
                                }
                                .frame(minHeight: 28)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(event.place), prowadź w Mapach")
                        } else {
                            Label(event.place, systemImage: "mappin.and.ellipse")
                                .font(EmmaTypography.caption())
                                .foregroundStyle(EmmaTheme.mutedSoft)
                        }
                    }

                    // Linki do powiązanych rekordów: osoba i sprawa jednym dotknięciem.
                    HStack(spacing: 14) {
                        if let clientID = event.clientID {
                            Button {
                                dependencies.openPerson(clientID)
                            } label: {
                                Label(
                                    model.clientNames[clientID] ?? "Karta klienta",
                                    systemImage: "person"
                                )
                                .font(EmmaTypography.caption(.medium))
                                .foregroundStyle(EmmaTheme.accent)
                                .frame(minHeight: 28)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        if let caseID = event.caseID, let number = model.caseNumbers[caseID] {
                            Button {
                                dependencies.openCase(caseID)
                            } label: {
                                Label(number, systemImage: "folder")
                                    .font(EmmaTypography.caption(.medium))
                                    .foregroundStyle(EmmaTheme.accent)
                                    .frame(minHeight: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        if let clientID = event.clientID {
                            PrimaryButton("Przygotuj mnie") {
                                // Skrót do rozmowy z Emmą w kontekście klienta —
                                // Emma robi streszczenie sprawy, nic nie zapisuje.
                                dependencies.openEmma(
                                    clientID: clientID,
                                    action: .prepareCase,
                                    startVoice: false
                                )
                            }
                        }
                        SecondaryButton("Szczegóły") {
                            dependencies.present(.eventDetail(event.id))
                        }
                    }
                    .padding(.top, 1)
                }
            }
        } else {
            SurfaceCard {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 20))
                        .foregroundStyle(EmmaTheme.mutedSoft)
                    Text("Brak terminów w najbliższych dwóch tygodniach.")
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Zadania

    @ViewBuilder
    private func tasksSection(_ model: TodayStore.Model) -> some View {
        let summary = TaskGrouping.summary(model.tasks, today: model.today)
        let groups = TaskGrouping.groups(model.tasks, today: model.today)
        let allEntries = groups.flatMap { group in
            group.tasks.map { TaskEntry(bucket: group.bucket, task: $0) }
        }
        // Ekran główny to podgląd, nie lista — reszta jest pod „Wszystkie zadania”.
        let entries = Array(allEntries.prefix(Self.tasksPreviewLimit))

        // Bez otwartych zadań zostaje sam nagłówek z wejściem do listy —
        // bez karty „wszystko zrobione” (decyzja właściciela, 0.22.1).
        if !entries.isEmpty {
            SurfaceCard(padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)) {
                VStack(alignment: .leading, spacing: 0) {
                    if summary.open > 0 {
                        Text(summaryLabel(summary))
                            .font(EmmaTypography.caption())
                            .foregroundStyle(summary.hasOverdue ? EmmaTheme.pillUrgentText : EmmaTheme.muted)
                            .padding(.horizontal, 15)
                            .padding(.top, 12)
                            .padding(.bottom, 2)
                    }

                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index == 0 || entries[index - 1].bucket != entry.bucket {
                            groupLabel(entry.bucket)
                        }
                        TaskRow(
                            task: entry.task,
                            dateText: entry.task.rowDateText(dependencies.dateText),
                            // Nazwę klienta rozwiązuje ekran — wiersz nie zna repozytorium.
                            clientName: entry.task.clientID.flatMap { model.clientNames[$0] }
                        ) {
                            Task { await toggle(entry.task) }
                        } onOpen: {
                            dependencies.present(.taskDetail(entry.task.id))
                        }
                        .taskContextMenu(entry.task, dependencies: dependencies) {
                            dependencies.present(.taskDetail(entry.task.id))
                        }
                        if index < entries.count - 1 {
                            Divider().overlay(EmmaTheme.rowSeparator).padding(.horizontal, 15)
                        }
                    }
                    if allEntries.count > entries.count {
                        Divider().overlay(EmmaTheme.rowSeparator).padding(.horizontal, 15)
                        attentionLink("Jeszcze \(allEntries.count - entries.count) · wszystkie zadania") {
                            dependencies.openTasks()
                        }
                    }
                }
            }
        }
    }

    private static let tasksPreviewLimit = 5

    private func summaryLabel(_ summary: TaskGrouping.Summary) -> String {
        if summary.hasOverdue {
            return "\(EmmaPlural.openTasks(summary.open)) · \(EmmaPlural.overdueTasks(summary.overdue))"
        }
        return EmmaPlural.openTasks(summary.open)
    }

    private func groupLabel(_ bucket: TaskGrouping.Bucket) -> some View {
        Text(bucket.title.uppercased())
            .font(EmmaTypography.caption(.semibold))
            .tracking(0.6)
            .foregroundStyle(bucket == .overdue ? EmmaTheme.pillUrgentText : EmmaTheme.mutedSoft)
            .padding(.horizontal, 15)
            .padding(.top, 12)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// Wibrację i natychmiastową zmianę kółka robi `TaskRow`.
    private func toggle(_ task: TaskItem) async {
        await dependencies.perform {
            _ = try await dependencies.repository.setDone(
                taskID: task.id,
                isDone: !task.isDone,
                expectedVersion: task.version
            )
        }
    }

    // MARK: Terminy dnia

    /// Jeden wspólny pojemnik zamiast osobnej karty na każdy termin: widać
    /// wtedy, że to **oś dnia**, a nie luźna lista.
    @ViewBuilder
    private func eventsCard(_ events: [ScheduledEvent]) -> some View {
        SurfaceCard(padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)) {
            VStack(spacing: 0) {
                let now = TimeOfDay.at(dependencies.clock.now())
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    TodayEventRow(
                        event: event,
                        now: now,
                        onOpen: { dependencies.present(.eventDetail(event.id)) },
                        onDelete: { eventPendingDeletion = event },
                        onFinish: { Task { await finishEvent(event) } }
                    )
                    if index < events.count - 1 {
                        Divider().overlay(EmmaTheme.rowSeparator).padding(.horizontal, 15)
                    }
                }
            }
        }
    }

    private func pastEventsSection(_ events: [ScheduledEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsPastEvents.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("Minione terminy")
                        .font(EmmaTypography.sectionTitle)
                        .foregroundStyle(EmmaTheme.ink)
                    Text("\(events.count)")
                        .font(EmmaTypography.caption(.medium))
                        .foregroundStyle(EmmaTheme.mutedSoft)
                    Spacer(minLength: 8)
                    Image(systemName: showsPastEvents ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EmmaTheme.mutedSoft)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .accessibilityLabel("Minione terminy, \(EmmaPlural.events(events.count))")
            .accessibilityHint(showsPastEvents ? "Dotknij, aby zwinąć" : "Dotknij, aby rozwinąć")

            if showsPastEvents {
                eventsCard(events)
            }
        }
    }

}

/// Wiersz zadania z informacją, do którego kubełka należy — potrzebne, żeby
/// wstawić nagłówek grupy dokładnie raz, na jej początku.
private struct TaskEntry: Identifiable {
    let bucket: TaskGrouping.Bucket
    let task: TaskItem

    var id: TaskID { task.id }
}

#Preview("Dzisiaj") {
    let dependencies = AppDependencies.demo()
    return TodayScreen(store: dependencies.todayStore, messages: dependencies.messagesStore)
        .environmentObject(dependencies)
}

/// Ikona stanu w kolejce „Wymaga Ciebie”: kolor mówi, jak pilne (0.22.0).
private struct AttentionIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}
