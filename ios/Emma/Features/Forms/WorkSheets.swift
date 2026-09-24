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

            PrimaryButton("Zapisz notatkę", systemImage: "checkmark", isEnabled: !isSaving) {
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

struct TaskFormSheet: View {

    let taskID: TaskID?
    let clientID: ClientID?
    let caseID: CaseID?

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var title = ""
    @State private var selectedClient: ClientID?
    @State private var dueDate = LocalDate(year: 2026, month: 9, day: 11)
    @State private var priority: TaskPriority = .normal
    @State private var error: String?
    @State private var clients: [Client] = []
    @State private var original: TaskItem?
    @State private var loaded = false

    var body: some View {
        SheetScaffold(title: taskID == nil ? "Nowe zadanie" : "Edytuj zadanie", onClose: { dependencies.dismissSheet() }) {
            LabeledField("Co trzeba zrobić?") {
                TextField("Nazwa zadania", text: $title)
                    .emmaFieldStyle()
                    .accessibilityLabel("Co trzeba zrobić?")
            }

            LabeledField("Powiązany klient") {
                Menu {
                    Button("Bez klienta") { selectedClient = nil }
                    ForEach(clients) { client in
                        Button(client.displayName) { selectedClient = client.id }
                    }
                } label: {
                    HStack {
                        Text(clients.first { $0.id == selectedClient }?.displayName ?? "Bez klienta")
                            .font(EmmaTypography.fieldValue)
                            .foregroundStyle(EmmaTheme.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(EmmaTheme.mutedSoft)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: EmmaMetrics.fieldMinHeight)
                    .background(EmmaTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.field, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: EmmaRadii.field, style: .continuous)
                            .strokeBorder(EmmaTheme.fieldBorder, lineWidth: 1)
                    }
                }
                .accessibilityLabel("Powiązany klient")
            }

            LabeledField("Termin") {
                HStack(spacing: 10) {
                    DatePicker(
                        "Termin",
                        selection: Binding(
                            get: { FirmDateTime.date(day: dueDate, time: TimeOfDay(minutes: 12 * 60)!) },
                            set: { dueDate = FirmDateTime.day(of: $0) }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .environment(\.timeZone, FirmDateTime.timeZone)
                    .environment(\.locale, Locale(identifier: "pl_PL"))
                    Spacer(minLength: 0)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach([("Dziś", 0), ("Jutro", 1), ("Za tydzień", 7)], id: \.1) { label, offset in
                            let target = dependencies.today.adding(days: offset)
                            QuickChip(title: label, isSelected: dueDate == target) { dueDate = target }
                        }
                    }
                }
            }

            LabeledField("Priorytet") {
                HStack(spacing: 6) {
                    ForEach([TaskPriority.normal, .urgent], id: \.self) { candidate in
                        let isSelected = candidate == priority
                        Button {
                            priority = candidate
                        } label: {
                            Text(candidate.displayName)
                                .font(EmmaTypography.caption(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? EmmaTheme.ink : EmmaTheme.muted)
                                .frame(maxWidth: .infinity, minHeight: EmmaMetrics.segmentedMinHeight - 6)
                                .background(isSelected ? EmmaTheme.controlSelected : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.segmentedInner, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
                .padding(3)
                .background(EmmaTheme.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.segmented, style: .continuous))
            }

            if let error { InlineError(error) }

            PrimaryButton(taskID == nil ? "Dodaj zadanie" : "Zapisz zadanie", systemImage: "checkmark") {
                Task { await save() }
            }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        guard !loaded else { return }
        loaded = true
        clients = (try? await dependencies.repository.clients(matching: "", stage: nil)) ?? []
        selectedClient = clientID
        dueDate = dependencies.today
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
            return
        }
        error = nil

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
                        caseID: caseID,
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
    }
}

// MARK: Szczegóły zadania

struct TaskDetailSheet: View {

    let taskID: TaskID

    @EnvironmentObject private var dependencies: AppDependencies
    @State private var phase: LoadPhase<TaskItem> = .idle
    @State private var error: String?

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
        Text(task.title)
            .font(EmmaTypography.body(for: task.title, size: 17))
            .foregroundStyle(EmmaTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 14)

        InfoList([
            .init("Termin", task.dueDate.map(dependencies.dateText.dayLabel) ?? TaskItem.noDueDateText),
            .init("Status", task.isDone ? "Wykonane" : "Do zrobienia")
        ])
        .padding(.bottom, 16)

        if let error { InlineError(error) }

        PrimaryButton(
            task.isDone ? "Przywróć zadanie" : "Oznacz jako wykonane",
            systemImage: "checkmark"
        ) {
            Task { await toggle(task) }
        }
        .padding(.bottom, 10)

        HStack(spacing: 10) {
            SecondaryButton("Edytuj") {
                dependencies.present(.taskForm(editing: task.id, clientID: task.clientID, caseID: task.caseID))
            }
            if let clientID = task.clientID {
                SecondaryButton("Karta klienta") {
                    dependencies.dismissSheet()
                    dependencies.openPerson(clientID)
                }
            }
        }
    }

    private func load() async {
        if !phase.hasLoaded { phase = .loading }
        phase = await RecordLoading.phase(
            missingMessage: "Nie znaleziono tego zadania. Mogło zostać usunięte.",
            fallback: "Nie udało się wczytać zadania."
        ) {
            try await dependencies.repository.task(id: taskID)
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
