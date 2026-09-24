import SwiftUI

// MARK: - Czynności na zgłoszeniu
//
// Jedno miejsce dla listy leadów, ekranu „Dzisiaj” i karty klienta.
//
// Review 24.09.2026 — ścieżka zgłoszenia była za długa: „wpada lead, trzeba go
// oznaczyć jako obsłużony, potem skonwertować na klienta, potem założyć sprawę”.
// Teraz są trzy etapy i każdy ma jedną oczywistą czynność:
//
//   1. **Do obsługi**  → skontaktuj się (telefon, WhatsApp, e-mail), umów
//                        konsultację albo zapisz notatkę — każda z tych czynności
//                        **sama** przenosi zgłoszenie do „W kontakcie”,
//   2. **W kontakcie** → „Przyjmij sprawę”: jeden formularz zakłada kartotekę
//                        i sprawę naraz (backend: `POST /cases` z `lead-N`),
//   3. **Klient**      → sprawa jest prowadzona.
//
// Osobne „Konwertuj na klienta” zniknęło — kartoteka powstaje razem ze sprawą.
// Szybka czynność nie pyta „czy na pewno” — wykonuje się od razu i daje „Cofnij”.

@MainActor
enum LeadActions {

    /// „W kontakcie”: etap `in_contact`. Cofnięcie wraca na `new` z wersją,
    /// którą oddał zapis — nie nadpisze cudzej zmiany.
    static func markInContact(
        _ client: Client,
        dependencies: AppDependencies,
        message: String? = nil
    ) async {
        guard client.stage == .new else { return }
        EmmaHaptics.success()
        // Świeża wersja: zgłoszenie mogło się zmienić od wczytania listy.
        let current = (try? await dependencies.repository.client(id: client.id)) ?? client
        guard current.stage == .new else { return }
        guard let saved = await setStage(current, to: .inContact, dependencies: dependencies) else { return }
        dependencies.showToast(
            message ?? "W kontakcie: \(client.displayName)",
            action: AppDependencies.ToastAction(title: "Cofnij") {
                Task { await LeadActions.undoInContact(saved, dependencies: dependencies) }
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

    /// Kontakt z zewnątrz aplikacji (telefon, WhatsApp, e-mail). Otwiera
    /// połączenie i — dla zgłoszenia do obsługi — przenosi je do „W kontakcie”
    /// z „Cofnij”, gdyby nikt nie odebrał.
    static func contact(
        _ client: Client,
        url: URL,
        channel: String,
        dependencies: AppDependencies,
        openURL: OpenURLAction
    ) {
        openURL(url)
        guard client.stage == .new else { return }
        Task {
            await markInContact(
                client,
                dependencies: dependencies,
                message: "\(channel) · \(client.displayName) jest teraz „W kontakcie”"
            )
        }
    }

    // MARK: Pomocnicze

    private static func undoInContact(_ saved: Client, dependencies: AppDependencies) async {
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
