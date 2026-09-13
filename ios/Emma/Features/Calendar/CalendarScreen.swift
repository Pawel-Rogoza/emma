import SwiftUI

// MARK: - Ekran „Kalendarz”
//
// Port `calendar()` z referencji. Świadomie **bez kolumny godzin**: referencja
// pokazuje pasek tygodnia z numerami dni i znacznikiem wydarzenia, a poniżej
// listę wydarzeń wybranego dnia w kartach.
//
// Rachuba tygodnia opiera się na typie `LocalDate` (poniedziałek jako pierwszy dzień),
// a nie na `Calendar.current` — prezentacja ma być deterministyczna i niezależna
// od ustawień telefonu (§2.2).

@MainActor
final class CalendarStore: ObservableObject {

    struct Model {
        var weekStart: LocalDate
        var days: [LocalDate]
        var selectedDay: LocalDate
        var today: LocalDate
        var events: [ScheduledEvent]
        var daysWithEvents: Set<LocalDate>
        var clientNames: [ClientID: String]
    }

    @Published private(set) var phase: LoadPhase<Model> = .idle
    @Published private(set) var selectedDay: LocalDate = LocalDate(year: 2026, month: 9, day: 11)
    @Published private(set) var weekStart: LocalDate = LocalDate(year: 2026, month: 9, day: 7)

    /// Jednorazowa inicjalizacja odświeżania (F01). Wcześniej `configure` sprawdzał
    /// `phase.hasLoaded`, ale `load` ustawiał `.loading` **przed** wywołaniem
    /// `configure` — warunek był zawsze fałszywy, więc każde odświeżenie cofało
    /// wybrany dzień i przesunięcie tygodnia do „dzisiaj”.
    private var didConfigure = false

    func configure(today: LocalDate) {
        guard !didConfigure else { return }
        didConfigure = true
        selectedDay = today
        weekStart = today.startOfWeekMonday
    }

    func load(_ dependencies: AppDependencies) async {
        // Odświeżenie nie chowa już wczytanej listy: pasek tygodnia i wydarzenia
        // zostają na ekranie, a wybór dnia nie jest resetowany (F01).
        if !phase.hasLoaded { phase = .loading }
        let today = dependencies.today
        configure(today: today)
        do {
            let days = (0..<7).map { weekStart.adding(days: $0) }
            let range = DateIntervalFilter(from: weekStart, through: weekStart.adding(days: 6))
            let weekEvents = try await dependencies.repository.events(in: range)
            let dayEvents = try await dependencies.repository.events(in: .day(selectedDay))
            let clients = try await dependencies.repository.clients(matching: "", stage: nil)

            // Znacznik „ma wydarzenie” liczymy z całego tygodnia, nie tylko z widocznego dnia.
            var markers: Set<LocalDate> = []
            for event in weekEvents where event.status != .finished {
                markers.insert(event.day)
            }

            phase = .loaded(
                Model(
                    weekStart: weekStart,
                    days: days,
                    selectedDay: selectedDay,
                    today: today,
                    events: dayEvents
                        .filter { $0.status != .finished }
                        .sorted { $0.time < $1.time },
                    daysWithEvents: markers,
                    clientNames: Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0.displayName) })
                )
            )
        } catch {
            phase = .failed(ScreenLoad.failure(for: error, fallback: "Nie udało się wczytać kalendarza."))
        }
    }

    /// Przesunięcie tygodnia razem z wybranym dniem — jak `shiftWeek(n)` w referencji.
    func shiftWeek(by days: Int, dependencies: AppDependencies) async {
        weekStart = weekStart.adding(days: days)
        selectedDay = selectedDay.adding(days: days)
        await load(dependencies)
    }

    func select(_ day: LocalDate, dependencies: AppDependencies) async {
        selectedDay = day
        await load(dependencies)
    }

    func backToToday(_ dependencies: AppDependencies) async {
        let today = dependencies.today
        weekStart = today.startOfWeekMonday
        selectedDay = today
        await load(dependencies)
    }
}

struct CalendarScreen: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout: EmmaLayoutMetrics
    @StateObject private var store = CalendarStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(
                    kicker: "WSPÓLNY PLAN",
                    title: dependencies.dateText.monthTitle(for: store.selectedDay),
                )

                HStack {
                    Spacer(minLength: 0)
                    IconButton(systemName: "plus", accessibilityLabel: "Dodaj termin") {
                        dependencies.present(.eventForm(editing: nil, clientID: nil, caseID: nil, initialDay: nil))
                    }
                }
                .padding(.bottom, 12)

                weekControls
                    .padding(.bottom, 12)

                switch store.phase {
                case .idle, .loading:
                    LoadingState("Wczytuję plan…")
                case .failed(let failure):
                    LoadFailureView(failure) {
                        Task { await store.load(dependencies) }
                    }
                case .loaded(let model):
                    dayStrip(model)
                        .padding(.bottom, 6)

                    SectionHeader(dependencies.dateText.dayLabel(model.selectedDay))
                    if model.events.isEmpty {
                        EmptyState(
                            systemImage: "calendar",
                            title: "Wolny termin",
                            message: "Nie ma wydarzeń w wybranym dniu."
                        )
                        .background(EmmaTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                                .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
                        }
                    } else {
                        ForEach(model.events, id: \.id) { event in
                            MeetingCard(
                                event: event,
                                clientName: model.clientNames[event.clientID] ?? Client.unknownDisplayName
                            ) {
                                dependencies.present(.eventDetail(event.id))
                            }
                            .padding(.bottom, EmmaSpacing.cardGap)
                        }
                    }

                    SecondaryButton("Dodaj termin na ten dzień", systemImage: "plus") {
                        // Wybrany dzień paska tygodnia jest dniem, na który naprawdę
                        // dodajemy termin — formularz dziedziczy go jawnie (F10).
                        dependencies.present(.eventForm(
                            editing: nil,
                            clientID: nil,
                            caseID: nil,
                            initialDay: store.selectedDay
                        ))
                    }
                    .padding(.top, 6)
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

    private var weekControls: some View {
        HStack(spacing: 10) {
            IconButton(systemName: "chevron.left", accessibilityLabel: "Poprzedni tydzień") {
                Task { await store.shiftWeek(by: -7, dependencies: dependencies) }
            }
            Button("Wróć do dzisiaj") {
                Task { await store.backToToday(dependencies) }
            }
            .font(EmmaTypography.caption(.medium))
            .foregroundStyle(EmmaTheme.weekControlText)
            .frame(maxWidth: .infinity, minHeight: EmmaSpacing.hitTarget)
            .background(EmmaTheme.weekControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous))

            IconButton(systemName: "chevron.right", accessibilityLabel: "Następny tydzień") {
                Task { await store.shiftWeek(by: 7, dependencies: dependencies) }
            }
        }
    }

    private func dayStrip(_ model: CalendarStore.Model) -> some View {
        HStack(spacing: 4) {
            ForEach(model.days, id: \.self) { day in
                let isSelected = day == model.selectedDay
                Button {
                    Task { await store.select(day, dependencies: dependencies) }
                } label: {
                    VStack(spacing: 5) {
                        Text(dependencies.dateText.weekdayShort(for: day))
                            .font(EmmaTypography.caption(.medium))
                            .foregroundStyle(isSelected ? EmmaTheme.daySelectedLabel : EmmaTheme.mutedSoft)
                        Text("\(day.day)")
                            .font(EmmaTypography.heading(16))
                            .foregroundStyle(isSelected ? EmmaTheme.daySelectedNumber : EmmaTheme.ink)
                        Circle()
                            .fill(model.daysWithEvents.contains(day)
                                  ? (isSelected ? EmmaTheme.daySelectedNumber : EmmaTheme.accent)
                                  : Color.clear)
                            .frame(width: 5, height: 5)
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
                .accessibilityLabel(
                    "\(dependencies.dateText.weekdayShort(for: day)) \(day.day), \(dependencies.dateText.dayLabel(day))"
                    + (model.daysWithEvents.contains(day) ? ", są wydarzenia" : "")
                )
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

#Preview("Kalendarz") {
    CalendarScreen()
        .environmentObject(AppDependencies.demo())
}
