import SwiftUI

// MARK: - Ekran „Dzisiaj”
//
// Odtworzenie `home()` z referencji: nagłówek z powitaniem, karta Emmy z briefingiem,
// statystyki obszaru pracy, najbliższa konsultacja, zadania na dziś i prowadzone sprawy.
//
// Jedno odstępstwo świadome: przycisk odsłuchu briefingu korzysta z koordynatora
// głosu (`startPlayback`) zamiast z syntezatora przeglądarki. Dzięki temu odsłuch
// ma jednego właściciela zasobu audio i nie otwiera mikrofonu (§5.3).

@MainActor
final class TodayStore: ObservableObject {

    struct Model {
        var today: LocalDate
        var greetingName: String
        var userInitials: String
        var briefing: String
        var leadCount: Int
        var activeCaseCount: Int
        var tasksDueToday: [TaskItem]
        var nextConsultation: ScheduledEvent?
        var nextConsultationClientName: String
        var clientNames: [ClientID: String]
        var activeCases: [(legalCase: LegalCase, clientName: String, openTaskCount: Int, nextEvent: ScheduledEvent?)]
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle

    func load(_ dependencies: AppDependencies) async {
        phase = .loading
        let today = dependencies.today
        let repository = dependencies.repository
        do {
            let clients = try await repository.clients(matching: "", stage: nil)
            let cases = try await repository.cases(status: nil)
            let tasks = try await repository.tasks(
                filter: TaskFilter(scope: .open, dueOnOrBefore: today)
            )
            let todayEvents = try await repository.events(in: .day(today), ownerID: nil)
            let upcoming = try await repository.events(
                in: DateIntervalFilter(from: today, through: today.adding(days: 60)),
                ownerID: nil
            )

            let names = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0.displayName) })
            let activeCases = cases.filter { $0.status != .closed }

            let mine = todayEvents
                .filter { $0.kind == .consultation && $0.status != .finished && $0.ownerID == dependencies.currentUser.id }
                .min { $0.time < $1.time }

            var caseSummaries: [(LegalCase, String, Int, ScheduledEvent?)] = []
            for legalCase in activeCases.prefix(2) {
                let caseTasks = try await repository.tasks(filter: TaskFilter(scope: .open, caseID: legalCase.id))
                let caseEvents = try await repository.events(
                    in: DateIntervalFilter(from: today, through: today.adding(days: 365)),
                    ownerID: nil
                )
                let next = caseEvents
                    .filter { $0.caseID == legalCase.id && $0.status != .finished }
                    .min { $0.day == $1.day ? $0.time < $1.time : $0.day < $1.day }
                caseSummaries.append((legalCase, names[legalCase.clientID] ?? "", caseTasks.count, next))
            }

            phase = .loaded(
                Model(
                    today: today,
                    greetingName: Self.vocative(dependencies.currentUser.displayName),
                    userInitials: dependencies.currentUser.initials,
                    briefing: Self.briefing(
                        events: todayEvents,
                        tasks: tasks,
                        waitingForReply: clients.filter(\.needsReply),
                        clientNames: names
                    ),
                    leadCount: clients.filter { $0.stage != .client }.count,
                    activeCaseCount: activeCases.count,
                    tasksDueToday: tasks.sorted { $0.dueDate < $1.dueDate },
                    nextConsultation: mine,
                    nextConsultationClientName: mine.flatMap { names[$0.clientID] } ?? "",
                    clientNames: names,
                    activeCases: caseSummaries.map {
                        (legalCase: $0.0, clientName: $0.1, openTaskCount: $0.2, nextEvent: $0.3)
                    }
                )
            )
        } catch {
            phase = .failed(ScreenLoad.message(for: error, fallback: "Nie udało się wczytać dnia."))
        }
    }

    /// „Tomasz” → „Tomaszu”. Referencja odmieniała imiona na sztywno.
    static func vocative(_ name: String) -> String {
        guard let first = name.split(separator: " ").first.map(String.init) else { return name }
        switch first {
        case "Tomasz": return "Tomaszu"
        case "Paweł": return "Pawle"
        default: return first
        }
    }

    /// Treść briefingu — port `briefing()` z referencji, z tymi samymi zdaniami.
    static func briefing(
        events: [ScheduledEvent],
        tasks: [TaskItem],
        waitingForReply: [Client],
        clientNames: [ClientID: String]
    ) -> String {
        let relevant = events.filter { $0.status != .finished }.sorted { $0.time < $1.time }
        var lines: [String] = []
        lines.append("Dzisiaj w zespole: \(EmmaPlural.label(relevant.count, "wydarzenie", "wydarzenia", "wydarzeń")).")
        for event in relevant {
            let who = clientNames[event.clientID] ?? "Klient"
            var line = "\(event.time.hhmm): \(who), \(event.title). Prowadzący: \(event.ownerLabel)."
            if event.status == .toConfirm { line += " Termin czeka na potwierdzenie." }
            lines.append(line)
        }
        lines.append("")
        if tasks.isEmpty {
            lines.append("Do załatwienia: brak otwartych zadań na dziś.")
        } else {
            let list = tasks.map { "\($0.title) (\(OwnerName.of($0.ownerID)))" }.joined(separator: "; ")
            lines.append("Do załatwienia: \(list).")
        }
        if waitingForReply.isEmpty {
            lines.append("Wszystkie rozmowy zaopiekowane.")
        } else {
            lines.append("Na odpowiedź czekają: \(waitingForReply.map(\.displayName).joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
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
                case .failed(let message):
                    InlineError(message)
                    SecondaryButton("Spróbuj ponownie") {
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

        emmaCard(model)

        WorkspaceStats([
            .init(value: "\(model.leadCount)", label: "Leady"),
            .init(value: "\(model.activeCaseCount)", label: "Prowadzone sprawy"),
            .init(value: "\(model.tasksDueToday.count)", label: "Zadania na dziś")
        ])
        .padding(.bottom, 4)

        SectionHeader("Najbliższa konsultacja", actionTitle: "Kalendarz") {
            dependencies.go(to: .calendar)
        }
        if let event = model.nextConsultation {
            MeetingCard(event: event, clientName: model.nextConsultationClientName) {
                dependencies.present(.eventDetail(event.id))
            }
        } else {
            emptyCard("Nie masz już dziś zaplanowanych konsultacji.")
        }

        SectionHeader("Do załatwienia", actionTitle: "Wszystkie") {
            dependencies.openTasks()
        }
        taskGroup(model.tasksDueToday, clientNames: model.clientNames, showAll: false)

        SectionHeader("Prowadzone sprawy", actionTitle: "Zobacz wszystkie") {
            dependencies.clientMode = .cases
            dependencies.go(to: .clients)
        }
        ForEach(model.activeCases, id: \.legalCase.id) { item in
            CaseCard(
                legalCase: item.legalCase,
                clientName: item.clientName,
                openTaskCount: item.openTaskCount,
                nextEvent: item.nextEvent
            ) {
                dependencies.openCase(item.legalCase.id)
            }
            .padding(.bottom, EmmaSpacing.cardGap)
        }
        if model.activeCases.isEmpty {
            emptyCard("Nie prowadzisz jeszcze żadnej sprawy.")
        }
    }

    // MARK: Karta Emmy

    @ViewBuilder
    private func emmaCard(_ model: TodayStore.Model) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                EmmaOrb(size: .card, isActive: dependencies.voice.state.isPlaybackActive)
                Text("Emma")
                    .font(EmmaTypography.ui(15, .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button {
                    Task { await playBriefing(model.briefing) }
                } label: {
                    Image(systemName: dependencies.voice.state.isPlaybackActive ? "stop.circle" : "speaker.wave.2")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(EmmaTheme.emmaCardText)
                        .frame(width: EmmaSpacing.hitTarget, height: EmmaSpacing.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    dependencies.voice.state.isPlaybackActive ? "Zatrzymaj odsłuch briefingu" : "Odsłuchaj briefing"
                )
            }

            Text(model.briefing)
                .font(EmmaTypography.body(for: model.briefing, size: 14))
                .foregroundStyle(EmmaTheme.emmaCardText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                dependencies.openEmma(clientID: nil, startVoice: true)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill").font(.system(size: 14, weight: .semibold))
                    Text("Porozmawiaj z Emmą").font(EmmaTypography.button)
                }
                .foregroundStyle(EmmaTheme.primaryButtonText)
                .frame(maxWidth: .infinity, minHeight: EmmaMetrics.previewButtonMinHeight)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Porozmawiaj z Emmą")
        }
        .padding(EdgeInsets(top: 17, leading: 18, bottom: 18, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EmmaTheme.emmaCard)
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.emmaCard, style: .continuous))
        .padding(.bottom, EmmaSpacing.cardGap)
    }

    /// Odsłuch briefingu przez jeden koordynator głosu. Streszczenie jest oznaczone
    /// jako streszczenie, aby było jasne, że to nie dosłowny zapis rozmowy (§5.2).
    private func playBriefing(_ text: String) async {
        if dependencies.voice.state.isPlaybackActive {
            await dependencies.voice.stopPlayback()
            return
        }
        await dependencies.voice.startPlayback(
            SpeechPlaybackRequest(text: text, language: .pl, isSummary: true, sourceID: "briefing-today"),
            service: dependencies.makePlaybackService()
        )
    }

    // MARK: Elementy listy

    @ViewBuilder
    private func taskGroup(
        _ tasks: [TaskItem],
        clientNames: [ClientID: String],
        showAll: Bool
    ) -> some View {
        SurfaceCard(padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)) {
            VStack(spacing: 0) {
                let visible = showAll ? tasks : Array(tasks.prefix(3))
                if visible.isEmpty {
                    Text("Wszystkie zadania na dziś wykonane.")
                        .font(EmmaTypography.ui(12))
                        .foregroundStyle(EmmaTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 16)
                } else {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, task in
                        TaskRow(
                            task: task,
                            dateText: taskDateText(task),
                            // Nazwę klienta rozwiązuje ekran — wiersz nie zna repozytorium.
                            clientName: task.clientID.flatMap { clientNames[$0] }
                        ) {
                            Task { await toggle(task) }
                        } onOpen: {
                            dependencies.present(.taskDetail(task.id))
                        }
                        if index < visible.count - 1 {
                            Divider().overlay(EmmaTheme.rowSeparator).padding(.horizontal, 15)
                        }
                    }
                }
            }
        }
    }

    private func taskDateText(_ task: TaskItem) -> String {
        if task.priority == .urgent && !task.isDone { return "Pilne" }
        return dependencies.dateText.dayLabel(task.dueDate)
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
