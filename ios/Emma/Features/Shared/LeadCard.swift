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
    private let onSetStage: ((ClientStage) -> Void)?
    private let onRename: (() -> Void)?

    init(
        client: Client,
        nextEvent: ScheduledEvent?,
        onOpen: @escaping () -> Void,
        onSetStage: ((ClientStage) -> Void)? = nil,
        onRename: (() -> Void)? = nil
    ) {
        self.client = client
        self.nextEvent = nextEvent
        self.onOpen = onOpen
        self.onSetStage = onSetStage
        self.onRename = onRename
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
        .contextMenu {
            contextMenuItems
        }
        // Identyfikator dla testów: etykieta niesie treść dla VoiceOver i zmienia
        // się razem z danymi, więc nie da się po niej stabilnie znaleźć karty.
        .accessibilityIdentifier("lead-card")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Otwiera kartę klienta. Przytrzymaj, aby przenieść lub zmienić nazwę.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Menu po przytrzymaniu

    /// Menu zbiera to, co backend naprawdę potrafi przyjąć: zmianę etapu
    /// (wejście na „Klient" konwertuje zgłoszenie w kartotekę) i zmianę nazwy.
    /// Usuwania nie ma — kontrakt mobilny nie zna `DELETE` dla kontaktu, więc
    /// nie udajemy, że jest.
    @ViewBuilder
    private var contextMenuItems: some View {
        if let onSetStage, client.stage != .client {
            ForEach(stageTargets, id: \.self) { stage in
                Button {
                    onSetStage(stage)
                } label: {
                    Label(stageActionLabel(stage), systemImage: stageIcon(stage))
                }
            }
        }
        if let onRename {
            Button {
                onRename()
            } label: {
                Label("Zmień nazwę", systemImage: "pencil")
            }
        }
        Button {
            onOpen()
        } label: {
            Label("Otwórz kartę", systemImage: "arrow.up.forward.square")
        }
    }

    private var stageTargets: [ClientStage] {
        [.new, .inContact, .client].filter { $0 != client.stage }
    }

    private func stageActionLabel(_ stage: ClientStage) -> String {
        switch stage {
        case .new: return "Przenieś do: nowe"
        case .inContact: return "Przenieś do: w kontakcie"
        case .client: return "Przenieś do: klient"
        }
    }

    private func stageIcon(_ stage: ClientStage) -> String {
        switch stage {
        case .new: return "tray.and.arrow.down"
        case .inContact: return "bubble.left.and.bubble.right"
        case .client: return "person.crop.circle.badge.checkmark"
        }
    }

    // MARK: Wiersze

    private var metaRow: some View {
        HStack(alignment: .center, spacing: 8) {
            StatusPill(statusPillText, kind: showsUrgentContact ? .amber : .neutral)
            Spacer(minLength: 8)
            Text(client.language.displayName)
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.muted)
        }
    }

    private var footerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(nextEventText)
                .font(EmmaTypography.caption())
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

    /// Stopka mówi, co jest do zrobienia. Gdy nie ma terminu, zamiast pustego
    /// „Termin do ustalenia" pokazujemy datę zgłoszenia — przy rezerwacji ze
    /// strony to najważniejsza informacja: jak długo zgłoszenie czeka.
    private var nextEventText: String {
        guard let nextEvent else {
            // `dayLabel` oddaje „Dzisiaj”/„Wczoraj” wielką literą, bo stoi na
            // początku zdania — tutaj jest w środku, więc zmniejszamy pierwszą.
            let label = dependencies.dateText.dayLabel(client.createdAt)
            let lowered = label.prefix(1).lowercased() + label.dropFirst()
            return "Zgłoszono \(lowered)"
        }
        return "\(dependencies.dateText.dayLabel(nextEvent.day)), \(nextEvent.time.hhmm)"
    }

    private var accessibilityText: String {
        var parts = [client.displayName, client.topic, statusPillText, client.language.displayName]
        parts.append(nextEventText)
        return parts.joined(separator: ", ")
    }
}
