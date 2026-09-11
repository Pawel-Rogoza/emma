import SwiftUI

// MARK: - Powłoka aplikacji
//
// Pięć zakładek z referencji, jeden pasek zakładek, jeden gospodarz arkuszy
// i jeden komunikat potwierdzający. Powłoka nie zna szczegółów ekranów —
// zna wyłącznie trasy (`AppRoute`) i arkusze (`AppSheet`).

public struct RootShell: View {
    @EnvironmentObject private var dependencies: AppDependencies

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                EmmaTheme.bg
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            EmmaTabBar(selection: $dependencies.tab, unreadCount: dependencies.unreadTotal)
        }
        .background(EmmaTheme.bg)
        .overlay(alignment: .bottom) { toastLayer }
        .sheet(item: $dependencies.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environmentObject(dependencies)
        }
        .onChange(of: dependencies.tab) { _, _ in
            // Wejście na zakładkę nie kończy rozmowy z Emmą: sesja głosowa ma
            // jednego właściciela i żyje dłużej niż widok (§5.3, §12.2).
            if dependencies.tab != .emma {
                dependencies.voice.viewDidDisappear()
            }
        }
        .onAppear { dependencies.refreshUnreadTotal() }
    }

    @ViewBuilder
    private var content: some View {
        switch dependencies.tab {
        case .today:
            TabContent(tab: .today) { TodayScreen() }
        case .clients:
            TabContent(tab: .clients) { ClientsScreen() }
        case .emma:
            TabContent(tab: .emma) { AssistantScreen() }
        case .messages:
            TabContent(tab: .messages) { MessagesScreen() }
        case .calendar:
            TabContent(tab: .calendar) { CalendarScreen() }
        }
    }

    @ViewBuilder
    private var toastLayer: some View {
        if let toast = dependencies.toast {
            TraceToast(toast)
                .padding(.horizontal, EmmaSpacing.screenH)
                .padding(.bottom, EmmaMetrics.tabBarHeight + 18)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Gospodarz arkuszy
//
// Jedno miejsce, w którym rozwijane są arkusze modalne. Każdy arkusz odpowiada
// jednemu wywołaniu `openSheet(…)` z referencji.

struct SheetHost: View {
    let sheet: AppSheet
    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        NavigationStack {
            Group {
                switch sheet {
                case .profile:
                    ProfileSheet()
                case .resetDemo:
                    ResetDemoSheet()
                case .newLead:
                    NewLeadSheet()
                case .assignOwner(let clientID):
                    AssignOwnerSheet(clientID: clientID)
                case .startCase(let clientID):
                    StartCaseSheet(clientID: clientID)
                case .caseSettings(let caseID):
                    CaseSettingsSheet(caseID: caseID)
                case .note(let clientID, let caseID):
                    NoteSheet(clientID: clientID, caseID: caseID)
                case .taskForm(let taskID, let clientID, let caseID):
                    TaskFormSheet(taskID: taskID, clientID: clientID, caseID: caseID)
                case .eventForm(let eventID, let clientID, let caseID):
                    EventFormSheet(eventID: eventID, clientID: clientID, caseID: caseID)
                case .eventDetail(let eventID):
                    EventDetailSheet(eventID: eventID)
                case .taskDetail(let taskID):
                    TaskDetailSheet(taskID: taskID)
                case .newConversation:
                    NewConversationSheet()
                case .conversationOptions(let threadID):
                    ConversationOptionsSheet(threadID: threadID)
                case .messageOptions(let threadID, let messageID):
                    MessageOptionsSheet(threadID: threadID, messageID: messageID)
                case .emmaContextSelection(let action):
                    EmmaContextSheet(action: action)
                }
            }
            .environment(\.emmaLayout, EmmaLayoutMetrics(width: EmmaMetrics.sheetMaxWidth))
        }
        .presentationDetents(sheet.detents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(EmmaRadii.sheet)
        .presentationBackground(EmmaTheme.sheetBackground)
    }
}

private extension AppSheet {
    /// Wysokości arkuszy. Trwałe wybory (np. opiekun) są niskie, formularze — wysokie.
    var detents: Set<PresentationDetent> {
        switch self {
        case .assignOwner, .conversationOptions, .messageOptions, .emmaContextSelection, .resetDemo:
            return [.height(320), .large]
        case .profile, .newLead, .startCase, .note, .taskForm, .taskDetail, .eventForm:
            return [.large]
        case .caseSettings, .newConversation, .eventDetail:
            return [.medium, .large]
        }
    }
}

/// Nagłówek arkusza: chwyt, tytuł i przycisk zamknięcia (`.sheet-header`).
public struct SheetHeader: View {
    private let title: String
    private let onClose: () -> Void

    public init(title: String, onClose: @escaping () -> Void) {
        self.title = title
        self.onClose = onClose
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(EmmaTypography.heading(17))
                .foregroundStyle(EmmaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EmmaTheme.muted)
                    .frame(width: EmmaMetrics.sheetCloseSize, height: EmmaMetrics.sheetCloseSize)
                    .background(EmmaTheme.closeButton, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zamknij")
        }
        .padding(.bottom, 14)
    }
}

/// Wspólna oprawa arkusza z nagłówkiem i przewijaniem.
public struct SheetScaffold<Content: View>: View {
    private let title: String
    private let onClose: () -> Void
    private let content: Content

    public init(title: String, onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onClose = onClose
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(title: title, onClose: onClose)
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(EmmaTheme.sheetBackground)
    }
}

#Preview("Powłoka z pięcioma zakładkami") {
    RootShell()
        .environmentObject(AppDependencies.demo())
}
