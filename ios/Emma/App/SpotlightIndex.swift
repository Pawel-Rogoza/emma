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
    nonisolated private static let indexName = "emma.records"

    /// Jeden wynik w wyszukiwarce — same teksty (`Sendable`), obiekty
    /// CoreSpotlight powstają dopiero przy zapisie, poza głównym wątkiem.
    private struct Entry: Hashable, Sendable {
        let identifier: String
        let domain: String
        let title: String
        let description: String
        let keywords: [String]
    }

    private let isEnabled: Bool
    /// Odcisk ostatnio zindeksowanych danych — odświeżenie dnia bez zmian
    /// w sprawach nie przepisuje indeksu.
    private var lastFingerprint: Int?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func update(cases: [LegalCase], clients: [Client]) {
        guard isEnabled else { return }
        let names = Dictionary(clients.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        var entries: [Entry] = []
        for legalCase in cases {
            let client = names[legalCase.clientID]
            entries.append(Entry(
                identifier: Self.casePrefix + legalCase.id.rawValue,
                domain: "cases",
                title: legalCase.title,
                description: [legalCase.signatureText ?? legalCase.number, legalCase.courtText, client]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                keywords: [legalCase.signatureText, legalCase.number, client, legalCase.kind?.displayName]
                    .compactMap { $0 }
            ))
        }
        for client in clients where client.stage == .client {
            entries.append(Entry(
                identifier: Self.clientPrefix + client.id.rawValue,
                domain: "clients",
                title: client.displayName,
                description: client.topic,
                keywords: [client.phone].compactMap { $0 }
            ))
        }
        let fingerprint = entries.hashValue
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        Task.detached { await Self.reindex(entries) }
    }

    /// Koniec sesji — indeks z nazwiskami nie przeżywa wylogowania.
    func removeAll() {
        lastFingerprint = nil
        Task.detached { await Self.reindex([]) }
    }

    /// Najpierw czyścimy: zamknięta czy usunięta sprawa nie może zostać w wynikach.
    nonisolated private static func reindex(_ entries: [Entry]) async {
        let index = CSSearchableIndex(name: indexName, protectionClass: .complete)
        try? await index.deleteAllSearchableItems()
        guard !entries.isEmpty else { return }
        let items = entries.map { entry in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = entry.title
            attributes.contentDescription = entry.description
            attributes.keywords = entry.keywords
            return CSSearchableItem(uniqueIdentifier: entry.identifier, domainIdentifier: entry.domain, attributeSet: attributes)
        }
        try? await index.indexSearchableItems(items)
    }
}
