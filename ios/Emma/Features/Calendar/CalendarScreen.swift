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
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle
    @Published private(set) var mode: CalendarMode = .month
    @Published private(set) var selectedDay: LocalDate = LocalDate(year: 2026, month: 9, day: 11)
    @Published private(set) var visibleMonth: LocalDate = LocalDate(year: 2026, month: 9, day: 1)

    /// Jednorazowa inicjalizacja (F01): odświeżenie nie cofa wyboru dnia.
    private var didConfigure = false
    private var events: [ScheduledEvent] = []
    private var loadedRange: DateIntervalFilter?
    private var clientNames: [ClientID: String] = [:]

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
            let loadedEvents = try await eventsTask
            let clients = try await clientsTask
            // W międzyczasie wybrano inny zakres — jego wczytanie ma ostatnie słowo.
            guard requested == range(today: today) else { return }
            events = loadedEvents
            loadedRange = requested
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
        var byDay: [LocalDate: [ScheduledEvent]] = [:]
        for event in events where event.status != .finished {
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
                clientNames: clientNames
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
                HStack(alignment: .top, spacing: 10) {
                    ScreenHeader(kicker: "WSPÓLNY PLAN", title: headerTitle)
                    IconButton(systemName: "plus", accessibilityLabel: "Dodaj termin") {
                        dependencies.present(store.newEventRoute)
                    }
                }
                .padding(.bottom, 12)

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
                        .padding(.bottom, 12)
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

    private var headerTitle: String {
        switch store.mode {
        case .month: return dependencies.dateText.monthTitle(for: store.visibleMonth)
        case .week: return dependencies.dateText.monthTitle(for: store.selectedDay)
        case .agenda: return "Najbliższe terminy"
        }
    }

    @ViewBuilder
    private func loaded(_ model: CalendarStore.Model) -> some View {
        switch model.mode {
        case .month:
            MonthGrid(model: model) { day in
                Task { await store.select(day, dependencies: dependencies) }
            }
            .simultaneousGesture(swipe)
            .padding(.bottom, 6)
            dayAgenda(model)
        case .week:
            weekStrip(model)
                .simultaneousGesture(swipe)
                .padding(.bottom, 6)
            dayAgenda(model)
        case .agenda:
            agendaList(model)
        }
    }

    // MARK: Nawigacja

    private var navigationControls: some View {
        HStack(spacing: 10) {
            IconButton(
                systemName: "chevron.left",
                accessibilityLabel: store.mode == .month ? "Poprzedni miesiąc" : "Poprzedni tydzień"
            ) {
                Task { await store.shift(by: -1, dependencies: dependencies) }
            }
            Button("Dzisiaj") {
                EmmaHaptics.selection()
                Task { await store.backToToday(dependencies) }
            }
            .font(EmmaTypography.caption(.medium))
            .foregroundStyle(EmmaTheme.weekControlText)
            .frame(maxWidth: .infinity, minHeight: EmmaSpacing.hitTarget)
            .background(EmmaTheme.weekControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous))

            IconButton(
                systemName: "chevron.right",
                accessibilityLabel: store.mode == .month ? "Następny miesiąc" : "Następny tydzień"
            ) {
                Task { await store.shift(by: 1, dependencies: dependencies) }
            }
        }
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

    // MARK: Dzień

    @ViewBuilder
    private func dayAgenda(_ model: CalendarStore.Model) -> some View {
        SectionHeader(daySectionTitle(model), actionTitle: "Dodaj", compact: true) {
            dependencies.present(store.newEventRoute)
        }
        if model.dayEvents.isEmpty {
            Button {
                dependencies.present(store.newEventRoute)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 20))
                        .foregroundStyle(EmmaTheme.accent)
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
        } else {
            ForEach(model.dayEvents, id: \.id) { event in
                MeetingCard(event: event, clientName: event.clientID.flatMap { model.clientNames[$0] }) {
                    dependencies.present(.eventDetail(event.id))
                }
                .eventContextMenu(event, dependencies: dependencies) {
                    dependencies.present(.eventDetail(event.id))
                }
                .padding(.bottom, EmmaSpacing.cardGap)
            }
        }
    }

    /// „Dzisiaj, 24 września · 3 terminy”.
    private func daySectionTitle(_ model: CalendarStore.Model) -> String {
        let label = dependencies.dateText.dayTitle(model.selectedDay)
        guard !model.dayEvents.isEmpty else { return label }
        return "\(label) · \(model.dayEvents.count)"
    }

    // MARK: Tydzień

    private func weekStrip(_ model: CalendarStore.Model) -> some View {
        HStack(spacing: 4) {
            ForEach(model.days, id: \.self) { day in
                let isSelected = day == model.selectedDay
                let count = model.eventsByDay[day]?.count ?? 0
                Button {
                    if day != model.selectedDay { EmmaHaptics.selection() }
                    Task { await store.select(day, dependencies: dependencies) }
                } label: {
                    VStack(spacing: 5) {
                        Text(dependencies.dateText.weekdayShort(for: day))
                            .font(EmmaTypography.caption(.medium))
                            .foregroundStyle(isSelected ? EmmaTheme.daySelectedLabel : EmmaTheme.mutedSoft)
                        Text("\(day.day)")
                            .font(EmmaTypography.heading(16))
                            .foregroundStyle(isSelected ? EmmaTheme.daySelectedNumber : EmmaTheme.ink)
                        EventDots(count: count, highlighted: isSelected)
                    }
                    .frame(maxWidth: .infinity, minHeight: EmmaMetrics.dayCellMinHeight)
                    .background(isSelected ? EmmaTheme.daySelected : EmmaTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.dayCell, style: .continuous))
                    .overlay {
                        if !isSelected && day == model.today {
                            RoundedRectangle(cornerRadius: EmmaRadii.dayCell, style: .continuous)
                                .strokeBorder(EmmaTheme.dayTodayDot, lineWidth: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(dependencies.dateText.dayTitle(day)), \(EmmaPlural.events(count))")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    // MARK: Lista

    @ViewBuilder
    private func agendaList(_ model: CalendarStore.Model) -> some View {
        let days = model.eventsByDay.keys.filter { $0 >= model.today }.sorted()
        if days.isEmpty {
            EmptyState(
                systemImage: "calendar",
                title: "Brak terminów",
                message: "W najbliższych \(CalendarStore.agendaDays) dniach nie ma zaplanowanych terminów."
            )
        } else {
            ForEach(days, id: \.self) { day in
                let events = model.eventsByDay[day] ?? []
                Text(dependencies.dateText.dayTitle(day).uppercased())
                    .font(EmmaTypography.caption(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(day == model.today ? EmmaTheme.accent : EmmaTheme.mutedSoft)
                    .padding(.top, 14)
                    .padding(.bottom, 7)
                    .accessibilityAddTraits(.isHeader)
                ForEach(events, id: \.id) { event in
                    MeetingCard(event: event, clientName: event.clientID.flatMap { model.clientNames[$0] }) {
                        dependencies.present(.eventDetail(event.id))
                    }
                    .eventContextMenu(event, dependencies: dependencies) {
                        dependencies.present(.eventDetail(event.id))
                    }
                    .padding(.bottom, EmmaSpacing.cardGap)
                }
            }
        }
    }
}

// MARK: - Siatka miesiąca

/// Siatka 6×7: numer dnia, kropki terminów, dziś w obwódce, wybrany dzień
/// wypełniony. Dni spoza miesiąca są przygaszone, ale klikalne.
private struct MonthGrid: View {
    @EnvironmentObject private var dependencies: AppDependencies

    let model: CalendarStore.Model
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
                EventDots(count: count, highlighted: isSelected)
                    .opacity(inMonth ? 1 : 0.5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(EmmaTheme.daySelected)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(EmmaTheme.accent, lineWidth: 1.2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dependencies.dateText.dayTitle(day)), \(EmmaPlural.events(count))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Kropki terminów dnia: do trzech kropek, powyżej — liczba.
private struct EventDots: View {
    let count: Int
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 3) {
            if count > 3 {
                Text("\(count)")
                    .font(EmmaTypography.caption(.semibold))
                    .foregroundStyle(highlighted ? EmmaTheme.daySelectedNumber : EmmaTheme.accent)
            } else {
                ForEach(0..<count, id: \.self) { _ in
                    Circle()
                        .fill(highlighted ? EmmaTheme.daySelectedNumber : EmmaTheme.accent)
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
