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
        var events: [ScheduledEvent]
        var tasks: [TaskItem]
        var clientNames: [ClientID: String]
        var caseNumbers: [CaseID: String]
        /// Wszystkie kontakty — z nich liczona jest kolejka leadów do obsługi.
        var clients: [Client]
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle

    func load(_ dependencies: AppDependencies) async {
        // Ponowne wczytanie po zapisie nie mruga stanem ładowania.
        if !phase.hasLoaded { phase = .loading }
        let today = dependencies.today
        let repository = dependencies.repository
        do {
            async let clientsTask = repository.clients(matching: "", stage: nil)
            async let casesTask = repository.cases(status: nil)
            async let eventsTask = repository.events(in: .day(today))
            async let tasksTask = repository.tasks(
                filter: TaskFilter(scope: .open, dueOnOrBefore: today)
            )

            let clients = try await clientsTask
            let cases = try await casesTask
            let events = try await eventsTask
            let tasks = try await tasksTask

            let model = Model(
                    today: today,
                    events: events.sorted { $0.time < $1.time },
                    tasks: tasks.sorted { $0.dueDate < $1.dueDate },
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
                    clients: clients
                )
            // Odświeżenie po zapisie (np. obsłużony lead) jest animowane.
            if phase.hasLoaded {
                withAnimation(.easeInOut(duration: 0.28)) { phase = .loaded(model) }
            } else {
                phase = .loaded(model)
            }
            dependencies.leadsNeedingAction = clients.filter { $0.stage == .new }.count
        } catch {
            phase = .failed(ScreenLoad.failure(for: error, fallback: "Nie udało się wczytać dnia."))
        }
    }
}

struct TodayScreen: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout: EmmaLayoutMetrics
    /// Magazyn żyje w `AppDependencies` — powrót na zakładkę pokazuje od razu
    /// ostatni stan dnia zamiast „Przygotowuję dzień…”.
    @ObservedObject var store: TodayStore
    /// Termin czekający na potwierdzenie usunięcia. Usunięcie jest nieodwracalne
    /// (demo nie ma kosza), więc pytamy — ale dopiero po wybraniu z menu.
    @State private var eventPendingDeletion: ScheduledEvent?
    /// Minione terminy są domyślnie zwinięte: to zapis dnia, nie plan na teraz.
    @State private var showsPastEvents = false

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
        .refreshable { await store.load(dependencies) }
        .task(id: dependencies.dataVersion) { await store.load(dependencies) }
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

        header(model)

        leadsSection(inbox)

        SectionHeader("Najbliższy termin", compact: true)
        nextEventCard(agenda.next, model: model)

        SectionHeader("Zadania", actionTitle: "Wszystkie zadania", compact: true) {
            dependencies.openTasks()
        }
        tasksSection(model)

        if !agenda.upcoming.isEmpty {
            SectionHeader("Dalej dziś", actionTitle: "Kalendarz", compact: true) {
                dependencies.go(to: .calendar)
            }
            eventsCard(agenda.upcoming)
        }

        if !agenda.past.isEmpty {
            pastEventsSection(agenda.past)
        }
    }

    // MARK: Nagłówek dnia

    /// Powitanie według pory dnia w strefie kancelarii.
    private var greeting: String {
        let hour = TimeOfDay.at(dependencies.clock.now()).hour
        switch hour {
        case 5..<18: return "Dzień dobry"
        default: return "Dobry wieczór"
        }
    }

    /// Nagłówek dnia: data, powitanie, portret Emmy i profil kancelarii.
    ///
    /// Portret jest wejściem do rozmowy — ta sama czynność, co dawny przycisk
    /// mikrofonu w karcie Emmy, ale bez zabierania wysokości pod leady i terminy.
    private func header(_ model: TodayStore.Model) -> some View {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
                isActive: dependencies.voice.state.isPlaybackActive,
                state: dependencies.voice.state.turn
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

    // MARK: Leady do obsługi

    /// Najwyżej trzy zgłoszenia: najpierw te, które czekają, potem nowe.
    /// Reszta jest pod „Wszystkie” — ekran główny nie zamienia się w listę.
    @ViewBuilder
    private func leadsSection(_ inbox: LeadInbox) -> some View {
        let queue = inbox.needsAction
        if !queue.isEmpty {
            SectionHeader(
                "Leady do obsługi · \(queue.count)",
                actionTitle: queue.count > Self.leadsPreviewLimit ? "Wszystkie" : "Lista",
                compact: true
            ) {
                dependencies.openLeads(filter: .needsAction)
            }
            SurfaceCard(padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
                VStack(spacing: 0) {
                    ForEach(Array(queue.prefix(Self.leadsPreviewLimit).enumerated()), id: \.element.id) { index, client in
                        LeadInboxRow(
                            client: client,
                            onOpen: { dependencies.openPerson(client.id) },
                            onMarkHandled: { await LeadActions.markHandled(client, dependencies: dependencies) }
                        )
                        if index < min(queue.count, Self.leadsPreviewLimit) - 1 {
                            Divider().overlay(EmmaTheme.rowSeparator).padding(.leading, 64)
                        }
                    }
                }
            }
        }
    }

    private static let leadsPreviewLimit = 3

    // MARK: Najbliższy termin

    @ViewBuilder
    private func nextEventCard(_ event: ScheduledEvent?, model: TodayStore.Model) -> some View {
        if let event {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(event.time.hhmm)
                            .font(EmmaTypography.heading(21))
                            .foregroundStyle(EmmaTheme.ink)
                        if event.durationMinutes > 0 {
                            Text("\(event.durationMinutes) min")
                                .font(EmmaTypography.caption())
                                .foregroundStyle(EmmaTheme.mutedSoft)
                        }
                        Spacer(minLength: 8)
                        StatusPill(
                            event.status.rawValue,
                            kind: event.status == .confirmed ? .green : .amber
                        )
                    }

                    Text(event.title)
                        .font(EmmaTypography.meetingTitle)
                        .foregroundStyle(EmmaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if !event.place.isEmpty {
                        Label(event.place, systemImage: "mappin.and.ellipse")
                            .font(EmmaTypography.caption())
                            .foregroundStyle(EmmaTheme.mutedSoft)
                    }

                    // Linki do powiązanych rekordów: osoba i sprawa jednym dotknięciem,
                    // bez szukania ich ponownie w listach.
                    HStack(spacing: 14) {
                        Button {
                            dependencies.openPerson(event.clientID)
                        } label: {
                            Label(
                                model.clientNames[event.clientID] ?? "Karta klienta",
                                systemImage: "person"
                            )
                            .font(EmmaTypography.caption(.medium))
                            .foregroundStyle(EmmaTheme.accent)
                            .frame(minHeight: 28)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

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
                        PrimaryButton("Przygotuj mnie") {
                            // „Przygotuj mnie” to skrót do rozmowy z Emmą w kontekście
                            // klienta — Emma robi streszczenie sprawy, nic nie zapisuje.
                            dependencies.openEmma(
                                clientID: event.clientID,
                                action: .prepareCase,
                                startVoice: false
                            )
                        }
                        SecondaryButton("Szczegóły") {
                            dependencies.present(.eventDetail(event.id))
                        }
                    }
                    .padding(.top, 1)
                }
            }
        } else {
            emptyCard("Nie masz już dziś zaplanowanych terminów.")
        }
    }

    // MARK: Zadania

    @ViewBuilder
    private func tasksSection(_ model: TodayStore.Model) -> some View {
        let summary = TaskGrouping.summary(model.tasks, today: model.today)
        let groups = TaskGrouping.groups(model.tasks, today: model.today)
        let entries = groups.flatMap { group in
            group.tasks.map { TaskEntry(bucket: group.bucket, task: $0) }
        }

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

                if entries.isEmpty {
                    Text("Wszystkie zadania na dziś wykonane.")
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 16)
                } else {
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
                        if index < entries.count - 1 {
                            Divider().overlay(EmmaTheme.rowSeparator).padding(.horizontal, 15)
                        }
                    }
                }
            }
        }
    }

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

    private func toggle(_ task: TaskItem) async {
        if task.isDone {
            EmmaHaptics.tap()
        } else {
            EmmaHaptics.success()
        }
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
                        onDelete: { eventPendingDeletion = event }
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

    private func emptyCard(_ text: String) -> some View {
        SurfaceCard {
            Text(text)
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
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
    return TodayScreen(store: dependencies.todayStore)
        .environmentObject(dependencies)
}
