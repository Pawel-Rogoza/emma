import SwiftUI

// MARK: - Arkusz „Nowy kontakt”
//
// Port `newLead()` i `saveLead()` z referencji. Formularz trzyma własne pola,
// a zapis idzie przez `AppDependencies.perform`, żeby błąd domeny pokazał się
// jako komunikat, a nie zniknął.

struct NewLeadSheet: View {

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var name = ""
    @State private var topic = ""
    @State private var language: LanguageCode = .pl
    @State private var context = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    /// Kolejność języków z referencji: Polski, Ukraiński, Rosyjski.
    private let languages: [LanguageCode] = [.pl, .uk, .ru]

    var body: some View {
        SheetScaffold(title: "Nowy kontakt", onClose: { dependencies.dismissSheet() }) {
            VStack(alignment: .leading, spacing: 0) {
                LabeledField("Imię i nazwisko") {
                    TextField("", text: $name)
                        .emmaFieldStyle()
                        .accessibilityLabel("Imię i nazwisko")
                }

                LabeledField("Temat zgłoszenia") {
                    TextField("", text: $topic)
                        .emmaFieldStyle()
                        .accessibilityLabel("Temat zgłoszenia")
                }

                LabeledField("Język") {
                    SegmentedFilter(items: languages, selection: $language, title: { $0.displayName })
                }

                LabeledField("Kontekst zgłoszenia") {
                    TextEditor(text: $context)
                        .scrollContentBackground(.hidden)
                        .emmaFieldStyle()
                        .font(EmmaTypography.body(for: context, size: 16))
                        .frame(minHeight: 110)
                        .accessibilityLabel("Kontekst zgłoszenia")
                }

                if let errorMessage {
                    InlineError(errorMessage)
                }

                PrimaryButton("Dodaj kontakt", isEnabled: !isSaving) {
                    Task { await save() }
                }
            }
        }
    }

    // MARK: Zapis

    private func save() async {
        guard !isSaving else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedTopic.isEmpty else {
            errorMessage = "Uzupełnij imię i temat zgłoszenia."
            return
        }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let draft = NewClientDraft(
            displayName: trimmedName,
            topic: trimmedTopic,
            language: language,
            context: context.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .manual,
            createdAt: dependencies.today
        )

        let created = await dependencies.perform {
            try await dependencies.repository.createClient(draft)
        }
        guard let created else { return }

        dependencies.dismissSheet()
        dependencies.openPerson(created.id)
    }
}
