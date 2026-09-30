import SwiftUI

// MARK: - Ekran „Kalendarz”
//
// Review 24.09.2026: „kalendarz bym znacznie usprawnił i rozbudował, fajnie
// by było widać od razu podgląd np. miesiąca”. Kalendarz ma teraz trzy widoki:
//
//   • **Miesiąc** (domyślny) — siatka 6×7 z kropkami terminów w każdym dniu;
//     dotknięcie dnia pokazuje jego terminy pod siatką, przesunięcie w bok
//     zmienia miesiąc,
//   • **Tydzień** — dotychczasowy pasek tygodnia z listą dnia,
//   • **Lista** — najbliższe 60 dni pogrupowane po dniach (tylko dni z terminami).
//
// Przebudowa 29.09.2026 — ten sam język co „Dzisiaj” i „Klienci”:
//   • tytuł „Kalendarz” i trzy kafelki: terminy dziś, najbliższe 7 dni i terminy
//     po czasie (ten sam próg 30 dni co karta „Po terminie” na „Dzisiaj”),
//   • miesiąc przewija się w stronę gestu, tytuł miesiąca „przewija” litery,
//     a wybór dnia to przesuwana pigułka (jak w filtrach),
//   • legenda kolorów kropek pod siatką,
//   • dzień jako **oś**: kropka w kolorze rodzaju, linia łącząca terminy,
//     znacznik „Teraz” między minionymi a nadchodzącymi, odliczanie przy
//     najbliższym i czerwona plakietka przy przegapionym terminie w sprawie.
//     Bez kolumny godzin — plan tego zakazuje (test `testCalendarHasNoHourColumn`).
//
// Terminy całego widoku są wczytywane jednym zapytaniem, a wybór dnia w obrębie
// wczytanego zakresu nie pyta serwera. Rachuba tygodnia opiera się na `LocalDate`
// (poniedziałek pierwszy), a nie na `Calendar.current` (§2.2).

enum CalendarMode: String, CaseIterable, Hashable {
    case month = "Miesiąc"
    case week = "Tydzień"
    case agenda = "Lista"
}

@MainActor
final class CalendarStore: ObservableObject {

    struct Model {
        var mode: CalendarMode
        var today: LocalDate
        var selectedDay: LocalDate
        /// Pierwszy dzień wyświetlanego miesiąca (widok miesiąca).
        var visibleMonth: LocalDate
        /// Dni siatki (miesiąc: 42, tydzień: 7).
        var days: [LocalDate]
        /// Terminy wybranego dnia.
        var dayEvents: [ScheduledEvent]
        /// Terminy każdego dnia wczytanego zakresu (kropki w siatce, lista).
        var eventsByDay: [LocalDate: [ScheduledEvent]]
        var clientNames: [ClientID: String]
        /// Kafelki nad kalendarzem — niezależne od wyświetlanego zakresu.
        var pulse: Pulse
    }

    /// Puls kalendarza: dziś, najbliższy tydzień i terminy po czasie.
    struct Pulse {
        var today = 0
        var week = 0
        /// Niezakończone terminy w sprawach z ostatnich 30 dni, najstarsze najpierw.
        var missed: [ScheduledEvent] = []

        static func make(_ events: [ScheduledEvent], today: LocalDate) -> Pulse {
            let open = events.filter { $0.status != .finished }
            return Pulse(
                today: open.filter { $0.day == today }.count,
                week: open.filter { $0.day >= today && $0.day <= today.adding(days: 6) }.count,
                missed: open
                    .filter { $0.kind == .caseDeadline && $0.day < today }
                    .sorted { $0.day != $1.day ? $0.day < $1.day : $0.time < $1.time }
            )
        }
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle
    @Published private(set) var mode: CalendarMode = .month
    @Published private(set) var selectedDay: LocalDate = LocalDate(year: 2026, month: 9, day: 11)
    @Published private(set) var visibleMonth: LocalDate = LocalDate(year: 2026, month: 9, day: 1)
    /// Kierunek ostatniej zmiany okresu (+1 dalej, −1 wstecz) — w tę stronę
    /// wjeżdża nowy miesiąc i „przewija się” jego nazwa.
    @Published private(set) var direction: Int = 1

    /// Jednorazowa inicjalizacja (F01): odświeżenie nie cofa wyboru dnia.
    private var didConfigure = false
    private var events: [ScheduledEvent] = []
    private var loadedRange: DateIntervalFilter?
    private var clientNames: [ClientID: String] = [:]
    private var pulse = Pulse()

    /// Horyzont widoku listy.
    static let agendaDays = 60

    func configure(today: LocalDate) {
        guard !didConfigure else { return }
        didConfigure = true
        selectedDay = today
        visibleMonth = today.firstOfMonth
    }

    /// Zakres dat potrzebny bieżącemu widokowi.
    func range(today: LocalDate) -> DateIntervalFilter {
        switch mode {
        case .month:
            let start = visibleMonth.startOfWeekMonday
            return DateIntervalFilter(from: start, through: start.adding(days: 41))
        case .week:
            let start = selectedDay.startOfWeekMonday
            return DateIntervalFilter(from: start, through: start.adding(days: 6))
        case .agenda:
            return DateIntervalFilter(from: today, through: today.adding(days: Self.agendaDays - 1))
        }
    }

    func load(_ dependencies: AppDependencies) async {
        if !phase.hasLoaded { phase = .loading }
        let today = dependencies.today
        configure(today: today)
        let requested = range(today: today)
        let repository = dependencies.repository
        do {
            async let eventsTask = repository.events(in: requested)
            async let clientsTask = repository.clients(matching: "", stage: nil)
            async let pulseTask = repository.events(
                in: DateIntervalFilter(
                    from: today.adding(days: -CaseUrgency.missedLookbackDays),
                    through: today.adding(days: 6)
                )
            )
            let loadedEvents = try await eventsTask
            let clients = try await clientsTask
            // Kafelki nie mogą zablokować kalendarza — bez nich zostaje siatka.
            let pulseEvents = (try? await pulseTask) ?? []
            // W międzyczasie wybrano inny zakres — jego wczytanie ma ostatnie słowo.
            guard requested == range(today: today) else { return }
            events = loadedEvents
            loadedRange = requested
            pulse = Pulse.make(pulseEvents, today: today)
            clientNames = Dictionary(clients.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            rebuild(today: today)
        } catch {
            if let message = phase.recordFailure(error, fallback: "Nie udało się wczytać kalendarza.") {
                dependencies.showToast(message)
            }
        }
    }

    /// Model ekranu z wczytanych danych, bez sieci.
    private func rebuild(today: LocalDate) {
        // Załatwione terminy zostają w kalendarzu (przygaszone, z plakietką).
        // Wcześniej znikały — po „Załatwione” nie dało się już sprawdzić,
        // kiedy była rozprawa. Kafelki i kropka „po terminie” liczą tylko otwarte.
        var byDay: [LocalDate: [ScheduledEvent]] = [:]
        for event in events {
            byDay[event.day, default: []].append(event)
        }
        for day in byDay.keys {
            byDay[day]?.sort { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.time != rhs.time ? lhs.time < rhs.time : lhs.id.rawValue < rhs.id.rawValue
            }
        }
        let days: [LocalDate]
        switch mode {
        case .month:
            let start = visibleMonth.startOfWeekMonday
            days = (0..<42).map { start.adding(days: $0) }
        case .week:
            let start = selectedDay.startOfWeekMonday
            days = (0..<7).map { start.adding(days: $0) }
        case .agenda:
            days = []
        }
        phase = .loaded(
            Model(
                mode: mode,
                today: today,
                selectedDay: selectedDay,
                visibleMonth: visibleMonth,
                days: days,
                dayEvents: byDay[selectedDay] ?? [],
                eventsByDay: byDay,
                clientNames: clientNames,
                pulse: pulse
            )
        )
    }

    private func isLoaded(_ day: LocalDate) -> Bool {
        loadedRange?.contains(day) == true && phase.hasLoaded
    }

    func setMode(_ newMode: CalendarMode, dependencies: AppDependencies) async {
        guard newMode != mode else { return }
        mode = newMode
        if newMode == .month { visibleMonth = selectedDay.firstOfMonth }
        await load(dependencies)
    }

    /// Wybór dnia. W obrębie wczytanego zakresu — natychmiast; dzień spoza
    /// zakresu przestawia widok na jego miesiąc albo tydzień.
    func select(_ day: LocalDate, dependencies: AppDependencies) async {
        configure(today: dependencies.today)
        if day != selectedDay { direction = day > selectedDay ? 1 : -1 }
        selectedDay = day
        if mode == .agenda { mode = .month }
        if mode == .month, day.firstOfMonth != visibleMonth {
            visibleMonth = day.firstOfMonth
            await load(dependencies)
            return
        }
        if isLoaded(day) && (mode != .week || loadedRange?.from == day.startOfWeekMonday) {
            rebuild(today: dependencies.today)
        } else {
            await load(dependencies)
        }
    }

    /// Poprzedni/następny miesiąc albo tydzień.
    func shift(by step: Int, dependencies: AppDependencies) async {
        direction = step >= 0 ? 1 : -1
        switch mode {
        case .month:
            visibleMonth = visibleMonth.addingMonths(step)
            // Wybrany dzień idzie za miesiącem: dziś, gdy to bieżący miesiąc,
            // inaczej ten sam dzień miesiąca.
            let today = dependencies.today
            selectedDay = visibleMonth == today.firstOfMonth ? today : selectedDay.addingMonths(step)
        case .week:
            selectedDay = selectedDay.adding(days: 7 * step)
        case .agenda:
            return
        }
        await load(dependencies)
    }

    func backToToday(_ dependencies: AppDependencies) async {
        let today = dependencies.today
        direction = today >= selectedDay ? 1 : -1
        selectedDay = today
        visibleMonth = today.firstOfMonth
        await load(dependencies)
    }

    /// Formularz nowego terminu **zawsze** dziedziczy wybrany dzień (F10).
    var newEventRoute: AppSheet {
        .eventForm(editing: nil, clientID: nil, caseID: nil, initialDay: selectedDay)
    }
}

struct CalendarScreen: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout: EmmaLayoutMetrics
    /// Magazyn żyje w `AppDependencies`: widok, miesiąc i wybrany dzień
    /// przetrwają przejście na inną zakładkę.
    @ObservedObject var store: CalendarStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 14)

                if case .loaded(let model) = store.phase {
                    pulseTiles(model.pulse)
                        .padding(.bottom, 14)
                }

                SegmentedFilter(
                    items: CalendarMode.allCases,
                    selection: Binding(
                        get: { store.mode },
                        set: { newMode in Task { await store.setMode(newMode, dependencies: dependencies) } }
                    ),
                    title: { $0.rawValue }
                )
                .padding(.bottom, 12)

                if store.mode != .agenda {
                    navigationControls
                        .padding(.bottom, 10)
                }

                switch store.phase {
                case .idle, .loading:
                    LoadingState("Wczytuję plan…")
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
    }

    // MARK: Nagłówek

    /// Sam tytuł i „+” — jak „Klienci” i „Rozmowy”. Miesiąc jest w pasku nawigacji.
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Kalendarz")
                .font(EmmaTypography.welcome)
                .tracking(-0.9)
                .foregroundStyle(EmmaTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(systemName: "plus", accessibilityLabel: "Dodaj termin") {
                dependencies.present(store.newEventRoute)
            }
        }
    }

    // MARK: Kafelki

    private func pulseTiles(_ pulse: CalendarStore.Pulse) -> some View {
        HStack(spacing: 8) {
            PulseTile(
                value: pulse.today,
                label: EmmaPlural.form(pulse.today, "termin dziś", "terminy dziś", "terminów dziś"),
                systemImage: "sun.max",
                tone: EmmaTheme.accent
            ) {
                Task { await store.select(dependencies.today, dependencies: dependencies) }
            }
            PulseTile(
                value: pulse.week,
                label: EmmaPlural.form(pulse.week, "termin w 7 dni", "terminy w 7 dni", "terminów w 7 dni"),
                systemImage: "calendar",
                tone: EmmaTheme.accent
            ) {
                Task { await store.setMode(.agenda, dependencies: dependencies) }
            }
            PulseTile(
                value: pulse.missed.count,
                label: "po terminie",
                systemImage: "exclamationmark.triangle",
                tone: pulse.missed.isEmpty ? EmmaTheme.accent : EmmaTheme.pillDangerText
            ) {
                // Najstarszy przegapiony termin — tam jest „Załatwione”.
                let day = pulse.missed.first?.day ?? dependencies.today
                Task { await store.select(day, dependencies: dependencies) }
            }
        }
    }

    // MARK: Widoki

    @ViewBuilder
    private func loaded(_ model: CalendarStore.Model) -> some View {
        switch model.mode {
        case .month:
            ZStack {
                MonthGrid(model: model, onAdd: addEvent) { day in
                    Task { await store.select(day, dependencies: dependencies) }
                }
                .id(model.visibleMonth)
                .transition(periodTransition)
            }
            .animation(EmmaMotion.smooth, value: model.visibleMonth)
            .simultaneousGesture(swipe)
            dotsLegend
                .padding(.top, 9)
                .padding(.bottom, 2)
            dayAgenda(model)
        case .week:
            ZStack {
                weekStrip(model)
                    .id(model.days.first)
                    .transition(periodTransition)
            }
            .animation(EmmaMotion.smooth, value: model.days.first)
            .simultaneousGesture(swipe)
            dotsLegend
                .padding(.top, 9)
                .padding(.bottom, 2)
            dayAgenda(model)
        case .agenda:
            agendaList(model)
        }
    }

    /// Nowy okres wjeżdża od strony gestu, stary gaśnie w miejscu.
    private var periodTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: store.direction >= 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .opacity
        )
    }

    // MARK: Nawigacja

    /// „Wrzesień 2026” po lewej, „Dzisiaj” tylko wtedy, gdy jesteśmy gdzie
    /// indziej, strzałki po prawej — jeden rząd zamiast dwóch.
    private var navigationControls: some View {
        HStack(spacing: 8) {
            Text(periodTitle)
                .font(EmmaTypography.heading(19))
                .tracking(-0.4)
                .foregroundStyle(EmmaTheme.ink)
                .contentTransition(.numericText(countsDown: store.direction < 0))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if !showsToday {
                Button {
                    EmmaHaptics.selection()
                    Task { await store.backToToday(dependencies) }
                } label: {
                    Text("Dzisiaj")
                        .font(EmmaTypography.caption(.semibold))
                        .foregroundStyle(EmmaTheme.weekControlText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(EmmaTheme.weekControlBackground, in: Capsule())
                        .frame(minHeight: EmmaSpacing.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .accessibilityLabel("Wróć do dzisiaj")
            }

            IconButton(
                systemName: "chevron.left",
                accessibilityLabel: store.mode == .month ? "Poprzedni miesiąc" : "Poprzedni tydzień"
            ) {
                EmmaHaptics.selection()
                Task { await store.shift(by: -1, dependencies: dependencies) }
            }
            IconButton(
                systemName: "chevron.right",
                accessibilityLabel: store.mode == .month ? "Następny miesiąc" : "Następny tydzień"
            ) {
                EmmaHaptics.selection()
                Task { await store.shift(by: 1, dependencies: dependencies) }
            }
        }
        .animation(EmmaMotion.snappy, value: periodTitle)
        .animation(EmmaMotion.snappy, value: showsToday)
    }

    private var periodTitle: String {
        switch store.mode {
        case .month: return dependencies.dateText.monthTitle(for: store.visibleMonth)
        case .week: return dependencies.dateText.monthTitle(for: store.selectedDay)
        case .agenda: return ""
        }
    }

    /// Czy widać dzisiejszy dzień z zaznaczeniem na nim.
    private var showsToday: Bool {
        let today = dependencies.today
        guard store.selectedDay == today else { return false }
        return store.mode != .month || store.visibleMonth == today.firstOfMonth
    }

    /// Wyraźnie poziomy ruch zmienia miesiąc/tydzień — nie łapie przewijania.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > 60, abs(horizontal) > abs(value.translation.height) * 1.5 else { return }
                EmmaHaptics.selection()
                Task { await store.shift(by: horizontal < 0 ? 1 : -1, dependencies: dependencies) }
            }
    }

    /// Co znaczą kolory kropek — bez zgadywania.
    private var dotsLegend: some View {
        HStack(spacing: 14) {
            legendItem(EmmaTheme.accent, "Konsultacja")
            legendItem(EmmaTheme.pillAmberText, "W sprawie")
            legendItem(EmmaTheme.pillDangerText, "Po terminie")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }

    private func legendItem(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.mutedSoft)
                .lineLimit(1)
        }
    }

    // MARK: Dzień

    @ViewBuilder
    private func dayAgenda(_ model: CalendarStore.Model) -> some View {
        SectionHeader(daySectionTitle(model), actionTitle: "Dodaj", compact: true) {
            dependencies.present(store.newEventRoute)
        }
        Group {
            if model.dayEvents.isEmpty {
                freeDay
                    .emmaAppear()
            } else {
                dayTimeline(model)
            }
        }
        // Nowy dzień — karty wchodzą od nowa, kaskadowo.
        .id(model.selectedDay)
        .transition(.opacity)
    }

    private var freeDay: some View {
        Button {
            dependencies.present(store.newEventRoute)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 20))
                    .foregroundStyle(EmmaTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(EmmaTheme.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wolny dzień")
                        .font(EmmaTypography.ui(14, .semibold))
                        .foregroundStyle(EmmaTheme.ink)
                    Text("Dotknij, aby dodać termin na ten dzień.")
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(15)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(EmmaCardButtonStyle())
    }

    /// Oś dnia: kropka w kolorze rodzaju, linia łącząca terminy, „Teraz”
    /// między minionymi a nadchodzącymi (tylko dziś).
    private func dayTimeline(_ model: CalendarStore.Model) -> some View {
        let now = TimeOfDay.at(dependencies.clock.now())
        let isToday = model.selectedDay == model.today
        let events = model.dayEvents
        let upcoming = events.first(where: { !$0.isAllDay && !$0.hasPassed(at: now) })
        let nextID: EventID? = isToday ? upcoming?.id : nil
        let allPassed = isToday && nextID == nil && events.contains { !$0.isAllDay }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                if event.id == nextID {
                    nowMarker(now)
                }
                timelineRow(
                    event,
                    model: model,
                    now: now,
                    isNext: event.id == nextID,
                    isFirst: index == 0,
                    isLast: index == events.count - 1
                )
                .emmaAppear(index)
            }
            if allPassed {
                nowMarker(now)
            }
        }
    }

    private func timelineRow(
        _ event: ScheduledEvent,
        model: CalendarStore.Model,
        now: TimeOfDay,
        isNext: Bool,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        let isFinished = event.status == .finished
        let isMissed = !isFinished && event.kind == .caseDeadline && event.day < model.today
        let isPast = !isMissed && (
            isFinished
                || event.day < model.today
                || (event.day == model.today && !event.isAllDay && event.hasPassed(at: now))
        )
        let tone = isFinished ? EmmaTheme.pillGreenText
            : isMissed ? EmmaTheme.pillDangerText
            : (event.kind == .caseDeadline ? EmmaTheme.pillAmberText : EmmaTheme.accent)

        return MeetingCard(event: event, clientName: event.clientID.flatMap { model.clientNames[$0] }) {
            dependencies.present(.eventDetail(event.id))
        }
        .overlay(alignment: .topTrailing) {
            timelineBadge(event, model: model, now: now, isMissed: isMissed, isNext: isNext)
                .padding(10)
        }
        .eventContextMenu(event, dependencies: dependencies) {
            dependencies.present(.eventDetail(event.id))
        }
        .opacity(isPast ? 0.6 : 1)
        .padding(.leading, 26)
        .padding(.bottom, EmmaSpacing.cardGap)
        .background(alignment: .topLeading) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : EmmaTheme.border)
                    .frame(width: 2, height: 15)
                ZStack {
                    if isNext {
                        Circle()
                            .fill(tone.opacity(0.16))
                            .frame(width: 20, height: 20)
                    }
                    Circle()
                        .fill(isPast ? EmmaTheme.bg : tone)
                        .frame(width: 10, height: 10)
                        .overlay { Circle().strokeBorder(tone, lineWidth: 2) }
                }
                .frame(width: 20, height: 20)
                Rectangle()
                    .fill(isLast ? Color.clear : EmmaTheme.border)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 20)
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityHidden(true)
        }
    }

    /// Plakietka w rogu karty: „Minął 2 dni temu” albo „za 45 min” przy najbliższym.
    @ViewBuilder
    private func timelineBadge(
        _ event: ScheduledEvent,
        model: CalendarStore.Model,
        now: TimeOfDay,
        isMissed: Bool,
        isNext: Bool
    ) -> some View {
        if event.status == .finished {
            StatusPill("Załatwione", kind: .green)
        } else if isMissed {
            let urgency = CaseUrgency(nextEvent: nil, missedEvent: event.day, overdueTasks: 0, today: model.today)
            if let text = urgency.countdownText {
                StatusPill(text.prefix(1).uppercased() + text.dropFirst(), kind: .danger)
            }
        } else if isNext {
            // „za 45 min” / „teraz” — odświeżane co minutę.
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                if let countdown = event.countdownText(now: TimeOfDay.at(dependencies.clock.now()), today: model.today) {
                    StatusPill(countdown, kind: countdown == "teraz" ? .green : .neutral)
                }
            }
        }
    }

    private func nowMarker(_ now: TimeOfDay) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(EmmaTheme.accent)
                .frame(width: 8, height: 8)
                .frame(width: 20)
            Text("Teraz · \(now.hhmm)")
                .font(EmmaTypography.caption(.semibold))
                .foregroundStyle(EmmaTheme.accent)
                .fixedSize()
            Rectangle()
                .fill(EmmaTheme.accent.opacity(0.35))
                .frame(height: 1)
        }
        .padding(.bottom, EmmaSpacing.cardGap)
        .accessibilityElement(children: .combine)
    }

    /// „Dzisiaj, 24 września · 3”.
    private func daySectionTitle(_ model: CalendarStore.Model) -> String {
        let label = dependencies.dateText.dayTitle(model.selectedDay)
        guard !model.dayEvents.isEmpty else { return label }
        return "\(label) · \(model.dayEvents.count)"
    }

    // MARK: Tydzień

    private func weekStrip(_ model: CalendarStore.Model) -> some View {
        WeekStrip(model: model, onAdd: addEvent) { day in
            Task { await store.select(day, dependencies: dependencies) }
        }
    }

    /// Nowy termin na konkretny dzień — z przytrzymania dnia w siatce,
    /// bez wybierania go najpierw i szukania „+”.
    private func addEvent(on day: LocalDate) {
        EmmaHaptics.tap()
        dependencies.present(.eventForm(editing: nil, clientID: nil, caseID: nil, initialDay: day))
    }

    // MARK: Lista

    @ViewBuilder
    private func agendaList(_ model: CalendarStore.Model) -> some View {
        let days = model.eventsByDay.keys.filter { $0 >= model.today }.sorted()
        // Lista pokazywała tylko przyszłość — przegapiony termin w sprawie był
        // widoczny wyłącznie w kafelku. Teraz stoi na samej górze, z „Załatwione”
        // pod przytrzymaniem.
        if !model.pulse.missed.isEmpty {
            missedSection(model)
        }
        if days.isEmpty {
            EmptyState(
                systemImage: "calendar",
                title: "Brak terminów",
                message: "W najbliższych \(CalendarStore.agendaDays) dniach nie ma zaplanowanych terminów."
            )
        } else {
            let firstIndex = Dictionary(
                uniqueKeysWithValues: days.enumerated().map { ($0.element, $0.offset) }
            )
            ForEach(days, id: \.self) { day in
                let events = model.eventsByDay[day] ?? []
                agendaDayHeader(day, count: events.count, today: model.today)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                    .emmaAppear(firstIndex[day] ?? 0)
                ForEach(events, id: \.id) { event in
                    MeetingCard(event: event, clientName: event.clientID.flatMap { model.clientNames[$0] }) {
                        dependencies.present(.eventDetail(event.id))
                    }
                    .eventContextMenu(event, dependencies: dependencies) {
                        dependencies.present(.eventDetail(event.id))
                    }
                    .padding(.bottom, EmmaSpacing.cardGap)
                    .emmaAppear(firstIndex[day] ?? 0)
                }
            }
        }
    }

    @ViewBuilder
    private func missedSection(_ model: CalendarStore.Model) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
            Text("Po terminie · \(model.pulse.missed.count)")
                .font(EmmaTypography.ui(15, .semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(EmmaTheme.pillDangerText)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .emmaAppear(0)

        ForEach(Array(model.pulse.missed.enumerated()), id: \.element.id) { index, event in
            MeetingCard(event: event, clientName: event.clientID.flatMap { model.clientNames[$0] }) {
                dependencies.present(.eventDetail(event.id))
            }
            .overlay(alignment: .topTrailing) {
                let urgency = CaseUrgency(nextEvent: nil, missedEvent: event.day, overdueTasks: 0, today: model.today)
                if let text = urgency.countdownText {
                    StatusPill(text.prefix(1).uppercased() + text.dropFirst(), kind: .danger)
                        .padding(10)
                }
            }
            .eventContextMenu(event, dependencies: dependencies) {
                dependencies.present(.eventDetail(event.id))
            }
            .padding(.bottom, EmmaSpacing.cardGap)
            .emmaAppear(index + 1)
        }
    }

    /// Dzień na liście: kafelek z datą (dziś — wypełniony) i „za 3 dni · 2 terminy”.
    private func agendaDayHeader(_ day: LocalDate, count: Int, today: LocalDate) -> some View {
        let isToday = day == today
        let distance = today.days(until: day)
        let relative: String
        switch distance {
        case 0: relative = "dziś"
        case 1: relative = "jutro"
        default: relative = "za \(EmmaPlural.days(distance))"
        }
        return HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(dependencies.dateText.weekdayShort(for: day).uppercased())
                    .font(EmmaTypography.caption(.semibold))
                    .foregroundStyle(isToday ? EmmaTheme.daySelectedLabel : EmmaTheme.mutedSoft)
                Text("\(day.day)")
                    .font(EmmaTypography.heading(18))
                    .foregroundStyle(isToday ? EmmaTheme.daySelectedNumber : EmmaTheme.ink)
            }
            .frame(width: 46, height: 50)
            .background(isToday ? EmmaTheme.daySelected : EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                if !isToday {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(dependencies.dateText.dayTitle(day))
                    .font(EmmaTypography.ui(15, .semibold))
                    .foregroundStyle(EmmaTheme.ink)
                Text("\(relative) · \(EmmaPlural.label(count, "termin", "terminy", "terminów"))")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(isToday ? EmmaTheme.accent : EmmaTheme.mutedSoft)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Pasek tygodnia

/// Siedem dni z kropkami; wybrany dzień to przesuwana ciemna pigułka.
private struct WeekStrip: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Namespace private var selectionSpace

    let model: CalendarStore.Model
    let onAdd: (LocalDate) -> Void
    let onSelect: (LocalDate) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.days, id: \.self) { day in
                cell(day)
            }
        }
        .animation(EmmaMotion.snappy, value: model.selectedDay)
    }

    private func cell(_ day: LocalDate) -> some View {
        let isSelected = day == model.selectedDay
        let count = model.eventsByDay[day]?.count ?? 0
        return Button {
            if !isSelected { EmmaHaptics.selection() }
            onSelect(day)
        } label: {
            VStack(spacing: 5) {
                Text(dependencies.dateText.weekdayShort(for: day))
                    .font(EmmaTypography.caption(.medium))
                    .foregroundStyle(isSelected ? EmmaTheme.daySelectedLabel : EmmaTheme.mutedSoft)
                Text("\(day.day)")
                    .font(EmmaTypography.heading(16))
                    .foregroundStyle(isSelected ? EmmaTheme.daySelectedNumber : EmmaTheme.ink)
                EventDots(events: model.eventsByDay[day] ?? [], today: model.today, highlighted: isSelected)
            }
            .frame(maxWidth: .infinity, minHeight: EmmaMetrics.dayCellMinHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: EmmaRadii.dayCell, style: .continuous)
                        .fill(EmmaTheme.daySelected)
                        .matchedGeometryEffect(id: "week-selection", in: selectionSpace)
                } else {
                    RoundedRectangle(cornerRadius: EmmaRadii.dayCell, style: .continuous)
                        .fill(EmmaTheme.surface)
                }
            }
            .overlay {
                if !isSelected && day == model.today {
                    RoundedRectangle(cornerRadius: EmmaRadii.dayCell, style: .continuous)
                        .strokeBorder(EmmaTheme.dayTodayDot, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onAdd(day)
            } label: {
                Label("Nowy termin tego dnia", systemImage: "calendar.badge.plus")
            }
        }
        .accessibilityLabel("\(dependencies.dateText.dayTitle(day)), \(EmmaPlural.events(count))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: "Nowy termin tego dnia") { onAdd(day) }
    }
}

// MARK: - Siatka miesiąca

/// Siatka 6×7: numer dnia, kropki terminów, dziś w obwódce, wybrany dzień
/// wypełniony (pigułka przesuwa się między dniami). Dni spoza miesiąca są
/// przygaszone, ale klikalne.
private struct MonthGrid: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Namespace private var selectionSpace

    let model: CalendarStore.Model
    let onAdd: (LocalDate) -> Void
    let onSelect: (LocalDate) -> Void

    private let weekdays = ["Pn", "Wt", "Śr", "Cz", "Pt", "So", "Nd"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(weekdays, id: \.self) { name in
                    Text(name)
                        .font(EmmaTypography.caption(.medium))
                        .foregroundStyle(name == "So" || name == "Nd" ? EmmaTheme.mutedSoft.opacity(0.7) : EmmaTheme.mutedSoft)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(model.days, id: \.self) { day in
                    cell(day)
                }
            }
            .animation(EmmaMotion.snappy, value: model.selectedDay)
        }
        .padding(8)
        .background(EmmaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
        }
        .emmaCardShadow()
    }

    private func cell(_ day: LocalDate) -> some View {
        let isSelected = day == model.selectedDay
        let isToday = day == model.today
        let inMonth = day.month == model.visibleMonth.month && day.year == model.visibleMonth.year
        let count = model.eventsByDay[day]?.count ?? 0
        return Button {
            if !isSelected { EmmaHaptics.selection() }
            onSelect(day)
        } label: {
            VStack(spacing: 3) {
                Text("\(day.day)")
                    .font(EmmaTypography.ui(15, isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(
                        isSelected ? EmmaTheme.daySelectedNumber
                            : (inMonth ? (isToday ? EmmaTheme.accent : EmmaTheme.ink) : EmmaTheme.mutedSoft.opacity(0.55))
                    )
                EventDots(events: model.eventsByDay[day] ?? [], today: model.today, highlighted: isSelected)
                    .opacity(inMonth ? 1 : 0.5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(EmmaTheme.daySelected)
                        .matchedGeometryEffect(id: "month-selection", in: selectionSpace)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(EmmaTheme.accent, lineWidth: 1.2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onAdd(day)
            } label: {
                Label("Nowy termin tego dnia", systemImage: "calendar.badge.plus")
            }
        }
        .accessibilityLabel("\(dependencies.dateText.dayTitle(day)), \(EmmaPlural.events(count))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: "Nowy termin tego dnia") { onAdd(day) }
    }
}

/// Kropki terminów dnia: do trzech kropek, powyżej — liczba.
///
/// Audyt 28.09.2026: konsultacja i rozprawa wyglądały w siatce tak samo.
/// Termin w sprawie ma kropkę bursztynową, a niezamknięty termin w sprawie,
/// który już minął — czerwoną. Konsultacje zostają niebieskie.
private struct EventDots: View {
    let events: [ScheduledEvent]
    let today: LocalDate
    let highlighted: Bool

    /// 0 — po terminie, 1 — termin w sprawie, 2 — konsultacja, 3 — załatwione;
    /// najważniejsze najpierw.
    private var ranks: [Int] {
        events.map { event in
            if event.status == .finished { return 3 }
            guard event.kind == .caseDeadline else { return 2 }
            return event.status != .finished && event.day < today ? 0 : 1
        }
        .sorted()
    }

    private func color(_ rank: Int) -> Color {
        switch rank {
        case 0: return EmmaTheme.pillDangerText
        case 1: return EmmaTheme.pillAmberText
        case 2: return EmmaTheme.accent
        default: return EmmaTheme.mutedSoft.opacity(0.6)
        }
    }

    var body: some View {
        let sorted = ranks
        HStack(spacing: 3) {
            if sorted.count > 3 {
                Text("\(sorted.count)")
                    .font(EmmaTypography.caption(.semibold))
                    .foregroundStyle(highlighted ? EmmaTheme.daySelectedNumber : color(sorted.first ?? 2))
            } else {
                ForEach(Array(sorted.enumerated()), id: \.offset) { _, rank in
                    Circle()
                        .fill(highlighted ? EmmaTheme.daySelectedNumber : color(rank))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .frame(height: 8)
    }
}

#Preview("Kalendarz") {
    let dependencies = AppDependencies.demo()
    return CalendarScreen(store: dependencies.calendarStore)
        .environmentObject(dependencies)
}
