import SwiftUI

// MARK: - Arkusz „Ustawienia sprawy”
//
// Port `caseSettings()` i `saveCaseSettings()` z referencji. Zapis idzie przez
// `updateCase(_:expectedVersion:clearing:)` — bez omijania blokady optymistycznej.
//
// Profil sprawy (01.10.2026): rodzaj → etap → rola klienta → pilnowana data.
// Każde pytanie to chipy na jedno dotknięcie i pojawia się dopiero wtedy, gdy
// ma sens (cudzoziemca nie pytamy o rolę procesową, sprawy karnej o pobyt).
// Zmiana etapu sama przestawia rolę (podejrzany → oskarżony), chyba że
// adwokat wybrał ją ręcznie.

struct CaseSettingsSheet: View {

    let caseID: CaseID

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var phase: LoadPhase<LegalCase> = .idle
    @State private var title = ""
    @State private var summary = ""
    @State private var status: CaseStatus = .inProgress
    @State private var signature = ""
    @State private var court = ""
    @State private var kind: CaseKind?
    @State private var stage: CaseStage?
    @State private var role: ClientRole?
    @State private var watchOn: [CaseWatch.Kind: Bool] = [:]
    @State private var watchDates: [CaseWatch.Kind: Date] = [:]
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var didPrefill = false

    var body: some View {
        SheetScaffold(title: "Ustawienia sprawy", onClose: { dependencies.dismissSheet() }) {
            content
                .task(id: dependencies.dataVersion) { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            LoadingState("Wczytuję sprawę…")
        case .failed(let failure):
            LoadFailureView(failure) {
                Task { await load() }
            }
        case .loaded(let legalCase):
            form(legalCase)
        }
    }

    private func form(_ legalCase: LegalCase) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LabeledField("Nazwa sprawy") {
                TextField("", text: $title)
                    .emmaFieldStyle()
                    .accessibilityLabel("Nazwa sprawy")
            }

            profileSection
                .padding(.bottom, 14)

            // Sygnatura akt — po niej karnista szuka sprawy („II K 123/26”).
            // Etykieta idzie za etapem: w przygotowawczym to sygnatura prokuratury.
            LabeledField(stage?.signatureLabel ?? "Sygnatura akt", help: "Pojawi się w nagłówku sprawy i w wyszukiwarce kartoteki.") {
                TextField(stage?.signaturePlaceholder ?? "np. II K 123/26", text: $signature)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .emmaFieldStyle()
                    .accessibilityLabel("Sygnatura akt")
                    .accessibilityIdentifier("case-signature")
            }

            LabeledField(stage?.authorityLabel ?? "Sąd lub organ") {
                TextField(stage?.authorityPlaceholder ?? "np. Sąd Rejonowy dla Warszawy-Śródmieścia", text: $court)
                    .textInputAutocapitalization(.sentences)
                    .emmaFieldStyle()
                    .accessibilityLabel("Sąd lub organ")
                    .accessibilityIdentifier("case-court")
            }

            LabeledField("Status") {
                ChoiceList(
                    items: CaseStatus.allCases,
                    title: { $0 == status ? "\($0.rawValue) ✓" : $0.rawValue }
                ) { newStatus in
                    status = newStatus
                }
                .disabled(isSaving)
            }

            // Panel kancelarii nie prowadzi pola „zakres sprawy” (ustalenia są
            // w notatkach), więc poza Demo formularz o nie nie pyta.
            if tracksSummary {
                LabeledField(
                    "Zakres sprawy",
                    help: "Status sprawy nie usuwa zaplanowanych terminów ani zadań."
                ) {
                    TextEditor(text: $summary)
                        .scrollContentBackground(.hidden)
                        .emmaFieldStyle()
                        .font(EmmaTypography.body(for: summary, size: 16))
                        .frame(minHeight: 110)
                        .accessibilityLabel("Zakres sprawy")
                }
            } else {
                Text("Status sprawy nie usuwa zaplanowanych terminów ani zadań. Ustalenia dopisuj jako notatki sprawy.")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
            }

            if let errorMessage {
                InlineError(errorMessage)
            }

            PrimaryButton("Zapisz zmiany", isLoading: isSaving) {
                Task { await save(legalCase) }
            }
        }
    }

    // MARK: Profil sprawy

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormSectionLabel("Rodzaj sprawy")
            ChipFlow {
                ForEach(CaseKind.allCases) { candidate in
                    ChoiceChip(title: candidate.displayName, systemImage: candidate.systemImage, isSelected: kind == candidate) {
                        selectKind(kind == candidate ? nil : candidate)
                    }
                    .accessibilityIdentifier("case-kind-\(candidate.rawValue)")
                }
            }

            if let kind, !kind.stages.isEmpty {
                FormSectionLabel("Etap")
                ChipFlow {
                    ForEach(kind.stages) { candidate in
                        ChoiceChip(title: candidate.displayName(in: kind), isSelected: stage == candidate) {
                            selectStage(stage == candidate ? nil : candidate)
                        }
                        .accessibilityIdentifier("case-stage-\(candidate.rawValue)")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let kind, !kind.roles.isEmpty {
                FormSectionLabel("Klient w sprawie")
                ChipFlow {
                    ForEach(kind.roles) { candidate in
                        ChoiceChip(title: candidate.displayName, isSelected: role == candidate) {
                            role = role == candidate ? nil : candidate
                        }
                        .accessibilityIdentifier("case-role-\(candidate.rawValue)")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ForEach(visibleWatchKinds, id: \.self) { watch in
                watchRow(watch)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(EmmaMotion.smooth, value: kind)
        .animation(EmmaMotion.snappy, value: stage)
    }

    /// Pilnowane daty dla rodzaju sprawy. Pokrzywdzony nie siedzi w areszcie.
    private var visibleWatchKinds: [CaseWatch.Kind] {
        guard let kind else { return [] }
        return kind.watchKinds.filter { $0 != .custody || role != .victim }
    }

    private func watchRow(_ watch: CaseWatch.Kind) -> some View {
        let isOn = Binding(
            get: { watchOn[watch] ?? false },
            set: { newValue in
                withAnimation(EmmaMotion.snappy) { watchOn[watch] = newValue }
                if newValue, watchDates[watch] == nil {
                    // Areszt stosuje się najczęściej na 3 miesiące; pobyt — data do wpisania.
                    let months = watch == .custody ? 3 : 1
                    watchDates[watch] = FirmDateTime.date(
                        day: dependencies.today.addingMonths(months),
                        time: TimeOfDay(minutes: 12 * 60)!
                    )
                }
            }
        )
        let date = Binding(
            get: { watchDates[watch] ?? dependencies.now },
            set: { watchDates[watch] = $0 }
        )
        return VStack(alignment: .leading, spacing: 0) {
            FormSectionLabel(watch.displayName)
            FormCard {
                FormRow(systemImage: watch.systemImage, title: watch.fieldLabel) {
                    Toggle(watch.fieldLabel, isOn: isOn)
                        .labelsHidden()
                        .tint(EmmaTheme.accent)
                        .accessibilityIdentifier("case-watch-\(watch.rawValue)")
                }
                if isOn.wrappedValue {
                    FormDivider()
                    FormRow(systemImage: "calendar", title: "Data") {
                        DatePicker(watch.fieldLabel, selection: date, displayedComponents: .date)
                            .labelsHidden()
                            .accessibilityIdentifier("case-watch-date-\(watch.rawValue)")
                    }
                }
            }
            Text(isOn.wrappedValue
                 ? "Emma przypomni 14, 7, 3 i 1 dzień wcześniej. \(watch.hint)"
                 : "Włącz, a Emma będzie odliczać dni na „Dzisiaj” i przypominać.")
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.mutedSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.horizontal, 4)
        }
    }

    private func selectKind(_ newKind: CaseKind?) {
        kind = newKind
        // Etap i rola z innego rodzaju nie mają sensu — znikają z wyborem.
        if let stage, !(newKind?.stages.contains(stage) ?? false) { self.stage = nil }
        if let role, !(newKind?.roles.contains(role) ?? false) { self.role = nil }
    }

    private func selectStage(_ newStage: CaseStage?) {
        role = ClientRole.afterStageChange(current: role, from: stage, to: newStage)
        stage = newStage
    }

    /// Zakres sprawy istnieje tylko w danych demo.
    private var tracksSummary: Bool { dependencies.configuration.usesMockServices }

    // MARK: Wczytanie i zapis

    private func load() async {
        if !phase.hasLoaded { phase = .loading }
        do {
            guard let legalCase = try await dependencies.repository.legalCase(id: caseID) else {
                phase = .failed(LoadFailure(message: "Nie znaleziono sprawy.", isRetryable: false))
                return
            }
            if !didPrefill {
                // Zmiany podyktowane Emmie wchodzą do pól; zapis — przyciskiem.
                var prefill = legalCase
                if let seed = dependencies.pendingCaseSeed, seed.caseID == caseID {
                    prefill = seed.applied(to: legalCase)
                    dependencies.pendingCaseSeed = nil
                }
                prefillFields(from: prefill)
                didPrefill = true
            }
            phase = .loaded(legalCase)
        } catch {
            if let message = phase.recordFailure(error, fallback: "Nie udało się wczytać sprawy.") {
                dependencies.showToast(message)
            }
        }
    }

    private func prefillFields(from legalCase: LegalCase) {
        title = legalCase.title
        summary = legalCase.summary
        status = legalCase.status
        signature = legalCase.signatureText ?? ""
        court = legalCase.courtText ?? ""
        kind = legalCase.kind
        stage = legalCase.stage
        role = legalCase.clientRole
        for watch in CaseWatch.Kind.allCases {
            if let day = legalCase.watchDate(watch) {
                watchOn[watch] = true
                watchDates[watch] = FirmDateTime.date(day: day, time: TimeOfDay(minutes: 12 * 60)!)
            }
        }
    }

    private func save(_ legalCase: LegalCase) async {
        guard !isSaving else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !tracksSummary || !trimmedSummary.isEmpty else {
            errorMessage = tracksSummary ? "Nazwa i zakres nie mogą być puste." : "Nazwa sprawy nie może być pusta."
            return
        }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        var updated = legalCase
        updated.title = trimmedTitle
        updated.summary = trimmedSummary
        updated.status = status
        // Pole nieznane serwerowi (`nil`) i nieruszone zostaje `nil` — zapis nie
        // może wyczyścić sygnatury, której aplikacja nie dostała.
        let trimmedSignature = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCourt = court.trimmingCharacters(in: .whitespacesAndNewlines)
        if legalCase.courtSignature != nil || !trimmedSignature.isEmpty {
            updated.courtSignature = trimmedSignature
        }
        if legalCase.court != nil || !trimmedCourt.isEmpty {
            updated.court = trimmedCourt
        }

        updated.kind = kind
        updated.stage = stage.flatMap { kind?.stages.contains($0) == true ? $0 : nil }
        updated.clientRole = role.flatMap { kind?.roles.contains($0) == true ? $0 : nil }
        let visible = Set(visibleWatchKinds)
        func watchDay(_ watch: CaseWatch.Kind) -> LocalDate? {
            guard visible.contains(watch), watchOn[watch] == true, let date = watchDates[watch] else { return nil }
            return FirmDateTime.day(of: date)
        }
        updated.custodyUntil = watchDay(.custody)
        updated.legalStayUntil = watchDay(.legalStay)
        let clearing = CaseProfileField.cleared(from: legalCase, to: updated)

        // Błąd do formularza, nie pod arkusz (audyt 29.09.2026).
        let outcome = await dependencies.submit(fallback: "Nie udało się zapisać sprawy.") {
            try await dependencies.repository.updateCase(updated, expectedVersion: legalCase.version, clearing: clearing)
        }
        guard let saved = outcome.value else {
            errorMessage = outcome.errorMessage
            return
        }
        EmmaHaptics.success()
        // Serwer bez profilu sprawy odsyła ją bez tych pól — nie udajemy, że
        // areszt został zapisany, skoro nie będzie przypomnień.
        if !CaseProfileField.dropped(sent: updated, returned: saved).isEmpty {
            dependencies.showToast("Zapisano. Serwer nie obsługuje jeszcze rodzaju, etapu i dat sprawy.")
        }

        dependencies.dismissSheet()
    }
}
