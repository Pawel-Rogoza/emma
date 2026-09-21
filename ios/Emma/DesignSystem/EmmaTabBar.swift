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

    public init(selection: Binding<AppTab>, unreadCount: Int) {
        self._selection = selection
        self.unreadCount = unreadCount
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
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
                selection = tab
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
                } else {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? EmmaTheme.tabActive : EmmaTheme.tabInactive)
                            .frame(height: EmmaMetrics.tabEmmaChipHeight)
                        if tab == .messages && unreadCount > 0 {
                            UnreadBadge(count: unreadCount, compact: true)
                                .offset(x: 10, y: -4)
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
