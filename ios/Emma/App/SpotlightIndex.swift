import CoreSpotlight
import UniformTypeIdentifiers

// MARK: - Wyszukiwanie spraw w Spotlight
//
// Karnista pamięta sygnaturę albo nazwisko, nie zakładkę w aplikacji:
// „II K 123/26” wpisane w wyszukiwarkę iPhone'a otwiera sprawę, nazwisko —
// kartę klienta. Otwarcie idzie przez `HomeScreenQuickActions`, więc czeka
// na Face ID jak każde wejście z zewnątrz.
//
// Tajemnica adwokacka: indeks ma klasę ochrony `.complete` — przy
// zablokowanym telefonie system nie może go odczytać, więc nazwiska nie
// pojawiają się w wynikach na ekranie blokady. Wylogowanie kasuje indeks.
// W Demo i w testach interfejsu indeks jest wyłączony.

@MainActor
final class SpotlightIndex {

    static let casePrefix = "case:"
    static let clientPrefix = "client:"

    private let isEnabled: Bool
    private let index = CSSearchableIndex(name: "emma.records", protectionClass: .complete)
    /// Odcisk ostatnio zindeksowanych danych — odświeżenie dnia bez zmian
    /// w sprawach nie przepisuje indeksu.
    private var lastFingerprint: Int?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func update(cases: [LegalCase], clients: [Client]) {
        guard isEnabled else { return }
        var hasher = Hasher()
        hasher.combine(cases)
        hasher.combine(clients.map { [$0.id.rawValue, $0.displayName, $0.phone ?? ""] })
        let fingerprint = hasher.finalize()
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint

        let names = Dictionary(clients.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        var items: [CSSearchableItem] = []
        for legalCase in cases {
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = legalCase.title
            let client = names[legalCase.clientID]
            attributes.contentDescription = [legalCase.signatureText ?? legalCase.number, legalCase.courtText, client]
                .compactMap { $0 }
                .joined(separator: " · ")
            attributes.keywords = [legalCase.signatureText, legalCase.number, client, legalCase.kind?.displayName]
                .compactMap { $0 }
            items.append(CSSearchableItem(
                uniqueIdentifier: Self.casePrefix + legalCase.id.rawValue,
                domainIdentifier: "cases",
                attributeSet: attributes
            ))
        }
        for client in clients where client.stage == .client {
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = client.displayName
            attributes.contentDescription = client.topic
            attributes.keywords = [client.phone].compactMap { $0 }
            items.append(CSSearchableItem(
                uniqueIdentifier: Self.clientPrefix + client.id.rawValue,
                domainIdentifier: "clients",
                attributeSet: attributes
            ))
        }
        let index = self.index
        // Najpierw czyścimy: zamknięta czy usunięta sprawa nie może zostać w wynikach.
        index.deleteAllSearchableItems { _ in
            index.indexSearchableItems(items) { _ in }
        }
    }

    /// Koniec sesji — indeks z nazwiskami nie przeżywa wylogowania.
    func removeAll() {
        lastFingerprint = nil
        index.deleteAllSearchableItems { _ in }
    }
}
