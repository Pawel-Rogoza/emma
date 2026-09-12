import SwiftUI

// MARK: - Ekran główny „Dzisiaj”
//
// Po audycie designu ekran przeszedł dwie iteracje: najpierw był pełnym kokpitem
// (briefing, statystyki, sprawy), potem czystym wejściem do Emmy. Właściciel
// wskazał, że samo wejście do Emmy nic nie wnosi — ekran ma pokazywać **dzisiejszy
// terminarz i zadania na dziś**, a rozmowę z Emmą mieć pod ręką jako skrót.
//
// Dlatego: powitanie, zwięzły wiersz „Zapytaj Emmę o dzień” + dzisiejsze terminy
// z kalendarza i zadania do wykonania. Bez statystyk i sekcji o sprawach.
// Odstępstwo od referencji `home()` jest w docs/ios/DESIGN_DEVIATIONS.md.

@MainActor
final class TodayStore: ObservableObject {

    struct Model {
        var today: LocalDate
        var events: [ScheduledEvent]
        var tasks: [TaskItem]
        var clientNames: [ClientID: String]
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle

    func load(_ dependencies: AppDependencies) async {
        // Ponowne wczytanie po zapisie nie mruga stanem ładowania.
        if !phase.hasLoaded { phase = .loading }
        let today = dependencies.today
        let repository = dependencies.repository
        do {
            async let clientsTask = repository.clients(matching: "", stage: nil)
            async let eventsTask = repository.events(in: .day(today))
            async let tasksTask = repository.tasks(
                filter: TaskFilter(scope: .open, dueOnOrBefore: today)
            )

            let clients = try await clientsTask
            let events = try await eventsTask
            let tasks = try await tasksTask

            phase = .loaded(
                Model(
                    today: today,
                    events: events.sorted { $0.time < $1.time },
                    tasks: tasks.sorted { $0.dueDate < $1.dueDate },
                    clientNames: Dictionary(
                        clients.map { ($0.id, $0.displayName) },
                        uniquingKeysWith: { first, _ in first }
                    )
                )
            )
        } catch {
            phase = .failed(ScreenLoad.failure(for: error, fallback: "Nie udało się wczytać dnia."))
        }
    }
}

struct TodayScreen: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout: EmmaLayoutMetrics
    @StateObject private var store = TodayStore()
    /// Termin czekający na potwierdzenie usunięcia. Usunięcie jest nieodwracalne
    /// (demo nie ma kosza), więc pytamy — ale dopiero po wybraniu z menu.
    @State private var eventPendingDeletion: ScheduledEvent?

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
        ScreenHeader(
            kicker: dependencies.dateText.headline(for: model.today),
            title: "Dzień dobry",
            onProfileTap: { dependencies.present(.profile) }
        )

        emmaStage(model)

        SectionHeader("Dziś w kalendarzu", actionTitle: "Kalendarz") {
            dependencies.go(to: .calendar)
        }
        calendarCard(model)

        SectionHeader("Zadania na dziś", actionTitle: "Wszystkie zadania") {
            dependencies.openTasks()
        }
        taskGroup(model.tasks, clientNames: model.clientNames)
    }

    // MARK: Emma — scena

    /// Emma dostaje na tym ekranie realną przestrzeń: duży orb, miękka poświata
    /// i jedno wyraźne wejście w rozmowę. Układ jest przygotowany na podmianę
    /// orba na animację 3D głowy — scena ma stałą wysokość, więc podmiana nie
    /// przesunie terminarza pod nią.
    private func emmaStage(_ model: TodayStore.Model) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [EmmaTheme.accentSoft, EmmaTheme.accentSoft.opacity(0)],
                            center: .center,
                            startRadius: 12,
                            endRadius: 126
                        )
                    )
                    .frame(width: 252, height: 252)

                EmmaOrb(
                    size: .stage,
                    isActive: dependencies.voice.state.isPlaybackActive,
                    breathing: true
                )
            }
            .frame(height: 186)

            Text("Jestem Emma")
                .font(EmmaTypography.heading(21))
                .foregroundStyle(EmmaTheme.ink)

            Text("Zapytam o dzień, sprawdzę terminy i przygotuję odpowiedź.")
                .font(EmmaTypography.ui(13))
                .foregroundStyle(EmmaTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
                .padding(.horizontal, 16)

            PrimaryButton("Porozmawiaj z Emmą", systemImage: "mic.fill") {
                dependencies.openEmma(clientID: nil, startVoice: true)
            }
            .padding(.top, 16)

            Button {
                dependencies.openEmma(clientID: nil, startVoice: false)
            } label: {
                Text("albo napisz wiadomość")
                    .font(EmmaTypography.ui(12, .medium))
                    .foregroundStyle(EmmaTheme.secondaryButtonText)
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Napisz wiadomość do Emmy")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, EmmaSpacing.sectionTop)
        .accessibilityElement(children: .contain)
    }

    // MARK: Terminarz dnia

    /// Jeden wspólny pojemnik zamiast osobnej karty na każdy termin: widać
    /// wtedy, że to **oś dnia**, a nie luźna lista. Minione terminy zostają,
    /// ale są wygaszone, żeby wzrok szedł po tym, co jeszcze przed nami.
    @ViewBuilder
    private func calendarCard(_ model: TodayStore.Model) -> some View {
        if model.events.isEmpty {
            emptyCard("Nie masz dziś zaplanowanych terminów.")
        } else {
            SurfaceCard(padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)) {
                VStack(spacing: 0) {
                    let now = TimeOfDay.at(dependencies.clock.now())
                    ForEach(Array(model.events.enumerated()), id: \.element.id) { index, event in
                        TodayEventRow(
                            event: event,
                            now: now,
                            onOpen: { dependencies.present(.eventDetail(event.id)) },
                            onDelete: { eventPendingDeletion = event }
                        )
                        if index < model.events.count - 1 {
                            Divider().overlay(EmmaTheme.rowSeparator).padding(.horizontal, 15)
                        }
                    }
                }
            }
        }
    }

    // MARK: Zadania

    @ViewBuilder
    private func taskGroup(_ tasks: [TaskItem], clientNames: [ClientID: String]) -> some View {
        SurfaceCard(padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)) {
            VStack(spacing: 0) {
                if tasks.isEmpty {
                    Text("Wszystkie zadania na dziś wykonane.")
                        .font(EmmaTypography.ui(12))
                        .foregroundStyle(EmmaTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 16)
                } else {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        TaskRow(
                            task: task,
                            dateText: task.rowDateText(dependencies.dateText),
                            // Nazwę klienta rozwiązuje ekran — wiersz nie zna repozytorium.
                            clientName: task.clientID.flatMap { clientNames[$0] }
                        ) {
                            Task { await toggle(task) }
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

    private func toggle(_ task: TaskItem) async {
        await dependencies.perform {
            _ = try await dependencies.repository.setDone(
                taskID: task.id,
                isDone: !task.isDone,
                expectedVersion: task.version
            )
        }
    }

    private func emptyCard(_ text: String) -> some View {
        SurfaceCard {
            Text(text)
                .font(EmmaTypography.ui(12))
                .foregroundStyle(EmmaTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Dzisiaj") {
    TodayScreen()
        .environmentObject(AppDependencies.demo())
}
