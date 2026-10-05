import SwiftUI

// MARK: - Powierzchnie i nagłówki

/// Biała karta z obramowaniem i promieniem z referencji (`.card`).
public struct SurfaceCard<Content: View>: View {
    private let padding: EdgeInsets
    private let content: Content

    public init(
        padding: EdgeInsets = EdgeInsets(top: 16, leading: 17, bottom: 16, trailing: 17),
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .emmaCardShadow()
    }
}

/// Nagłówek sekcji: tytuł i opcjonalna akcja tekstowa po prawej.
public struct SectionHeader: View {
    private let title: String
    private let actionTitle: String?
    private let compact: Bool
    private let action: (() -> Void)?

    /// `compact` zmniejsza odstępy nagłówka. Używa tego ekran „Dzisiaj” (etap 3
    /// audytu), gdzie najbliższy termin i zadania mają zmieścić się nad zgięciem
    /// ekranu — pełne odstępy sekcji spychały je poza pierwszy widok.
    public init(
        _ title: String,
        actionTitle: String? = nil,
        compact: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.compact = compact
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(EmmaTypography.sectionTitle)
                .foregroundStyle(EmmaTheme.ink)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(EmmaTypography.caption(.medium))
                    .foregroundStyle(EmmaTheme.accent)
                    .frame(minHeight: EmmaSpacing.hitTarget)
                    .contentShape(Rectangle())
            }
        }
        .frame(minHeight: compact ? 30 : EmmaSpacing.sectionHeaderMinHeight, alignment: .bottom)
        .padding(.top, compact ? 12 : EmmaSpacing.sectionTop)
        .padding(.bottom, compact ? 6 : EmmaSpacing.sectionBottom)
    }
}

/// Nagłówek ekranu głównego: kicker z datą, powitanie i awatar użytkownika.
public struct ScreenHeader: View {
    private let kicker: String
    private let title: String
    private let onProfileTap: (() -> Void)?

    /// Nagłówek ekranu: podpis z datą i tytuł.
    ///
    /// Nie ma tu awatara z inicjałami użytkownika. Konto jest jedno i wspólne dla
    /// kancelarii, więc plakietka „KR” nic nie wnosiła, a zabierała uwagę
    /// (decyzja właściciela). Wejście do profilu jest opcjonalne i celowo ciche —
    /// na ekranie „Dzisiaj” to jedyne miejsce, z którego można się wylogować
    /// albo zablokować aplikację.
    public init(kicker: String, title: String, onProfileTap: (() -> Void)? = nil) {
        self.kicker = kicker
        self.title = title
        self.onProfileTap = onProfileTap
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(kicker)
                    .font(EmmaTypography.kicker)
                    .tracking(1.5)
                    .foregroundStyle(EmmaTheme.mutedSoft)
                Text(title)
                    .font(EmmaTypography.welcome)
                    .tracking(-0.9)
                    .foregroundStyle(EmmaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onProfileTap {
                Button(action: onProfileTap) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(EmmaTheme.mutedSoft)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profil kancelarii")
            }
        }
        .padding(.bottom, 4)
    }
}

/// Nagłówek ekranu szczegółu: przycisk powrotu, podpis i tytuł.
public struct DetailHeader: View {
    private let caption: String
    private let title: String
    private let onBack: () -> Void
    private let trailing: AnyView?

    public init(
        caption: String,
        title: String,
        onBack: @escaping () -> Void,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) {
        self.caption = caption
        self.title = title
        self.onBack = onBack
        self.trailing = AnyView(trailing())
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(EmmaTheme.ink)
                    .frame(width: EmmaSpacing.hitTarget, height: EmmaSpacing.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wróć")

            VStack(alignment: .leading, spacing: 3) {
                Text(caption.uppercased())
                    .font(EmmaTypography.caption(.semibold))
                    .tracking(1)
                    .foregroundStyle(EmmaTheme.mutedSoft)
                Text(title)
                    .font(EmmaTypography.detailTitle)
                    .foregroundStyle(EmmaTheme.ink)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.bottom, 12)
    }
}

// MARK: - Awatary

public struct PersonAvatar: View {

    public enum Style: Sendable {
        /// Karty osób, klientów i spraw.
        case person
        /// Stały kolor osoby liczony z jej identyfikatora (`IdentityTone`) —
        /// ta sama osoba wygląda tak samo na każdej liście (D-34).
        case identity(ClientID)
    }

    private let initials: String
    private let style: Style
    private let diameter: CGFloat

    public init(initials: String, style: Style = .person, diameter: CGFloat = EmmaMetrics.avatar) {
        self.initials = initials
        self.style = style
        self.diameter = diameter
    }

    public var body: some View {
        Text(initials)
            .font(.system(size: max(10, diameter * 0.30), weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background(background, in: Circle())
            .accessibilityHidden(true)
    }

    private var background: Color {
        switch style {
        case .person: return EmmaTheme.personAvatarBackground
        case .identity(let id): return EmmaTheme.identityAvatar(IdentityTone.index(for: id)).background
        }
    }

    private var foreground: Color {
        switch style {
        case .person: return EmmaTheme.personAvatarText
        case .identity(let id): return EmmaTheme.identityAvatar(IdentityTone.index(for: id)).foreground
        }
    }
}

// MARK: - Pigułki statusu

public struct StatusPill: View {

    public enum Kind: Sendable {
        case neutral
        case green
        case amber
        case urgent
        /// Termin za 0–3 dni na liście spraw.
        case danger

        var colors: (background: Color, text: Color) {
            switch self {
            case .neutral: return (EmmaTheme.pillNeutralBackground, EmmaTheme.pillNeutralText)
            case .green: return (EmmaTheme.pillGreenBackground, EmmaTheme.pillGreenText)
            case .amber: return (EmmaTheme.pillAmberBackground, EmmaTheme.pillAmberText)
            case .urgent: return (EmmaTheme.pillUrgentBackground, EmmaTheme.pillUrgentText)
            case .danger: return (EmmaTheme.pillDangerBackground, EmmaTheme.pillDangerText)
            }
        }
    }

    private let text: String
    private let kind: Kind

    public init(_ text: String, kind: Kind = .neutral) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        Text(text)
            .font(EmmaTypography.pill)
            .foregroundStyle(kind.colors.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(kind.colors.background)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.pill, style: .continuous))
    }
}

/// Licznik nieprzeczytanych wiadomości.
public struct UnreadBadge: View {
    private let count: Int
    private let compact: Bool

    public init(count: Int, compact: Bool = false) {
        self.count = count
        self.compact = compact
    }

    public var body: some View {
        Text("\(count)")
            .font(EmmaTypography.ui(compact ? 11 : 12, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: compact ? EmmaMetrics.tabBadgeMinWidth : 19,
                   minHeight: compact ? EmmaMetrics.tabBadgeHeight : 19)
            .background(EmmaTheme.unreadBadge, in: Capsule())
            .accessibilityLabel(EmmaPlural.unread(count))
    }
}

// MARK: - Sterowanie

/// Filtr segmentowy z referencji (`.segmented`).
public struct SegmentedFilter<Item: Hashable>: View {
    private let items: [Item]
    private let title: (Item) -> String
    @Binding private var selection: Item
    /// Wspólna przestrzeń dla przesuwanej „pigułki” wyboru.
    @Namespace private var selectionSpace

    public init(
        items: [Item],
        selection: Binding<Item>,
        title: @escaping (Item) -> String
    ) {
        self.items = items
        self._selection = selection
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    guard selection != item else { return }
                    EmmaHaptics.selection()
                    // Bez `withAnimation`: animowana byłaby też podmiana treści
                    // pod przełącznikiem (dwie listy przenikały się na zrzutach
                    // z CI). Rusza się tylko pigułka — patrz `.animation` niżej.
                    selection = item
                } label: {
                    Text(title(item))
                        .font(EmmaTypography.caption(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? EmmaTheme.ink : EmmaTheme.muted)
                        // Przy największym Dynamic Type etykiety filtrów („Nieprzeczytane”)
                        // nie mieszczą się w segmencie. Zamiast zawijać je w trzy linie
                        // (co rozjeżdżało pasek) — jedna linia i czytelne zmniejszenie.
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        // Filtr to kontrolka, nie treść — przy XXXL „Nieprzeczytane”
                        // nie mieści się w segmencie nawet po zmniejszeniu, więc
                        // ograniczamy skalę tak jak w pasku zakładek.
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .frame(maxWidth: .infinity, minHeight: EmmaMetrics.segmentedMinHeight - 6)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: EmmaRadii.segmentedInner, style: .continuous)
                                    .fill(EmmaTheme.controlSelected)
                                    .shadow(color: EmmaTheme.ink.opacity(0.08), radius: 3, x: 0, y: 1)
                                    .matchedGeometryEffect(id: "segment-selection", in: selectionSpace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(EmmaTheme.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.segmented, style: .continuous))
        .frame(minHeight: EmmaMetrics.segmentedMinHeight)
        // Biała pigułka przesuwa się do nowego segmentu, zamiast przeskoczyć.
        .animation(EmmaMotion.snappy, value: selection)
    }
}

/// Pole wyszukiwania z referencji (`.search`).
public struct SearchField: View {
    @Binding private var text: String
    private let placeholder: String
    /// Ekran może ustawić fokus (np. lupa na „Dzisiaj” otwiera od razu klawiaturę).
    private let isFocused: FocusState<Bool>.Binding?

    public init(text: Binding<String>, placeholder: String = "Szukaj", isFocused: FocusState<Bool>.Binding? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.isFocused = isFocused
    }

    @ViewBuilder
    private var field: some View {
        let base = TextField(placeholder, text: $text)
            .font(EmmaTypography.ui(16))
            .foregroundStyle(EmmaTheme.ink)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
        if let isFocused {
            base.focused(isFocused)
        } else {
            base
        }
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(EmmaTheme.muted)
            field
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(EmmaTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wyczyść wyszukiwanie")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: EmmaMetrics.searchMinHeight)
        .background(EmmaTheme.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.search, style: .continuous))
    }
}

/// Przyciski z referencji: `.primary` i `.secondary`.
public struct PrimaryButton: View {
    private let title: String
    private let systemImage: String?
    private let isEnabled: Bool
    /// Trwa zapis albo logowanie — kręciołek zamiast ikony, przycisk nieaktywny,
    /// ale w kolorze głównym (widać, że coś się dzieje, a nie że „nie działa”).
    private let isLoading: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    private var looksEnabled: Bool { isEnabled || isLoading }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(EmmaTheme.primaryButtonText)
                        .transition(.scale.combined(with: .opacity))
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                        .transition(.scale.combined(with: .opacity))
                }
                Text(title).font(EmmaTypography.button)
            }
            .foregroundStyle(looksEnabled ? EmmaTheme.primaryButtonText : EmmaTheme.disabledButtonText)
            .frame(maxWidth: .infinity, minHeight: EmmaMetrics.primaryButtonMinHeight)
            .background(looksEnabled ? EmmaTheme.primaryButton : EmmaTheme.disabledButton)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous))
            .shadow(color: EmmaTheme.primaryButton.opacity(looksEnabled ? 0.18 : 0), radius: 8, x: 0, y: 4)
            .contentShape(Rectangle())
        }
        // Audyt 29.09.2026: główny przycisk nie reagował na dotyk — teraz zapada
        // się pod palcem, a przejście aktywny/nieaktywny jest płynne.
        .buttonStyle(EmmaCardButtonStyle())
        .animation(EmmaMotion.smooth, value: isEnabled)
        .animation(EmmaMotion.smooth, value: isLoading)
        .disabled(!isEnabled || isLoading)
    }
}

public struct SecondaryButton: View {
    private let title: String
    private let systemImage: String?
    private let isEnabled: Bool
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(EmmaTypography.button)
            }
            .foregroundStyle(EmmaTheme.secondaryButtonText)
            .frame(maxWidth: .infinity, minHeight: EmmaMetrics.primaryButtonMinHeight)
            .background(EmmaTheme.secondaryButton)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Kwadratowy przycisk ikony (`.icon-button`).
public struct IconButton: View {
    private let systemName: String
    private let accessibilityLabel: String
    private let isSelected: Bool
    private let size: CGFloat
    private let action: () -> Void

    public init(
        systemName: String,
        accessibilityLabel: String,
        isSelected: Bool = false,
        size: CGFloat = EmmaMetrics.iconButtonSize,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.isSelected = isSelected
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : EmmaTheme.secondaryButtonText)
                .frame(width: size, height: size)
                .background(isSelected ? EmmaTheme.primaryButton : EmmaTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.iconButton, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: EmmaRadii.iconButton, style: .continuous)
                        .strokeBorder(EmmaTheme.fieldBorder, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Listy informacji i formularze

public struct InfoList: View {
    public struct Row: Identifiable {
        public let id = UUID()
        public let label: String
        public let value: String
        public let isMultiline: Bool

        public init(_ label: String, _ value: String, isMultiline: Bool = false) {
            self.label = label
            self.value = value
            self.isMultiline = isMultiline
        }
    }

    private let rows: [Row]

    public init(_ rows: [Row]) {
        self.rows = rows
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .top, spacing: 12) {
                    Text(row.label)
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.muted)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(EmmaTypography.caption(.medium))
                        .foregroundStyle(EmmaTheme.ink)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
                if index < rows.count - 1 {
                    Divider().overlay(EmmaTheme.infoRowBorder)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(EmmaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(EmmaTheme.infoRowBorder, lineWidth: 1)
        }
    }
}

/// Etykieta i treść pola formularza (`.form-field`).
public struct LabeledField<Content: View>: View {
    private let label: String
    private let help: String?
    private let error: String?
    private let content: Content

    public init(
        _ label: String,
        help: String? = nil,
        error: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.help = help
        self.error = error
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(EmmaTypography.fieldLabel)
                .foregroundStyle(EmmaTheme.muted)
            content
            if let help {
                Text(help)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error)
                    .font(EmmaTypography.error)
                    .foregroundStyle(EmmaTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 14)
    }
}

/// Styl pola tekstowego zgodny z referencją.
public struct EmmaFieldStyle: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(EmmaTypography.fieldValue)
            .foregroundStyle(EmmaTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: EmmaMetrics.fieldMinHeight, alignment: .topLeading)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.field, style: .continuous)
                    .strokeBorder(EmmaTheme.fieldBorder, lineWidth: 1)
            }
    }
}

public extension View {
    func emmaFieldStyle() -> some View { modifier(EmmaFieldStyle()) }
}

/// Lista wyboru (`.choice-list`).
public struct ChoiceList<Item: Hashable>: View {
    private let items: [Item]
    private let title: (Item) -> String
    private let subtitle: ((Item) -> String)?
    private let onSelect: (Item) -> Void

    public init(
        items: [Item],
        title: @escaping (Item) -> String,
        subtitle: ((Item) -> String)? = nil,
        onSelect: @escaping (Item) -> Void
    ) {
        self.items = items
        self.title = title
        self.subtitle = subtitle
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title(item))
                                .font(EmmaTypography.ui(14, .medium))
                                .foregroundStyle(EmmaTheme.ink)
                                .multilineTextAlignment(.leading)
                            if let subtitle {
                                Text(subtitle(item))
                                    .font(EmmaTypography.caption())
                                    .foregroundStyle(EmmaTheme.mutedSoft)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(EmmaTheme.mutedSoft)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 14)
                    .frame(minHeight: EmmaMetrics.choiceRowMinHeight, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < items.count - 1 {
                    Divider().overlay(EmmaTheme.cardBorder)
                }
            }
        }
        .background(EmmaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.choiceList, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EmmaRadii.choiceList, style: .continuous)
                .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
        }
    }
}

// MARK: - Stany

public struct EmptyState: View {
    private let systemImage: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 10) {
            // Ikona w miękkim kółku akcentu — pusty stan to informacja, a nie
            // błąd (audyt 29.09.2026: szara ikona wyglądała jak „nic nie działa”).
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(EmmaTheme.accent)
                .frame(width: 62, height: 62)
                .background(EmmaTheme.accentSoft, in: Circle())
                .padding(.bottom, 4)
            Text(title)
                .font(EmmaTypography.ui(15, .semibold))
                .foregroundStyle(EmmaTheme.ink)
            Text(message)
                .font(EmmaTypography.emptyState)
                .foregroundStyle(EmmaTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                SecondaryButton(actionTitle, action: action)
                    .frame(maxWidth: 240)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .emmaAppear()
    }
}

/// Stan ładowania. Nie używamy nieskończonego wskaźnika bez etykiety.
public struct LoadingState: View {
    private let label: String

    public init(_ label: String = "Wczytuję…") {
        self.label = label
    }

    /// Audyt 28.09.2026: zamiast kręciołka z podpisem — szkielet trzech kart
    /// w kształcie treści, która zaraz się pojawi. Ekran od razu ma swój układ,
    /// a przejście do danych jest płynne, nie „mignięciem”.
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                skeletonCard(wide: index % 2 == 0)
            }
            Text(label)
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.mutedSoft)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func skeletonCard(wide: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(EmmaTheme.controlBackground)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 8) {
                Capsule()
                    .fill(EmmaTheme.controlBackground)
                    .frame(width: wide ? 170 : 130, height: 12)
                Capsule()
                    .fill(EmmaTheme.controlBackground.opacity(0.7))
                    .frame(width: wide ? 220 : 180, height: 10)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(EmmaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
        }
        .emmaShimmer()
    }
}

/// Komunikat błędu w formularzu (`.form-error`).
/// Błąd wczytania ekranu: komunikat plus ponowienie **tylko wtedy, gdy ma sens**.
///
/// Wcześniej każdy ekran decydował o tym sam: trzy pokazywały przycisk zawsze,
/// dziewięć nigdy. Reguła ponowienia jest w domenie (`DomainError.isRetryable`),
/// więc tutaj jest tylko jej wykonanie — jedno dla wszystkich ekranów.
public struct LoadFailureView: View {
    private let failure: LoadFailure
    private let retry: () -> Void

    public init(_ failure: LoadFailure, retry: @escaping () -> Void) {
        self.failure = failure
        self.retry = retry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InlineError(failure.message)
            if failure.isRetryable {
                SecondaryButton("Spróbuj ponownie", systemImage: "arrow.clockwise", action: retry)
            }
        }
    }
}

public struct InlineError: View {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        Text(message)
            .font(EmmaTypography.error)
            .foregroundStyle(EmmaTheme.danger)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Krótkie potwierdzenie operacji (`#toast`), opcjonalnie z akcją („Cofnij”).
///
/// Akcja jest po to, żeby szybka czynność — obsłużenie leada, odhaczenie —
/// nie wymagała potwierdzenia przed, tylko dawała się odwrócić po.
public struct TraceToast: View {
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    /// Komunikaty o niepowodzeniu zaczynają się w aplikacji od „Nie…”
    /// („Nie udało się…”, „Nie znaleziono…”) — ikona mówi to, zanim się przeczyta.
    static func isFailure(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.hasPrefix("nie ") || lowered.contains("błąd") || lowered.contains("brak połączenia")
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Audyt 28.09.2026: sam tekst na granatowym tle nie odróżniał
            // „Zapisano” od „Nie udało się zapisać”.
            Image(systemName: Self.isFailure(message) ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Self.isFailure(message) ? EmmaTheme.pillAmberBackground : EmmaTheme.pillGreenBackground)
                .symbolEffect(.bounce, value: message)
                .accessibilityHidden(true)
            Text(message)
                .font(EmmaTypography.caption(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isStaticText)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(EmmaTypography.caption(.semibold))
                        .foregroundStyle(EmmaTheme.toastBackground)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(Color.white, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(minHeight: EmmaSpacing.hitTarget)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, actionTitle == nil ? 16 : 8)
        .padding(.vertical, actionTitle == nil ? 13 : 2)
        .background(EmmaTheme.toastBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 6)
    }
}

/// Licznik na zakładce albo przy nagłówku sekcji (np. leady do obsługi).
///
/// `UnreadBadge` mówi VoiceOver „nieprzeczytane wiadomości”, więc dla innych
/// liczników jest osobny element z własnym opisem.
public struct CountBadge: View {
    private let count: Int
    private let accessibilityText: String

    public init(count: Int, accessibilityText: String) {
        self.count = count
        self.accessibilityText = accessibilityText
    }

    public var body: some View {
        Text("\(count)")
            .font(EmmaTypography.ui(12, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: EmmaMetrics.tabBadgeMinWidth, minHeight: EmmaMetrics.tabBadgeHeight)
            .background(EmmaTheme.unreadBadge, in: Capsule())
            .accessibilityLabel(accessibilityText)
    }
}

// MARK: - Elementy kancelarii

/// Szybkie akcje (`.quick-actions`): cztery kafle z ikoną i etykietą.
public struct QuickActions: View {
    public struct Action: Identifiable {
        public let id = UUID()
        public let systemImage: String
        public let title: String
        public let handler: () -> Void

        public init(systemImage: String, title: String, handler: @escaping () -> Void) {
            self.systemImage = systemImage
            self.title = title
            self.handler = handler
        }
    }

    private let actions: [Action]

    public init(_ actions: [Action]) {
        self.actions = actions
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                Button {
                    EmmaHaptics.tap()
                    action.handler()
                } label: {
                    // Audyt 29.09.2026: szare ikony na białym tle nie wyglądały na
                    // przyciski. Ikona w kafelku akcentu, cień i zapadnięcie pod palcem.
                    VStack(spacing: 7) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(EmmaTheme.accent)
                            .frame(width: 36, height: 36)
                            .background(EmmaTheme.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        Text(action.title)
                            .font(EmmaTypography.caption(.medium))
                            .foregroundStyle(EmmaTheme.ink)
                            .multilineTextAlignment(.center)
                            // Pięć kafelków na 375 pt: jednowyrazowy podpis
                            // („Zadzwoń”) zmniejsza się, zamiast łamać się w środku słowa.
                            .lineLimit(actions.count > 4 ? 1 : 2)
                            .minimumScaleFactor(actions.count > 4 ? 0.8 : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: EmmaMetrics.quickActionMinHeight)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 10)
                    .background(EmmaTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
                    }
                    .emmaCardShadow()
                    .contentShape(Rectangle())
                }
                .buttonStyle(EmmaCardButtonStyle())
                .emmaAppear(index)
                .accessibilityLabel(action.title)
            }
        }
    }
}

/// Statystyki nagłówka przestrzeni roboczej (`.workspace-stats`).
public struct WorkspaceStats: View {
    public struct Item: Identifiable {
        public let id = UUID()
        public let value: String
        public let label: String

        public init(value: String, label: String) {
            self.value = value
            self.label = label
        }
    }

    private let items: [Item]

    public init(_ items: [Item]) {
        self.items = items
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.value)
                        .font(EmmaTypography.heading(23))
                        .foregroundStyle(EmmaTheme.ink)
                    Text(item.label)
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.mutedSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if index < items.count - 1 {
                    Rectangle()
                        .fill(EmmaTheme.border)
                        .frame(width: 1, height: 34)
                        .padding(.trailing, 12)
                }
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

/// Wiersz historii sprawy (`.activity-row`).
public struct ActivityRow: View {
    private let text: String
    private let dateText: String

    public init(text: String, dateText: String) {
        self.text = text
        self.dateText = dateText
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(EmmaTheme.activityMarker)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(EmmaTypography.ui(13, .medium))
                    .foregroundStyle(EmmaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dateText)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.mutedSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Karta notatki z rozmowy (`.note-card`).
public struct NoteCard: View {
    private let text: String
    private let footer: String

    public init(text: String, footer: String) {
        self.text = text
        self.footer = footer
    }

    public var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(EmmaTypography.body(for: text, size: 14))
                    .foregroundStyle(EmmaTheme.ink.opacity(0.88))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(footer)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.mutedSoft)
            }
        }
    }
}

/// Wiersz zadania (`.task-row`).
public struct TaskRow: View {
    private let task: TaskItem
    private let dateText: String
    /// Nazwa klienta rozwiązana przez ekran. Wiersz nie zna repozytorium.
    private let clientName: String?
    private let onToggle: () -> Void
    private let onOpen: () -> Void

    public init(
        task: TaskItem,
        dateText: String,
        clientName: String?,
        onToggle: @escaping () -> Void,
        onOpen: @escaping () -> Void
    ) {
        self.task = task
        self.dateText = dateText
        self.clientName = clientName
        self.onToggle = onToggle
        self.onOpen = onOpen
    }

    public var body: some View {
        Group {
            // Przy rozmiarach dostępności trzy kolumny zostawiają tytułowi zbyt
            // wąskie pole i długie słowa łamią się w środku („zatrzyma / nia” na
            // zrzucie `25-duzy-tekst-zadania.png`). Data i plakietka schodzą
            // wtedy pod tytuł, na pełną szerokość.
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 11) {
                    checkButton
                    VStack(alignment: .leading, spacing: 6) {
                        openButton
                        dateLabel
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .top, spacing: 11) {
                    checkButton
                    openButton
                    VStack(alignment: .trailing, spacing: 6) {
                        dateLabel
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 15)
        .contentShape(Rectangle())
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Stan pokazany od razu po dotknięciu, zanim backend potwierdzi zapis.
    /// Audyt 28.09.2026: kółko zmieniało się dopiero po odświeżeniu listy
    /// (pół sekundy później), więc odhaczenie „nie trafiało”. Gdy zapis się
    /// nie uda, lista nie zmieni `task.isDone` i po chwili wracamy do prawdy.
    @State private var optimisticDone: Bool?

    private var isDone: Bool { optimisticDone ?? task.isDone }

    private var checkButton: some View {
        Button {
            let target = !isDone
            if target { EmmaHaptics.success() } else { EmmaHaptics.tap() }
            withAnimation(EmmaMotion.bouncy) { optimisticDone = target }
            onToggle()
        } label: {
            ZStack {
                // Świadomie nie „biały checkbox”: puste pole czytało się jak
                // formularz do wypełnienia, a nie jak zadanie do odhaczenia.
                // Pierścień pokazuje stan, a nie miejsce na treść.
                Circle()
                    .fill(isDone ? EmmaTheme.accent : Color.clear)
                    .scaleEffect(isDone ? 1 : 0.4)
                Circle()
                    .strokeBorder(
                        isDone ? EmmaTheme.accent : EmmaTheme.accent.opacity(0.38),
                        lineWidth: isDone ? 0 : 1.6
                    )
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(EmmaTheme.primaryButtonText)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .frame(width: EmmaMetrics.taskCheckSize, height: EmmaMetrics.taskCheckSize)
            .frame(width: EmmaSpacing.hitTarget, height: EmmaSpacing.hitTarget, alignment: .topLeading)
            .contentShape(Rectangle())
            .animation(EmmaMotion.bouncy, value: isDone)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "Przywróć zadanie" : "Oznacz jako wykonane")
        .onChange(of: task.isDone) { _, _ in optimisticDone = nil }
        .task(id: optimisticDone) {
            // Bezpiecznik na nieudany zapis: bez potwierdzenia po 4 s wracamy do stanu z danych.
            guard optimisticDone != nil else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { withAnimation(EmmaMotion.smooth) { optimisticDone = nil } }
        }
    }

    private var openButton: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(EmmaTypography.taskTitle)
                    .foregroundStyle(EmmaTheme.ink)
                    .strikethrough(isDone, color: EmmaTheme.mutedSoft)
                    .opacity(isDone ? 0.6 : 1)
                    .animation(EmmaMotion.smooth, value: isDone)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(TaskItem.taskMeta(clientName: clientName))
                    .font(EmmaTypography.taskMeta)
                    .foregroundStyle(EmmaTheme.taskMetaText)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dateLabel: some View {
        Text(dateText)
            .font(EmmaTypography.taskDate)
            // Wyróżnienie liczy rdzeń (`showsUrgentBadge`), a nie sam priorytet:
            // referencja pokazuje je tylko dla zadań niewykonanych.
            .foregroundStyle(task.showsUrgentBadge ? EmmaTheme.pillUrgentText : EmmaTheme.taskDateText)
            .padding(.horizontal, task.showsUrgentBadge ? 7 : 0)
            .padding(.vertical, task.showsUrgentBadge ? 5 : 0)
            .background(task.showsUrgentBadge ? EmmaTheme.pillUrgentBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.pill, style: .continuous))
    }
}
