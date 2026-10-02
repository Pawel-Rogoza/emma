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
    /// Okno 24 h WhatsApp — ostrzeżenie pod linijką stanu, gdy się zamyka.
    let replyWindow: ReplyWindow
    let onOpen: () -> Void
    let onOptions: () -> Void

    @EnvironmentObject private var dependencies: AppDependencies

    // Przebudowa 02.10.2026 — wiersz jak w WhatsAppie. Właściciel chce od razu
    // widzieć: kto napisał, kiedy, komu odpisano, a komu nie. Karta z linijką
    // stanu, linijką okna 24 h, kolumną znaczników i „…” była nieczytelna.
    // Teraz:
    //   • u góry imię i godzina ostatniej wiadomości (zielona, gdy są nowe),
    //   • podgląd: nasza wiadomość ma ptaszki dostarczenia i „Ty:”, więc
    //     „odpisano” widać bez dodatkowego napisu,
    //   • tylko gdy ruch jest nasz — jedna dyskretna linijka „Bez odpowiedzi ·
    //     3 godz.”, po 24 h „Ponad 24 h bez odpowiedzi” (wtedy WhatsApp
    //     przyjmie już tylko szablon),
    //   • opcje pod przytrzymaniem i przesunięciem, bez „…” w każdym wierszu.
    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                PersonAvatar(
                    initials: client.initials,
                    style: .identity(client.id),
                    diameter: EmmaMetrics.conversationAvatar
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(client.displayName)
                            .font(EmmaTypography.ui(16, isUnread ? .semibold : .medium))
                            .foregroundStyle(EmmaTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(timeLabel)
                            .font(EmmaTypography.ui(12, isUnread ? .semibold : .regular))
                            .foregroundStyle(isUnread ? EmmaTheme.unreadBadge : EmmaTheme.mutedSoft)
                            .fixedSize()
                    }

                    HStack(alignment: .top, spacing: 8) {
                        previewLine
                        Spacer(minLength: 4)
                        trailingMarks
                    }

                    if let waiting = waitingLine {
                        HStack(spacing: 4) {
                            Image(systemName: waiting.isOverdue ? "clock.badge.exclamationmark" : "clock")
                                .font(.system(size: 10, weight: .semibold))
                            Text(waiting.text)
                                .font(EmmaTypography.ui(12, .medium))
                        }
                        .foregroundStyle(waiting.isOverdue ? EmmaTheme.danger : EmmaTheme.pillAmberText)
                        .lineLimit(1)
                        .padding(.top, 1)
                    }
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            // Cienka linia od tekstu, nie od awatara — jak w WhatsAppie.
            Rectangle()
                .fill(EmmaTheme.cardBorder)
                .frame(height: 1)
                .padding(.leading, EmmaMetrics.conversationAvatar + 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Opcje rozmowy", onOptions)
        .animation(EmmaMotion.bouncy, value: unreadCount)
        .animation(EmmaMotion.smooth, value: isPinned)
    }

    private var isUnread: Bool { unreadCount > 0 }

    // MARK: Podgląd

    private var previewLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if !hasDraft, let preview, preview.isOutgoing {
                ReceiptMark(transport: preview.transport)
            }
            // Prefiks i treść w jednym napisie — druga linia zaczyna się pod
            // pierwszą, a nie wcięta za „Telefon:”.
            (prefixText + Text(previewText)
                .font(EmmaTypography.body(for: previewText, size: 14, weight: isUnread ? .medium : .regular))
                .foregroundColor(isUnread ? EmmaTheme.ink : EmmaTheme.muted))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var prefixText: Text {
        if hasDraft {
            return Text("Szkic: ").font(EmmaTypography.ui(14, .semibold)).foregroundColor(EmmaTheme.accent)
        }
        guard let preview, preview.isOutgoing else { return Text("") }
        return Text("\(outgoingPrefix(preview)) ")
            .font(EmmaTypography.ui(14, .medium))
            .foregroundColor(EmmaTheme.mutedSoft)
    }

    /// „Ty:” dla wiadomości z Emmy, „Telefon:” dla odpowiedzi z WhatsApp Business.
    private func outgoingPrefix(_ message: Message) -> String {
        message.authorID == nil ? "Telefon:" : "Ty:"
    }

    private var previewText: String {
        if hasDraft { return "Szkic w toku" }
        return preview?.previewText ?? "Brak wiadomości"
    }

    @ViewBuilder
    private var trailingMarks: some View {
        HStack(spacing: 6) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .rotationEffect(.degrees(35))
                    .accessibilityLabel("Rozmowa przypięta")
            }
            if unreadCount > 0 {
                UnreadBadge(count: unreadCount, compact: true)
                    .contentTransition(.numericText())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.top, 1)
    }

    // MARK: Bez odpowiedzi

    private struct WaitingLine {
        let text: String
        /// Ponad 24 h — WhatsApp przyjmie już tylko zatwierdzony szablon.
        let isOverdue: Bool
    }

    private var waitingLine: WaitingLine? {
        guard status.needsReply, !hasDraft else { return nil }
        let now = dependencies.now
        if replyWindow.isClosed || waitingSince.map({ now.timeIntervalSince($0) >= ReplyWindow.duration }) == true {
            return WaitingLine(text: "Ponad 24 h bez odpowiedzi", isOverdue: true)
        }
        var text = "Bez odpowiedzi"
        if let waitingSince {
            text += " · \(ConversationInbox.waitingText(since: waitingSince, now: now))"
        }
        if replyWindow.isClosingSoon(now: now), let left = replyWindow.remainingText(now: now) {
            text += " · zostało \(left)"
        }
        return WaitingLine(text: text, isOverdue: false)
    }

    // MARK: Czas

    /// Dziś — godzina, wczoraj — „Wczoraj”, w tym tygodniu — dzień tygodnia,
    /// dalej — data. Jak w WhatsAppie.
    private var timeLabel: String {
        guard let preview else { return "" }
        let day = AppDependencies.localDate(from: preview.sentAt)
        let today = dependencies.today
        if day == today { return dependencies.dateText.clockTime(preview.sentAt) }
        if day == today.adding(days: -1) { return "Wczoraj" }
        if day >= today.adding(days: -6) { return dependencies.dateText.weekdayName(for: day) }
        return String(format: "%02d.%02d.%02d", day.day, day.month, day.year % 100)
    }

    private var accessibilityLabel: String {
        var parts = [client.displayName]
        if unreadCount > 0 { parts.append(EmmaPlural.unread(unreadCount)) }
        if let waitingLine { parts.append(waitingLine.text) }
        if let preview {
            parts.append(preview.isOutgoing ? "Twoja wiadomość: \(preview.previewText)" : preview.previewText)
            parts.append(timeLabel)
        }
        if isPinned { parts.append("przypięta") }
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

/// Czynności przy pliku od klienta. Sam plik zostaje w WhatsApp Business —
/// Emma zna jego rodzaj i nazwę, a do akt trafia notatka z datą.
struct AttachmentActions {
    /// Otwiera rozmowę w WhatsApp (tam jest plik). `nil` — brak numeru.
    var openInWhatsApp: (() -> Void)?
    /// Notatka „Od: … — dokument · wyrok.pdf” w sprawie klienta.
    var addToCase: () -> Void
    /// Formularz terminu liczonego od dnia, w którym przyszedł plik.
    var countDeadline: (() -> Void)?
}

struct MessageBubble: View {

    let message: Message
    let senderLabel: String
    let showsAuthor: Bool
    var attachmentActions: AttachmentActions? = nil
    let onOptions: () -> Void

    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.isOutgoing { Spacer(minLength: 44) }

            VStack(alignment: .leading, spacing: 6) {
                if let quote = message.quote {
                    quoteView(quote)
                }

                if message.kind.isAttachment {
                    attachmentChip
                    if let caption = message.caption {
                        Text(caption)
                            .font(EmmaTypography.bubbleText(caption))
                            .foregroundStyle(EmmaTheme.ink)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(message.text)
                        .font(EmmaTypography.bubbleText(message.text))
                        .foregroundStyle(EmmaTheme.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
                }
            }
            .padding(EdgeInsets(top: 9, leading: 12, bottom: 8, trailing: 12))
            .background(message.isOutgoing ? EmmaTheme.bubbleOutgoing : EmmaTheme.bubbleIncoming)
            .clipShape(bubbleShape)
            .overlay {
                if !message.isOutgoing {
                    bubbleShape.strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
                }
            }

            if !message.isOutgoing { Spacer(minLength: 44) }
        }
        // Opcje (odpowiedz, kopiuj, szczegóły) pod przytrzymaniem dymka — jak
        // w WhatsAppie; wcześniej każdy dymek miał własne „…” (02.10.2026).
        .onLongPressGesture(minimumDuration: 0.35) {
            EmmaHaptics.selection()
            onOptions()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: message.isOutgoing ? "Szczegóły wiadomości" : "Odpowiedz na wiadomość", onOptions)
    }

    // MARK: Plik

    /// „Dokument · wyrok.pdf” z ikoną. Dotknięcie — menu czynności; bez
    /// czynności (np. plik wysłany przez kancelarię) — sama etykieta.
    @ViewBuilder
    private var attachmentChip: some View {
        if let actions = attachmentActions {
            Menu {
                if let open = actions.openInWhatsApp {
                    Button(action: open) {
                        Label("Otwórz w WhatsApp", systemImage: "arrow.up.forward.app")
                    }
                }
                Button(action: actions.addToCase) {
                    Label("Dołącz do akt sprawy", systemImage: "tray.and.arrow.down")
                }
                if let count = actions.countDeadline {
                    Button(action: count) {
                        Label("Policz termin od doręczenia", systemImage: "calendar.badge.clock")
                    }
                }
            } label: {
                attachmentLabel(interactive: true)
            }
            .accessibilityHint("Otwiera czynności: WhatsApp, akta sprawy, termin")
        } else {
            attachmentLabel(interactive: false)
        }
    }

    private func attachmentLabel(interactive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: message.kind.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EmmaTheme.accent)
                .frame(width: 34, height: 34)
                .background(EmmaTheme.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(message.attachmentName ?? message.kind.displayName)
                    .font(EmmaTypography.ui(14, .semibold))
                    .foregroundStyle(EmmaTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(interactive ? "\(message.kind.displayName) · w WhatsApp" : message.kind.displayName)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.muted)
            }
            if interactive {
                Spacer(minLength: 4)
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(EmmaTheme.accent)
            }
        }
        .padding(8)
        .frame(minWidth: 200, alignment: .leading)
        .background(EmmaTheme.quoteBackground)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
