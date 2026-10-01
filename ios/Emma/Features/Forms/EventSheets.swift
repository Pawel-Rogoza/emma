import SwiftUI

// MARK: - Termin: formularz i szczegóły
//
// Review 24.09.2026: „dodawanie terminów nie działa + formularz brzydko
// wygląda, czas trwania jest bez sensu, status też — to ma być w celu dodania
// terminu i później powiadomień / pamiętania o nim”.
//
// Co się zmieniło:
//   • formularz pyta o to, co potrzebne do pamiętania o terminie: co, kiedy,
//     z kim (opcjonalnie), gdzie (opcjonalnie) i **kiedy przypomnieć**,
//   • data i godzina mają systemowe kontrolki i skróty („Jutro”, „Za tydzień”),
//   • czas trwania i status zniknęły z formularza (CRM ich nie używa do niczego,
//     co widać w aplikacji); zapis zachowuje istniejące wartości,
//   • klient jest opcjonalny — termin kancelarii (rozprawa, spotkanie) też jest
//     terminem; miejsce nie jest już wymagane,
//   • błąd zapisu pokazuje się **w formularzu** — wcześniej lądował pod arkuszem
//     i przycisk „Dodaj termin” wyglądał, jakby nie działał,
//   • termin umówiony ze zgłoszeniem „do obsługi” przenosi je do „W kontakcie”.

struct EventFormSheet: View {

    let eventID: EventID?
    let clientID: ClientID?
    let caseID: CaseID?
    /// Dzień, na który otwarto formularz (np. wybrany w kalendarzu). `nil` —
    /// dzień bieżący aplikacji.
    let initialDay: LocalDate?

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var title = ""
    @State private var kind: EventKind = .consultation
    @State private var start = Date()
    @State private var selectedClient: ClientID?
    @State private var place = ""
    @State private var reminder: ReminderOffset = .standard
    @State private var clients: [Client] = []
    @State private var original: ScheduledEvent?
    @State private var error: String?
    @State private var loadError: String?
    @State private var isSaving = false
    @State private var loaded = false
    @State private var remindersDenied = false
    @State private var confirmsDelete = false
    /// Czy użytkownik sam zmienił nazwę — wtedy wybór klienta jej nie nadpisuje.
    @State private var titleEdited = false
    /// Kalkulator terminu procesowego: czynność i dzień, od którego biegnie termin.
    @State private var deadlineRule: DeadlineRule?
    @State private var deadlineFrom = Date()
    /// Czynności w kolejności dla etapu sprawy (najpierw te, które na nim biegną).
    @State private var deadlineRules: [DeadlineRule] = ProceduralDeadlines.common
    /// Czynność z ziarna formularza — wybierana po wczytaniu listy dla sprawy.
    @State private var pendingRuleID: String?

    private static let placeSuggestions = ["Kancelaria", "Online", "Telefonicznie", "Sąd"]

    var body: some View {
        SheetScaffold(title: eventID == nil ? "Nowy termin" : "Edytuj termin", onClose: { dependencies.dismissSheet() }) {
            if let loadError {
                InlineError(loadError)
            }

            whatSection
            if kind == .caseDeadline {
                deadlineSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            whenSection
            whoSection
            whereSection
            reminderSection

            if let error {
                InlineError(error)
                    .padding(.top, 12)
            }

            PrimaryButton(
                eventID == nil ? "Dodaj termin" : "Zapisz zmiany",
                systemImage: "checkmark",
                isEnabled: eventID == nil || original != nil,
                isLoading: isSaving
            ) {
                Task { await save() }
            }
            .padding(.top, 20)
            .accessibilityIdentifier("event-save")

            if original != nil {
                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    Text("Usuń termin")
                        .font(EmmaTypography.ui(15, .medium))
                        .foregroundStyle(EmmaTheme.danger)
                        .frame(maxWidth: .infinity, minHeight: EmmaSpacing.hitTarget)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .environment(\.timeZone, FirmDateTime.timeZone)
        .environment(\.locale, Locale(identifier: "pl_PL"))
        .task { await prepare() }
        .confirmationDialog("Usunąć termin?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Usuń termin", role: .destructive) { Task { await delete() } }
            Button("Wróć", role: .cancel) {}
        } message: {
            Text("Termin zniknie z kalendarza kancelarii razem z przypomnieniem.")
        }
    }

    // MARK: Sekcje

    private var whatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Nazwa, np. Konsultacja", text: Binding(
                get: { title },
                set: { title = $0; titleEdited = true }
            ))
            .font(EmmaTypography.heading(20))
            .foregroundStyle(EmmaTheme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .accessibilityLabel("Nazwa terminu")
            .accessibilityIdentifier("event-title")

            HStack(spacing: 8) {
                kindChip(.consultation, systemImage: "person.2")
                kindChip(.caseDeadline, systemImage: "building.columns")
            }
            .animation(EmmaMotion.snappy, value: kind)
        }
    }

    private func kindChip(_ candidate: EventKind, systemImage: String) -> some View {
        let isSelected = kind == candidate
        return Button {
            EmmaHaptics.selection()
            if !titleEdited || title == defaultTitle(for: kind) {
                title = defaultTitle(for: candidate)
                titleEdited = false
            }
            // Sekcja „Policz termin” wjeżdża płynnie przy „Termin w sprawie”.
            withAnimation(EmmaMotion.smooth) { kind = candidate }
        } label: {
            Label(candidate.displayTitle, systemImage: systemImage)
                .font(EmmaTypography.ui(14, isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? EmmaTheme.primaryButtonText : EmmaTheme.secondaryButtonText)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(isSelected ? EmmaTheme.primaryButton : EmmaTheme.secondaryButton)
                .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormSectionLabel("Kiedy")
            FormCard {
                FormRow(systemImage: "calendar", title: "Data") {
                    DatePicker("Data", selection: $start, displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityIdentifier("event-date")
                }
                FormDivider()
                FormRow(systemImage: "clock", title: "Godzina") {
                    DatePicker("Godzina", selection: $start, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityIdentifier("event-time")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    dayChip("Dziś", offset: 0)
                    dayChip("Jutro", offset: 1)
                    dayChip("Pojutrze", offset: 2)
                    dayChip("Za tydzień", offset: 7)
                }
                .padding(.horizontal, 2)
            }
            .padding(.top, 4)
        }
    }

    // MARK: Termin procesowy

    /// „Apelacja — 14 dni od doręczenia wyroku” → data terminu policzona sama,
    /// z przesunięciem z soboty i dni ustawowo wolnych. Wybór czynności
    /// ustawia datę w sekcji „Kiedy”; tam wciąż można ją zmienić ręcznie.
    private var deadlineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormSectionLabel("Policz termin")
            FormCard {
                FormRow(systemImage: "building.columns", title: "Czynność") {
                    Menu {
                        Button("Bez liczenia") { deadlineRule = nil }
                        ForEach(deadlineRules) { rule in
                            Button("\(rule.title) · \(rule.spanText)") { deadlineRule = rule }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(deadlineRule.map { "\($0.title) · \($0.spanText)" } ?? "Wybierz")
                                .font(EmmaTypography.ui(15, .medium))
                                .foregroundStyle(EmmaTheme.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(EmmaTheme.accent)
                        }
                    }
                    .accessibilityIdentifier("event-deadline-rule")
                }
                if deadlineRule != nil {
                    FormDivider()
                    FormRow(
                        systemImage: deadlineRule?.isHourly == true ? "person.badge.clock" : "envelope.open",
                        title: deadlineRule?.isHourly == true ? "Zatrzymanie" : "Liczone od"
                    ) {
                        // Zatrzymanie liczy się co do godziny — stąd także godzina.
                        DatePicker(
                            "Liczone od",
                            selection: $deadlineFrom,
                            displayedComponents: deadlineRule?.isHourly == true ? [.date, .hourAndMinute] : .date
                        )
                            .labelsHidden()
                            .accessibilityIdentifier("event-deadline-from")
                    }
                }
            }
            if let rule = deadlineRule {
                deadlineExplanation(rule)
                    .padding(.top, 6)
                    .padding(.horizontal, 4)
            } else {
                Text("Wybierz czynność — Emma policzy ostatni dzień z sobotami i świętami.")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .padding(.horizontal, 4)
            }
        }
        .animation(EmmaMotion.snappy, value: deadlineRule)
        .onChange(of: deadlineRule) { old, rule in
            if rule == nil {
                if !titleEdited { title = defaultTitle(for: kind) }
                return
            }
            // Zatrzymanie trwa teraz — domyślnie liczymy od bieżącej chwili.
            if rule?.isHourly == true, old?.isHourly != true {
                deadlineFrom = dependencies.now
            }
            applyDeadline()
        }
        .onChange(of: deadlineFrom) { _, _ in applyDeadline() }
    }

    private func deadlineExplanation(_ rule: DeadlineRule) -> some View {
        var lines: [String] = []
        var shifted = false
        switch rule.span {
        case .days, .months:
            guard let result = ProceduralDeadlines.due(from: FirmDateTime.day(of: deadlineFrom), rule: rule) else { break }
            lines.append("Ostatni dzień: \(dependencies.dateText.dayTitle(result.due)).")
            lines.append("\(rule.spanText) \(rule.startsFrom) (\(rule.legalBasis)).")
            if let reason = result.shiftReason {
                shifted = true
                lines.append("\(result.nominal.day) \(Self.monthGenitive(result.nominal.month)) to \(reason) — termin przesunięty na najbliższy dzień roboczy.")
            }
            lines.append("Sprawdź datę z pouczeniem.")
        case .hours(let hours):
            let end = ProceduralDeadlines.due(from: deadlineFrom, hours: hours)
            lines.append("Koniec: \(dependencies.dateText.dayTitle(FirmDateTime.day(of: end))), \(FirmDateTime.time(of: end).hhmm).")
            lines.append("\(rule.spanText) \(rule.startsFrom) (\(rule.legalBasis)).")
            lines.append("Zegar biegnie też w weekend i święta.")
            shifted = true
        }
        return Text(lines.joined(separator: " "))
            .font(EmmaTypography.caption())
            .foregroundStyle(shifted ? EmmaTheme.pillAmberText : EmmaTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("event-deadline-explanation")
    }

    private static func monthGenitive(_ month: Int) -> String {
        ["stycznia", "lutego", "marca", "kwietnia", "maja", "czerwca", "lipca",
         "sierpnia", "września", "października", "listopada", "grudnia"][max(0, min(11, month - 1))]
    }

    /// Ustawia datę terminu z kalkulatora i nazwę („Apelacja — Jan Kowalski”),
    /// dopóki użytkownik nie wpisał własnej.
    private func applyDeadline() {
        // Bez wybranej czynności nic nie liczymy — edycja istniejącego terminu
        // nie może zmienić jego daty ani nazwy.
        guard let rule = deadlineRule else { return }
        switch rule.span {
        case .days, .months:
            guard let result = ProceduralDeadlines.due(from: FirmDateTime.day(of: deadlineFrom), rule: rule) else { return }
            start = FirmDateTime.date(day: result.due, time: FirmDateTime.time(of: start))
        case .hours(let hours):
            start = ProceduralDeadlines.due(from: deadlineFrom, hours: hours)
        }
        if !titleEdited { title = defaultTitle(for: kind) }
    }

    private func dayChip(_ label: String, offset: Int) -> some View {
        let target = dependencies.today.adding(days: offset)
        let current = FirmDateTime.day(of: start)
        return QuickChip(title: label, isSelected: current == target) {
            start = FirmDateTime.date(day: target, time: FirmDateTime.time(of: start))
        }
    }

    private var whoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormSectionLabel("Z kim")
            FormCard {
                NavigationLink {
                    ClientPickerView(clients: clients, selection: $selectedClient)
                } label: {
                    FormRow(systemImage: "person", title: "Klient") {
                        HStack(spacing: 6) {
                            Text(selectedClientName)
                                .font(EmmaTypography.ui(15))
                                .foregroundStyle(selectedClient == nil ? EmmaTheme.mutedSoft : EmmaTheme.ink)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(EmmaTheme.mutedSoft)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("event-client")
            }
        }
        .onChange(of: selectedClient) { _, _ in
            // Nazwa „Konsultacja” zamienia się w „Konsultacja — Maria Kowalska”,
            // dopóki użytkownik nie wpisał własnej.
            if !titleEdited { title = defaultTitle(for: kind) }
        }
    }

    private var whereSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormSectionLabel("Gdzie")
            FormCard {
                FormRow(systemImage: "mappin.and.ellipse", title: "") {
                    TextField("Miejsce (opcjonalnie)", text: $place)
                        .font(EmmaTypography.ui(15))
                        .foregroundStyle(EmmaTheme.ink)
                        .accessibilityLabel("Miejsce")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.placeSuggestions, id: \.self) { suggestion in
                        QuickChip(title: suggestion, isSelected: place == suggestion) {
                            place = place == suggestion ? "" : suggestion
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(.top, 4)
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormSectionLabel("Przypomnienie")
            FormCard {
                FormRow(systemImage: reminder == .none ? "bell.slash" : "bell", title: "Przypomnij") {
                    Menu {
                        Picker("Przypomnienie", selection: $reminder) {
                            ForEach(ReminderOffset.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(reminder.title)
                                .font(EmmaTypography.ui(15, .medium))
                                .foregroundStyle(EmmaTheme.accent)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(EmmaTheme.accent)
                        }
                    }
                    .accessibilityIdentifier("event-reminder")
                }
            }
            if remindersDenied && reminder != .none {
                Text("Powiadomienia Emmy są wyłączone. Włącz je w Ustawieniach iOS → Emma → Powiadomienia.")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.pillAmberText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .padding(.horizontal, 4)
            } else {
                Text("Telefon przypomni o terminie powiadomieniem.")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .padding(.top, 6)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: Dane

    private var selectedClientName: String {
        guard let selectedClient else { return "Bez klienta" }
        return clients.first { $0.id == selectedClient }?.displayName ?? "Wybrany klient"
    }

    private func defaultTitle(for kind: EventKind) -> String {
        let base = kind == .consultation ? "Konsultacja" : (deadlineRule?.title ?? "Termin w sprawie")
        guard let selectedClient, let name = clients.first(where: { $0.id == selectedClient })?.displayName else {
            return base
        }
        return "\(base) — \(name)"
    }

    private func prepare() async {
        guard !loaded else { return }
        loaded = true
        remindersDenied = await dependencies.reminders.isDenied()
        clients = (try? await dependencies.repository.clients(matching: "", stage: nil)) ?? []
        selectedClient = clientID
        let day = initialDay ?? dependencies.today
        start = FirmDateTime.date(day: day, time: Self.suggestedTime(for: day, dependencies: dependencies))
        // Termin procesowy zwykle liczy się od dzisiejszego doręczenia.
        deadlineFrom = FirmDateTime.date(day: dependencies.today, time: FirmDateTime.time(of: start))
        reminder = dependencies.reminders.preferences.defaultOffset
        title = defaultTitle(for: kind)

        // Nowe spotkanie z głosu: pola rozpoznane w wypowiedzi wypełniają formularz
        // (F14). Nowe wydarzenie nigdy nie nadpisuje istniejącego.
        if eventID == nil, let seed = dependencies.pendingEventDraft {
            dependencies.pendingEventDraft = nil
            if let seededTitle = seed.title, !seededTitle.isEmpty {
                title = seededTitle
                titleEdited = true
            }
            let seededDay = seed.day ?? FirmDateTime.day(of: start)
            let seededTime = seed.time ?? FirmDateTime.time(of: start)
            start = FirmDateTime.date(day: seededDay, time: seededTime)
            if let from = seed.deadlineFrom {
                kind = .caseDeadline
                deadlineFrom = FirmDateTime.date(day: from, time: FirmDateTime.time(of: start))
            }
            pendingRuleID = seed.deadlineRuleID
        }

        // Sprawa podpowiada czynności dla swojego etapu, a jej sąd — miejsce.
        if eventID == nil, let caseID, let legalCase = try? await dependencies.repository.legalCase(id: caseID) {
            deadlineRules = ProceduralDeadlines.suggested(kind: legalCase.kind, stage: legalCase.stage)
            if place.isEmpty, let court = legalCase.courtText {
                place = court
            }
        }
        if let pendingRuleID, let rule = deadlineRules.first(where: { $0.id == pendingRuleID }) {
            kind = .caseDeadline
            deadlineRule = rule
        }

        guard let eventID else { return }
        // Nieudany odczyt nie może zamienić edycji w nowy termin (duplikat).
        do {
            guard let existing = try await dependencies.repository.event(id: eventID) else {
                loadError = "Nie znaleziono tego terminu. Mógł zostać usunięty."
                return
            }
            original = existing
            selectedClient = existing.clientID
            title = existing.title
            titleEdited = true
            kind = existing.kind
            start = FirmDateTime.date(day: existing.day, time: existing.time)
            place = existing.place
            reminder = dependencies.reminders.preferences.offset(for: existing.id)
        } catch {
            loadError = ScreenLoad.message(for: error, fallback: "Nie udało się wczytać terminu.")
        }
    }

    /// Najbliższa pełna godzina w przyszłości, gdy termin jest na dziś;
    /// na inny dzień — 10:00.
    static func suggestedTime(for day: LocalDate, dependencies: AppDependencies) -> TimeOfDay {
        guard day == dependencies.today else { return TimeOfDay(minutes: 10 * 60)! }
        let now = TimeOfDay.at(dependencies.clock.now())
        let nextHour = min(now.hour + 1, 23)
        return TimeOfDay(minutes: max(nextHour, 8) * 60)!
    }

    private func save() async {
        guard !isSaving else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.count >= 3 else {
            error = "Nazwij termin — co najmniej 3 znaki, np. „Konsultacja”."
            EmmaHaptics.error()
            return
        }
        error = nil
        isSaving = true
        defer { isSaving = false }

        let day = FirmDateTime.day(of: start)
        let time = FirmDateTime.time(of: start)
        let trimmedPlace = place.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = clients.first { $0.id == selectedClient }

        let outcome: SubmitOutcome<ScheduledEvent>
        if let original {
            var updated = original
            updated.title = trimmedTitle
            updated.kind = kind
            updated.day = day
            updated.time = time
            updated.place = trimmedPlace
            // Audyt 29.09.2026: wybór klienta w edycji był ignorowany — termin
            // zostawał przy dawnym kliencie mimo „Zapisano zmiany”. Zmiana klienta
            // odpina sprawę, która należała do poprzedniego.
            if updated.clientID != selectedClient {
                updated.clientID = selectedClient
                updated.caseID = nil
            }
            outcome = await dependencies.submit(fallback: "Nie udało się zapisać terminu.") {
                try await dependencies.repository.updateEvent(updated, expectedVersion: original.version)
            }
        } else {
            // Sprawa z trasy obowiązuje tylko dla klienta, z którym ją otwarto.
            let linkedCase = selectedClient == clientID ? caseID : nil
            outcome = await dependencies.submit(fallback: "Nie udało się dodać terminu.") {
                try await dependencies.repository.createEvent(
                    NewEventDraft(
                        clientID: selectedClient,
                        caseID: linkedCase,
                        title: trimmedTitle,
                        day: day,
                        time: time,
                        // Czas trwania nie jest już pytany — CRM wymaga wartości,
                        // więc godzina jest rozsądnym domyślnym blokiem w kalendarzu.
                        durationMinutes: 60,
                        kind: kind,
                        status: .toConfirm,
                        place: trimmedPlace
                    )
                )
            }
        }

        switch outcome {
        case .failed(let message):
            error = Self.friendly(message)
        case .saved(let saved):
            EmmaHaptics.success()
            dependencies.reminders.preferences.setOffset(reminder, for: saved.id)
            dependencies.dismissSheet()
            if original == nil, let client, client.stage == .new {
                // Umówiony termin to kontakt ze zgłoszeniem — nie zostaje „do obsługi”.
                await LeadActions.markInContact(
                    client,
                    dependencies: dependencies,
                    message: "Termin dodany · \(client.displayName) jest teraz „W kontakcie”"
                )
            } else {
                dependencies.showToast(original == nil ? "Termin dodany do kalendarza." : "Zapisano zmiany terminu.")
            }
            if reminder != .none {
                await dependencies.reminders.requestAuthorizationIfNeeded()
            }
            dependencies.reminders.scheduleRefresh(dependencies)
        }
    }

    private func delete() async {
        guard let original else { return }
        let outcome = await dependencies.submit(fallback: "Nie udało się usunąć terminu.") {
            try await dependencies.repository.deleteEvent(id: original.id, expectedVersion: original.version)
        }
        if let message = outcome.errorMessage {
            error = message
            return
        }
        dependencies.reminders.removeReminder(for: original.id)
        dependencies.dismissSheet()
        dependencies.showToast("Usunięto termin: \(original.title)")
    }

    /// Starszy backend przyjmuje termin tylko z kartoteką klienta (`client-N`).
    /// Jego komunikat walidacji nic nie mówi użytkownikowi — tłumaczymy go.
    static func friendly(_ message: String) -> String {
        if message.contains("client_id") {
            return "Serwer kancelarii nie przyjmuje jeszcze terminu bez kartoteki klienta "
                + "(np. dla nowego zgłoszenia). Wybierz klienta kancelarii albo poproś o aktualizację serwera."
        }
        return message
    }
}

extension EventKind {
    /// Nazwa w interfejsie.
    var displayTitle: String {
        switch self {
        case .consultation: return "Konsultacja"
        case .caseDeadline: return "Termin w sprawie"
        }
    }

    var systemImage: String {
        switch self {
        case .consultation: return "person.2"
        case .caseDeadline: return "building.columns"
        }
    }
}

// MARK: - Wybór klienta

/// Lista do wyboru klienta terminu: wyszukiwarka, „Bez klienta”, klienci
/// kancelarii i zgłoszenia osobno.
struct ClientPickerView: View {
    let clients: [Client]
    @Binding var selection: ClientID?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            Section {
                row(title: "Bez klienta", subtitle: "Termin kancelarii", id: nil)
            }
            let firm = filtered.filter { $0.stage == .client }
            if !firm.isEmpty {
                Section("Klienci kancelarii") {
                    ForEach(firm) { client in
                        row(title: client.displayName, subtitle: nil, id: client.id)
                    }
                }
            }
            let leads = filtered.filter { $0.stage != .client }
            if !leads.isEmpty {
                Section("Zgłoszenia") {
                    ForEach(leads) { client in
                        row(title: client.displayName, subtitle: LeadStatusStyle.topicText(LeadTopic.parse(client.topic)), id: client.id)
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Szukaj osoby")
        .navigationTitle("Klient")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filtered: [Client] {
        clients
            .filter { SearchText.matches(query, in: [$0.displayName, $0.topic]) }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    private func row(title: String, subtitle: String?, id: ClientID?) -> some View {
        Button {
            selection = id
            dismiss()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(EmmaTypography.ui(15))
                        .foregroundStyle(EmmaTheme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(EmmaTypography.caption())
                            .foregroundStyle(EmmaTheme.mutedSoft)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if selection == id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(EmmaTheme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Szczegóły terminu

/// Szczegóły terminu. Bez „Potwierdź” i „Zakończ spotkanie”: CRM nie prowadzi
/// stanu terminu, więc każdy termin wisiał jako „Do potwierdzenia” — to był
/// szum, a nie informacja. Zostały: co, kiedy, gdzie, z kim, przypomnienie
/// i czynności (edycja, notatka, przygotowanie z Emmą, usunięcie).
struct EventDetailSheet: View {

    let eventID: EventID

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.openURL) private var openURL
    @State private var phase: LoadPhase<ScheduledEvent> = .idle
    @State private var client: Client?
    @State private var reminder: ReminderOffset = .standard
    @State private var error: String?
    @State private var confirmsDelete = false

    var body: some View {
        SheetScaffold(title: "Termin", onClose: { dependencies.dismissSheet() }) {
            switch phase {
            case .idle, .loading:
                LoadingState("Wczytuję termin…")
            case .failed(let failure):
                LoadFailureView(failure) {
                    Task { await load() }
                }
            case .loaded(let event):
                content(event)
            }
        }
        .task { await load() }
        .confirmationDialog("Usunąć termin?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Usuń termin", role: .destructive) { Task { await delete() } }
            Button("Wróć", role: .cancel) {}
        } message: {
            Text("Termin zniknie z kalendarza kancelarii razem z przypomnieniem.")
        }
    }

    @ViewBuilder
    private func content(_ event: ScheduledEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(event.kind.displayTitle, systemImage: event.kind.systemImage)
                .font(EmmaTypography.caption(.semibold))
                .foregroundStyle(EmmaTheme.accent)
            Text(event.title)
                .font(EmmaTypography.heading(22))
                .foregroundStyle(EmmaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(whenText(event))
                .font(EmmaTypography.ui(15, .medium))
                .foregroundStyle(EmmaTheme.muted)
        }
        .padding(.bottom, 16)

        FormCard {
            if !event.place.isEmpty {
                // Sąd czy komisariat — jedno dotknięcie do nawigacji w Mapach.
                if let mapsURL = ContactLinks.mapsURL(event.place) {
                    Button {
                        openURL(mapsURL)
                    } label: {
                        FormRow(systemImage: "mappin.and.ellipse", title: "Miejsce") {
                            HStack(spacing: 6) {
                                Text(event.place)
                                    .font(EmmaTypography.ui(15))
                                    .foregroundStyle(EmmaTheme.accent)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                                Image(systemName: "arrow.triangle.turn.up.right.diamond")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(EmmaTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Otwiera nawigację w Mapach")
                } else {
                    FormRow(systemImage: "mappin.and.ellipse", title: "Miejsce") {
                        Text(event.place)
                            .font(EmmaTypography.ui(15))
                            .foregroundStyle(EmmaTheme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
                FormDivider()
            }
            if let client {
                Button {
                    dependencies.dismissSheet()
                    dependencies.openPerson(client.id)
                } label: {
                    FormRow(systemImage: "person", title: "Klient") {
                        HStack(spacing: 6) {
                            Text(client.displayName)
                                .font(EmmaTypography.ui(15))
                                .foregroundStyle(EmmaTheme.accent)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(EmmaTheme.mutedSoft)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                FormDivider()
            }
            FormRow(systemImage: reminder == .none ? "bell.slash" : "bell", title: "Przypomnienie") {
                Menu {
                    Picker("Przypomnienie", selection: Binding(
                        get: { reminder },
                        set: { changeReminder($0, for: event) }
                    )) {
                        ForEach(ReminderOffset.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(reminder.shortTitle)
                            .font(EmmaTypography.ui(15, .medium))
                            .foregroundStyle(EmmaTheme.accent)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(EmmaTheme.accent)
                    }
                }
            }
        }
        .padding(.bottom, 18)

        if let error { InlineError(error) }

        // Audyt 28.09.2026: termin, który już minął (albo trwa dziś), dało się
        // tylko edytować albo usunąć — a „załatwione” to jedno dotknięcie.
        // Bez tego przegapiony termin wisiał na czerwono na „Dzisiaj”.
        if EventActions.canFinish(event, today: dependencies.today) {
            PrimaryButton("Załatwione", systemImage: "checkmark.circle") {
                Task { await markFinished(event) }
            }
            .padding(.bottom, 10)
            SecondaryButton("Edytuj termin", systemImage: "pencil") {
                dependencies.present(.eventForm(editing: event.id, clientID: event.clientID, caseID: event.caseID, initialDay: nil))
            }
            .padding(.bottom, 10)
        } else {
            PrimaryButton("Edytuj termin", systemImage: "pencil") {
                dependencies.present(.eventForm(editing: event.id, clientID: event.clientID, caseID: event.caseID, initialDay: nil))
            }
            .padding(.bottom, 10)
        }

        if let clientID = event.clientID {
            HStack(spacing: 10) {
                SecondaryButton("Notatka", systemImage: "square.and.pencil") {
                    dependencies.present(.note(clientID: clientID, caseID: event.caseID))
                }
                SecondaryButton("Przygotuj mnie", systemImage: "sparkles") {
                    dependencies.dismissSheet()
                    dependencies.openEmma(clientID: clientID, action: .prepareCase)
                }
            }
            .padding(.bottom, 6)
        }

        Button(role: .destructive) {
            confirmsDelete = true
        } label: {
            Text("Usuń termin")
                .font(EmmaTypography.ui(15, .medium))
                .foregroundStyle(EmmaTheme.danger)
                .frame(maxWidth: .infinity, minHeight: EmmaSpacing.hitTarget)
        }
        .buttonStyle(.plain)
    }

    private func whenText(_ event: ScheduledEvent) -> String {
        let day = dependencies.dateText.dayLabel(event.day)
        return event.isAllDay ? "\(day), cały dzień" : "\(day), \(event.time.hhmm)"
    }

    private func load() async {
        if !phase.hasLoaded { phase = .loading }
        let result = await RecordLoading.phase(
            missingMessage: "Nie znaleziono tego terminu. Mógł zostać usunięty.",
            fallback: "Nie udało się wczytać terminu."
        ) {
            try await dependencies.repository.event(id: eventID)
        }
        phase = result
        if case .loaded(let event) = result {
            reminder = dependencies.reminders.preferences.offset(for: event.id)
            if let clientID = event.clientID {
                client = try? await dependencies.repository.client(id: clientID)
            }
        }
    }

    private func changeReminder(_ value: ReminderOffset, for event: ScheduledEvent) {
        reminder = value
        dependencies.reminders.preferences.setOffset(value, for: event.id)
        Task {
            if value != .none {
                await dependencies.reminders.requestAuthorizationIfNeeded()
            }
            dependencies.reminders.scheduleRefresh(dependencies)
        }
        dependencies.showToast(value == .none ? "Bez przypomnienia." : "Przypomnę: \(value.title.lowercased()).")
    }

    private func delete() async {
        guard case .loaded(let event) = phase else { return }
        let outcome = await dependencies.submit(fallback: "Nie udało się usunąć terminu.") {
            try await dependencies.repository.deleteEvent(id: event.id, expectedVersion: event.version)
        }
        if let message = outcome.errorMessage {
            error = message
            return
        }
        dependencies.reminders.removeReminder(for: event.id)
        dependencies.dismissSheet()
        dependencies.showToast("Usunięto termin: \(event.title)")
    }

    private func markFinished(_ event: ScheduledEvent) async {
        if let message = await EventActions.finish(event, dependencies: dependencies) {
            error = message
            return
        }
        dependencies.dismissSheet()
    }
}
