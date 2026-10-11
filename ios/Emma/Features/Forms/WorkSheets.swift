import SwiftUI

// MARK: - Formularze pracy kancelarii
//
// Port arkuszy z referencji: `noteForm`, `taskForm`/`saveTask`, `eventForm`/`saveEvent`,
// `taskDetail`, `eventDetail`/`confirmEvent`/`finishEvent`.
//
// Zasada: walidacja i reguły biznesowe (kolizja w kalendarzu) należą do
// repozytorium. Formularz pokazuje komunikat zwrócony przez repozytorium zamiast
// powielać te reguły po stronie widoku.

// MARK: Notatka

/// Arkusz notatki z rozmowy. Dyktowanie wpisuje tekst do pola na bieżąco
/// i **niczego nie zapisuje** — zapis jest zawsze decyzją użytkownika.
struct NoteSheet: View {

    let clientID: ClientID
    let caseID: CaseID?

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var text: String = ""
    @State private var error: String?
    @State private var isSaving = false
    @State private var client: Client?
    @State private var legalCase: LegalCase?
    @FocusState private var editorFocused: Bool

    var body: some View {
        SheetScaffold(title: "Notatka", onClose: { dependencies.dismissSheet() }) {
            Text(caption)
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.mutedSoft)
                .padding(.bottom, 12)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(EmmaTypography.ui(16))
                    .foregroundStyle(EmmaTheme.ink)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .frame(minHeight: 180)
                    .padding(8)
                    .accessibilityLabel("Treść notatki")
                    .accessibilityIdentifier("note-text")
                if text.isEmpty {
                    Text("Ustalenia z rozmowy, kolejne kroki…")
                        .font(EmmaTypography.ui(16))
                        .foregroundStyle(EmmaTheme.mutedSoft)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .padding(.bottom, 10)

            DictationButton(text: $text, target: .caseNote(clientID: clientID, caseID: caseID))
                .padding(.bottom, 14)

            if let error { InlineError(error) }

            PrimaryButton("Zapisz notatkę", systemImage: "checkmark", isLoading: isSaving) {
                Task { await save() }
            }
            .accessibilityIdentifier("note-save")
        }
        .task {
            client = try? await dependencies.repository.client(id: clientID)
            if let caseID { legalCase = try? await dependencies.repository.legalCase(id: caseID) }
        }
    }

    private var caption: String {
        let name = client?.displayName ?? Client.unknownDisplayName
        if let legalCase { return "\(name) · \(legalCase.number)" }
        return name
    }

    private func save() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Wpisz lub podyktuj treść notatki."
            return
        }
        guard !isSaving else { return }
        error = nil
        isSaving = true
        defer { isSaving = false }
        let outcome = await dependencies.submit(fallback: "Nie udało się zapisać notatki.") {
            try await dependencies.repository.addNote(
                NewNoteDraft(
                    clientID: clientID,
                    caseID: caseID,
                    text: trimmed,
                    authorID: dependencies.currentUser.id,
                    createdAt: dependencies.today
                )
            )
        }
        switch outcome {
        case .failed(let message):
            error = NoteSheet.friendly(message)
        case .saved:
            EmmaHaptics.success()
            dependencies.dismissSheet()
            dependencies.showToast("Notatka zapisana.")
            // Notatka to ślad kontaktu — zgłoszenie „do obsługi” przechodzi do „W kontakcie”.
            if let client, client.stage == .new {
                await LeadActions.markInContact(
                    client,
                    dependencies: dependencies,
                    message: "Notatka zapisana · \(client.displayName) jest teraz „W kontakcie”"
                )
            }
        }
    }

    /// Starszy backend przyjmuje notatkę tylko do kartoteki (`client-N`).
    static func friendly(_ message: String) -> String {
        if message.contains("client_id") {
            return "Serwer kancelarii nie przyjmuje jeszcze notatek do zgłoszeń bez kartoteki. "
                + "Zaktualizuj serwer albo najpierw przyjmij sprawę."
        }
        return message
    }
}

// MARK: Zadanie

/// Review 11.10.2026: „formularz ma być przejrzysty i prosty w użyciu”.
/// Jedno pytanie na raz, od góry: **co** (pole z kursorem od razu, podpowiedzi
/// typowych czynności), **kiedy** (chipy widoczne naraz + opis wybranego dnia
/// z ostrzeżeniem o weekendzie i święcie), **dla kogo** i przełącznik „Pilne”.
/// „Gotowe” na klawiaturze zapisuje — nie trzeba szukać przycisku pod spodem.
struct TaskFormSheet: View {

    let taskID: TaskID?
    let clientID: ClientID?
    let caseID: CaseID?
    /// Dzień z kalendarza, na który otwarto formularz. `nil` — dziś.
    var initialDay: LocalDate? = nil

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var title = ""
    @State private var selectedClient: ClientID?
    @State private var dueDate = LocalDate(year: 2026, month: 9, day: 11)
    @State private var priority: TaskPriority = .normal
    @State private var error: String?
    @State private var clients: [Client] = []
    @State private var original: TaskItem?
    @State private var loaded = false
    @State private var remindersDenied = false
    @FocusState private var titleFocused: Bool
    /// Audyt 29.09.2026: bez tej blokady szybkie dwa dotknięcia „Dodaj
    /// zadanie” zakładały dwa identyczne zadania.
    @State private var isSaving = false

    /// Najczęstsze czynności kancelarii — jedno dotknięcie zamiast pisania.
    private static let suggestions = ["Oddzwonić", "Wysłać pismo", "Przygotować dokumenty", "Sprawdzić akta", "Wystawić fakturę"]

    var body: some View {
        SheetScaffold(title: taskID == nil ? "Nowe zadanie" : "Edytuj zadanie", onClose: { dependencies.dismissSheet() }) {
            whatSection
            whenSection
            whoSection

            if let error {
                InlineError(error)
                    .padding(.top, 12)
            }

            PrimaryButton(
                taskID == nil ? "Dodaj zadanie" : "Zapisz zadanie",
                systemImage: "checkmark",
                isEnabled: taskID == nil || original != nil,
                isLoading: isSaving
            ) {
                Task { await save() }
            }
            .padding(.top, 20)
            .accessibilityIdentifier("task-save")
        }
        .environment(\.timeZone, FirmDateTime.timeZone)
        .environment(\.locale, Locale(identifier: "pl_PL"))
        .task { await prepare() }
    }

    // MARK: Sekcje

    private var whatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Co trzeba zrobić?", text: $title, axis: .vertical)
                .font(EmmaTypography.heading(20))
                .foregroundStyle(EmmaTheme.ink)
                .lineLimit(1...4)
                .focused($titleFocused)
                .submitLabel(.done)
                .onChange(of: title) { _, newValue in
                    // Pole wielowierszowe: „Gotowe” wstawia znak nowej linii —
                    // traktujemy go jak zapis, a nie jak drugą linijkę.
                    guard newValue.contains("\n") else { return }
                    title = newValue.replacingOccurrences(of: "\n", with: "")
                    titleFocused = false
                    Task { await save() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(minHeight: 56)
                .background(EmmaTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                        .strokeBorder(titleFocused ? EmmaTheme.accent.opacity(0.5) : EmmaTheme.cardBorder, lineWidth: 1)
                }
                .accessibilityLabel("Co trzeba zrobić?")
                .accessibilityIdentifier("task-title")

            if taskID == nil && title.trimmingCharacters(in: .whitespaces).isEmpty {
                ChipFlow {
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        QuickChip(title: suggestion, isSelected: false) {
                            title = suggestion + " "
                            titleFocused = true
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(EmmaMotion.snappy, value: title.isEmpty)
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormSectionLabel("Do kiedy")
            DayShortcutChips(today: dependencies.today, selection: dueDate) { dueDate = $0 }
                .padding(.bottom, 6)
            FormCard {
                FormRow(systemImage: "calendar", title: "Data") {
                    DatePicker(
                        "Termin",
                        selection: Binding(
                            get: { FirmDateTime.date(day: dueDate, time: TimeOfDay(minutes: 12 * 60)!) },
                            set: { dueDate = FirmDateTime.day(of: $0) }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("task-date")
                }
                FormDivider()
                FormRow(systemImage: "flame", title: "Pilne") {
                    Toggle("Pilne", isOn: Binding(
                        get: { priority == .urgent },
                        set: { isOn in
                            EmmaHaptics.selection()
                            priority = isOn ? .urgent : .normal
                        }
                    ))
                    .labelsHidden()
                    .tint(EmmaTheme.pillDangerText)
                    .accessibilityIdentifier("task-urgent")
                }
            }
            DaySummaryLine(day: dueDate, today: dependencies.today, dateText: dependencies.dateText)
            ReminderHint(
                text: "Pojawi się w kalendarzu, a telefon przypomni o 9:00 w dniu zadania.",
                isDenied: remindersDenied
            )
        }
    }

    private var whoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormSectionLabel("Dla kogo")
            FormCard {
                NavigationLink {
                    ClientPickerView(clients: clients, selection: $selectedClient)
                } label: {
                    FormRow(systemImage: "person", title: "Klient") {
                        HStack(spacing: 6) {
                            Text(clients.first { $0.id == selectedClient }?.displayName ?? "Bez klienta")
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
                .accessibilityLabel("Powiązany klient")
            }
        }
    }

    // MARK: Dane

    private func prepare() async {
        guard !loaded else { return }
        loaded = true
        selectedClient = clientID
        dueDate = initialDay ?? dependencies.today
        // Nowe zadanie: kursor od razu w polu — można pisać bez dotykania.
        if taskID == nil { titleFocused = true }
        remindersDenied = await dependencies.reminders.isDenied()
        clients = (try? await dependencies.repository.clients(matching: "", stage: nil)) ?? []
        guard let taskID else { return }
        // Edycja bez wczytanego oryginału nie może udawać nowego zadania:
        // wcześniej błąd odczytu dawał pusty formularz, a „Zapisz” zakładało duplikat.
        do {
            guard let existing = try await dependencies.repository.task(id: taskID) else {
                error = "Nie znaleziono tego zadania. Mogło zostać usunięte."
                return
            }
            original = existing
            title = existing.title
            selectedClient = existing.clientID
            // Zadanie bez terminu dostaje w formularzu dzień bieżący — widoczny,
            // więc zapisany termin jest tym, co użytkownik ma przed oczami.
            dueDate = existing.dueDate ?? dependencies.today
            priority = existing.priority
        } catch {
            self.error = ScreenLoad.message(for: error, fallback: "Nie udało się wczytać zadania.")
        }
    }

    private func save() async {
        guard taskID == nil || original != nil else {
            error = "Nie udało się wczytać zadania — zamknij formularz i spróbuj ponownie."
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Wpisz, co trzeba zrobić."
            EmmaHaptics.error()
            titleFocused = true
            return
        }
        guard !isSaving else { return }
        error = nil
        isSaving = true
        defer { isSaving = false }

        let outcome: SubmitOutcome<TaskItem>
        if let original {
            var updated = original
            updated.title = trimmed
            updated.clientID = selectedClient
            updated.dueDate = dueDate
            updated.priority = priority
            outcome = await dependencies.submit(fallback: "Nie udało się zapisać zadania.") {
                try await dependencies.repository.updateTask(updated, expectedVersion: original.version)
            }
        } else {
            outcome = await dependencies.submit(fallback: "Nie udało się dodać zadania.") {
                try await dependencies.repository.createTask(
                    NewTaskDraft(
                        title: trimmed,
                        clientID: selectedClient,
                        // Sprawa z trasy tylko dla klienta, z którym ją otwarto.
                        caseID: selectedClient == clientID ? caseID : nil,
                        dueDate: dueDate,
                        priority: priority
                    )
                )
            }
        }
        if let message = outcome.errorMessage {
            error = message
            return
        }
        EmmaHaptics.success()
        dependencies.dismissSheet()
        let when = PlanningShortcuts.relative(dueDate, today: dependencies.today)
        dependencies.showToast(original == nil ? "Zadanie dodane · \(when)." : "Zapisano zadanie · \(when).")
        // Zadanie z terminem przypomina się rano — o zgodę pytamy, gdy to ma sens.
        await dependencies.reminders.requestAuthorizationIfNeeded()
        dependencies.reminders.scheduleRefresh(dependencies)
    }
}

// MARK: Szczegóły zadania

/// 0.23.0: szczegóły zadania wyglądały jak szkic (dwa wiersze tekstu i dwa
/// szare przyciski). Teraz ten sam język co szczegóły terminu: stan w pigułkach
/// (pilne, po terminie, wykonane), karta z terminem, klientem i sprawą —
/// klient i sprawa otwierają się jednym dotknięciem.
struct TaskDetailSheet: View {

    let taskID: TaskID

    @EnvironmentObject private var dependencies: AppDependencies
    @State private var phase: LoadPhase<TaskItem> = .idle
    @State private var error: String?
    @State private var clientName: String?
    @State private var caseNumber: String?

    var body: some View {
        SheetScaffold(title: "Zadanie", onClose: { dependencies.dismissSheet() }) {
            switch phase {
            case .idle, .loading:
                LoadingState("Wczytuję zadanie…")
            case .failed(let failure):
                LoadFailureView(failure) {
                    Task { await load() }
                }
            case .loaded(let task):
                content(task)
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ task: TaskItem) -> some View {
        let isOverdue = !task.isDone && (task.dueDate.map { $0 < dependencies.today } ?? false)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if task.isDone {
                    StatusPill("Wykonane", kind: .green)
                } else if isOverdue {
                    StatusPill("Po terminie", kind: .danger)
                }
                if task.showsUrgentBadge {
                    StatusPill("Pilne", kind: .urgent)
                }
            }
            Text(task.title)
                .font(EmmaTypography.heading(22))
                .foregroundStyle(EmmaTheme.ink)
                .strikethrough(task.isDone, color: EmmaTheme.mutedSoft)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("task-detail-title")
        }
        .padding(.bottom, 16)
        .animation(EmmaMotion.smooth, value: task.isDone)

        FormCard {
            FormRow(systemImage: "calendar", title: "Termin") {
                Text(task.dueDate.map(dependencies.dateText.dayLabel) ?? TaskItem.noDueDateText)
                    .font(EmmaTypography.ui(15, isOverdue ? .semibold : .regular))
                    .foregroundStyle(isOverdue ? EmmaTheme.pillDangerText : EmmaTheme.ink)
            }
            if let clientID = task.clientID {
                FormDivider()
                linkRow(systemImage: "person", title: "Klient", value: clientName ?? "Karta klienta") {
                    dependencies.dismissSheet()
                    dependencies.openPerson(clientID)
                }
            }
            if let caseID = task.caseID {
                FormDivider()
                linkRow(systemImage: "folder", title: "Sprawa", value: caseNumber ?? "Otwórz sprawę") {
                    dependencies.dismissSheet()
                    dependencies.openCase(caseID)
                }
            }
        }
        .padding(.bottom, 18)

        if let error { InlineError(error) }

        PrimaryButton(
            task.isDone ? "Przywróć zadanie" : "Oznacz jako wykonane",
            systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark.circle"
        ) {
            Task { await toggle(task) }
        }
        .padding(.bottom, 10)
        .accessibilityIdentifier("task-detail-toggle")

        SecondaryButton("Edytuj zadanie", systemImage: "pencil") {
            dependencies.present(.taskForm(editing: task.id, clientID: task.clientID, caseID: task.caseID))
        }
    }

    private func linkRow(systemImage: String, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FormRow(systemImage: systemImage, title: title) {
                HStack(spacing: 6) {
                    Text(value)
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
    }

    private func load() async {
        if !phase.hasLoaded { phase = .loading }
        phase = await RecordLoading.phase(
            missingMessage: "Nie znaleziono tego zadania. Mogło zostać usunięte.",
            fallback: "Nie udało się wczytać zadania."
        ) {
            try await dependencies.repository.task(id: taskID)
        }
        guard case .loaded(let task) = phase else { return }
        if let clientID = task.clientID {
            clientName = (try? await dependencies.repository.client(id: clientID))?.displayName
        }
        if let caseID = task.caseID {
            caseNumber = (try? await dependencies.repository.legalCase(id: caseID))?.number
        }
    }

    private func toggle(_ task: TaskItem) async {
        error = nil
        let updated = await dependencies.perform {
            try await dependencies.repository.setDone(
                taskID: task.id,
                isDone: !task.isDone,
                expectedVersion: task.version
            )
        }
        if let updated {
            phase = .loaded(updated)
        } else {
            error = "Nie udało się zmienić stanu zadania."
        }
    }
}
