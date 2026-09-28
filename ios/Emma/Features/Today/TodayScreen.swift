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
                    missedDeadlines: missed
                )
            // Odświeżenie po zapisie (np. obsłużony lead) jest animowane.
            if phase.hasLoaded {
                withAnimation(.easeInOut(duration: 0.28)) { phase = .loaded(model) }
            } else {
                phase = .loaded(model)
            }
            dependencies.leadsNeedingAction = clients.filter { $0.stage == .new }.count
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

    /// „Załatwione” z menu wiersza — ten sam zapis co w szczegółach terminu.
    private func finishEvent(_ event: ScheduledEvent) async {
        var finished = event
        finished.status = .finished
        let outcome = await dependencies.submit(fallback: "Nie udało się zamknąć terminu.") {
            try await dependencies.repository.updateEvent(finished, expectedVersion: event.version)
        }
        if let message = outcome.errorMessage {
            dependencies.showToast(message)
            return
        }
        EmmaHaptics.success()
        dependencies.reminders.removeReminder(for: event.id)
        dependencies.showToast("Załatwione: \(event.title)")
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

        pulse(model, inbox: inbox)
            .padding(.top, 6)

        if !model.missedDeadlines.isEmpty {
            missedDeadlinesCard(model)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
        }

        leadsSection(inbox)

        SectionHeader("Najbliższy termin", actionTitle: "Dodaj", compact: true) {
            dependencies.present(.eventForm(editing: nil, clientID: nil, caseID: nil, initialDay: nil))
        }
        nextEventCard(agenda.next ?? model.upcomingEvents.first, model: model)

        if !agenda.upcoming.isEmpty {
            SectionHeader("Dalej dziś", actionTitle: "Kalendarz", compact: true) {
                dependencies.go(to: .calendar)
            }
            eventsCard(agenda.upcoming)
        }

        SectionHeader("Zadania", actionTitle: "Wszystkie zadania", compact: true) {
            dependencies.openTasks()
        }
        tasksSection(model)

        weekStrip(model)

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

    // MARK: Po terminie

    /// Czerwona karta nad wszystkim innym: terminy w sprawach, które minęły,
    /// a nikt ich nie zamknął. Dotknięcie otwiera termin (tam „Zakończ”
    /// albo przesunięcie), przytrzymanie — sprawę.
    private func missedDeadlinesCard(_ model: TodayStore.Model) -> some View {
        let shown = Array(model.missedDeadlines.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating.speed(0.5))
                Text("Po terminie · \(model.missedDeadlines.count)")
                    .font(EmmaTypography.ui(15, .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(EmmaTheme.pillDangerText)
            .padding(.horizontal, 15)
            .padding(.top, 13)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(Array(shown.enumerated()), id: \.element.id) { index, event in
                Button {
                    dependencies.present(.eventDetail(event.id))
                } label: {
                    missedRow(event, model: model)
                }
                .buttonStyle(EmmaCardButtonStyle())
                .contextMenu {
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
                if index < shown.count - 1 {
                    Divider().overlay(EmmaTheme.pillDangerText.opacity(0.15)).padding(.horizontal, 15)
                }
            }
            if model.missedDeadlines.count > shown.count {
                Button {
                    dependencies.clientMode = .cases
                    dependencies.go(to: .clients, resetStack: true)
                } label: {
                    Text("Wszystkie sprawy po terminie")
                        .font(EmmaTypography.caption(.semibold))
                        .foregroundStyle(EmmaTheme.pillDangerText)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 6)
        .background(EmmaTheme.pillDangerBackground)
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                .strokeBorder(EmmaTheme.pillDangerText.opacity(0.25), lineWidth: 1)
        }
        .accessibilityIdentifier("today-missed-deadlines")
    }

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

    // MARK: Leady do obsługi

    /// Najwyżej trzy zgłoszenia: najpierw te, które czekają, potem nowe.
    /// Reszta jest pod „Wszystkie” — ekran główny nie zamienia się w listę.
    /// Sekcja jest zawsze: brak leadów to też informacja („nic nie czeka”).
    @ViewBuilder
    private func leadsSection(_ inbox: LeadInbox) -> some View {
        let queue = inbox.needsAction
        SectionHeader(
            queue.isEmpty ? "Nowe leady" : "Nowe leady · \(queue.count)",
            actionTitle: queue.isEmpty ? "Wszystkie" : (queue.count > Self.leadsPreviewLimit ? "Wszystkie" : "Lista"),
            compact: true
        ) {
            dependencies.openLeads(filter: queue.isEmpty ? .all : .needsAction)
        }
        if queue.isEmpty {
            SurfaceCard {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(EmmaTheme.pillGreenText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Brak nowych leadów")
                            .font(EmmaTypography.ui(14, .semibold))
                            .foregroundStyle(EmmaTheme.ink)
                        Text(inbox.inContact.isEmpty
                             ? "Nowe zgłoszenia ze strony pojawią się tutaj."
                             : "W kontakcie: \(EmmaPlural.leads(inbox.inContact.count)). Nowe zgłoszenia pojawią się tutaj.")
                            .font(EmmaTypography.caption())
                            .foregroundStyle(EmmaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today-no-leads")
        } else {
            SurfaceCard(padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
                VStack(spacing: 0) {
                    ForEach(Array(queue.prefix(Self.leadsPreviewLimit).enumerated()), id: \.element.id) { index, client in
                        LeadInboxRow(
                            client: client,
                            onOpen: { dependencies.openPerson(client.id) },
                            onMarkHandled: { await LeadActions.markInContact(client, dependencies: dependencies) }
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
                        Text(event.isAllDay ? "Cały dzień" : event.time.hhmm)
                            .font(EmmaTypography.heading(21))
                            .foregroundStyle(EmmaTheme.ink)
                        if event.day != model.today {
                            Text(dependencies.dateText.dayLabel(event.day))
                                .font(EmmaTypography.ui(14, .semibold))
                                .foregroundStyle(EmmaTheme.accent)
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
                        Label(event.place, systemImage: "mappin.and.ellipse")
                            .font(EmmaTypography.caption())
                            .foregroundStyle(EmmaTheme.mutedSoft)
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

    // MARK: Puls dnia

    /// Trzy kafelki: ile czeka leadów, ile terminów dziś, ile zadań.
    private func pulse(_ model: TodayStore.Model, inbox: LeadInbox) -> some View {
        let summary = TaskGrouping.summary(model.tasks, today: model.today)
        return HStack(spacing: 8) {
            PulseTile(
                value: inbox.needsAction.count,
                label: "leady do obsługi",
                systemImage: "tray.full",
                tone: inbox.waiting.isEmpty ? EmmaTheme.accent : EmmaTheme.pillAmberText
            ) {
                dependencies.openLeads(filter: .needsAction)
            }
            PulseTile(
                value: model.events.count,
                label: model.events.count == 1 ? "termin dziś" : "terminy dziś",
                systemImage: "calendar",
                tone: EmmaTheme.accent
            ) {
                dependencies.openCalendar(on: model.today)
            }
            PulseTile(
                value: summary.open,
                label: summary.hasOverdue ? "zadania · \(summary.overdue) po terminie" : "zadania na dziś",
                systemImage: "checklist",
                tone: summary.hasOverdue ? EmmaTheme.pillUrgentText : EmmaTheme.accent
            ) {
                dependencies.openTasks()
            }
            .accessibilityIdentifier("pulse-tasks")
        }
    }

    // MARK: Tydzień

    /// Siedem najbliższych dni z liczbą terminów — dotknięcie otwiera kalendarz
    /// na tym dniu. Wolny dzień nie jest już pustą kartą, tylko częścią planu.
    private func weekStrip(_ model: TodayStore.Model) -> some View {
        let all = model.events + model.upcomingEvents
        let days = (0..<7).map { model.today.adding(days: $0) }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Najbliższe 7 dni", actionTitle: "Kalendarz", compact: true) {
                dependencies.go(to: .calendar)
            }
            HStack(spacing: 5) {
                ForEach(days, id: \.self) { day in
                    let count = all.filter { $0.day == day }.count
                    let isToday = day == model.today
                    Button {
                        EmmaHaptics.selection()
                        dependencies.openCalendar(on: day)
                    } label: {
                        VStack(spacing: 4) {
                            Text(dependencies.dateText.weekdayShort(for: day))
                                .font(EmmaTypography.caption(.medium))
                                .foregroundStyle(isToday ? EmmaTheme.daySelectedLabel : EmmaTheme.mutedSoft)
                            Text("\(day.day)")
                                .font(EmmaTypography.heading(16))
                                .foregroundStyle(isToday ? EmmaTheme.daySelectedNumber : EmmaTheme.ink)
                            Text(count == 0 ? "–" : "\(count)")
                                .font(EmmaTypography.caption(.semibold))
                                .foregroundStyle(isToday
                                                 ? EmmaTheme.daySelectedNumber
                                                 : (count == 0 ? EmmaTheme.mutedSoft : EmmaTheme.accent))
                                .frame(minWidth: 20, minHeight: 18)
                                .background(
                                    count > 0 && !isToday ? EmmaTheme.accentSoft : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .frame(maxWidth: .infinity, minHeight: 74)
                        .background(isToday ? EmmaTheme.daySelected : EmmaTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.dayCell, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: EmmaRadii.dayCell, style: .continuous)
                                .strokeBorder(isToday ? Color.clear : EmmaTheme.cardBorder, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(EmmaCardButtonStyle())
                    .accessibilityLabel("\(dependencies.dateText.dayLabel(day)), \(EmmaPlural.events(count))")
                }
            }
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
    return TodayScreen(store: dependencies.todayStore)
        .environmentObject(dependencies)
}
