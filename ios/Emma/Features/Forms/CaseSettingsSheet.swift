import SwiftUI

// MARK: - Arkusz „Ustawienia sprawy”
//
// Port `caseSettings()` i `saveCaseSettings()` z referencji. Zapis idzie przez
// `updateCase(_:expectedVersion:)` — bez omijania blokady optymistycznej.

struct CaseSettingsSheet: View {

    let caseID: CaseID

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var phase: LoadPhase<LegalCase> = .idle
    @State private var title = ""
    @State private var summary = ""
    @State private var status: CaseStatus = .inProgress
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

            PrimaryButton("Zapisz zmiany", isEnabled: !isSaving) {
                Task { await save(legalCase) }
            }
        }
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
                title = legalCase.title
                summary = legalCase.summary
                status = legalCase.status
                didPrefill = true
            }
            phase = .loaded(legalCase)
        } catch {
            if let message = phase.recordFailure(error, fallback: "Nie udało się wczytać sprawy.") {
                dependencies.showToast(message)
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

        // Błąd do formularza, nie pod arkusz (audyt 29.09.2026).
        let outcome = await dependencies.submit(fallback: "Nie udało się zapisać sprawy.") {
            try await dependencies.repository.updateCase(updated, expectedVersion: legalCase.version)
        }
        guard outcome.value != nil else {
            errorMessage = outcome.errorMessage
            return
        }
        EmmaHaptics.success()

        dependencies.dismissSheet()
    }
}
