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

    /// Terminy wczytanego tygodnia i nazwy klientów. Wybór dnia w obrębie
    /// tygodnia liczy się z nich lokalnie — wcześniej każde dotknięcie dnia
    /// wysyłało trzy zapytania (tydzień, dzień i **cała** lista klientów).
    private var weekEvents: [ScheduledEvent] = []
    private var loadedWeekStart: LocalDate?
    private var clientNames: [ClientID: String] = [:]

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
        let requestedWeek = weekStart
        let repository = dependencies.repository
        do {
            let range = DateIntervalFilter(from: requestedWeek, through: requestedWeek.adding(days: 6))
            async let eventsTask = repository.events(in: range)
            async let clientsTask = repository.clients(matching: "", stage: nil)
            let events = try await eventsTask
            let clients = try await clientsTask

            // W międzyczasie wybrano inny tydzień — jego wczytanie jest w drodze
            // i to ono ma ostatnie słowo.
            guard requestedWeek == weekStart else { return }
            weekEvents = events
            loadedWeekStart = requestedWeek
            clientNames = Dictionary(clients.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            rebuild(today: today)
        } catch {
            phase = .failed(ScreenLoad.failure(for: error, fallback: "Nie udało się wczytać kalendarza."))
        }
    }

    /// Model ekranu z danych tygodnia, bez sieci.
    private func rebuild(today: LocalDate) {
        let days = (0..<7).map { weekStart.adding(days: $0) }
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
                events: weekEvents
                    .filter { $0.day == selectedDay && $0.status != .finished }
                    .sorted { $0.time < $1.time },
                daysWithEvents: markers,
                clientNames: clientNames
            )
        )
    }

    /// Przesunięcie tygodnia razem z wybranym dniem — jak `shiftWeek(n)` w referencji.
    func shiftWeek(by days: Int, dependencies: AppDependencies) async {
        weekStart = weekStart.adding(days: days)
        selectedDay = selectedDay.adding(days: days)
        await load(dependencies)
    }

    /// Wybór dnia. W obrębie wczytanego tygodnia — natychmiast, bez zapytań;
    /// dzień z innego tygodnia przestawia pasek na jego tydzień.
    func select(_ day: LocalDate, dependencies: AppDependencies) async {
        selectedDay = day
        if day.startOfWeekMonday == weekStart, loadedWeekStart == weekStart, phase.hasLoaded {
            rebuild(today: dependencies.today)
        } else {
            weekStart = day.startOfWeekMonday
            await load(dependencies)
        }
    }

    /// Trasa formularza nowego terminu. **Zawsze** dziedziczy wybrany dzień (F10):
    /// przycisk w nagłówku i przycisk w sekcji dnia muszą prowadzić do tego samego
    /// dnia, który użytkownik widzi na pasku tygodnia. Wcześniej nagłówek otwierał
    /// formularz z `initialDay: nil`, więc formularz pokazywał „dzisiaj”, ignorując
    /// wybór dnia — mimo że data na ekranie była inna (§8, wiersz 1).
    var newEventRoute: AppSheet {
        .eventForm(editing: nil, clientID: nil, caseID: nil, initialDay: selectedDay)
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
    /// Magazyn żyje w `AppDependencies`: wybrany dzień i tydzień przetrwają
    /// przejście na inną zakładkę.
    @ObservedObject var store: CalendarStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // „+” obok tytułu, jak na liście klientów — wcześniej stał
                // w osobnym wierszu i zabierał wysokość nad paskiem tygodnia.
                HStack(alignment: .top, spacing: 10) {
                    ScreenHeader(
                        kicker: "WSPÓLNY PLAN",
                        title: dependencies.dateText.monthTitle(for: store.selectedDay)
                    )
                    IconButton(systemName: "plus", accessibilityLabel: "Dodaj termin") {
                        dependencies.present(store.newEventRoute)
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
                        // Przesunięcie paska w bok zmienia tydzień — tak jak
                        // w systemowym kalendarzu. Strzałki zostają dla VoiceOver.
                        .simultaneousGesture(weekSwipe)

                    SectionHeader(daySectionTitle(model))
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
                        dependencies.present(store.newEventRoute)
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
        .refreshable { await store.load(dependencies) }
        .task(id: dependencies.dataVersion) { await store.load(dependencies) }
    }

    /// „Dzisiaj · 3 terminy” — liczba mówi od razu, jak wygląda dzień.
    private func daySectionTitle(_ model: CalendarStore.Model) -> String {
        let label = dependencies.dateText.dayLabel(model.selectedDay)
        guard !model.events.isEmpty else { return label }
        let count = model.events.count
        return "\(label) · \(count) \(EmmaPlural.form(count, "termin", "terminy", "terminów"))"
    }

    /// Gest zmiany tygodnia: wyraźnie poziomy ruch, żeby nie łapał przewijania.
    private var weekSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > 60, abs(horizontal) > abs(value.translation.height) * 1.5 else { return }
                EmmaHaptics.selection()
                Task { await store.shiftWeek(by: horizontal < 0 ? 7 : -7, dependencies: dependencies) }
            }
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
                    if day != model.selectedDay {
                        EmmaHaptics.selection()
                    }
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
    let dependencies = AppDependencies.demo()
    return CalendarScreen(store: dependencies.calendarStore)
        .environmentObject(dependencies)
}
