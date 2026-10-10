import SwiftUI

// MARK: - Ekran „Zadania”
//
// Wspólna lista zespołu — port `tasksPage()`. Jeden filtr segmentowy (zakres)
// i jedna grupa zadań w karcie. Zakładka „Dzisiaj” pozostaje podświetlona,
// bo ekran jest wypychany na jej stosie (mapowanie z `nav()`).

@MainActor
final class TasksStore: ObservableObject {

    enum Scope: String, CaseIterable, Identifiable, Hashable {
        case open = "Otwarte"
        case done = "Wykonane"
        case all = "Wszystkie"

        var id: String { rawValue }

        var filterScope: TaskFilter.Scope {
            switch self {
            case .open: return .open
            case .done: return .done
            case .all: return .all
            }
        }
    }

    struct Model {
        var tasks: [TaskItem]
        var clientNames: [ClientID: String]
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle
    @Published var scope: Scope = .open

    func load(_ dependencies: AppDependencies) async {
        // Odświeżenie po zapisie (np. odhaczeniu zadania) nie mruga stanem
        // ładowania: lista zostaje na ekranie i **zachowuje pozycję**. Etap 3
        // audytu stawia to jako warunek zakończenia; ten sam wzorzec ma już
        // „Dzisiaj” (`TodayStore.load`).
        if !phase.hasLoaded { phase = .loading }
        let requestedScope = scope
        do {
            let tasks = try await dependencies.repository.tasks(
                filter: TaskFilter(scope: requestedScope.filterScope)
            )
            let clients = try await dependencies.repository.clients(matching: "", stage: nil)
            // Szybkie przełączenie zakresu: wynik starszego zapytania nie może
            // nadpisać listy nowszego (audyt 29.09.2026).
            guard requestedScope == scope else { return }
            phase = .loaded(
                Model(
                    tasks: tasks.sorted(by: TaskItem.isOrderedByDueDate),
                    clientNames: Dictionary(clients.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
                )
            )
        } catch {
            if let message = phase.recordFailure(error, fallback: "Nie udało się wczytać zadań.") {
                dependencies.showToast(message)
            }
        }
    }
}

struct TasksScreen: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout: EmmaLayoutMetrics
    @StateObject private var store = TasksStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SegmentedFilter(items: TasksStore.Scope.allCases, selection: $store.scope) { $0.rawValue }
                    .padding(.bottom, 14)

                switch store.phase {
                case .idle, .loading:
                    LoadingState("Wczytuję zadania…")
                case .failed(let failure):
                    LoadFailureView(failure) {
                        Task { await store.load(dependencies) }
                    }
                case .loaded(let model):
                    list(model)
                }
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, EmmaSpacing.contentTop)
            .padding(.bottom, EmmaSpacing.contentBottom)
        }
        .background(EmmaTheme.bg)
        .scrollIndicators(.hidden)
        // iOS 26: tytuł i „Dodaj zadanie” w systemowym pasku nawigacji.
        .navigationTitle("Zadania")
        .navigationSubtitle("Wspólna lista")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dependencies.present(.taskForm(editing: nil, clientID: nil, caseID: nil))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Dodaj zadanie")
            }
        }
        .refreshable { await store.load(dependencies) }
        .task(id: dependencies.dataVersion) { await store.load(dependencies) }
        .onChange(of: store.scope) { _, _ in Task { await store.load(dependencies) } }
    }

    @ViewBuilder
    private func list(_ model: TasksStore.Model) -> some View {
        // Grupowanie (etap 3 audytu) ma sens dla zadań otwartych i „wszystkich”:
        // pokazuje, co jest zaległe, a co dopiero przed nami. Widok „Wykonane”
        // zostaje płaski — grupowanie zamkniętych zadań nic nie wnosi.
        let isDoneScope = store.scope == .done
        let groups = isDoneScope
            ? []
            : TaskGrouping.groups(model.tasks, today: dependencies.today)

        if !isDoneScope, !model.tasks.isEmpty {
            let summary = TaskGrouping.summary(model.tasks, today: dependencies.today)
            Text(summaryLabel(summary))
                .font(EmmaTypography.caption())
                .foregroundStyle(summary.hasOverdue ? EmmaTheme.pillUrgentText : EmmaTheme.muted)
                .padding(.bottom, 8)
        }

        SurfaceCard(padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)) {
            VStack(spacing: 0) {
                if model.tasks.isEmpty {
                    Text("Brak zadań w tym widoku.")
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 16)
                } else if isDoneScope {
                    ForEach(Array(model.tasks.enumerated()), id: \.element.id) { index, task in
                        taskRow(task, model: model, showsDivider: index < model.tasks.count - 1)
                    }
                } else {
                    ForEach(groups, id: \.bucket) { group in
                        groupLabel(group.bucket)
                        ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
                            taskRow(
                                task,
                                model: model,
                                showsDivider: !(group.bucket == groups.last?.bucket
                                    && index == group.tasks.count - 1)
                            )
                        }
                    }
                }
            }
        }
    }

    private func taskRow(_ task: TaskItem, model: TasksStore.Model, showsDivider: Bool) -> some View {
        VStack(spacing: 0) {
            TaskRow(
                task: task,
                dateText: task.rowDateText(dependencies.dateText),
                clientName: task.clientID.flatMap { model.clientNames[$0] }
            ) {
                Task { await toggle(task) }
            } onOpen: {
                dependencies.present(.taskDetail(task.id))
            }
            .taskContextMenu(task, dependencies: dependencies) {
                dependencies.present(.taskDetail(task.id))
            }
            if showsDivider {
                Divider().overlay(EmmaTheme.rowSeparator).padding(.horizontal, 15)
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
}

#Preview("Zadania") {
    TasksScreen()
        .environmentObject(AppDependencies.demo())
}
