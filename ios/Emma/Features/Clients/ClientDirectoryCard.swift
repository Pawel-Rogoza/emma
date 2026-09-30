import SwiftUI

// MARK: - Kartoteka klientów
//
// Review 27.09.2026: zakładka nazywała się „Klienci”, a klientów kancelarii
// (etap `client`) nie było na niej wcale — tylko leady i sprawy. Kartoteka
// pokazuje każdą osobę z tym, co prawnik chce wiedzieć bez otwierania karty:
// co u niej prowadzimy, kiedy jest najbliższy termin i czy coś zalega.

/// Wiersz kartoteki: awatar w stałym kolorze osoby, nazwisko z językiem,
/// prowadzone sprawy, najbliższy termin i zaległe zadania.
struct ClientDirectoryCard: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.openURL) private var openURL

    let client: Client
    let cases: [LegalCase]
    let nextEvent: ScheduledEvent?
    /// Niezakończony termin w sprawie klienta, który już minął.
    var missedEvent: ScheduledEvent? = nil
    let overdueTaskCount: Int
    /// Aktywna sprawa, w której od miesiąca nic się nie dzieje.
    var isStale = false
    let onOpen: () -> Void

    /// Rozmowa WhatsApp klienta (z listy „Rozmowy”) — „2 nowe”, „czeka 3 godz.”.
    var conversation: MessagesStore.Row? = nil
    var onOpenConversation: ((ThreadID) -> Void)? = nil

    // Level up 30.09.2026: telefon był tylko pod przesunięciem, którego nikt
    // nie odkrywa. Teraz karta ma widoczny przycisk „Zadzwoń” zamiast strzałki,
    // a aktywność WhatsApp (nowe wiadomości, czekanie na odpowiedź) jest w linii
    // stanu — bez wchodzenia w Rozmowy.
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 12) {
                    PersonAvatar(initials: client.initials, style: .identity(client.id), diameter: 44)
                        .overlay(alignment: .topTrailing) {
                            if let unread = conversation?.unreadCount, unread > 0 {
                                UnreadBadge(count: unread, compact: true)
                                    .offset(x: 5, y: -4)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(client.displayName)
                                .font(EmmaTypography.personName)
                                .foregroundStyle(EmmaTheme.ink)
                                .lineLimit(1)
                            LanguageBadge(language: client.language)
                        }
                        Text(casesText)
                            .font(EmmaTypography.body(for: casesText, size: 13))
                            .foregroundStyle(EmmaTheme.muted)
                            .lineLimit(1)
                        if hasMeta {
                            metaLine
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("client-card")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Otwiera kartę klienta. Przesuń, aby zadzwonić albo umówić termin.")
            .accessibilityAddTraits(.isButton)

            trailingAction
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EmmaTheme.surface)
        // Nowa wiadomość od klienta — pasek z lewej jak na karcie rozmowy.
        .overlay(alignment: .leading) {
            if (conversation?.unreadCount ?? 0) > 0 {
                Rectangle().fill(EmmaTheme.unreadBadge).frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
        }
        .emmaCardShadow()
        .contextMenu { menu }
        .animation(EmmaMotion.bouncy, value: conversation?.unreadCount)
    }

    /// Telefon jednym dotknięciem; bez numeru — zwykła strzałka.
    @ViewBuilder
    private var trailingAction: some View {
        if let phoneURL = client.phone.flatMap(ContactLinks.phoneURL) {
            Button {
                EmmaHaptics.tap()
                openURL(phoneURL)
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(EmmaTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(EmmaTheme.accentSoft, in: Circle())
                    .frame(width: 54)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(EmmaCardButtonStyle())
            .accessibilityLabel("Zadzwoń do \(client.displayName)")
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EmmaTheme.mutedSoft)
                .padding(.trailing, 14)
                .accessibilityHidden(true)
        }
    }

    // MARK: Treść

    private var activeCases: [LegalCase] {
        cases.filter { $0.status.isActive }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    /// „Deportacja · +1 sprawa”, „Tylko zakończone sprawy”, „Bez prowadzonej sprawy”.
    private var casesText: String {
        let active = activeCases
        if let first = active.first {
            let rest = active.count - 1
            return rest > 0 ? "\(first.title) · +\(rest)" : first.title
        }
        if !cases.isEmpty {
            return cases.count == 1 ? "Sprawa zakończona" : "Sprawy zakończone (\(cases.count))"
        }
        let topic = LeadStatusStyle.topicText(LeadTopic.parse(client.topic))
        return "Bez sprawy · \(topic)"
    }

    private var hasMeta: Bool {
        missedEvent != nil || nextEvent != nil || overdueTaskCount > 0 || isStale || conversationText != nil
    }

    /// „2 nowe wiadomości” albo „Czeka 3 godz.” — tylko gdy ruch jest nasz.
    private var conversationText: String? {
        guard let conversation, conversation.status.needsReply else { return nil }
        if conversation.unreadCount > 0 {
            return EmmaPlural.label(conversation.unreadCount, "nowa wiadomość", "nowe wiadomości", "nowych wiadomości")
        }
        guard let since = conversation.waitingSince else { return "Czeka na odpowiedź" }
        return "Czeka \(ConversationInbox.waitingText(since: since, now: dependencies.now))"
    }

    private var metaLine: some View {
        HStack(spacing: 10) {
            if let conversationText {
                Label {
                    Text(conversationText)
                        .font(EmmaTypography.caption(.semibold))
                } icon: {
                    Image(systemName: "bubble.left.fill").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle((conversation?.unreadCount ?? 0) > 0 ? EmmaTheme.unreadBadge : EmmaTheme.pillAmberText)
            }
            if let missedEvent {
                Label {
                    Text("Minął: \(dependencies.dateText.dayLabel(missedEvent.day))")
                        .font(EmmaTypography.caption(.semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(EmmaTheme.pillDangerText)
            } else if let nextEvent {
                let isSoon = nextEvent.day <= dependencies.today.adding(days: 1)
                Label {
                    Text(eventText(nextEvent))
                        .font(EmmaTypography.caption(isSoon ? .semibold : .medium))
                } icon: {
                    Image(systemName: "calendar").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(isSoon ? EmmaTheme.accent : EmmaTheme.mutedSoft)
            }
            if overdueTaskCount > 0 {
                Label {
                    Text(EmmaPlural.overdueTasks(overdueTaskCount))
                        .font(EmmaTypography.caption(.medium))
                } icon: {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(EmmaTheme.pillDangerText)
            }
            if isStale {
                Label {
                    Text("Bez ruchu od miesiąca")
                        .font(EmmaTypography.caption(.medium))
                } icon: {
                    Image(systemName: "moon.zzz").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(EmmaTheme.pillAmberText)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private func eventText(_ event: ScheduledEvent) -> String {
        let day = dependencies.dateText.dayLabel(event.day)
        return event.isAllDay ? day : "\(day), \(event.time.hhmm)"
    }

    // MARK: Czynności

    @ViewBuilder
    private var menu: some View {
        if let conversation, let onOpenConversation {
            Button {
                onOpenConversation(conversation.thread.id)
            } label: {
                Label("Otwórz rozmowę", systemImage: "bubble.left.and.bubble.right")
            }
        }
        Button {
            dependencies.present(.eventForm(editing: nil, clientID: client.id, caseID: nil, initialDay: nil))
        } label: {
            Label("Umów termin", systemImage: "calendar.badge.plus")
        }
        Button {
            dependencies.present(.startCase(client.id))
        } label: {
            Label("Nowa sprawa", systemImage: "folder.badge.plus")
        }
        if let phoneURL = client.phone.flatMap(ContactLinks.phoneURL) {
            Button {
                openURL(phoneURL)
            } label: {
                Label("Zadzwoń", systemImage: "phone")
            }
        }
        Button {
            onOpen()
        } label: {
            Label("Otwórz kartę", systemImage: "arrow.up.forward.square")
        }
    }

    private var accessibilityText: String {
        var parts = [client.displayName, client.language.displayName, casesText]
        if let conversationText { parts.append(conversationText) }
        if let missedEvent {
            parts.append("minął termin \(missedEvent.title), \(dependencies.dateText.dayLabel(missedEvent.day))")
        } else if let nextEvent {
            parts.append("najbliższy termin \(eventText(nextEvent))")
        }
        if overdueTaskCount > 0 {
            parts.append(EmmaPlural.overdueTasks(overdueTaskCount))
        }
        if isStale {
            parts.append("bez ruchu od miesiąca")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Ostatnio otwierani

/// Pasek awatarów nad kartoteką: powrót jednym dotknięciem do osób,
/// nad którymi ostatnio się pracowało.
struct RecentClientsStrip: View {
    let clients: [Client]
    let horizontalPadding: CGFloat
    let onOpen: (Client) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OSTATNIO OTWIERANI")
                .font(EmmaTypography.caption(.semibold))
                .tracking(0.6)
                .foregroundStyle(EmmaTheme.mutedSoft)
                .padding(.horizontal, horizontalPadding)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(clients) { client in
                        Button {
                            onOpen(client)
                        } label: {
                            VStack(spacing: 5) {
                                PersonAvatar(initials: client.initials, style: .identity(client.id), diameter: 48)
                                Text(firstName(client))
                                    .font(EmmaTypography.caption(.medium))
                                    .foregroundStyle(EmmaTheme.ink)
                                    .lineLimit(1)
                            }
                            .frame(width: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(EmmaCardButtonStyle())
                        .accessibilityLabel(client.displayName)
                        .accessibilityHint("Otwiera kartę klienta")
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }

    private func firstName(_ client: Client) -> String {
        client.displayName.split(separator: " ").first.map(String.init) ?? client.displayName
    }
}
