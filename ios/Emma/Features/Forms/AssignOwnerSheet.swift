import SwiftUI

// MARK: - Arkusz „Opiekun klienta”
//
// Port `assignPerson()` i `savePersonOwner()` z referencji. Wybór opiekuna
// zapisujemy przez repozytorium z `expectedVersion` — zmiana opiekuna klienta
// **nie** przenosi przypisań istniejących terminów (potwierdza to komunikat).

struct AssignOwnerSheet: View {

    let clientID: ClientID

    @EnvironmentObject private var dependencies: AppDependencies

    @State private var phase: LoadPhase<Client> = .idle
    @State private var isSaving = false

    var body: some View {
        SheetScaffold(title: "Opiekun klienta", onClose: { dependencies.dismissSheet() }) {
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
            VStack(alignment: .leading, spacing: 0) {
                // Imię i nazwisko klienta może zawierać cyrylicę — czcionka zależna od pisma.
                Text(client.displayName)
                    .font(EmmaTypography.body(for: client.displayName, size: 14))
                    .foregroundStyle(EmmaTheme.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 19)

                ChoiceList(
                    items: OwnerOption.allCases,
                    title: { $0.title(current: client.ownerID) }
                ) { option in
                    Task { await assign(option, to: client) }
                }
                .disabled(isSaving)
            }
        }
    }

    // MARK: Wczytanie i zapis

    private func load() async {
        if !phase.hasLoaded { phase = .loading }
        do {
            guard let client = try await dependencies.repository.client(id: clientID) else {
                phase = .failed(LoadFailure(message: "Nie znaleziono klienta.", isRetryable: false))
                return
            }
            phase = .loaded(client)
        } catch {
            phase = .failed(ScreenLoad.failure(for: error, fallback: "Nie udało się wczytać danych klienta."))
        }
    }

    private func assign(_ option: OwnerOption, to client: Client) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let updated = await dependencies.perform {
            try await dependencies.repository.assignOwner(
                clientID: client.id,
                ownerID: option.userID,
                expectedVersion: client.version
            )
        }
        guard updated != nil else { return }

        dependencies.dismissSheet()
        dependencies.showToast("Zmieniono opiekuna klienta. Terminy mają własne przypisania.")
    }
}

// MARK: - Wybór opiekuna

/// Wspólny wybór opiekuna dla formularzy: opiekun klienta, prowadzący sprawę.
/// `nil` oznacza „Nieprzypisany” — w domenie nie ma magicznego użytkownika.
enum OwnerOption: Hashable, CaseIterable, Identifiable {

    case unassigned
    case tomasz
    case pawel

    var id: Self { self }

    var userID: UserID? {
        switch self {
        case .unassigned: return nil
        case .tomasz: return UserID.tomasz
        case .pawel: return UserID.pawel
        }
    }

    var title: String {
        switch self {
        case .unassigned: return OwnerName.unassigned
        case .tomasz: return OwnerName.of(UserID.tomasz)
        case .pawel: return OwnerName.of(UserID.pawel)
        }
    }

    init(userID: UserID?) {
        if let userID, userID == UserID.tomasz {
            self = .tomasz
        } else if let userID, userID == UserID.pawel {
            self = .pawel
        } else {
            self = .unassigned
        }
    }

    /// Etykieta wiersza. `ChoiceList` rysuje na końcu chevron, więc bieżący wybór
    /// oznaczamy znakiem „✓” w tytule wiersza — dokładnie tam, gdzie referencja
    /// pokazywała `ic('check')`.
    func title(current: UserID?) -> String {
        userID == current ? "\(title) ✓" : title
    }
}
