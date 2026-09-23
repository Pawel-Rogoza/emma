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
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle
    @Published var tab: Tab = .overview

    func load(_ dependencies: AppDependencies, caseID: CaseID) async {
        // Jak na „Dzisiaj” i „Zadaniach”: odświeżenie po zapisie nie cofa listy
        // do stanu ładowania, więc sprawa zachowuje pozycję i wybraną zakładkę.
        if !phase.hasLoaded { phase = .loading }
        do {
            guard let legalCase = try await dependencies.repository.legalCase(id: caseID) else {
                phase = .failed(ScreenLoad.failure(for: DomainError.notFound(resource: "sprawa", id: caseID.rawValue), fallback: "Nie znaleziono sprawy."))
                return
            }
            guard let client = try await dependencies.repository.client(id: legalCase.clientID) else {
                phase = .failed(ScreenLoad.failure(for: DomainError.notFound(resource: "klient", id: legalCase.clientID.rawValue), fallback: "Nie znaleziono klienta."))
                return
            }
            let today = dependencies.today
            let tasks = try await dependencies.repository.tasks(filter: TaskFilter(scope: .all, caseID: caseID))
            let events = try await dependencies.repository.events(
                in: DateIntervalFilter(from: today.adding(days: -365), through: today.adding(days: 365))
            )
            let notes = try await dependencies.repository.notes(clientID: legalCase.clientID, caseID: caseID)
            let activity = try await dependencies.repository.activity(caseID: caseID)

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
            phase = .failed(ScreenLoad.failure(for: error, fallback: "Nie udało się wczytać sprawy."))
        }
    }
}

struct CaseScreen: View {

    let caseID: CaseID

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout: EmmaLayoutMetrics
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
        .navigationBarBackButtonHidden(true)
        .emmaPreservesSwipeBack()
        .refreshable { await store.load(dependencies, caseID: caseID) }
        .task(id: dependencies.dataVersion) { await store.load(dependencies, caseID: caseID) }
    }

    @ViewBuilder
    private func loaded(_ model: CaseStore.Model) -> some View {
        DetailHeader(
            caption: model.legalCase.number,
            title: "Prowadzona sprawa",
            onBack: { dependencies.back() }
        ) {
            IconButton(
                systemName: "ellipsis",
                accessibilityLabel: "Zmień status i opiekuna sprawy"
            ) {
                dependencies.present(.caseSettings(model.legalCase.id))
            }
        }

        caseTitle(model)
            .padding(.bottom, 12)

        emmaCard(model)
            .padding(.bottom, 14)

        SegmentedFilter(items: CaseStore.Tab.allCases, selection: $store.tab) { $0.rawValue }
            .padding(.bottom, 14)

        switch store.tab {
        case .overview: overview(model)
        case .tasks: tasksTab(model)
        case .notes: notesTab(model)
        case .history: historyTab(model)
        }
    }

    // MARK: Sekcje

    @ViewBuilder
    private func caseTitle(_ model: CaseStore.Model) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusPill(model.legalCase.status.rawValue, kind: model.legalCase.status == .inProgress ? .green : .neutral)
            Text(model.legalCase.title)
                .font(EmmaTypography.caseTitle)
                .tracking(-0.8)
                .foregroundStyle(EmmaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                dependencies.openPerson(model.client.id)
            } label: {
                HStack(spacing: 11) {
                    PersonAvatar(initials: model.client.initials, style: .person)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.client.displayName)
                            .font(EmmaTypography.personName)
                            .foregroundStyle(EmmaTheme.ink)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(EmmaTheme.mutedSoft)
                }
                .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
                .background(EmmaTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.client.displayName)
        }
    }

    @ViewBuilder
    private func emmaCard(_ model: CaseStore.Model) -> some View {
        Button {
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
        .buttonStyle(.plain)
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
