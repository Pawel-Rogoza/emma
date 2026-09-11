import SwiftUI

// MARK: - Arkusz „Rozpocznij prowadzenie sprawy”
//
// Port `caseForm()` i `saveCase()` z referencji. Repozytorium samo promuje
// kontakt do etapu „Klient”, przypisuje luźne notatki, zadania i terminy oraz
// odmawia utworzenia drugiej sprawy dla tego samego klienta.

struct StartCaseSheet: View {

    let clientID: ClientID

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var phase: LoadPhase<Client> = .idle
    @State private var title = ""
    @State private var summary = ""
    @State private var ownerID: UserID = UserID.tomasz
    @State private var errorMessage: String?
    @State private var isSaving = false
    /// Pola wypełniamy raz, przy pierwszym wczytaniu — później nie nadpisujemy
    /// tego, co już wpisał użytkownik.
    @State private var didPrefill = false

    var body: some View {
        SheetScaffold(title: "Rozpocznij prowadzenie sprawy", onClose: { dependencies.dismissSheet() }) {
            content
                .task(id: dependencies.dataVersion) { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            LoadingState("Wczytuję dane klienta…")
        case .failed(let message):
            InlineError(message)
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

            LabeledField("Nazwa sprawy") {
                TextField("", text: $title)
                    .emmaFieldStyle()
                    .accessibilityLabel("Nazwa sprawy")
            }

            LabeledField("Prowadzący") {
                SegmentedFilter(items: UserID.both, selection: $ownerID, title: { OwnerName.of($0) })
            }

            LabeledField(
                "Zakres i ustalenia",
                help: "Kontakt, konsultacje i dotychczasowe notatki zostaną powiązane z tą sprawą."
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

            PrimaryButton("Utwórz sprawę", systemImage: "folder", isEnabled: !isSaving) {
                Task { await save(client) }
            }
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
                phase = .failed("Nie znaleziono klienta.")
                return
            }
            if !didPrefill {
                title = client.topic
                summary = client.briefing
                // Domyślnie prowadzi opiekun klienta; nowy klient nie ma opiekuna,
                // więc proponujemy zalogowanego adwokata (jak `data.user` w referencji).
                ownerID = client.ownerID ?? dependencies.currentUser.id
                didPrefill = true
            }
            phase = .loaded(client)
        } catch {
            phase = .failed(ScreenLoad.message(for: error, fallback: "Nie udało się wczytać danych klienta."))
        }
    }

    private func save(_ client: Client) async {
        guard !isSaving else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedSummary.isEmpty else {
            errorMessage = "Uzupełnij nazwę i zakres sprawy."
            return
        }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let draft = NewCaseDraft(
            clientID: client.id,
            title: trimmedTitle,
            summary: trimmedSummary,
            ownerID: ownerID,
            createdAt: dependencies.today
        )

        let created = await dependencies.perform {
            try await dependencies.repository.createCase(draft)
        }
        guard let created else { return }

        // Referencja po utworzeniu sprawy przełącza listę klientów na „Sprawy”
        // i otwiera nową sprawę.
        dependencies.clientMode = .cases
        dependencies.dismissSheet()
        dependencies.openCase(created.id)
    }
}
