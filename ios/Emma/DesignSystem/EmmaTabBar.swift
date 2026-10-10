import SwiftUI

// MARK: - Pasek zakładek
//
// Redesign 0.22.0 (iOS 26): pływająca kapsuła z materiałem Liquid Glass nad
// treścią (treść przewija się pod nią), cztery zwykłe zakładki i **Emma
// w środku** jako wyeksponowany, uniesiony przycisk z jej portretem — decyzja
// właściciela: Emma zostaje środkową zakładką, ale ma się wyróżniać.
//
// Świadomie nie używamy `TabView`: systemowy pasek nie pozwala wyróżnić jednej
// zakładki. Materiał (`glassEffect`) jest jednak systemowy, więc pasek wygląda
// jak reszta iOS 26.

public struct EmmaTabBar: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Binding private var selection: AppTab
    private let unreadCount: Int
    /// Zgłoszenia do obsługi — plakietka na zakładce „Klienci”.
    private let leadCount: Int
    /// Licznik „odbić” ikony — tylko nowo wybrana zakładka podskakuje.
    @State private var bounces: [AppTab: Int] = [:]
    /// Pigułka pod wybraną ikoną przesuwa się między zakładkami.
    @Namespace private var selectionSpace

    public init(selection: Binding<AppTab>, unreadCount: Int, leadCount: Int = 0) {
        self._selection = selection
        self.unreadCount = unreadCount
        self.leadCount = leadCount
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                if tab.isEmmaChip {
                    // Niewidoczna kopia trzyma w szkle miejsce i wysokość Emmy.
                    emmaButton(tab)
                        .hidden()
                        .accessibilityHidden(true)
                } else {
                    tabButton(tab)
                }
            }
        }
        // Liczniki pojawiają się i zmieniają sprężyście, a nie skokiem.
        .animation(EmmaMotion.bouncy, value: unreadCount)
        .animation(EmmaMotion.bouncy, value: leadCount)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular.interactive(), in: Capsule())
        // Emma leży **nad** szkłem, nie w nim. Treść wewnątrz `glassEffect`
        // jest przycinana do kapsuły przy każdym przerysowaniu szkła (zmiana
        // zakładki, przenikanie treści pod spodem), więc wystająca nad pasek
        // górna część okręgu mrugała i znikała. Ten sam rząd miejsc co pod
        // spodem trzyma ją dokładnie w środkowym gnieździe.
        .overlay {
            HStack(alignment: .center, spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    if tab.isEmmaChip {
                        emmaButton(tab)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private func select(_ tab: AppTab) {
        // Ponowne dotknięcie aktywnej zakładki wraca do jej ekranu głównego.
        if tab == selection {
            dependencies.go(to: tab, resetStack: true)
        } else {
            EmmaHaptics.selection()
            bounces[tab, default: 0] += 1
            withAnimation(EmmaMotion.smooth) { selection = tab }
        }
    }

    // MARK: Emma — środek paska

    private func emmaButton(_ tab: AppTab) -> some View {
        let isSelected = tab == selection
        return Button {
            select(tab)
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(EmmaTheme.surface)
                    EmmaOrb(size: .compact)
                        .clipShape(Circle())
                        .padding(3)
                }
                .frame(width: EmmaMetrics.tabEmmaButton, height: EmmaMetrics.tabEmmaButton)
                .overlay {
                    Circle()
                        .strokeBorder(EmmaTheme.emma, lineWidth: isSelected ? 3 : 2)
                }
                .shadow(color: EmmaTheme.emma.opacity(isSelected ? 0.45 : 0.25), radius: isSelected ? 10 : 6, y: 3)
                .scaleEffect(isSelected ? 1.04 : 1)
                .symbolEffect(.bounce, value: bounces[tab, default: 0])
                // Przycisk wystaje ponad kapsułę — znak, że to główne wejście.
                .offset(y: -12)
                .padding(.bottom, -12)

                Text(tab.title)
                    .font(EmmaTypography.tabLabel)
                    .fontWeight(.semibold)
                    .foregroundStyle(EmmaTheme.emma)
                    .lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .frame(maxWidth: .infinity, minHeight: EmmaMetrics.tabItemMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(EmmaMotion.bouncy, value: isSelected)
        .accessibilityLabel("Emma, asystentka")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }

    // MARK: Zwykła zakładka

    @ViewBuilder
    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = tab == selection
        Button {
            select(tab)
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .symbolVariant(isSelected ? .fill : .none)
                        .foregroundStyle(isSelected ? EmmaTheme.tabActive : EmmaTheme.tabInactive)
                        .symbolEffect(.bounce, value: bounces[tab, default: 0])
                        .frame(width: 48, height: 30)
                    if tab == .messages && unreadCount > 0 {
                        UnreadBadge(count: unreadCount, compact: true)
                            .contentTransition(.numericText())
                            .transition(.scale.combined(with: .opacity))
                            .offset(x: 8, y: -4)
                    }
                    if tab == .clients && leadCount > 0 {
                        CountBadge(count: leadCount, accessibilityText: EmmaPlural.leads(leadCount))
                            .contentTransition(.numericText())
                            .transition(.scale.combined(with: .opacity))
                            .offset(x: 10, y: -4)
                    }
                }
                Text(tab.title)
                    .font(EmmaTypography.tabLabel)
                    .foregroundStyle(isSelected ? EmmaTheme.tabActive : EmmaTheme.tabInactive)
                    // Pasek to nawigacja, nie treść — przy największym tekście
                    // etykieta zmniejsza się w jednej linii, zamiast nachodzić.
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: EmmaMetrics.tabItemMinHeight)
            .background {
                if isSelected {
                    Capsule()
                        .fill(EmmaTheme.accentSoft)
                        .matchedGeometryEffect(id: "tab-selection", in: selectionSpace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: tab))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        // Identyfikator dla testów interfejsu: etykieta zmienia się wraz z licznikiem.
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }

    private func accessibilityLabel(for tab: AppTab) -> String {
        if tab == .messages && unreadCount > 0 {
            return "\(tab.title), \(EmmaPlural.unreadConversations(unreadCount))"
        }
        if tab == .clients && leadCount > 0 {
            return "\(tab.title), \(EmmaPlural.leads(leadCount)) do obsługi"
        }
        return tab.title
    }
}

// MARK: - Ramka treści zakładki

/// Wspólna oprawa treści: `NavigationStack` z własnym stosem zakładki,
/// margines boczny zależny od szerokości ekranu i cel nawigacji dla tras.
public struct TabContent<Root: View>: View {
    private let tab: AppTab
    private let root: Root

    public init(tab: AppTab, @ViewBuilder root: () -> Root) {
        self.tab = tab
        self.root = root()
    }

    @EnvironmentObject private var dependencies: AppDependencies

    public var body: some View {
        NavigationStack(path: dependencies.binding(for: tab)) {
            GeometryReader { proxy in
                root
                    .environment(\.emmaLayout, EmmaLayoutMetrics(width: proxy.size.width))
            }
            .navigationDestination(for: AppRoute.self) { route in
                RouteDestination(route: route)
            }
        }
    }
}

/// Rozwinięcie trasy na ekran. Wszystkie ekrany są tu wymienione raz,
/// dzięki czemu stos nawigacji jest sterowany danymi.
struct RouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .person(let clientID):
            ClientCardScreen(clientID: clientID)
        case .legalCase(let caseID):
            CaseScreen(caseID: caseID)
        case .tasks:
            TasksScreen()
        case .thread(let threadID):
            ThreadScreen(threadID: threadID)
        }
    }
}
