import SwiftUI

// MARK: - Czynności na zgłoszeniu
//
// Jedno miejsce dla listy leadów, ekranu „Dzisiaj” i karty klienta. Wcześniej
// przeniesienie etapu żyło tylko w menu po przytrzymaniu na liście, więc
// z karty klienta nie dało się zgłoszenia „odhaczyć”.
//
// Zasada: szybka czynność nie pyta „czy na pewno” — wykonuje się od razu
// i daje „Cofnij” w komunikacie. Pytamy wyłącznie o to, czego cofnąć się nie da
// (konwersja w kartotekę zakłada rekord klienta, usunięcie jest nieodwracalne).

@MainActor
enum LeadActions {

    /// „Obsłużone”: etap `in_contact`. Cofnięcie wraca na `new` z wersją,
    /// którą oddał zapis — nie nadpisze cudzej zmiany.
    static func markHandled(_ client: Client, dependencies: AppDependencies) async {
        guard client.stage == .new else { return }
        EmmaHaptics.success()
        guard let saved = await setStage(client, to: .inContact, dependencies: dependencies) else { return }
        dependencies.showToast(
            "Obsłużone: \(client.displayName)",
            action: AppDependencies.ToastAction(title: "Cofnij") {
                Task { await LeadActions.undoHandled(saved, dependencies: dependencies) }
            }
        )
    }

    /// Powrót do kolejki „Do obsługi” (np. trzeba jednak oddzwonić).
    static func reopen(_ client: Client, dependencies: AppDependencies) async {
        guard client.stage == .inContact else { return }
        EmmaHaptics.tap()
        guard let saved = await setStage(client, to: .new, dependencies: dependencies) else { return }
        dependencies.showToast(
            "Przywrócono do obsługi: \(client.displayName)",
            action: AppDependencies.ToastAction(title: "Cofnij") {
                Task { await LeadActions.setStage(saved, to: .inContact, dependencies: dependencies) }
            }
        )
    }

    /// Konwersja w kartotekę. Wywoływana dopiero po potwierdzeniu w interfejsie.
    static func convertToClient(_ client: Client, dependencies: AppDependencies) async {
        guard client.stage != .client else { return }
        guard await setStage(client, to: .client, dependencies: dependencies) != nil else { return }
        EmmaHaptics.success()
        dependencies.showToast("\(client.displayName) jest teraz klientem kancelarii.")
    }

    // MARK: Pomocnicze

    private static func undoHandled(_ saved: Client, dependencies: AppDependencies) async {
        EmmaHaptics.tap()
        await setStage(saved, to: .new, dependencies: dependencies)
    }

    /// Zapis etapu przez repozytorium. Błąd pokazuje `perform` (komunikat),
    /// a wynik `nil` znaczy, że nic się nie zmieniło.
    @discardableResult
    private static func setStage(
        _ client: Client,
        to stage: ClientStage,
        dependencies: AppDependencies
    ) async -> Client? {
        var draft = client
        draft.stage = stage
        let updated = draft
        return await dependencies.perform {
            try await dependencies.repository.updateClient(updated, expectedVersion: client.version)
        }
    }
}
