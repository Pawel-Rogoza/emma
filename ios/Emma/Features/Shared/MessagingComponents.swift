import SwiftUI

// MARK: - Elementy komunikatora
//
// Odtworzenie `.messenger-row`, `.chat-message`, `.chat-day` i `.unread-divider`.
//
// Świadome wykluczenia z referencji: brak etykiet pilności w rozmowach oraz brak
// liczników czasu przy statusie dostarczenia. Status pochodzi wyłącznie z wartości
// `MessageTransport` — w demo oznacza to „Wysyłanie”, bo nic nie zostało wysłane.

// MARK: Wiersz listy rozmów

struct ConversationRow: View {

    let thread: ConversationThread
    let client: Client
    let preview: Message?
    let unreadCount: Int
    let isPinned: Bool
    let avatarTone: Client.AvatarTone
    let hasDraft: Bool
    let onOpen: () -> Void
    let onOptions: () -> Void

    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    PersonAvatar(
                        initials: client.initials,
                        style: .conversation(avatarTone),
                        diameter: EmmaMetrics.conversationAvatar
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(client.displayName)
                                .font(EmmaTypography.threadName)
                                .foregroundStyle(EmmaTheme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(previewLabel)
                                .font(EmmaTypography.threadTime)
                                .foregroundStyle(EmmaTheme.mutedSoft)
                        }

                        HStack(alignment: .top, spacing: 6) {
                            if hasDraft {
                                Text("Szkic:")
                                    .font(EmmaTypography.ui(14, .semibold))
                                    .foregroundStyle(EmmaTheme.muted)
                            } else if preview?.isOutgoing == true, let transport = preview?.transport {
                                ReceiptMark(transport: transport)
                            }
                            Text(previewText)
                                .font(EmmaTypography.body(for: previewText, size: 14))
                                .foregroundStyle(unreadCount > 0 ? EmmaTheme.ink : EmmaTheme.muted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 13)
                .padding(.leading, 15)
                .padding(.trailing, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)

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
        .background(unreadCount > 0 ? EmmaTheme.accentSoft.opacity(0.55) : Color.clear)
        .overlay(alignment: .trailing) {
            if unreadCount > 0 {
                UnreadBadge(count: unreadCount, compact: true)
                    .padding(.trailing, 54)
            }
        }
        .overlay(alignment: .trailing) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .padding(.trailing, 16)
                    .offset(y: 14)
            }
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
        var parts = [client.displayName]
        if unreadCount > 0 { parts.append(EmmaPlural.unread(unreadCount)) }
        if isPinned { parts.append("przypięta") }
        if hasDraft { parts.append("szkic w toku") }
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

    /// Tłumaczenie jest zwinięte, dopóki użytkownik go nie rozwinie — jak `<details>`
    /// w referencji. Stan żyje w dymku, więc nie rozjeżdża się między wiadomościami.
    @State private var isTranslationExpanded = false


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

                if let translation = message.translation {
                    translationView(translation)
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
                    .font(EmmaTypography.ui(11, .semibold))
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

    /// Tłumaczenie w dymku. Referencja trzyma je w `<details>` — czyli **zwinięte**,
    /// z rozwijanym nagłówkiem „Tłumaczenie” i linią oddzielającą od treści.
    /// Wartości z reguł `.bubble-translation`: linia `#E1E7EE`, odstęp 9 pt nad linią
    /// i 8 pt pod nią, etykieta 13 pt `#627790`, treść 14 pt `#4E6178`.
    @ViewBuilder
    private func translationView(_ translation: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isTranslationExpanded.toggle()
            } label: {
                Text("Tłumaczenie")
                    .font(EmmaTypography.body(for: translation, size: 13))
                    .foregroundStyle(EmmaTheme.bubbleTranslationLabel)
                    .frame(minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tłumaczenie")
            .accessibilityHint(isTranslationExpanded ? "Zwiń tłumaczenie" : "Rozwiń tłumaczenie")

            if isTranslationExpanded {
                Text(translation)
                    .font(EmmaTypography.body(for: translation, size: 14))
                    .foregroundStyle(EmmaTheme.bubbleTranslationText)
                    .lineSpacing(4)
                    .padding(.vertical, 5)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Tłumaczenie: \(translation)")
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EmmaTheme.bubbleTranslationRule)
                .frame(height: 1)
        }
        .padding(.top, 9)
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
