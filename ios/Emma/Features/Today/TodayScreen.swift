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
        var greetingName: String
        var userInitials: String
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
                    greetingName: EmmaBriefing.vocative(dependencies.currentUser.displayName),
                    userInitials: dependencies.currentUser.initials,
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
    }

    @ViewBuilder
    private func loaded(_ model: TodayStore.Model) -> some View {
        ScreenHeader(
            kicker: dependencies.dateText.headline(for: model.today),
            title: "Dzień dobry, \(model.greetingName)",
            userInitials: model.userInitials,
            onUserTap: { dependencies.present(.profile) }
        )

        emmaPrompt

        SectionHeader("Dziś w kalendarzu", actionTitle: "Kalendarz") {
            dependencies.go(to: .calendar)
        }
        if model.events.isEmpty {
            emptyCard("Nie masz dziś zaplanowanych terminów.")
        } else {
            ForEach(model.events) { event in
                EventRow(event: event) {
                    dependencies.present(.eventDetail(event.id))
                }
                .padding(.bottom, EmmaSpacing.cardGap)
            }
        }

        SectionHeader("Zadania na dziś", actionTitle: "Wszystkie zadania") {
            dependencies.openTasks()
        }
        taskGroup(model.tasks, clientNames: model.clientNames)
    }

    // MARK: Skrót do rozmowy z Emmą

    /// Zamiast osobnego ekranu-hero: jeden zwięzły wiersz z orbem, który
    /// od razu startuje rozmowę głosową. Orb oddycha, gdy nic się nie dzieje,
    /// i pulsuje mocniej, gdy Emma mówi.
    private var emmaPrompt: some View {
        Button {
            dependencies.openEmma(clientID: nil, startVoice: true)
        } label: {
            HStack(spacing: 12) {
                EmmaOrb(
                    size: .card,
                    isActive: dependencies.voice.state.isPlaybackActive,
                    breathing: true
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Zapytaj Emmę o dzień")
                        .font(EmmaTypography.ui(14, .semibold))
                        .foregroundStyle(EmmaTheme.ink)
                    Text("Głosem albo na piśmie — terminy, sprawy, odpowiedzi")
                        .font(EmmaTypography.ui(12))
                        .foregroundStyle(EmmaTheme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(EmmaTheme.secondaryButtonText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zapytaj Emmę o dzień. Rozpoczyna rozmowę głosową")
        .padding(.top, EmmaSpacing.sectionTop)
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
