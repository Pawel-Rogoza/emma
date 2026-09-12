import SwiftUI

// MARK: - Ekran „Zadania”
//
// Wspólna lista zespołu — port `tasksPage()`. Dwa filtry segmentowe (zakres i osoba)
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

    struct Owner: Hashable, Identifiable {
        let id: UserID?
        let title: String

        static let both = Owner(id: nil, title: "Obaj")
        static let all: [Owner] = [
            .both,
            Owner(id: .tomasz, title: OwnerName.of(.tomasz)),
            Owner(id: .pawel, title: OwnerName.of(.pawel))
        ]
    }

    struct Model {
        var tasks: [TaskItem]
        var clientNames: [ClientID: String]
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle
    @Published var scope: Scope = .open
    @Published var owner: Owner = .both

    func load(_ dependencies: AppDependencies) async {
        phase = .loading
        do {
            let tasks = try await dependencies.repository.tasks(
                filter: TaskFilter(scope: scope.filterScope, ownerID: owner.id)
            )
            let clients = try await dependencies.repository.clients(matching: "", stage: nil)
            phase = .loaded(
                Model(
                    tasks: tasks.sorted { $0.dueDate < $1.dueDate },
                    clientNames: Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0.displayName) })
                )
            )
        } catch {
            phase = .failed(ScreenLoad.failure(for: error, fallback: "Nie udało się wczytać zadań."))
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
                ScreenHeader(
                    kicker: "WSPÓLNA LISTA",
                    title: "Zadania",
                    userInitials: dependencies.currentUser.initials,
                    onUserTap: nil
                )

                HStack {
                    Spacer(minLength: 0)
                    IconButton(
                        systemName: "plus",
                        accessibilityLabel: "Dodaj zadanie"
                    ) {
                        dependencies.present(.taskForm(editing: nil, clientID: nil, caseID: nil))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: EmmaRadii.iconButton, style: .continuous)
                            .strokeBorder(EmmaTheme.fieldBorder, lineWidth: 1)
                    }
                }
                .padding(.bottom, 12)

                SegmentedFilter(items: TasksStore.Scope.allCases, selection: $store.scope) { $0.rawValue }
                    .padding(.bottom, 8)

                SegmentedFilter(items: TasksStore.Owner.all, selection: $store.owner) { $0.title }
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
        .task(id: dependencies.dataVersion) { await store.load(dependencies) }
        .onChange(of: store.scope) { _, _ in Task { await store.load(dependencies) } }
        .onChange(of: store.owner) { _, _ in Task { await store.load(dependencies) } }
    }

    @ViewBuilder
    private func list(_ model: TasksStore.Model) -> some View {
        SurfaceCard(padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)) {
            VStack(spacing: 0) {
                if model.tasks.isEmpty {
                    Text("Brak zadań w tym widoku.")
                        .font(EmmaTypography.ui(12))
                        .foregroundStyle(EmmaTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 16)
                } else {
                    ForEach(Array(model.tasks.enumerated()), id: \.element.id) { index, task in
                        TaskRow(
                            task: task,
                            dateText: task.rowDateText(dependencies.dateText),
                            clientName: task.clientID.flatMap { model.clientNames[$0] }
                        ) {
                            Task { await toggle(task) }
                        } onOpen: {
                            dependencies.present(.taskDetail(task.id))
                        }
                        if index < model.tasks.count - 1 {
                            Divider().overlay(EmmaTheme.rowSeparator).padding(.horizontal, 15)
                        }
                    }
                }
            }
        }
    }

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
