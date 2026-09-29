import SwiftUI

// MARK: - Elementy komunikatora
//
// Odtworzenie `.messenger-row`, `.chat-message`, `.chat-day` i `.unread-divider`.
//
// Świadome wykluczenia z referencji: brak etykiet pilności w rozmowach oraz brak
// liczników czasu przy statusie dostarczenia. Status pochodzi wyłącznie z wartości
// `MessageTransport` — w demo oznacza to „Wysyłanie”, bo nic nie zostało wysłane.

// MARK: Wiersz listy rozmów

/// Karta rozmowy (przebudowa 29.09.2026, język „Klientów”): awatar w stałym
/// kolorze osoby, nazwisko z językiem, **linijka stanu** — czyj jest ruch
/// i od kiedy klient czeka — oraz podgląd ostatniej wiadomości. Nowe
/// wiadomości wyróżniają pasek z lewej i pulsująca obwódka awatara.
struct ConversationRow: View {

    let thread: ConversationThread
    let client: Client
    let preview: Message?
    let unreadCount: Int
    let isPinned: Bool
    let hasDraft: Bool
    let status: ConversationStatus
    let waitingSince: Date?
    let onOpen: () -> Void
    let onOptions: () -> Void

    @EnvironmentObject private var dependencies: AppDependencies

    // F13 audytu: licznik nieprzeczytanych był nakładką wyśrodkowaną w pionie, więc
    // nachodził na dwuliniowy podgląd (najgorzej w pierwszym wierszu i przy długiej
    // cyrylicy). Teraz czas, licznik, pinezka i menu tworzą **osobną kolumnę**
    // w układzie, a nie warstwę nad tekstem. Podgląd nie może wejść w jej prostokąt,
    // bo kolumna zajmuje własną szerokość — także przy największym Dynamic Type.
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    avatar

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(client.displayName)
                                .font(EmmaTypography.threadName)
                                .foregroundStyle(EmmaTheme.ink)
                                // Bez `lineLimit(1)`: przy największym Dynamic Type długie
                                // nazwisko („Maria Sokołowa”) ucinało się do „Maria…”.
                                // Zawinięcie do dwóch linii jest czytelniejsze niż wielokropek.
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                                .fixedSize(horizontal: false, vertical: true)
                            LanguageBadge(language: client.language)
                        }

                        statusLine

                        previewLine
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 13)
                .padding(.leading, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)

            // Kolumna znaczników: czas u góry, pod nim licznik i pinezka, menu na dole.
            VStack(alignment: .trailing, spacing: 5) {
                Text(previewLabel)
                    .font(EmmaTypography.threadTime)
                    .foregroundStyle(isUnread ? EmmaTheme.unreadBadge : EmmaTheme.mutedSoft)
                    .fixedSize()

                if unreadCount > 0 {
                    UnreadBadge(count: unreadCount, compact: true)
                        .contentTransition(.numericText())
                        .transition(.scale.combined(with: .opacity))
                }

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(EmmaTheme.mutedSoft)
                        .rotationEffect(.degrees(35))
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Rozmowa przypięta")
                }

                Spacer(minLength: 0)

                Button(action: onOptions) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(EmmaTheme.mutedSoft)
                        .frame(width: EmmaSpacing.hitTarget, height: EmmaSpacing.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Opcje rozmowy z \(client.displayName)")
            }
            .padding(.top, 13)
            .padding(.bottom, 4)
            .padding(.trailing, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EmmaTheme.surface)
        // Pasek z lewej — jak przy pilnej sprawie: wiadomość czeka na przeczytanie.
        .overlay(alignment: .leading) {
            if isUnread {
                Rectangle()
                    .fill(EmmaTheme.unreadBadge)
                    .frame(width: 3)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
        }
        .emmaCardShadow()
        .animation(EmmaMotion.bouncy, value: unreadCount)
        .animation(EmmaMotion.smooth, value: isPinned)
    }

    private var isUnread: Bool { status == .unread }

    // MARK: Awatar

    private var avatar: some View {
        PersonAvatar(
            initials: client.initials,
            style: .identity(client.id),
            diameter: EmmaMetrics.conversationAvatar
        )
        .overlay {
            if isUnread {
                EmmaPulseRing(color: EmmaTheme.unreadBadge, diameter: EmmaMetrics.conversationAvatar + 6)
            }
        }
        .frame(width: EmmaMetrics.conversationAvatar + 6, height: EmmaMetrics.conversationAvatar + 6)
    }

    // MARK: Linijka stanu

    /// „Nowe · czeka 12 min”, „Do odpowiedzi · czeka 7 min”, „Odpisano · odczytane”.
    private var statusLine: some View {
        HStack(spacing: 5) {
            if showsReceipt, let transport = preview?.transport {
                ReceiptMark(transport: transport)
            } else {
                Image(systemName: statusIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolEffect(.bounce, value: status)
            }
            Text(statusText)
                .font(EmmaTypography.caption(.semibold))
                .contentTransition(.opacity)
        }
        .foregroundStyle(statusColor)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .animation(EmmaMotion.smooth, value: status)
    }

    private var showsReceipt: Bool {
        !hasDraft && (status == .replied || status == .seen) && preview?.transport.receiptGlyph != MessageTransport.ReceiptGlyph.none
    }

    private var waitingText: String? {
        guard let waitingSince else { return nil }
        return ConversationInbox.waitingText(since: waitingSince, now: dependencies.now)
    }

    private var statusText: String {
        if hasDraft { return "Szkic odpowiedzi" }
        switch status {
        case .unread:
            return waitingText.map { "Nowe · czeka \($0)" } ?? "Nowe"
        case .awaitingReply:
            return waitingText.map { "Do odpowiedzi · czeka \($0)" } ?? "Do odpowiedzi"
        case .replied:
            switch preview?.transport {
            case .failed?: return "Nie wysłano"
            case .unknown?: return "Sprawdzamy wysyłkę"
            case .delivered?: return "Odpisano · dostarczono"
            case .accepted?, .sent?: return "Odpisano · wysłano"
            default: return "Odpisano · wysyłanie"
            }
        case .seen:
            return "Odpisano · odczytane"
        case .empty:
            return "Brak wiadomości"
        }
    }

    private var statusIcon: String {
        if hasDraft { return "square.and.pencil" }
        switch status {
        case .unread: return "envelope.badge.fill"
        case .awaitingReply: return "arrowshape.turn.up.left.fill"
        case .replied:
            return preview?.transport == .failed ? "exclamationmark.circle.fill" : "clock"
        case .seen: return "checkmark"
        case .empty: return "bubble.left"
        }
    }

    private var statusColor: Color {
        if hasDraft { return EmmaTheme.accent }
        switch status {
        case .unread: return EmmaTheme.unreadBadge
        case .awaitingReply:
            // Świeżo przeczytane — spokojnie; klient czeka ponad godzinę — bursztyn.
            guard let waitingSince else { return EmmaTheme.pillAmberText }
            return ConversationInbox.isWaitingLong(since: waitingSince, now: dependencies.now)
                ? EmmaTheme.pillAmberText
                : EmmaTheme.secondaryButtonText
        case .replied: return preview?.transport == .failed ? EmmaTheme.danger : EmmaTheme.mutedSoft
        case .seen: return EmmaTheme.pillGreenText
        case .empty: return EmmaTheme.mutedSoft
        }
    }

    // MARK: Podgląd

    private var previewLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if hasDraft {
                Text("Szkic:")
                    .font(EmmaTypography.ui(14, .semibold))
                    .foregroundStyle(EmmaTheme.muted)
            } else if preview?.isOutgoing == true {
                Text("Ty:")
                    .font(EmmaTypography.ui(14, .medium))
                    .foregroundStyle(EmmaTheme.mutedSoft)
            }
            Text(previewText)
                .font(EmmaTypography.body(for: previewText, size: 14, weight: isUnread ? .medium : .regular))
                .foregroundStyle(isUnread ? EmmaTheme.ink : EmmaTheme.muted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var previewText: String {
        if hasDraft { return "Szkic w toku" }
        return preview?.text ?? "Rozpocznij rozmowę"
    }

    private var previewLabel: String {
        guard let preview else { return "" }
        let day = AppDependencies.localDate(from: preview.sentAt)
        if day == dependencies.today {
            return dependencies.dateText.clockTime(preview.sentAt)
        }
        return dependencies.dateText.dayLabel(day)
    }

    private var accessibilityLabel: String {
        var parts = [client.displayName, statusText]
        if unreadCount > 0 { parts.append(EmmaPlural.unread(unreadCount)) }
        if isPinned { parts.append("przypięta") }
        if let preview { parts.append(preview.text) }
        return parts.joined(separator: ", ")
    }

}

// MARK: Potwierdzenie dostarczenia

/// Znacznik statusu wysyłki. Etykieta tekstowa trafia do czytnika ekranu, a sam
/// znacznik nie udaje potwierdzenia od dostawcy, którego nie ma.
///
/// Który znacznik odpowiada któremu stanowi, rozstrzyga **reguła domenowa**
/// `MessageTransport.receiptGlyph` — wcześniej ta sama decyzja była powtórzona tutaj
/// (`== .pending`, `== .delivered || == .read`), czyli w dwóch miejscach naraz.
struct ReceiptMark: View {
    let transport: MessageTransport

    var body: some View {
        HStack(spacing: 1) {
            switch transport.receiptGlyph {
            case .none:
                EmptyView()
            case .clock:
                glyph("clock")
            case .single:
                glyph("checkmark")
            case .double:
                glyph("checkmark")
                glyph("checkmark")
            }
        }
        .foregroundStyle(transport == .read ? EmmaTheme.receiptRead : EmmaTheme.receiptDefault)
        .accessibilityLabel(transport.displayName)
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .semibold))
    }
}

// MARK: Dymek wiadomości

struct MessageBubble: View {

    let message: Message
    let senderLabel: String
    let showsAuthor: Bool
    let onOptions: () -> Void

    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.isOutgoing { Spacer(minLength: 44) }

            VStack(alignment: .leading, spacing: 6) {
                if let quote = message.quote {
                    quoteView(quote)
                }

                Text(message.text)
                    .font(EmmaTypography.bubbleText(message.text))
                    .foregroundStyle(EmmaTheme.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if message.isOutgoing && showsAuthor {
                        Text(senderLabel)
                            .font(EmmaTypography.bubbleMeta)
                            .foregroundStyle(EmmaTheme.bubbleMeta)
                    }
                    Text(clockText)
                        .font(EmmaTypography.bubbleMeta)
                        .foregroundStyle(EmmaTheme.bubbleMeta)
                    if message.isOutgoing {
                        ReceiptMark(transport: message.transport)
                    }
                    Button(action: onOptions) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(EmmaTheme.bubbleMeta)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        message.isOutgoing
                            ? "Szczegóły wysłanej wiadomości z \(clockText)"
                            : "Odpowiedz na wiadomość z \(clockText)"
                    )
                }
            }
            .padding(EdgeInsets(top: 11, leading: 13, bottom: 9, trailing: 11))
            .background(message.isOutgoing ? EmmaTheme.bubbleOutgoing : EmmaTheme.bubbleIncoming)
            .clipShape(bubbleShape)
            .overlay {
                if !message.isOutgoing {
                    bubbleShape.strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
                }
            }

            if !message.isOutgoing { Spacer(minLength: 44) }
        }
        .accessibilityElement(children: .contain)
    }

    /// Narożnik po stronie nadawcy jest mniejszy — jak w referencji (`.chat-message`).
    private var bubbleShape: UnevenRoundedRectangle {
        if message.isOutgoing {
            return UnevenRoundedRectangle(
                topLeadingRadius: EmmaRadii.bubble,
                bottomLeadingRadius: EmmaRadii.bubble,
                bottomTrailingRadius: EmmaRadii.bubbleTail,
                topTrailingRadius: EmmaRadii.bubble
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: EmmaRadii.bubble,
            bottomLeadingRadius: EmmaRadii.bubbleTail,
            bottomTrailingRadius: EmmaRadii.bubble,
            topTrailingRadius: EmmaRadii.bubble
        )
    }

    @ViewBuilder
    private func quoteView(_ quote: QuotedReference) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(EmmaTheme.quoteRule)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.authorLabel)
                    .font(EmmaTypography.caption(.semibold))
                    .foregroundStyle(EmmaTheme.quoteRule)
                Text(quote.isAvailable ? quote.text : "Wiadomość niedostępna")
                    .font(EmmaTypography.quotedText(quote.text))
                    .foregroundStyle(EmmaTheme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EmmaTheme.quoteBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var clockText: String {
        dependencies.dateText.clockTime(message.sentAt)
    }

}

// MARK: Separatory

/// Separator dnia w historii rozmowy (`.chat-day`).
struct ChatDaySeparator: View {
    let text: String

    var body: some View {
        Text(text)
            .font(EmmaTypography.daySeparator)
            .foregroundStyle(EmmaTheme.chatDayChipText)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(EmmaTheme.chatDayChip)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Separator „Nowe wiadomości” przed pierwszą nieprzeczytaną wiadomością.
struct UnreadDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(EmmaTheme.unreadDivider)
                .frame(height: 1)
            Text("Nowe wiadomości")
                .font(EmmaTypography.unreadDivider)
                .foregroundStyle(EmmaTheme.unreadDividerText)
                .fixedSize()
            Rectangle()
                .fill(EmmaTheme.unreadDivider)
                .frame(height: 1)
        }
        .padding(.vertical, 10)
        .accessibilityAddTraits(.isHeader)
    }
}
