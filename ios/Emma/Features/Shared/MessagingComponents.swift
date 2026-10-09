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
    /// Treść szkicu — „Szkic: Dzień dobry…” jak w WhatsAppie.
    var draftText: String? = nil
    let status: ConversationStatus
    let waitingSince: Date?
    /// Okno 24 h WhatsApp — ostrzeżenie pod linijką stanu, gdy się zamyka.
    let replyWindow: ReplyWindow
    let onOpen: () -> Void
    let onOptions: () -> Void

    @EnvironmentObject private var dependencies: AppDependencies

    // Wiersz 1:1 jak w WhatsAppie (02.10.2026, druga runda na zrzutach
    // właściciela): systemowa czcionka, duży okrągły awatar, godzina po prawej,
    // dwie linijki podglądu. Poprawka 03.10.2026: pogrubienie, zielona godzina
    // i licznik znaczą **nieprzeczytane** — jak w WhatsAppie. Wcześniej znaczyły
    // „nie odpisano”, więc przeczytana rozmowa dalej wyglądała na nową. Po
    // przeczytaniu bez odpowiedzi zostaje szara kropka, a po 24 h bez odpowiedzi
    // dyskretny czerwony zegar (WhatsApp przyjmie już tylko szablon). Nasza
    // ostatnia wiadomość ma ptaszki — niebieskie po odczytaniu.
    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 13) {
                ChatAvatar(client: client)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(client.displayName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(EmmaTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(timeLabel)
                            .font(.system(size: 14))
                            .foregroundStyle(isUnread ? EmmaTheme.chatGreen : EmmaTheme.mutedSoft)
                            .fixedSize()
                    }

                    HStack(alignment: .top, spacing: 8) {
                        previewLine
                            .frame(maxWidth: .infinity, alignment: .leading)
                        trailingMarks
                    }
                }
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    // Linia od tekstu do krawędzi, nie pod awatarem — jak w WhatsAppie.
                    Rectangle()
                        .fill(EmmaTheme.cardBorder)
                        .frame(height: 0.5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Opcje rozmowy", onOptions)
        .animation(EmmaMotion.bouncy, value: unreadCount)
        .animation(EmmaMotion.smooth, value: isPinned)
    }

    /// Ruch po naszej stronie: klient napisał, a my nie odpisaliśmy.
    private var needsReply: Bool { status.needsReply && !hasDraft }

    /// Nowe wiadomości (albo ręczne „oznacz jako nową”).
    private var isUnread: Bool { unreadCount > 0 }

    /// Klient czeka ponad 24 h — WhatsApp przyjmie już tylko zatwierdzony szablon.
    private var isOverdue: Bool {
        // Okno 24 h to reguła WhatsAppa — mail nie „przeterminowuje się”.
        guard needsReply, !thread.isEmail else { return false }
        if replyWindow.isClosed { return true }
        guard let waitingSince else { return false }
        return dependencies.now.timeIntervalSince(waitingSince) >= ReplyWindow.duration
    }

    // MARK: Podgląd

    private var previewLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            // Ptaszki w samym napisie: druga linijka zaczyna się od lewej
            // krawędzi, a nie wcięta za nimi — jak w WhatsAppie.
            (ticksPrefix + draftPrefix + Text(previewText))
                .font(.system(size: 15, weight: isUnread ? .semibold : .regular))
                .foregroundStyle(isUnread ? EmmaTheme.ink : EmmaTheme.mutedSoft)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ticksPrefix: Text {
        guard !hasDraft, let preview, preview.isOutgoing else { return Text("") }
        return ChatTicks.text(for: preview.transport)
    }

    /// „Szkic:” na zielono — jak „Wersja robocza:” w WhatsAppie.
    private var draftPrefix: Text {
        guard hasDraft else { return Text("") }
        return Text("Szkic: ").foregroundColor(EmmaTheme.chatGreen)
    }

    private var previewText: String {
        if hasDraft {
            let text = draftText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Sam cytat bez tekstu to też zaczęta odpowiedź.
            return text.isEmpty ? "odpowiedź w toku" : text
        }
        guard let preview else { return "Brak wiadomości" }
        // Mail: koperta i temat przed treścią — od razu widać, że to poczta.
        if thread.isEmail {
            let subject = preview.subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return subject.isEmpty ? "✉︎ \(preview.previewText)" : "✉︎ \(subject) — \(preview.previewText)"
        }
        return preview.previewText
    }

    /// Prawa kolumna pod godziną: licznik nowych, kropka „bez odpowiedzi”
    /// albo zegar po 24 h; pinezka dla przypiętych.
    private var trailingMarks: some View {
        HStack(spacing: 6) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .rotationEffect(.degrees(35))
                    .accessibilityLabel("Rozmowa przypięta")
            }
            if isOverdue {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(EmmaTheme.danger)
                    .accessibilityLabel("Ponad 24 godziny bez odpowiedzi")
            }
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(EmmaTheme.chatGreen, in: Capsule())
                    .contentTransition(.numericText())
                    .transition(.scale.combined(with: .opacity))
            } else if needsReply && !isOverdue {
                Circle()
                    .fill(EmmaTheme.chatAwaitingDot)
                    .frame(width: 9, height: 9)
                    .padding(.top, 4)
                    .accessibilityLabel("Bez odpowiedzi")
            }
        }
        .padding(.top, 3)
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
        return String(format: "%02d.%02d.%04d", day.day, day.month, day.year)
    }

    private var accessibilityLabel: String {
        var parts = [client.displayName]
        if unreadCount > 0 { parts.append(EmmaPlural.unread(unreadCount)) }
        if isOverdue {
            parts.append("ponad 24 godziny bez odpowiedzi")
        } else if needsReply {
            parts.append("bez odpowiedzi")
        }
        if let preview {
            parts.append(preview.isOutgoing ? "Twoja wiadomość: \(preview.previewText)" : preview.previewText)
            parts.append(timeLabel)
        }
        if hasDraft { parts.append("szkic: \(previewText)") }
        if isPinned { parts.append("przypięta") }
        return parts.joined(separator: ", ")
    }

}

/// Awatar rozmowy. WhatsApp Business API nie udostępnia zdjęć profilowych,
/// więc awatar mówi to, po czym kancelaria rozpoznaje ludzi (03.10.2026):
///   • stały kolor osoby,
///   • inicjały, a pod nimi końcówka numeru („OK / 709”) — dwie Oleny
///     z różnych numerów nie wyglądają już tak samo,
///   • sam numer bez imienia — duża końcówka numeru zamiast sylwetki,
///   • flaga kraju numeru w rogu, gdy numer nie jest polski.
struct ChatAvatar: View {
    let client: Client
    var diameter: CGFloat = 54

    var body: some View {
        let tone = EmmaTheme.identityAvatar(IdentityTone.index(for: client.id))
        ZStack {
            Circle().fill(tone.background)
            content
        }
        .foregroundStyle(tone.foreground)
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .bottomTrailing) {
            if diameter >= 36, let flag = ChatIdentity.foreignFlag(phone: client.phone) {
                Text(flag)
                    .font(.system(size: diameter * 0.27))
                    .padding(diameter * 0.03)
                    .background(EmmaTheme.surface, in: Circle())
                    .offset(x: diameter * 0.06, y: diameter * 0.04)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        let suffix = ChatIdentity.phoneSuffix(client.phone)
        if initials.isEmpty {
            if let suffix {
                Text(suffix)
                    .font(.system(size: diameter * 0.33, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: diameter * 0.42))
            }
        } else if diameter >= 44, let suffix {
            VStack(spacing: -1) {
                Text(initials)
                    .font(.system(size: diameter * 0.31, weight: .semibold))
                Text(suffix)
                    .font(.system(size: diameter * 0.19, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .opacity(0.72)
            }
        } else {
            Text(initials)
                .font(.system(size: max(10, diameter * 0.32), weight: .semibold))
        }
    }

    private var initials: String {
        guard !ChatIdentity.isBareNumber(client.displayName) else { return "" }
        let given = client.initials.trimmingCharacters(in: .whitespaces)
        return given.isEmpty ? ChatIdentity.initials(client.displayName) : given
    }
}

/// Ptaszki na liście: szare — wysłano/dostarczono, niebieskie — odczytano.
struct ChatTicks: View {
    let transport: MessageTransport

    /// Ptaszki jako `Text` do sklejenia z podglądem (zawija się razem z treścią).
    static func text(for transport: MessageTransport) -> Text {
        let color = transport == .read ? EmmaTheme.chatReadTicks : EmmaTheme.mutedSoft
        let mark = Text(Image(systemName: "checkmark")).font(.system(size: 12, weight: .bold)).foregroundColor(color)
        switch transport.receiptGlyph {
        case .none: return Text("")
        case .clock:
            return Text(Image(systemName: "clock")).font(.system(size: 12)).foregroundColor(color) + Text(" ")
        case .single: return mark + Text(" ")
        case .double: return mark.tracking(-6) + mark + Text(" ")
        }
    }

    var body: some View {
        Group {
            switch transport.receiptGlyph {
            case .none:
                EmptyView()
            case .clock:
                Image(systemName: "clock")
            case .single:
                Image(systemName: "checkmark")
            case .double:
                ZStack(alignment: .leading) {
                    Image(systemName: "checkmark")
                    Image(systemName: "checkmark").offset(x: 5)
                }
                .padding(.trailing, 5)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(transport == .read ? EmmaTheme.chatReadTicks : EmmaTheme.mutedSoft)
        .accessibilityLabel(transport.displayName)
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
    /// Notatka „Od: … — dokument · wyrok.pdf” w sprawie klienta. `nil` dla
    /// rozmówcy spoza kartoteki — nie ma akt, do których można dołączyć.
    var addToCase: (() -> Void)?
    /// Formularz terminu liczonego od dnia, w którym przyszedł plik.
    var countDeadline: (() -> Void)?
    /// Lokalizacja od klienta w Mapach Apple.
    var openInMaps: (() -> Void)?

    var isEmpty: Bool {
        openInWhatsApp == nil && addToCase == nil && countDeadline == nil && openInMaps == nil
    }
}

/// Dymek wiadomości (przebudowa 03.10.2026, bliżej WhatsAppa):
///   • kolejne wiadomości jednej strony tworzą grupę — mały odstęp, „ogonek”
///     tylko przy ostatniej, nadawca (kancelaria / WhatsApp Business) nad
///     pierwszą,
///   • godzina i ptaszki w rogu dymka, w ostatniej linijce tekstu,
///   • same emoji — duże, bez dymka,
///   • pliki jako karty z rodzajem (PDF, zdjęcie, nagranie, lokalizacja),
///   • wiadomość, której Emma nie pokaże — czytelna informacja i przejście
///     do WhatsAppa, zamiast suchego „[Wiadomość nieobsługiwana…]”,
///   • niewysłana wiadomość — od razu „Wyślij z WhatsApp”,
///   • linki w treści dają się otworzyć.
struct MessageBubble: View {

    let message: Message
    let senderLabel: String
    var position = ChatLayout.Position(startsGroup: true, endsGroup: true)
    var attachmentActions: AttachmentActions? = nil
    /// Rozmowa w aplikacji WhatsApp — dla wiadomości, których tu nie ma
    /// albo które nie wyszły. `nil` — brak numeru.
    var onOpenWhatsApp: (() -> Void)? = nil
    let onOptions: () -> Void

    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        if message.kind == .system {
            systemNotice
        } else {
            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 0) {
                    if message.isOutgoing { Spacer(minLength: 52) }
                    if isEmojiOnly {
                        emojiOnly
                    } else {
                        bubble
                    }
                    if !message.isOutgoing { Spacer(minLength: 52) }
                }
                if message.isOutgoing && message.transport == .failed {
                    failedNotice
                }
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
    }

    // MARK: Dymek

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 5) {
            if message.isOutgoing && position.startsGroup {
                Text(senderLabel)
                    .font(EmmaTypography.ui(12, .semibold))
                    .foregroundStyle(EmmaTheme.quoteRule)
            }

            if let quote = message.quote {
                quoteView(quote)
            }

            if message.kind.isAttachment {
                if !metaOnCard, let caption = message.caption {
                    attachment
                    textWithMeta(caption)
                } else {
                    // Bez podpisu godzina siedzi w rogu karty — jak na zdjęciu w WhatsAppie.
                    attachment
                        .overlay(alignment: .bottomTrailing) { attachmentMeta }
                }
            } else {
                if let subject = message.subject?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
                    Text(subject)
                        .font(EmmaTypography.ui(15, .semibold))
                        .foregroundStyle(EmmaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                textWithMeta(message.text)
            }
        }
        .padding(EdgeInsets(top: 7, leading: 11, bottom: 6, trailing: 11))
        .background {
            // Cień tylko pod kształtem dymka, nie pod literami.
            bubbleShape
                .fill(message.isOutgoing ? EmmaTheme.bubbleOutgoing : EmmaTheme.bubbleIncoming)
                .shadow(color: EmmaTheme.bubbleShadow, radius: 0.5, x: 0, y: 1)
        }
    }

    /// Treść z godziną w ostatniej linijce. Na końcu tekstu stoi niewidoczny
    /// zapas szerokości godziny — krótka wiadomość ma godzinę obok siebie,
    /// a pełna linijka przenosi ją niżej, zamiast na nią nachodzić.
    private func textWithMeta(_ text: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            (Text(ChatText.attributed(text)) + Text(metaReserve).font(EmmaTypography.bubbleMeta))
                .font(EmmaTypography.bubbleText(text))
                .foregroundStyle(EmmaTheme.ink)
                .tint(EmmaTheme.receiptRead)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            meta
                .padding(.bottom, -1)
        }
    }

    /// Zapas pod godzinę (i ptaszki) — spacje o szerokości cyfry.
    private var metaReserve: String {
        "\u{2007}" + String(repeating: "\u{2007}", count: message.isOutgoing ? 9 : 6)
    }

    private var meta: some View {
        HStack(spacing: 4) {
            Text(clockText)
                .font(EmmaTypography.bubbleMeta)
                .foregroundStyle(EmmaTheme.bubbleMeta)
            if message.isOutgoing {
                ReceiptMark(transport: message.transport)
            }
        }
        .fixedSize()
    }

    /// Godzina na karcie pliku, a nie pod podpisem: brak podpisu albo
    /// lokalizacja (jej „podpis” to nazwa miejsca na karcie).
    private var metaOnCard: Bool {
        message.caption == nil || message.kind == .location
    }

    @ViewBuilder
    private var attachmentMeta: some View {
        if message.kind.hasMediaTile {
            meta
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.85), in: Capsule())
                .padding(7)
        } else {
            meta
                .padding(.trailing, 9)
                .padding(.bottom, 5)
        }
    }

    /// Ogonek tylko przy ostatniej wiadomości grupy; wewnątrz grupy narożniki
    /// po stronie nadawcy są mniejsze, więc dymki „sklejają się” w jedną wypowiedź.
    private var bubbleShape: UnevenRoundedRectangle {
        let round = EmmaRadii.bubble
        let joined: CGFloat = 6
        let senderTop = position.startsGroup ? round : joined
        let senderBottom = position.endsGroup ? EmmaRadii.bubbleTail : joined
        if message.isOutgoing {
            return UnevenRoundedRectangle(
                topLeadingRadius: round,
                bottomLeadingRadius: round,
                bottomTrailingRadius: senderBottom,
                topTrailingRadius: senderTop
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: senderTop,
            bottomLeadingRadius: senderBottom,
            bottomTrailingRadius: round,
            topTrailingRadius: round
        )
    }

    // MARK: Same emoji

    private var isEmojiOnly: Bool {
        message.kind == .text && message.quote == nil && ChatLayout.isEmojiOnly(message.text)
    }

    private var emojiOnly: some View {
        VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 2) {
            Text(message.text)
                .font(.system(size: 44))
            meta
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(EmmaTheme.bubbleIncoming.opacity(0.85), in: Capsule())
        }
    }

    // MARK: Nie wysłano

    private var failedNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(EmmaTheme.danger)
            Text("Nie wysłano")
                .foregroundStyle(EmmaTheme.danger)
            if let onOpenWhatsApp {
                Button {
                    EmmaHaptics.tap()
                    onOpenWhatsApp()
                } label: {
                    Text("Wyślij z WhatsApp")
                        .foregroundStyle(EmmaTheme.chatGreen)
                        .underline()
                }
                .buttonStyle(.plain)
                .frame(minHeight: EmmaSpacing.hitTarget)
            }
        }
        .font(EmmaTypography.caption(.semibold))
    }

    // MARK: Wiadomość niedostępna w Emmie

    private var systemNotice: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: message.isUnavailableInApp ? "eye.slash" : "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text(message.isUnavailableInApp ? "Tej wiadomości nie da się pokazać w Emmie" : message.text)
                    .font(EmmaTypography.caption(.semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(EmmaTheme.chatNoticeText)
            if message.isUnavailableInApp {
                Text("Np. ankieta, zdjęcie do jednorazowego wyświetlenia, wiadomość usunięta albo edytowana. Treść jest w WhatsAppie.")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let onOpenWhatsApp {
                    Button {
                        EmmaHaptics.tap()
                        onOpenWhatsApp()
                    } label: {
                        Label("Otwórz w WhatsApp", systemImage: "arrow.up.forward.app")
                            .font(EmmaTypography.caption(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 32)
                            .background(EmmaTheme.chatGreen, in: Capsule())
                            .frame(minHeight: EmmaSpacing.hitTarget)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(EmmaCardButtonStyle())
                }
            }
            Text("\(message.isOutgoing ? "Wysłana" : "Od klienta") · \(clockText)")
                .font(EmmaTypography.bubbleMeta)
                .foregroundStyle(EmmaTheme.bubbleMeta)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 310)
        .background(EmmaTheme.chatNoticeBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(EmmaTheme.chatNoticeBorder, lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Plik

    /// Karta pliku. Dotknięcie — menu czynności; bez czynności (np. plik
    /// wysłany przez kancelarię) — sama karta.
    @ViewBuilder
    private var attachment: some View {
        if let actions = attachmentActions, !actions.isEmpty {
            Menu {
                if let open = actions.openInWhatsApp {
                    Button(action: open) {
                        Label("Otwórz w WhatsApp", systemImage: "arrow.up.forward.app")
                    }
                }
                if let maps = actions.openInMaps {
                    Button(action: maps) {
                        Label("Pokaż w Mapach", systemImage: "map")
                    }
                }
                if let add = actions.addToCase {
                    Button(action: add) {
                        Label("Dołącz do akt sprawy", systemImage: "tray.and.arrow.down")
                    }
                }
                if let count = actions.countDeadline {
                    Button(action: count) {
                        Label("Policz termin od doręczenia", systemImage: "calendar.badge.clock")
                    }
                }
            } label: {
                AttachmentCard(message: message, interactive: true, reservesMeta: metaOnCard)
            }
            .accessibilityHint("Otwiera czynności przy pliku")
        } else {
            AttachmentCard(message: message, interactive: false, reservesMeta: metaOnCard)
        }
    }

    @ViewBuilder
    private func quoteView(_ quote: QuotedReference) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(EmmaTheme.quoteRule)
                .frame(width: 3)
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
            .padding(.vertical, 6)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 8)
        .background(EmmaTheme.quoteBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var clockText: String {
        dependencies.dateText.clockTime(message.sentAt)
    }
}

// MARK: Karta pliku

/// Plik od klienta bez podglądu (sam plik zostaje w WhatsAppie), ale z tym,
/// co widać od razu: rodzaj, rozszerzenie, nazwa. Zdjęcie i film to kafel,
/// nagranie — „fala” jak w WhatsAppie, dokument — znacznik PDF/DOC.
struct AttachmentCard: View {

    let message: Message
    let interactive: Bool
    /// Miejsce na godzinę w prawym dolnym rogu karty.
    var reservesMeta = false

    var body: some View {
        Group {
            switch message.kind {
            case .image, .video, .sticker:
                mediaTile
            case .audio:
                voiceNote
                    .padding(.bottom, reservesMeta ? 12 : 0)
            case .location:
                locationTile
                    .padding(.bottom, reservesMeta ? 12 : 0)
            default:
                document
                    .padding(.bottom, reservesMeta ? 12 : 0)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.attachmentLabel ?? message.kind.displayName)
    }

    private var hint: String {
        interactive ? "Dotknij — otwórz w WhatsApp" : "Plik w WhatsApp"
    }

    private var document: some View {
        HStack(spacing: 11) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(badgeColor.opacity(0.13))
                    .frame(width: 38, height: 46)
                Image(systemName: "doc.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(badgeColor.opacity(0.85))
                    .frame(width: 38, height: 46)
                if let ext = message.attachmentExtension {
                    Text(ext)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(badgeColor, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .offset(y: 4)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(message.attachmentName ?? message.kind.displayName)
                    .font(EmmaTypography.ui(14, .semibold))
                    .foregroundStyle(EmmaTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(hint)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.muted)
            }
            Spacer(minLength: 0)
            if interactive {
                Image(systemName: "chevron.down.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(EmmaTheme.quoteRule)
            }
        }
        .padding(9)
        .frame(minWidth: 220, alignment: .leading)
        .background(EmmaTheme.quoteBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var badgeColor: Color {
        switch message.attachmentExtension {
        case "PDF": return EmmaTheme.filePDF
        case "DOC", "DOCX", "ODT", "RTF", "PAGES": return EmmaTheme.fileWord
        case "XLS", "XLSX", "ODS", "CSV", "NUMBERS": return EmmaTheme.fileSheet
        default: return EmmaTheme.fileOther
        }
    }

    private var mediaTile: some View {
        ZStack {
            LinearGradient(
                colors: [EmmaTheme.mediaTileStart, EmmaTheme.mediaTileEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: message.kind == .video ? "play.circle.fill" : message.kind == .sticker ? "face.smiling" : "photo")
                .font(.system(size: message.kind == .video ? 40 : 34, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.95))
                .shadow(color: EmmaTheme.bubbleShadow, radius: 3, y: 1)
        }
        .frame(width: 230, height: message.kind == .sticker ? 110 : 140)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 5) {
                Image(systemName: message.kind.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(message.kind.displayName) · w WhatsApp")
                    .font(EmmaTypography.ui(12, .semibold))
            }
            .foregroundStyle(EmmaTheme.ink.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.8), in: Capsule())
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var voiceNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(EmmaTheme.quoteRule)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(Array(waveform.enumerated()), id: \.offset) { _, level in
                        Capsule()
                            .fill(EmmaTheme.quoteRule.opacity(0.55))
                            .frame(width: 3, height: 4 + 18 * level)
                    }
                }
                .frame(height: 22)
                Text("Nagranie głosowe · \(interactive ? "odsłuchaj w WhatsApp" : "w WhatsApp")")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.muted)
            }
        }
        .padding(.vertical, 3)
        .frame(minWidth: 220, alignment: .leading)
    }

    /// Stała „fala” z identyfikatora wiadomości — to ozdoba, nie prawdziwe audio,
    /// ale każde nagranie wygląda inaczej i nie skacze przy odświeżeniu.
    private var waveform: [CGFloat] {
        var seed: UInt32 = 2_166_136_261
        for byte in message.id.rawValue.utf8 {
            seed = (seed ^ UInt32(byte)) &* 16_777_619
        }
        return (0..<26).map { index in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = CGFloat(seed >> 24) / 255
            let envelope = sin(CGFloat(index) / 25 * .pi) * 0.6 + 0.4
            return min(1, max(0.08, noise * envelope))
        }
    }

    private var locationTile: some View {
        HStack(spacing: 11) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(EmmaTheme.filePDF)
                .frame(width: 46, height: 46)
                .background(EmmaTheme.fileSheet.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(message.caption ?? "Lokalizacja")
                    .font(EmmaTypography.ui(14, .semibold))
                    .foregroundStyle(EmmaTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(interactive ? "Lokalizacja · dotknij, aby otworzyć" : "Lokalizacja")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(minWidth: 220, alignment: .leading)
        .background(EmmaTheme.quoteBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

// MARK: Treść z linkami

enum ChatText {

    /// Tekst z klikalnymi adresami stron. Wykrywamy tylko linki — numery
    /// (PESEL, sygnatury) nie mogą stać się przypadkiem numerem do dzwonienia.
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let lowered = text.lowercased()
        guard lowered.contains("http") || lowered.contains("www.") else { return result }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return result
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url,
                  let stringRange = Range(match.range, in: text),
                  let attributedRange = Range(stringRange, in: result) else { continue }
            result[attributedRange].link = url
        }
        return result
    }
}

// MARK: Tło rozmowy

/// Ciche tło historii — rzadkie kropki jak tapeta WhatsAppa, żeby dymki
/// nie „wisiały” na płaskim kolorze.
struct ChatWallpaper: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 24
            var row = 0
            var y: CGFloat = 6
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 6 : 6 + step / 2
                while x < size.width {
                    let radius: CGFloat = (Int(x / step) + row).isMultiple(of: 3) ? 1.6 : 1.1
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(EmmaTheme.chatWallpaperDot)
                    )
                    x += step
                }
                y += step
                row += 1
            }
        }
        .background(EmmaTheme.chatBackground)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// „Na dół” nad polem wiadomości, gdy historia jest przewinięta w górę;
/// z licznikiem wiadomości, które w tym czasie przyszły.
struct JumpToLatestButton: View {
    let newCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EmmaTheme.muted)
                .frame(width: 40, height: 40)
                .background(EmmaTheme.surface, in: Circle())
                .shadow(color: EmmaTheme.bubbleShadow, radius: 4, y: 2)
                .overlay(alignment: .topTrailing) {
                    if newCount > 0 {
                        Text("\(newCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(EmmaTheme.chatGreen, in: Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
                .frame(width: EmmaSpacing.hitTarget, height: EmmaSpacing.hitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(newCount > 0 ? "Przewiń do najnowszych, \(EmmaPlural.unread(newCount))" : "Przewiń do najnowszych")
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
