import SwiftUI

// MARK: - Arkusz „Przyjmij sprawę”
//
// Port `caseForm()` i `saveCase()` z referencji. Review 24.09.2026: to jest
// teraz **jedyny** krok od zgłoszenia do klienta — wcześniej były dwa
// („Konwertuj na klienta”, potem „Rozpocznij prowadzenie sprawy”). Backend
// (`POST /cases` z `lead-N`) zakłada kartotekę i sprawę jednym zapisem;
// repozytorium demo robi to samo. Zakres jest opcjonalny — nazwa wystarczy.

struct StartCaseSheet: View {

    let clientID: ClientID

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var phase: LoadPhase<Client> = .idle
    @State private var title = ""
    @State private var summary = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    /// Pola wypełniamy raz, przy pierwszym wczytaniu — później nie nadpisujemy
    /// tego, co już wpisał użytkownik.
    @State private var didPrefill = false

    var body: some View {
        SheetScaffold(title: "Przyjmij sprawę", onClose: { dependencies.dismissSheet() }) {
            content
                .task(id: dependencies.dataVersion) { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            LoadingState("Wczytuję dane klienta…")
        case .failed(let failure):
            LoadFailureView(failure) {
                Task { await load() }
            }
        case .loaded(let client):
            form(client)
        }
    }

    private func form(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Nagłówek osoby bez chevronu — kontekst formularza (`.form-person`).
            PersonRow(client: client, subtitle: client.topic, showsChevron: false, onOpen: nil)
                .padding(.top, 7)
                .padding(.bottom, 20)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(EmmaTheme.infoRowBorder)
                        .frame(height: 1)
                }
                .padding(.bottom, 10)

            if client.stage != .client {
                Label("Powstanie kartoteka klienta i sprawa. Dotychczasowe notatki i terminy zostaną przy kliencie.", systemImage: "info.circle")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
            }

            LabeledField("Nazwa sprawy") {
                TextField("np. Legalizacja pobytu", text: $title)
                    .emmaFieldStyle()
                    .accessibilityLabel("Nazwa sprawy")
            }

            LabeledField(
                "Zakres i ustalenia (opcjonalnie)",
                help: "Trafi do notatki sprawy."
            ) {
                TextEditor(text: $summary)
                    .scrollContentBackground(.hidden)
                    .emmaFieldStyle()
                    .font(EmmaTypography.body(for: summary, size: 16))
                    .frame(minHeight: 110)
                    .accessibilityLabel("Zakres i ustalenia")
            }

            if let errorMessage {
                InlineError(errorMessage)
            }

            PrimaryButton("Przyjmij sprawę", systemImage: "folder.badge.plus", isEnabled: !isSaving) {
                Task { await save(client) }
            }
            .accessibilityIdentifier("case-accept-save")
        }
    }

    // MARK: Wczytanie i zapis

    private func load() async {
        if !phase.hasLoaded { phase = .loading }
        do {
            let repository = dependencies.repository
            if let existing = try await repository.caseForClient(clientID) {
                // Jedna aktywna sprawa na klienta — zamiast tworzyć drugą, otwieramy istniejącą.
                dependencies.dismissSheet()
                dependencies.openCase(existing.id)
                return
            }
            guard let client = try await repository.client(id: clientID) else {
                phase = .failed(LoadFailure(message: "Nie znaleziono klienta.", isRetryable: false))
                return
            }
            if !didPrefill {
                title = LeadTopic.parse(client.topic).text
                summary = LeadTopic.parse(client.briefing).text
                didPrefill = true
            }
            phase = .loaded(client)
        } catch {
            if let message = phase.recordFailure(error, fallback: "Nie udało się wczytać danych klienta.") {
                dependencies.showToast(message)
            }
        }
    }

    private func save(_ client: Client) async {
        guard !isSaving else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.count >= 3 else {
            errorMessage = "Nazwij sprawę — co najmniej 3 znaki."
            return
        }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let draft = NewCaseDraft(
            clientID: client.id,
            title: trimmedTitle,
            summary: trimmedSummary,
            createdAt: dependencies.today
        )

        let outcome = await dependencies.submit(fallback: "Nie udało się przyjąć sprawy.") {
            try await dependencies.repository.createCase(draft)
        }
        guard let created = outcome.value else {
            errorMessage = outcome.errorMessage
            return
        }
        EmmaHaptics.success()
        dependencies.showToast("\(client.displayName) jest klientem kancelarii. Sprawa założona.")

        // Referencja po utworzeniu sprawy przełącza listę klientów na „Sprawy”
        // i otwiera nową sprawę.
        dependencies.clientMode = .cases
        dependencies.dismissSheet()
        dependencies.openCase(created.id)
    }
}
