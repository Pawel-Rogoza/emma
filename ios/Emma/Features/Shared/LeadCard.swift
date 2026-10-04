import SwiftUI

// MARK: - Karta leada
//
// Przebudowa z review 23.09.2026. Karta odpowiada na trzy pytania w tej
// kolejności, w jakiej zadaje je prawnik:
//
//   1. **Czy to czeka?** — kolorowy pasek z lewej i plakietka „Nowy · 3 godz.
//      temu” / „Oczekuje · 2 dni” / „W kontakcie” (reguła w `LeadWorkflow`),
//   2. **Kto i w jakiej sprawie?** — osoba i temat bez surowego prefiksu
//      „Termin: 2026-09-15 20:00”, który z formularza trafiał na początek tematu,
//   3. **Kiedy chce rozmawiać?** — termin z rezerwacji jako osobna linia.
//
// Po prawej jest okrągły przycisk „W kontakcie” — ten sam gest co odhaczenie
// zadania. Karta sama jest przyciskiem otwierającym kartę klienta; przycisk
// obsłużenia leży obok niej (nie w środku), żeby dotknięcia się nie myliły.

/// Wygląd stanu zgłoszenia: kolor paska, kropki i plakietki.
enum LeadStatusStyle {
    static func tone(_ status: LeadStatus) -> Color {
        switch status {
        case .fresh: return EmmaTheme.accent
        case .waiting: return EmmaTheme.pillAmberText
        case .inContact: return EmmaTheme.pillGreenText
        case .client: return EmmaTheme.mutedSoft
        }
    }

    static func pillKind(_ status: LeadStatus) -> StatusPill.Kind {
        switch status {
        case .fresh, .client: return .neutral
        case .waiting: return .amber
        case .inContact: return .green
        }
    }

    /// Temat do pokazania: bez prefiksu rezerwacji, a gdy nic nie zostało —
    /// opis zastępczy zamiast pustej linii.
    static func topicText(_ topic: LeadTopic) -> String {
        if !topic.text.isEmpty { return topic.text }
        return topic.booking == nil ? "Bez opisu zgłoszenia" : "Rezerwacja konsultacji"
    }

    /// „Termin z rezerwacji: Jutro, 10:00”; termin, który już minął, mówi to wprost.
    /// Z wariantem rezerwacji: „Konsultacja: Jutro, 10:00 · 60 min · 490 zł”.
    static func bookingText(
        _ booking: LeadBooking,
        consultation: ConsultationRequest? = nil,
        dateText: DateTextFormatter,
        today: LocalDate
    ) -> String {
        let variant = consultation?.variantText
        var text = (variant == nil ? "Termin z rezerwacji: " : "Konsultacja: ") + dateText.dayLabel(booking.day)
        if let time = booking.time {
            text += ", \(time.hhmm)"
        }
        if let variant {
            text += " · \(variant)"
        }
        if booking.day < today {
            text += " · minął"
        }
        return text
    }

    /// Linia rezerwacji dla zgłoszenia: termin z wariantem, a bez terminu —
    /// sam wariant („Konsultacja 60 min · 490 zł”).
    static func consultationLine(for client: Client, dateText: DateTextFormatter, today: LocalDate) -> String? {
        if let booking = LeadWorkflow.booking(of: client) {
            return bookingText(booking, consultation: client.consultation, dateText: dateText, today: today)
        }
        return client.consultation?.variantText.map { "Konsultacja \($0)" }
    }
}

/// Plakietka stanu z kropką: „● Oczekuje · 2 dni”.
struct LeadStatusBadge: View {
    let status: LeadStatus
    let text: String

    var body: some View {
        let colors = LeadStatusStyle.pillKind(status).colors
        HStack(spacing: 6) {
            Circle()
                .fill(LeadStatusStyle.tone(status))
                .frame(width: 6, height: 6)
            Text(text)
                .font(EmmaTypography.pill)
                .foregroundStyle(colors.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(colors.background)
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.pill, style: .continuous))
    }
}

/// Okrągły przycisk „obsłużone” — ten sam gest co odhaczenie zadania.
///
/// W stanie nieodhaczonym ptaszek jest widoczny, ale blady: podpowiada, co się
/// stanie po dotknięciu, zamiast udawać pole do wypełnienia.
struct LeadCheckButton: View {
    let isDone: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isDone ? EmmaTheme.pillGreenText : EmmaTheme.surface)
                Circle()
                    .strokeBorder(EmmaTheme.pillGreenText.opacity(isDone ? 0 : 0.45), lineWidth: 1.6)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isDone ? EmmaTheme.primaryButtonText : EmmaTheme.pillGreenText.opacity(0.5))
                    .symbolEffect(.bounce, value: isDone)
            }
            .frame(width: 30, height: 30)
            .frame(width: EmmaSpacing.hitTarget, height: EmmaSpacing.hitTarget)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.62), value: isDone)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(isDone ? "Przywróć do obsługi" : "Oznacz jako w kontakcie")
        .accessibilityIdentifier("lead-check")
    }
}

struct LeadCard: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.openURL) private var openURL

    private let client: Client
    private let nextEvent: ScheduledEvent?
    private let onOpen: () -> Void
    private let onMarkHandled: (() async -> Void)?
    private let onReopen: (() async -> Void)?
    private let onRename: (() -> Void)?
    private let onDelete: (() -> Void)?
    /// Rozmowa WhatsApp zgłoszenia — nowy numer, który sam napisał, jest leadem.
    private let conversation: MessagesStore.Row?
    private let onOpenConversation: ((ThreadID) -> Void)?

    /// Natychmiastowe „odhaczenie”, zanim wróci zapis — odpowiedź na dotknięcie
    /// nie może czekać na sieć.
    @State private var isMarking = false

    init(
        client: Client,
        nextEvent: ScheduledEvent?,
        onOpen: @escaping () -> Void,
        onMarkHandled: (() async -> Void)? = nil,
        onReopen: (() async -> Void)? = nil,
        onRename: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        conversation: MessagesStore.Row? = nil,
        onOpenConversation: ((ThreadID) -> Void)? = nil
    ) {
        self.conversation = conversation
        self.onOpenConversation = onOpenConversation
        self.client = client
        self.nextEvent = nextEvent
        self.onOpen = onOpen
        self.onMarkHandled = onMarkHandled
        self.onReopen = onReopen
        self.onRename = onRename
        self.onDelete = onDelete
    }

    var body: some View {
        let status = LeadWorkflow.status(of: client, now: dependencies.now)
        ZStack(alignment: .trailing) {
            Button(action: onOpen) {
                cardContent(status)
            }
            .buttonStyle(EmmaCardButtonStyle())
            .contextMenu { contextMenuItems(status) }
            // Identyfikator dla testów: etykieta niesie treść dla VoiceOver i zmienia
            // się razem z danymi, więc nie da się po niej stabilnie znaleźć karty.
            .accessibilityIdentifier("lead-card")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(status))
            .accessibilityHint("Otwiera kartę klienta. Przytrzymaj, aby zobaczyć więcej czynności.")
            .accessibilityAddTraits(.isButton)

            if status != .client {
                LeadCheckButton(isDone: isMarking || status == .inContact, isBusy: isMarking) {
                    toggleHandled(status)
                }
                .padding(.trailing, 6)
            }
        }
    }

    // MARK: Treść

    private func cardContent(_ status: LeadStatus) -> some View {
        let topic = LeadTopic.parse(client.topic)
        let topicText = LeadStatusStyle.topicText(topic)
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 8) {
                LeadStatusBadge(
                    status: status,
                    text: LeadWorkflow.badgeText(for: client, now: dependencies.now, today: dependencies.today)
                )
                Spacer(minLength: 8)
                LanguageBadge(language: client.language)
            }

            HStack(alignment: .center, spacing: 12) {
                PersonAvatar(initials: client.initials, style: .identity(client.id))
                VStack(alignment: .leading, spacing: 3) {
                    Text(client.displayName)
                        .font(EmmaTypography.personName)
                        .foregroundStyle(EmmaTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(topicText)
                        .font(EmmaTypography.body(for: topicText, size: 13))
                        .foregroundStyle(EmmaTheme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Co klient napisał na WhatsApp — zanim adwokat oddzwoni, wie, o co chodzi.
            if let message = customerMessage {
                HStack(alignment: .top, spacing: 9) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(EmmaTheme.quoteRule)
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversationLabel)
                            .font(EmmaTypography.caption(.semibold))
                            .foregroundStyle((conversation?.unreadCount ?? 0) > 0 ? EmmaTheme.unreadBadge : EmmaTheme.mutedSoft)
                        Text(message)
                            .font(EmmaTypography.body(for: message, size: 13))
                            .foregroundStyle(EmmaTheme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            if let footer = footerLine(topic) {
                HStack(spacing: 6) {
                    Image(systemName: footer.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                    Text(footer.text)
                        .font(EmmaTypography.caption(.medium))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(footer.isSoon ? EmmaTheme.accent : EmmaTheme.mutedSoft)
            }
        }
        .padding(.leading, 20)
        // Miejsce na przycisk „obsłużone” po prawej — treść nie wchodzi pod niego.
        .padding(.trailing, status == .client ? 17 : 50)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EmmaTheme.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(LeadStatusStyle.tone(status))
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
        }
        .emmaCardShadow()
        .contentShape(Rectangle())
    }

    /// Ostatnia wiadomość klienta (nie nasza odpowiedź).
    private var customerMessage: String? {
        guard let preview = conversation?.preview, !preview.isOutgoing else { return nil }
        let text = preview.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// „WhatsApp · 2 nowe · czeka 20 min”.
    private var conversationLabel: String {
        var parts = ["WhatsApp"]
        if let unread = conversation?.unreadCount, unread > 0 {
            parts.append(EmmaPlural.label(unread, "nowa", "nowe", "nowych"))
        }
        if let since = conversation?.waitingSince {
            parts.append("czeka \(ConversationInbox.waitingText(since: since, now: dependencies.now))")
        }
        return parts.joined(separator: " · ")
    }

    private struct Footer {
        let systemImage: String
        let text: String
        /// Dziś albo jutro — wtedy linia jest wyróżniona.
        let isSoon: Bool
    }

    /// Stopka mówi, kiedy jest rozmowa: umówiony termin, a gdy go nie ma —
    /// termin wybrany przy rezerwacji na stronie.
    private func footerLine(_ topic: LeadTopic) -> Footer? {
        let today = dependencies.today
        if let nextEvent {
            var text = "Spotkanie: \(dependencies.dateText.dayLabel(nextEvent.day)), \(nextEvent.time.hhmm)"
            if let variant = client.consultation?.variantText {
                text += " · \(variant)"
            }
            return Footer(
                systemImage: "calendar",
                text: text,
                isSoon: nextEvent.day >= today && nextEvent.day <= today.adding(days: 1)
            )
        }
        if let text = LeadStatusStyle.consultationLine(for: client, dateText: dependencies.dateText, today: today) {
            let day = LeadWorkflow.booking(of: client)?.day
            return Footer(
                systemImage: "calendar.badge.clock",
                text: text,
                isSoon: day.map { $0 >= today && $0 <= today.adding(days: 1) } ?? false
            )
        }
        return nil
    }

    // MARK: Czynności

    private func toggleHandled(_ status: LeadStatus) {
        if status.needsAction, let onMarkHandled {
            isMarking = true
            Task {
                await onMarkHandled()
                isMarking = false
            }
        } else if status == .inContact, let onReopen {
            Task { await onReopen() }
        }
    }

    /// Menu po przytrzymaniu: wszystko, co backend przyjmuje dla zgłoszenia.
    @ViewBuilder
    private func contextMenuItems(_ status: LeadStatus) -> some View {
        if let conversation, let onOpenConversation {
            Button {
                onOpenConversation(conversation.thread.id)
            } label: {
                Label("Odpisz na WhatsApp", systemImage: "arrowshape.turn.up.left")
            }
        }
        if status.needsAction, onMarkHandled != nil {
            Button {
                toggleHandled(status)
            } label: {
                Label("Oznacz „W kontakcie”", systemImage: "checkmark.circle")
            }
        }
        if status != .client {
            Button {
                dependencies.present(.eventForm(editing: nil, clientID: client.id, caseID: nil, initialDay: nil))
            } label: {
                Label("Umów konsultację", systemImage: "calendar.badge.plus")
            }
        }
        if status == .inContact {
            Button {
                dependencies.present(.startCase(client.id))
            } label: {
                Label("Przyjmij sprawę", systemImage: "folder.badge.plus")
            }
        }
        if status == .inContact, onReopen != nil {
            Button {
                toggleHandled(status)
            } label: {
                Label("Przywróć do obsługi", systemImage: "arrow.uturn.backward.circle")
            }
        }
        if let phoneURL = client.phone.flatMap(ContactLinks.phoneURL) {
            Button {
                LeadActions.contact(client, url: phoneURL, channel: "Połączenie", dependencies: dependencies, openURL: openURL)
            } label: {
                Label("Zadzwoń", systemImage: "phone")
            }
        }
        if let onRename {
            Button {
                onRename()
            } label: {
                Label("Zmień nazwę", systemImage: "pencil")
            }
        }
        // Usuwanie jest tylko dla zgłoszeń. Kartoteka ma sprawy, terminy
        // i dokumenty — jej usunięcie nie jest tym samym co skasowanie spamu.
        if let onDelete, status != .client {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Usuń zgłoszenie", systemImage: "trash")
            }
        }
        Button {
            onOpen()
        } label: {
            Label("Otwórz kartę", systemImage: "arrow.up.forward.square")
        }
    }

    private func accessibilityText(_ status: LeadStatus) -> String {
        let topic = LeadTopic.parse(client.topic)
        var parts = [
            client.displayName,
            LeadStatusStyle.topicText(topic),
            LeadWorkflow.badgeText(for: client, now: dependencies.now, today: dependencies.today),
            client.language.displayName
        ]
        if let message = customerMessage {
            parts.append("\(conversationLabel): \(message)")
        }
        if let footer = footerLine(topic) {
            parts.append(footer.text)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Wiersz leada na „Dzisiaj”

/// Zwarty wiersz zgłoszenia do sekcji „Leady do obsługi” na ekranie głównym:
/// awatar z kropką stanu, osoba, wiek i temat w jednej linii, przycisk „obsłużone”.
struct LeadInboxRow: View {

    @EnvironmentObject private var dependencies: AppDependencies

    let client: Client
    let onOpen: () -> Void
    let onMarkHandled: () async -> Void

    @State private var isMarking = false

    var body: some View {
        let status = LeadWorkflow.status(of: client, now: dependencies.now)
        let subtitle = subtitleText(status)
        HStack(alignment: .center, spacing: 2) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 11) {
                    ZStack(alignment: .bottomTrailing) {
                        PersonAvatar(initials: client.initials, style: .identity(client.id), diameter: 38)
                        Circle()
                            .fill(LeadStatusStyle.tone(status))
                            .frame(width: 11, height: 11)
                            .overlay {
                                Circle().strokeBorder(EmmaTheme.surface, lineWidth: 2)
                            }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(client.displayName)
                            .font(EmmaTypography.ui(14, .semibold))
                            .foregroundStyle(EmmaTheme.ink)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(EmmaTypography.body(for: subtitle, size: 12))
                            .foregroundStyle(status == .waiting ? EmmaTheme.pillAmberText : EmmaTheme.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(client.displayName), \(subtitle)")
            .accessibilityHint("Otwiera kartę klienta")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("today-lead-row")

            LeadCheckButton(isDone: isMarking, isBusy: isMarking) {
                isMarking = true
                Task {
                    await onMarkHandled()
                    isMarking = false
                }
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 5)
        .padding(.vertical, 6)
    }

    /// „Oczekuje · 2 dni · Zatrzymanie osoby bliskiej”.
    private func subtitleText(_ status: LeadStatus) -> String {
        let badge = LeadWorkflow.badgeText(for: client, now: dependencies.now, today: dependencies.today)
        let topic = LeadStatusStyle.topicText(LeadTopic.parse(client.topic))
        return "\(badge) · \(topic)"
    }
}
