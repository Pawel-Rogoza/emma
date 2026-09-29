import SwiftUI

// MARK: - Pasek zakładek
//
// Odtworzenie `nav()` z referencji: pięć zakładek, środkowa (Emma) w ciemnym
// „chipie”, plakietka nieprzeczytanych na zakładce „Rozmowy”.
//
// Świadomie **nie** używamy `TabView`: referencja ma własny pasek z chipem Emmy,
// a natywny pasek iOS nie pozwala odtworzyć tego wyglądu bez utraty zgodności.

public struct EmmaTabBar: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Binding private var selection: AppTab
    private let unreadCount: Int
    /// Zgłoszenia do obsługi — plakietka na zakładce „Klienci”.
    private let leadCount: Int
    /// Licznik „odbić” ikony — tylko nowo wybrana zakładka podskakuje
    /// (efekt na samym `isSelected` ruszałby też ikonę, którą opuszczamy).
    @State private var bounces: [AppTab: Int] = [:]
    /// Pigułka pod wybraną ikoną przesuwa się między zakładkami (audyt 29.09.2026).
    @Namespace private var selectionSpace

    public init(selection: Binding<AppTab>, unreadCount: Int, leadCount: Int = 0) {
        self._selection = selection
        self.unreadCount = unreadCount
        self.leadCount = leadCount
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        // Liczniki pojawiają się i zmieniają sprężyście, a nie skokiem.
        .animation(EmmaMotion.bouncy, value: unreadCount)
        .animation(EmmaMotion.bouncy, value: leadCount)
        .padding(.horizontal, 6)
        .padding(.top, EmmaMetrics.tabBarTopPadding)
        .padding(.bottom, EmmaMetrics.tabBarBottomPadding)
        .background(EmmaTheme.tabBarBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(EmmaTheme.tabBarBorder).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = tab == selection
        Button {
            // Ponowne dotknięcie aktywnej zakładki wraca do jej ekranu głównego —
            // zachowanie standardowe dla pasków zakładek (popToRoot).
            if isSelected {
                dependencies.go(to: tab, resetStack: true)
            } else {
                EmmaHaptics.selection()
                bounces[tab, default: 0] += 1
                withAnimation(EmmaMotion.smooth) { selection = tab }
            }
        } label: {
            VStack(spacing: 3) {
                if tab.isEmmaChip {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isSelected ? EmmaTheme.tabEmmaChipText : EmmaTheme.ink)
                        .frame(width: EmmaMetrics.tabEmmaChipWidth, height: EmmaMetrics.tabEmmaChipHeight)
                        .background(isSelected ? EmmaTheme.tabEmmaChip : EmmaTheme.controlBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .symbolEffect(.bounce, value: bounces[tab, default: 0])
                } else {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? EmmaTheme.tabActive : EmmaTheme.tabInactive)
                            // Wybrana ikona „odbija” — drobny, ale czytelny znak,
                            // że przejście zaszło (audyt 28.09.2026).
                            .symbolEffect(.bounce, value: bounces[tab, default: 0])
                            .frame(width: 52, height: EmmaMetrics.tabEmmaChipHeight)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(EmmaTheme.accentSoft)
                                        .matchedGeometryEffect(id: "tab-selection", in: selectionSpace)
                                }
                            }
                        if tab == .messages && unreadCount > 0 {
                            UnreadBadge(count: unreadCount, compact: true)
                                .contentTransition(.numericText())
                                .transition(.scale.combined(with: .opacity))
                                .offset(x: 10, y: -4)
                        }
                        if tab == .clients && leadCount > 0 {
                            CountBadge(count: leadCount, accessibilityText: EmmaPlural.leads(leadCount))
                                .contentTransition(.numericText())
                                .transition(.scale.combined(with: .opacity))
                                .offset(x: 12, y: -4)
                        }
                    }
                }
                Text(tab.title)
                    .font(EmmaTypography.tabLabel)
                    .foregroundStyle(isSelected ? EmmaTheme.tabActive : EmmaTheme.tabInactive)
                    // Pięć stałych kolumn nie mieści etykiet przy największym tekście
                    // dostępności: „Kalendarz” nachodziło na sąsiednie zakładki.
                    // Pasek to nawigacja, nie treść — ograniczamy skalę i pozwalamy
                    // etykiecie zmniejszyć się w jednej linii, zamiast się nakładać.
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .frame(maxWidth: .infinity, minHeight: EmmaMetrics.tabItemMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: tab))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        // Identyfikator dla testów interfejsu: etykieta zmienia się wraz z licznikiem
        // nieprzeczytanych, więc nie nadaje się na stały uchwyt.
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }

    private func accessibilityLabel(for tab: AppTab) -> String {
        if tab == .messages && unreadCount > 0 {
            return "\(tab.title), \(EmmaPlural.unread(unreadCount))"
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
