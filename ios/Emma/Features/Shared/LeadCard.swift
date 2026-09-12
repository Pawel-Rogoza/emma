import SwiftUI

// MARK: - Karta leada
//
// Odtworzenie `.card.large-lead` z referencji (`clientList()` w
// `reference/prototype/app.js`): wiersz metadanych z pigułką statusu i językiem,
// wiersz osoby oraz stopkę z najbliższym terminem.
//
// Karta jest jednym przyciskiem — jak w referencji, gdzie całe `.large-lead`
// było elementem klikalnym prowadzącym do karty klienta.

struct LeadCard: View {

    @EnvironmentObject private var dependencies: AppDependencies

    private let client: Client
    private let nextEvent: ScheduledEvent?
    private let onOpen: () -> Void

    init(client: Client, nextEvent: ScheduledEvent?, onOpen: @escaping () -> Void) {
        self.client = client
        self.nextEvent = nextEvent
        self.onOpen = onOpen
    }

    var body: some View {
        Button(action: onOpen) {
            SurfaceCard(padding: EdgeInsets(top: 17, leading: 17, bottom: 17, trailing: 17)) {
                VStack(alignment: .leading, spacing: 0) {
                    metaRow
                    PersonRow(client: client, subtitle: client.topic, showsChevron: false, onOpen: nil)
                        .padding(.vertical, 11)
                        // Karta jest jednym celem dotyku; wiersz osoby nie przechwytuje tapnięcia.
                        .allowsHitTesting(false)
                    footerRow
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Otwiera kartę klienta")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Wiersze

    private var metaRow: some View {
        HStack(alignment: .center, spacing: 8) {
            StatusPill(statusPillText, kind: showsUrgentContact ? .amber : .neutral)
            Spacer(minLength: 8)
            Text(client.language.displayName)
                .font(EmmaTypography.ui(11))
                .foregroundStyle(EmmaTheme.muted)
        }
    }

    private var footerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(nextEventText)
                .font(EmmaTypography.ui(11))
                .foregroundStyle(EmmaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
        }
    }

    // MARK: Treści

    /// Referencja pokazywała pigułkę „Pilny kontakt”, gdy `urgent && needsReply`.
    /// Model domeny nie ma osobnego pola `urgent` na kliencie (`Client` w
    /// `Core/Domain/Models.swift`), więc znacznikiem pilności jest `needsReply`.
    private var showsUrgentContact: Bool { client.needsReply }

    private var statusPillText: String {
        showsUrgentContact ? "Pilny kontakt" : client.stage.displayName
    }

    private var nextEventText: String {
        guard let nextEvent else { return "Termin do ustalenia" }
        return "\(dependencies.dateText.dayLabel(nextEvent.day)), \(nextEvent.time.hhmm)"
    }

    private var accessibilityText: String {
        var parts = [client.displayName, client.topic, statusPillText, client.language.displayName]
        parts.append(nextEventText)
        return parts.joined(separator: ", ")
    }
}
