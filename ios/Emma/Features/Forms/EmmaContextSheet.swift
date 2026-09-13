import SwiftUI

// MARK: - Wybór kontekstu Emmy (`chooseContext` / `setEmmaContext`)
//
// Arkusz odpowiada `chooseContext(action)` z referencji: lista „Cała kancelaria”
// oraz wszystkich klientów z ich tematem. Wybór ustawia `emmaContext`, zamyka
// arkusz, a jeśli arkusz otwarto z konkretnym skrótem — uruchamia ten skrót
// (`setEmmaContext(id, action)` → `assistantExample(action)`).

@MainActor
struct EmmaContextSheet: View {

    /// Skrót do wykonania po wybraniu kontekstu (odpowiada `action` w referencji).
    private let action: EmmaQuickAction?

    @EnvironmentObject private var dependencies: AppDependencies
    @State private var clients: [Client] = []

    init(action: EmmaQuickAction?) {
        self.action = action
    }

    var body: some View {
        SheetScaffold(
            title: "Wybierz kontekst Emmy",
            onClose: { dependencies.dismissSheet() }
        ) {
            // Referencja ukrywa „Całą kancelarię”, gdy arkusz otwarto z konkretnym
            // skrótem: bez klienta skrót (odpowiedź, notatka, zadanie) nie ma adresata.
            if action == nil {
                ChoiceList(
                    items: firmOptions,
                    title: { _ in AssistantContext.firm.displayLabel },
                    subtitle: { _ in "Plan dnia i kolejne kroki" }
                ) { _ in
                    select(nil)
                }
                .padding(.bottom, EmmaSpacing.cardGap)
            }

            ChoiceList(
                items: clients,
                title: { $0.displayName },
                subtitle: { client in
                    let stage = client.stage.rawValue
                    return client.topic.isEmpty ? stage : "\(client.topic) · \(stage)"
                }
            ) { client in
                select(client.id)
            }

            Text("Emma pracuje na danych przykładowych. Rozmowa głosowa w tej wersji jest demonstracyjna — bez kont dostawców.")
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.mutedSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .task {
            clients = (try? await dependencies.repository.clients(matching: "", stage: nil)) ?? []
        }
    }

    /// Lista jednoelementowa, aby użyć tego samego komponentu co dla klientów.
    private var firmOptions: [ClientID?] { [nil] }

    private func select(_ clientID: ClientID?) {
        dependencies.emmaContext = clientID
        dependencies.dismissSheet()
        if let action {
            // Arkusz otwarty ze skrótem: po wyborze kontekstu wracamy na ekran Emmy
            // i tam wykonujemy skrót (`pendingEmmaAction`).
            dependencies.openEmma(clientID: clientID, action: action)
        }
    }
}

#Preview("Wybór kontekstu Emmy") {
    EmmaContextSheet(action: nil)
        .environmentObject(AppDependencies.demo())
}
