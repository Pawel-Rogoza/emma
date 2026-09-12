import SwiftUI

// MARK: - Formularze pracy kancelarii
//
// Port arkuszy z referencji: `noteForm`, `taskForm`/`saveTask`, `eventForm`/`saveEvent`,
// `taskDetail`, `eventDetail`/`confirmEvent`/`finishEvent`.
//
// Zasada: walidacja i reguły biznesowe (kolizja w kalendarzu) należą do
// repozytorium. Formularz pokazuje komunikat zwrócony przez repozytorium zamiast
// powielać te reguły po stronie widoku.

// MARK: Wspólne pola

/// Pole daty w formacie `yyyy-MM-dd` z zachowaniem typu `LocalDate`.
private struct DateField: View {
    let label: String
    @Binding var day: LocalDate

    @State private var text: String = ""

    var body: some View {
        LabeledField(label) {
            TextField("2026-09-11", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .emmaFieldStyle()
                .onAppear { text = day.isoString }
                .onChange(of: text) { _, newValue in
                    if let parsed = LocalDate(iso: newValue) { day = parsed }
                }
                .accessibilityLabel(label)
        }
    }
}

/// Pole godziny w zapisie `HH:mm`.
private struct TimeField: View {
    let label: String
    @Binding var time: TimeOfDay

    @State private var text: String = ""

    var body: some View {
        LabeledField(label) {
            TextField("10:30", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .emmaFieldStyle()
                .onAppear { text = time.hhmm }
                .onChange(of: text) { _, newValue in
                    if let parsed = TimeOfDay(hhmm: newValue) { time = parsed }
                }
                .accessibilityLabel(label)
        }
    }
}

// MARK: Notatka

/// Arkusz notatki z rozmowy. Dyktowanie wpisuje tekst do pola i **niczego nie zapisuje**.
struct NoteSheet: View {

    let clientID: ClientID
    let caseID: CaseID?

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var error: String?
    @State private var isDictating = false
    @State private var client: Client?
    @State private var legalCase: LegalCase?
    @State private var previousDictationHandler: ((DictationTarget, String) -> Void)?

    var body: some View {
        SheetScaffold(title: "Notatka z rozmowy", onClose: { close() }) {
            Text(caption)
                .font(EmmaTypography.ui(12))
                .foregroundStyle(EmmaTheme.mutedSoft)
                .padding(.bottom, 14)

            LabeledField("Ustalenia") {
                TextEditor(text: $text)
                    .font(EmmaTypography.ui(16))
                    .foregroundStyle(EmmaTheme.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(EmmaTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.field, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: EmmaRadii.field, style: .continuous)
                            .strokeBorder(EmmaTheme.fieldBorder, lineWidth: 1)
                    }
            }

            SecondaryButton(
                isDictating ? "Zakończ dyktowanie" : "Podyktuj notatkę",
                systemImage: "mic"
            ) {
                Task { await toggleDictation() }
            }
            .padding(.bottom, 8)

            if isDictating {
                Text("Dyktowanie wpisuje tekst do pola. Nic nie zapisze się samo.")
                    .font(EmmaTypography.ui(11))
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .padding(.bottom, 10)
            }

            if let error { InlineError(error) }

            PrimaryButton("Zapisz notatkę", systemImage: "checkmark") {
                Task { await save() }
            }
        }
        .task {
            client = try? await dependencies.repository.client(id: clientID)
            if let caseID { legalCase = try? await dependencies.repository.legalCase(id: caseID) }
            previousDictationHandler = dependencies.voice.onDictationResult
            dependencies.voice.onDictationResult = { _, dictated in
                text = dictated
                isDictating = false
            }
        }
        .onDisappear {
            dependencies.voice.onDictationResult = previousDictationHandler
            Task { await dependencies.voice.cancelDictation() }
        }
    }

    private var caption: String {
        let name = client?.displayName ?? Client.unknownDisplayName
        if let legalCase { return "\(name) · \(legalCase.number)" }
        return name
    }

    private func toggleDictation() async {
        if isDictating {
            await dependencies.voice.finishDictation()
            isDictating = false
            return
        }
        isDictating = true
        await dependencies.voice.startDictation(
            target: .caseNote(clientID: clientID, caseID: caseID),
            language: client?.language ?? .pl,
            service: dependencies.makeDictationService()
        )
    }

    private func save() async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "Wpisz lub podyktuj treść notatki."
            return
        }
        error = nil
        let saved = await dependencies.perform {
            try await dependencies.repository.addNote(
                NewNoteDraft(
                    clientID: clientID,
                    caseID: caseID,
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    authorID: dependencies.currentUser.id,
                    createdAt: dependencies.today
                )
            )
        }
        guard saved != nil else { return }
        close()
        dependencies.showToast("Notatka zapisana w karcie klienta.")
    }

    private func close() {
        Task { await dependencies.voice.cancelDictation() }
        dependencies.dismissSheet()
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
        SheetScaffold(title: original == nil ? "Nowe zadanie" : "Edytuj zadanie", onClose: { dependencies.dismissSheet() }) {
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

            DateField(label: "Termin", day: $dueDate)

            LabeledField("Priorytet") {
                HStack(spacing: 6) {
                    ForEach([TaskPriority.normal, .urgent], id: \.self) { candidate in
                        let isSelected = candidate == priority
                        Button {
                            priority = candidate
                        } label: {
                            Text(candidate.displayName)
                                .font(EmmaTypography.ui(12, isSelected ? .semibold : .regular))
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

            PrimaryButton(original == nil ? "Dodaj zadanie" : "Zapisz zadanie", systemImage: "checkmark") {
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
        if let taskID, let existing = try? await dependencies.repository.task(id: taskID) {
            original = existing
            title = existing.title
            selectedClient = existing.clientID
            dueDate = existing.dueDate
            priority = existing.priority
        }
    }

    private func save() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Uzupełnij nazwę i prawidłową datę."
            return
        }
        error = nil

        let result: TaskItem?
        if let original {
            var updated = original
            updated.title = trimmed
            updated.clientID = selectedClient
            updated.dueDate = dueDate
            updated.priority = priority
            result = await dependencies.perform {
                try await dependencies.repository.updateTask(updated, expectedVersion: original.version)
            }
        } else {
            result = await dependencies.perform {
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
        guard result != nil else { return }
        dependencies.dismissSheet()
    }
}

// MARK: Termin

struct EventFormSheet: View {

    let eventID: EventID?
    let clientID: ClientID?
    let caseID: CaseID?

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var selectedClient: ClientID?
    @State private var title = "Konsultacja"
    @State private var kind: EventKind = .consultation
    @State private var day = LocalDate(year: 2026, month: 9, day: 11)
    @State private var time = TimeOfDay(hhmm: "15:00") ?? TimeOfDay(minutes: 900)!
    @State private var duration = 30
    @State private var status: EventStatus = .toConfirm
    @State private var place = ""
    @State private var error: String?
    @State private var clients: [Client] = []
    @State private var original: ScheduledEvent?
    @State private var loaded = false

    var body: some View {
        SheetScaffold(title: original == nil ? "Nowy termin" : "Edytuj termin", onClose: { dependencies.dismissSheet() }) {
            LabeledField("Klient") {
                Menu {
                    ForEach(clients) { client in
                        Button(client.displayName) { selectedClient = client.id }
                    }
                } label: {
                    HStack {
                        Text(clients.first { $0.id == selectedClient }?.displayName ?? "Wybierz klienta")
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
                .accessibilityLabel("Klient")
            }

            LabeledField("Nazwa wydarzenia") {
                TextField("Konsultacja", text: $title)
                    .emmaFieldStyle()
                    .accessibilityLabel("Nazwa wydarzenia")
            }

            LabeledField("Rodzaj") {
                Picker("Rodzaj", selection: $kind) {
                    ForEach(EventKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            DateField(label: "Data", day: $day)
            TimeField(label: "Godzina", time: $time)

            LabeledField("Czas trwania") {
                Picker("Czas trwania", selection: $duration) {
                    ForEach([30, 60, 90, 120], id: \.self) { Text("\($0) minut").tag($0) }
                }
                .pickerStyle(.segmented)
            }

            LabeledField("Status") {
                Picker("Status", selection: $status) {
                    ForEach(EventStatus.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            LabeledField("Miejsce") {
                TextField("Online albo adres", text: $place)
                    .emmaFieldStyle()
                    .accessibilityLabel("Miejsce")
            }

            if let error { InlineError(error) }

            PrimaryButton(original == nil ? "Dodaj termin" : "Zapisz termin", systemImage: "checkmark") {
                Task { await save() }
            }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        guard !loaded else { return }
        loaded = true
        clients = (try? await dependencies.repository.clients(matching: "", stage: nil)) ?? []
        selectedClient = clientID ?? clients.first?.id
        day = dependencies.today
        if let eventID, let existing = try? await dependencies.repository.event(id: eventID) {
            original = existing
            selectedClient = existing.clientID
            title = existing.title
            kind = existing.kind
            day = existing.day
            time = existing.time
            duration = existing.durationMinutes
            status = existing.status
            place = existing.place
        }
    }

    private func save() async {
        guard let client = selectedClient else {
            error = "Uzupełnij klienta, nazwę, miejsce i prawidłowy termin."
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlace = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedPlace.isEmpty else {
            error = "Uzupełnij klienta, nazwę, miejsce i prawidłowy termin."
            return
        }
        error = nil

        if let original {
            var updated = original
            updated.title = trimmedTitle
            updated.kind = kind
            updated.day = day
            updated.time = time
            updated.durationMinutes = duration
            updated.status = status
            updated.place = trimmedPlace
            let saved = await dependencies.perform {
                try await dependencies.repository.updateEvent(updated, expectedVersion: original.version)
            }
            guard saved != nil else { return }
        } else {
            let saved = await dependencies.perform {
                try await dependencies.repository.createEvent(
                    NewEventDraft(
                        clientID: client,
                        caseID: caseID,
                        title: trimmedTitle,
                        day: day,
                        time: time,
                        durationMinutes: duration,
                        kind: kind,
                        status: status,
                        place: trimmedPlace
                    )
                )
            }
            guard saved != nil else { return }
        }
        dependencies.dismissSheet()
    }
}

// MARK: Szczegóły zadania

struct TaskDetailSheet: View {

    let taskID: TaskID

    @EnvironmentObject private var dependencies: AppDependencies
    @State private var task: TaskItem?
    @State private var error: String?

    var body: some View {
        SheetScaffold(title: "Zadanie", onClose: { dependencies.dismissSheet() }) {
            if let task {
                Text(task.title)
                    .font(EmmaTypography.body(for: task.title, size: 17))
                    .foregroundStyle(EmmaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)

                InfoList([
                    .init("Termin", dependencies.dateText.dayLabel(task.dueDate)),
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
            } else {
                LoadingState("Wczytuję zadanie…")
            }
        }
        .task {
            task = try? await dependencies.repository.task(id: taskID)
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
        if updated == nil { error = "Nie udało się zmienić stanu zadania." }
        self.task = updated ?? self.task
    }
}

// MARK: Szczegóły terminu

struct EventDetailSheet: View {

    let eventID: EventID

    @EnvironmentObject private var dependencies: AppDependencies
    @State private var event: ScheduledEvent?
    @State private var client: Client?
    @State private var error: String?

    var body: some View {
        SheetScaffold(title: event?.kind.rawValue ?? "Termin", onClose: { dependencies.dismissSheet() }) {
            if let event {
                if let client {
                    PersonRow(client: client, subtitle: event.title, showsChevron: false, onOpen: nil)
                        .padding(.bottom, 14)
                }

                InfoList([
                    .init("Kiedy", "\(dependencies.dateText.dayLabel(event.day)), \(event.time.hhmm)"),
                    .init("Czas", "\(event.durationMinutes) min"),
                    .init("Miejsce", event.place),
                    .init("Status", event.status.rawValue)
                ])
                .padding(.bottom, 16)

                if let error { InlineError(error) }

                actions(event)
            } else {
                LoadingState("Wczytuję termin…")
            }
        }
        .task {
            event = try? await dependencies.repository.event(id: eventID)
            if let event { client = try? await dependencies.repository.client(id: event.clientID) }
        }
    }

    @ViewBuilder
    private func actions(_ event: ScheduledEvent) -> some View {
        switch event.status {
        case .finished:
            PrimaryButton("Dodaj notatkę po spotkaniu", systemImage: "square.and.pencil") {
                dependencies.present(.note(clientID: event.clientID, caseID: event.caseID))
            }
            .padding(.bottom, 10)
            Button {
                dependencies.dismissSheet()
                dependencies.openEmma(clientID: event.clientID, action: .prepareCase)
            } label: {
                Text("Przygotuj mnie z Emmą")
                    .font(EmmaTypography.button)
                    .foregroundStyle(EmmaTheme.secondaryButtonText)
                    .frame(maxWidth: .infinity, minHeight: EmmaMetrics.primaryButtonMinHeight)
                    .background(EmmaTheme.secondaryButton)
                    .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous))
            }
            .buttonStyle(.plain)
        case .toConfirm:
            PrimaryButton("Potwierdź termin", systemImage: "checkmark") {
                Task { await update(event, status: .confirmed) }
            }
            .padding(.bottom, 10)
            SecondaryButton("Edytuj termin") {
                dependencies.present(.eventForm(editing: event.id, clientID: event.clientID, caseID: event.caseID))
            }
        case .confirmed:
            PrimaryButton("Zakończ spotkanie", systemImage: "checkmark") {
                Task { await update(event, status: .finished) }
            }
            .padding(.bottom, 10)
            SecondaryButton("Edytuj termin") {
                dependencies.present(.eventForm(editing: event.id, clientID: event.clientID, caseID: event.caseID))
            }
        }
    }

    /// Potwierdzenie i zakończenie przechodzą przez repozytorium, dzięki czemu
    /// reguła kolizji w kalendarzu jest sprawdzana w jednym miejscu.
    private func update(_ event: ScheduledEvent, status: EventStatus) async {
        error = nil
        var updated = event
        updated.status = status
        let saved = await dependencies.perform {
            try await dependencies.repository.updateEvent(updated, expectedVersion: event.version)
        }
        if let saved {
            self.event = saved
        } else {
            error = "Nie udało się zmienić statusu terminu."
        }
    }
}
