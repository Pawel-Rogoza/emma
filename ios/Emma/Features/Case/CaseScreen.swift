import SwiftUI

// MARK: - Ekran sprawy
//
// Port `casePage()`: nagłówek z numerem sprawy, sekcja tytułu z klientem,
// karta Emmy „Przygotuj mnie do tej sprawy” oraz cztery zakładki:
// Przegląd · Zadania · Notatki · Historia.

@MainActor
final class CaseStore: ObservableObject {

    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case overview = "Przegląd"
        case tasks = "Zadania"
        case notes = "Notatki"
        case documents = "Akta"
        case history = "Historia"

        var id: String { rawValue }
    }

    struct Model {
        var legalCase: LegalCase
        var client: Client
        var tasks: [TaskItem]
        var events: [ScheduledEvent]
        var notes: [CaseNote]
        var activity: [ActivityEvent]
        var today: LocalDate

        var openTasks: [TaskItem] { tasks.filter { !$0.isDone } }
        var upcomingEvents: [ScheduledEvent] {
            events
                .filter { $0.day >= today && $0.status != .finished }
                .sorted { $0.day == $1.day ? $0.time < $1.time : $0.day < $1.day }
        }

        /// Najświeższy niezakończony termin **tej sprawy**, który już minął.
        var missedEvent: ScheduledEvent? {
            let from = today.adding(days: -CaseUrgency.missedLookbackDays)
            return events
                .filter {
                    $0.caseID == legalCase.id && $0.kind == .caseDeadline && $0.status != .finished
                        && $0.day < today && $0.day >= from
                }
                .max { $0.day == $1.day ? $0.time < $1.time : $0.day < $1.day }
        }

        var urgency: CaseUrgency {
            CaseUrgency(
                nextEvent: upcomingEvents.first(where: { $0.caseID == legalCase.id })?.day,
                missedEvent: legalCase.status.isActive ? missedEvent?.day : nil,
                overdueTasks: openTasks.filter { $0.dueDate.map { $0 < today } ?? false }.count,
                today: today
            )
        }
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle
    @Published var tab: Tab = .overview

    func load(_ dependencies: AppDependencies, caseID: CaseID) async {
        // Jak na „Dzisiaj” i „Zadaniach”: odświeżenie po zapisie nie cofa listy
        // do stanu ładowania, więc sprawa zachowuje pozycję i wybraną zakładkę.
        if !phase.hasLoaded { phase = .loading }
        do {
            let today = dependencies.today
            let repository = dependencies.repository
            // Zadania, terminy sprawy i historia nie zależą od klienta — idą od
            // razu, równolegle z odczytem sprawy (05.10.2026).
            async let tasksTask = repository.tasks(filter: TaskFilter(scope: .all, caseID: caseID))
            // Audyt 28.09.2026: termin sprawy bez wpisanego klienta (rozprawa
            // z kalendarza sądu) nie przychodził z zapytania po kliencie, więc
            // znikał z ekranu sprawy. Drugie, krótsze okno bez filtra klienta.
            async let caseEventsTask = repository.events(
                in: DateIntervalFilter(from: today.adding(days: -30), through: today.adding(days: 120))
            )
            async let activityTask = repository.activity(caseID: caseID)
            guard let legalCase = try await dependencies.repository.legalCase(id: caseID) else {
                phase = .failed(ScreenLoad.failure(for: DomainError.notFound(resource: "sprawa", id: caseID.rawValue), fallback: "Nie znaleziono sprawy."))
                return
            }
            // Zapytania są niezależne, więc idą równolegle (wcześniej po kolei).
            // Terminy tylko tego klienta i od niedawna: backend oddaje najwyżej
            // 200 pozycji od najstarszej, więc szerokie okno dla wszystkich
            // klientów gubiło nadchodzące terminy sprawy.
            async let eventsTask = repository.events(
                in: DateIntervalFilter(from: today.adding(days: -30), through: today.adding(days: 365 * 2)),
                clientID: legalCase.clientID
            )
            async let notesTask = repository.notes(clientID: legalCase.clientID, caseID: caseID)
            async let clientTask = repository.client(id: legalCase.clientID)
            guard let client = try await clientTask else {
                phase = .failed(ScreenLoad.failure(for: DomainError.notFound(resource: "klient", id: legalCase.clientID.rawValue), fallback: "Nie znaleziono klienta."))
                return
            }
            let tasks = try await tasksTask
            let clientEvents = try await eventsTask
            let caseEvents = ((try? await caseEventsTask) ?? []).filter { $0.caseID == caseID }
            var seen = Set<EventID>()
            let events = (clientEvents + caseEvents).filter { seen.insert($0.id).inserted }
            let notes = try await notesTask
            let activity = try await activityTask

            phase = .loaded(
                Model(
                    legalCase: legalCase,
                    client: client,
                    tasks: tasks,
                    events: events.filter { $0.caseID == caseID || $0.clientID == legalCase.clientID },
                    notes: notes,
                    activity: activity,
                    today: today
                )
            )
        } catch {
            if let message = phase.recordFailure(error, fallback: "Nie udało się wczytać sprawy.") {
                dependencies.showToast(message)
            }
        }
    }
}

struct CaseScreen: View {

    let caseID: CaseID

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout: EmmaLayoutMetrics
    @Environment(\.openURL) private var openURL
    @StateObject private var store = CaseStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch store.phase {
                case .idle, .loading:
                    LoadingState("Wczytuję sprawę…")
                case .failed(let failure):
                    LoadFailureView(failure) {
                        Task { await store.load(dependencies, caseID: caseID) }
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
        // iOS 26: systemowy pasek nawigacji (szkło), opcje sprawy w pasku.
        .navigationTitle("Prowadzona sprawa")
        .navigationSubtitle(store.phase.value?.legalCase.referenceNumber ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let model = store.phase.value {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dependencies.present(.caseSettings(model.legalCase.id))
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Zmień status i opiekuna sprawy")
                }
            }
        }
        .refreshable { await store.load(dependencies, caseID: caseID) }
        .task(id: dependencies.dataVersion) { await store.load(dependencies, caseID: caseID) }
    }

    @ViewBuilder
    private func loaded(_ model: CaseStore.Model) -> some View {
        caseTitle(model)
            .padding(.bottom, 12)
            .emmaAppear(0)

        // Puls sprawy (audyt 29.09.2026) — jak kafelki na „Dzisiaj”:
        // dotknięcie przełącza na właściwą zakładkę.
        casePulse(model)
            .padding(.bottom, 12)
            .emmaAppear(1)

        // Areszt albo koniec legalnego pobytu — licznik dni nad wszystkim,
        // co da się odłożyć na jutro.
        ForEach(CaseWatch.items(for: model.legalCase, today: model.today)) { watch in
            CaseWatchCard(watch: watch) {
                dependencies.present(.caseSettings(model.legalCase.id))
            }
            .contextMenu { watchMenu(watch, model: model) }
            .padding(.bottom, 12)
            .emmaAppear(1)
        }

        emmaCard(model)
            .padding(.bottom, 14)
            .emmaAppear(2)

        SegmentedFilter(items: CaseStore.Tab.allCases, selection: $store.tab) { $0.rawValue }
            .padding(.bottom, 14)

        switch store.tab {
        case .overview: overview(model)
        case .tasks: tasksTab(model)
        case .notes: notesTab(model)
        case .documents: CaseDocumentsTab(caseID: model.legalCase.id, caseTitle: model.legalCase.title)
        case .history: historyTab(model)
        }
    }

    // MARK: Puls sprawy

    private func casePulse(_ model: CaseStore.Model) -> some View {
        let open = model.openTasks.count
        let overdue = model.urgency.overdueTasks
        let upcoming = model.upcomingEvents.filter { $0.caseID == model.legalCase.id || $0.caseID == nil }.count
        return HStack(spacing: 8) {
            PulseTile(
                value: upcoming,
                label: EmmaPlural.form(upcoming, "termin przed nami", "terminy przed nami", "terminów przed nami"),
                systemImage: "calendar",
                tone: model.urgency.isCritical ? EmmaTheme.pillDangerText : EmmaTheme.accent
            ) { selectTab(.overview) }
            PulseTile(
                value: open,
                label: overdue > 0 ? "zadania · \(overdue) po terminie" : EmmaPlural.form(open, "otwarte zadanie", "otwarte zadania", "otwartych zadań"),
                systemImage: "checklist",
                tone: overdue > 0 ? EmmaTheme.pillUrgentText : EmmaTheme.accent
            ) { selectTab(.tasks) }
            PulseTile(
                value: model.notes.count,
                label: EmmaPlural.form(model.notes.count, "notatka", "notatki", "notatek"),
                systemImage: "note.text",
                tone: EmmaTheme.accent
            ) { selectTab(.notes) }
        }
    }

    /// Koniec aresztu do kalendarza (z przypomnieniem jak każdy termin) albo
    /// zmiana daty, gdy sąd przedłużył areszt.
    @ViewBuilder
    private func watchMenu(_ watch: CaseWatch, model: CaseStore.Model) -> some View {
        Button {
            dependencies.pendingEventDraft = EventDraftSeed(
                title: "Koniec: \(watch.kind.displayName.lowercased()) — \(model.client.displayName)",
                day: watch.until
            )
            dependencies.present(.eventForm(editing: nil, clientID: model.client.id, caseID: model.legalCase.id, initialDay: watch.until))
        } label: {
            Label("Dodaj do kalendarza", systemImage: "calendar.badge.plus")
        }
        Button {
            dependencies.present(.caseSettings(model.legalCase.id))
        } label: {
            Label("Zmień datę", systemImage: "pencil")
        }
    }

    private func selectTab(_ tab: CaseStore.Tab) {
        guard store.tab != tab else { return }
        EmmaHaptics.selection()
        store.tab = tab
    }

    // MARK: Sekcje

    /// „Karna · Przygotowawcze · Podejrzany” — dotknięcie otwiera ustawienia,
    /// gdzie etap zmienia się jednym chipem.
    @ViewBuilder
    private func profileLine(_ legalCase: LegalCase) -> some View {
        if let profile = legalCase.profileText {
            Button {
                dependencies.present(.caseSettings(legalCase.id))
            } label: {
                Label(profile, systemImage: legalCase.kind?.systemImage ?? "folder")
                    .font(EmmaTypography.caption(.semibold))
                    .foregroundStyle(EmmaTheme.pillNeutralText)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                    .background(EmmaTheme.pillNeutralBackground, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(EmmaCardButtonStyle())
            .accessibilityHint("Zmień rodzaj, etap lub rolę klienta")
        }
    }

    /// „Sąd Rejonowy dla Warszawy-Śródmieścia · II K 123/26” — przytrzymanie
    /// kopiuje sygnaturę (do pisma, maila, e-Sądu). Bez sygnatury — zachęta
    /// do jej wpisania, bo po niej sprawy szuka się w sądzie i w kartotece.
    @ViewBuilder
    private func courtLine(_ legalCase: LegalCase) -> some View {
        let parts = [legalCase.courtText, legalCase.signatureText].compactMap { $0 }
        if !parts.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "building.columns")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EmmaTheme.mutedSoft)
                Text(parts.joined(separator: " · "))
                    .font(EmmaTypography.caption(.medium))
                    .foregroundStyle(EmmaTheme.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contextMenu {
                if let signature = legalCase.signatureText {
                    Button {
                        UIPasteboard.general.string = signature
                        EmmaHaptics.success()
                        dependencies.showToast("Skopiowano sygnaturę \(signature)")
                    } label: {
                        Label("Kopiuj sygnaturę", systemImage: "doc.on.doc")
                    }
                }
                Button {
                    dependencies.present(.caseSettings(legalCase.id))
                } label: {
                    Label("Zmień sygnaturę lub sąd", systemImage: "pencil")
                }
            }
            .accessibilityElement(children: .combine)
        } else if legalCase.status.isActive {
            Button {
                dependencies.present(.caseSettings(legalCase.id))
            } label: {
                Label(legalCase.kind == nil ? "Dodaj sygnaturę, rodzaj i etap sprawy" : "Dodaj sygnaturę akt i sąd", systemImage: "plus.circle")
                    .font(EmmaTypography.caption(.medium))
                    .foregroundStyle(EmmaTheme.accent)
                    .frame(minHeight: EmmaSpacing.hitTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -10)
        }
    }

    private func caseTitle(_ model: CaseStore.Model) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                StatusPill(model.legalCase.status.rawValue, kind: model.legalCase.status == .inProgress ? .green : .neutral)
                // Pilność na samej górze: „minął 2 dni temu” / „jutro” — to
                // pierwsze, co adwokat chce wiedzieć po otwarciu sprawy.
                if model.legalCase.status.isActive, let countdown = model.urgency.countdownText {
                    StatusPill("Termin \(countdown)", kind: model.urgency.isCritical ? .danger : .amber)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            Text(model.legalCase.title)
                .font(EmmaTypography.caseTitle)
                .tracking(-0.8)
                .foregroundStyle(EmmaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            profileLine(model.legalCase)

            courtLine(model.legalCase)

            HStack(spacing: 8) {
                Button {
                    dependencies.openPerson(model.client.id)
                } label: {
                    HStack(spacing: 11) {
                        PersonAvatar(initials: model.client.initials, style: .identity(model.client.id))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.client.displayName)
                                .font(EmmaTypography.personName)
                                .foregroundStyle(EmmaTheme.ink)
                                .lineLimit(1)
                            LanguageBadge(language: model.client.language)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(EmmaTheme.mutedSoft)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(EmmaCardButtonStyle())
                .accessibilityLabel(model.client.displayName)
                .accessibilityHint("Otwiera kartę klienta")

                // Telefon do klienta bez wchodzenia w jego kartę — najczęstsza
                // czynność przy otwartej sprawie (audyt 28.09.2026).
                if let phone = model.client.phone {
                    if let url = ContactLinks.phoneURL(phone) {
                        contactButton("phone.fill", label: "Zadzwoń do klienta", url: url)
                    }
                    if let url = ContactLinks.whatsAppURL(phone) {
                        contactButton("message.fill", label: "Napisz na WhatsApp", url: url)
                    }
                }
            }
            .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 10))
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .emmaCardShadow()
        }
    }

    private func contactButton(_ systemImage: String, label: String, url: URL) -> some View {
        Button {
            EmmaHaptics.tap()
            openURL(url)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EmmaTheme.accent)
                .frame(width: 40, height: 40)
                .background(EmmaTheme.accentSoft, in: Circle())
                .frame(width: EmmaSpacing.hitTarget, height: EmmaSpacing.hitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func emmaCard(_ model: CaseStore.Model) -> some View {
        Button {
            EmmaHaptics.tap()
            dependencies.openEmma(clientID: model.client.id, action: .prepareCase)
        } label: {
            // Wartości z reguły `.case-emma` referencji: gradient 110°, orb 32 pt,
            // tytuł 13 pt, podtytuł 10 pt, ikona 18 pt, promień 14 pt.
            HStack(spacing: EmmaSpacing.caseEmmaGap) {
                EmmaOrb(size: .medium)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Przygotuj mnie do tej sprawy")
                        .font(EmmaTypography.ui(13, .medium))
                        .foregroundStyle(EmmaTheme.ink)
                    Text("Emma · notatki, terminy, kolejne kroki")
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.caseEmmaSubtitle)
                }
                Spacer(minLength: 0)
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(EmmaTheme.caseEmmaIcon)
            }
            .padding(14)
            .background(
                // `110deg` z CSS: kierunek w prawo i lekko w dół.
                LinearGradient(
                    colors: [EmmaTheme.emmaGradientStart, EmmaTheme.emmaGradientEnd],
                    startPoint: UnitPoint(x: 0.03, y: 0.33),
                    endPoint: UnitPoint(x: 0.97, y: 0.67)
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.caseEmmaCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.caseEmmaCard, style: .continuous)
                    .strokeBorder(EmmaTheme.caseEmmaBorder, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .accessibilityLabel("Przygotuj mnie do tej sprawy z Emmą")
    }

    @ViewBuilder
    private func overview(_ model: CaseStore.Model) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Zakres sprawy")
                    .font(EmmaTypography.detailTitle)
                    .foregroundStyle(EmmaTheme.ink)
                Text(model.legalCase.summary)
                    .font(EmmaTypography.body(for: model.legalCase.summary, size: 14))
                    .foregroundStyle(EmmaTheme.ink.opacity(0.88))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)

        SectionHeader("Kolejny termin", actionTitle: "Dodaj") {
            dependencies.present(.eventForm(editing: nil, clientID: model.client.id, caseID: model.legalCase.id, initialDay: nil))
        }
        if model.upcomingEvents.isEmpty {
            emptyCard("Brak kolejnego terminu", "Dodaj konsultację lub termin dotyczący sprawy.")
        } else {
            ForEach(model.upcomingEvents.prefix(2), id: \.id) { event in
                MeetingCard(event: event, clientName: model.client.displayName) {
                    dependencies.present(.eventDetail(event.id))
                }
                .eventContextMenu(event, dependencies: dependencies) {
                    dependencies.present(.eventDetail(event.id))
                }
                .padding(.bottom, EmmaSpacing.cardGap)
            }
        }

        SectionHeader("Otwarte zadania", actionTitle: "Dodaj") {
            dependencies.present(.taskForm(editing: nil, clientID: model.client.id, caseID: model.legalCase.id))
        }
        taskGroup(model.openTasks, empty: "Wszystkie zadania wykonane.", model: model)

        SectionHeader("Ostatnia notatka", actionTitle: "Dodaj") {
            dependencies.present(.note(clientID: model.client.id, caseID: model.legalCase.id))
        }
        if let last = model.notes.last {
            NoteCard(
                text: last.text,
                footer: dependencies.dateText.dayLabel(last.createdAt)
            )
        } else {
            emptyCard("Brak notatek", "Zapisz lub podyktuj ustalenia z klientem.")
        }
    }

    @ViewBuilder
    private func tasksTab(_ model: CaseStore.Model) -> some View {
        SectionHeader("Lista zadań", actionTitle: "Dodaj") {
            dependencies.present(.taskForm(editing: nil, clientID: model.client.id, caseID: model.legalCase.id))
        }
        taskGroup(model.tasks, empty: "Brak zadań w tej sprawie.", model: model)
    }

    @ViewBuilder
    private func notesTab(_ model: CaseStore.Model) -> some View {
        SectionHeader("Ustalenia i notatki", actionTitle: "Dodaj") {
            dependencies.present(.note(clientID: model.client.id, caseID: model.legalCase.id))
        }
        if model.notes.isEmpty {
            emptyCard("Brak notatek", "Dodaj pierwsze ustalenia z klientem.")
        } else {
            ForEach(model.notes.reversed(), id: \.id) { note in
                NoteCard(
                    text: note.text,
                    footer: dependencies.dateText.dayLabel(note.createdAt)
                )
                .padding(.bottom, EmmaSpacing.cardGap)
            }
        }
    }

    @ViewBuilder
    private func historyTab(_ model: CaseStore.Model) -> some View {
        SectionHeader("Historia sprawy")
        SurfaceCard {
            VStack(spacing: 0) {
                if model.activity.isEmpty {
                    Text("Brak zdarzeń w historii.")
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(model.activity.enumerated()), id: \.element.id) { index, entry in
                        ActivityRow(
                            text: entry.text,
                            dateText: dependencies.dateText.dayLabel(entry.createdAt)
                        )
                        if index < model.activity.count - 1 {
                            Divider().overlay(EmmaTheme.rowSeparator)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func taskGroup(_ tasks: [TaskItem], empty: String, model: CaseStore.Model) -> some View {
        SurfaceCard(padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)) {
            VStack(spacing: 0) {
                if tasks.isEmpty {
                    Text(empty)
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 16)
                } else {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        TaskRow(
                            task: task,
                            dateText: task.rowDateText(dependencies.dateText),
                            clientName: model.client.displayName
                        ) {
                            Task {
                                await dependencies.perform {
                                    _ = try await dependencies.repository.setDone(
                                        taskID: task.id,
                                        isDone: !task.isDone,
                                        expectedVersion: task.version
                                    )
                                }
                            }
                        } onOpen: {
                            dependencies.present(.taskDetail(task.id))
                        }
                        .taskContextMenu(task, dependencies: dependencies) {
                            dependencies.present(.taskDetail(task.id))
                        }
                        if index < tasks.count - 1 {
                            Divider().overlay(EmmaTheme.rowSeparator).padding(.horizontal, 15)
                        }
                    }
                }
            }
        }
    }

    private func emptyCard(_ title: String, _ message: String) -> some View {
        EmptyState(systemImage: "folder", title: title, message: message)
            .frame(maxWidth: .infinity)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
    }
}

#Preview("Sprawa") {
    CaseScreen(caseID: DemoFixtures.caseOlenaID)
        .environmentObject(AppDependencies.demo())
}
