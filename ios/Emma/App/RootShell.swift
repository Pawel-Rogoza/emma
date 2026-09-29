import SwiftUI

// MARK: - Powłoka aplikacji
//
// Pięć zakładek z referencji, jeden pasek zakładek, jeden gospodarz arkuszy
// i jeden komunikat potwierdzający. Powłoka nie zna szczegółów ekranów —
// zna wyłącznie trasy (`AppRoute`) i arkusze (`AppSheet`).

public struct RootShell: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var quickActions = HomeScreenQuickActions.shared
    /// Przy otwartej klawiaturze pasek zakładek znika (jak w aplikacjach
    /// systemowych) — wcześniej unosił się nad klawiaturą i zabierał ~70 pt
    /// liście wyników i polu wiadomości (zrzut 19 z CI, audyt 28.09.2026).
    @State private var keyboardVisible = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                EmmaTheme.bg
                // Zakładki przenikają się zamiast przeskakiwać (animację
                // uruchamia pasek zakładek; `go(to:)` z kodu zostaje natychmiastowe).
                content
                    .id(dependencies.tab)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Mini-panel sesji (§4, F06): nad paskiem zakładek i **z rezerwacją
            // miejsca w układzie**, więc nie zasłania treści. Na ekranie Emmy
            // jest pełny panel sterowania, a nad arkuszem panel rysuje sam
            // arkusz — tutaj go wtedy nie ma, żeby nie istniała druga, ukryta
            // kopia tego samego sterowania (VoiceOver i testy trafiłyby w nią).
            if dependencies.voiceState.showsGlobalVoicePanel,
               dependencies.tab != .emma,
               dependencies.sheet == nil {
                VoiceMiniPanel(
                    state: dependencies.voiceState,
                    onOpen: { dependencies.go(to: .emma) },
                    onToggleMicrophone: { Task { await dependencies.toggleVoiceMicrophone() } },
                    onEnd: { Task { await dependencies.endVoiceSession() } }
                )
            }

            if !keyboardVisible {
                EmmaTabBar(
                    selection: $dependencies.tab,
                    unreadCount: dependencies.unreadTotal,
                    leadCount: dependencies.leadsNeedingAction
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            // Klawiatura arkusza nie dotyczy powłoki pod spodem.
            guard dependencies.sheet == nil else { return }
            withAnimation(EmmaMotion.smooth) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(EmmaMotion.smooth) { keyboardVisible = false }
        }
        .background(EmmaTheme.bg)
        .overlay(alignment: .bottom) {
            ToastLayer(bottomPadding: EmmaMetrics.tabBarHeight + 18)
        }
        .sheet(item: $dependencies.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environmentObject(dependencies)
                // Arkusz leży nad powłoką, więc zasłania też ekran blokady —
                // zasłaniamy go własną kopią blokady (stan i Face ID są wspólne).
                .overlay {
                    if auth.state == .locked {
                        LockScreen()
                    }
                }
                .environmentObject(auth)
        }
        .onChange(of: dependencies.tab) { _, _ in
            // Wejście na zakładkę nie kończy rozmowy z Emmą: sesja głosowa ma
            // jednego właściciela i żyje dłużej niż widok (§5.3, §12.2).
            if dependencies.tab != .emma {
                dependencies.voice.viewDidDisappear()
            }
        }
        // Skrót z ikony aplikacji — dopiero po odblokowaniu (Face ID).
        .onChange(of: quickActions.pending) { _, _ in consumeQuickAction() }
        .onChange(of: auth.state) { _, _ in consumeQuickAction() }
        .onAppear {
            consumeQuickAction()
            dependencies.refreshUnreadTotal()
            dependencies.refreshLeadCount()
            dependencies.reminders.scheduleRefresh(dependencies)
            // Literówka w nazwie zestawu danych nie może wyglądać jak „inne demo”:
            // pokazujemy ją raz, wprost, i zaraz zniknie.
            if let notice = dependencies.fixtureNotice {
                dependencies.fixtureNotice = nil
                dependencies.showToast(notice)
            }
        }
    }

    private func consumeQuickAction() {
        guard auth.state == .unlocked else { return }
        quickActions.consume(dependencies)
    }

    @ViewBuilder
    private var content: some View {
        switch dependencies.tab {
        case .today:
            TabContent(tab: .today) { TodayScreen(store: dependencies.todayStore) }
        case .clients:
            TabContent(tab: .clients) { ClientsScreen(store: dependencies.clientsStore) }
        case .emma:
            TabContent(tab: .emma) { AssistantScreen() }
        case .messages:
            TabContent(tab: .messages) { MessagesScreen(store: dependencies.messagesStore) }
        case .calendar:
            TabContent(tab: .calendar) { CalendarScreen(store: dependencies.calendarStore) }
        }
    }

}

/// Komunikat nad paskiem zakładek albo nad treścią arkusza. Bez akcji nie
/// przechwytuje dotyku (nie zasłania treści); z akcją („Cofnij”) musi dać się
/// nacisnąć.
///
/// Arkusz ma własną kopię warstwy: komunikat powłoki rysował się **pod**
/// arkuszem, więc potwierdzenia i błędy z formularzy były niewidoczne.
struct ToastLayer: View {
    @EnvironmentObject private var dependencies: AppDependencies
    let bottomPadding: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            if let toast = dependencies.toast {
                TraceToast(
                    toast,
                    actionTitle: dependencies.toastAction?.title,
                    // Przycisk pojawia się tylko razem z tytułem akcji.
                    action: { dependencies.runToastAction() }
                )
                .padding(.horizontal, EmmaSpacing.screenH)
                .padding(.bottom, bottomPadding)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .scale(scale: 0.92)).combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .allowsHitTesting(dependencies.toastAction != nil)
            }
        }
        .animation(EmmaMotion.bouncy, value: dependencies.toast)
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
            // Formularz prezentowany modalnie musi mieć sterowanie sesją, jeśli
            // rozmowa trwa pod spodem (F06). Panel jest **w układzie** arkusza,
            // nad jego treścią, a nie nakładką: dzięki temu klawiatura wypycha
            // go w górę i nie zasłania zakończenia rozmowy.
            VStack(spacing: 0) {
                Group {
                    switch sheet {
                    case .profile:
                        ProfileSheet()
                    case .resetDemo:
                        ResetDemoSheet()
                    case .newLead:
                        NewLeadSheet()
                    case .startCase(let clientID):
                        StartCaseSheet(clientID: clientID)
                    case .caseSettings(let caseID):
                        CaseSettingsSheet(caseID: caseID)
                    case .note(let clientID, let caseID):
                        NoteSheet(clientID: clientID, caseID: caseID)
                    case .taskForm(let taskID, let clientID, let caseID):
                        TaskFormSheet(taskID: taskID, clientID: clientID, caseID: caseID)
                    case .eventForm(let eventID, let clientID, let caseID, let initialDay):
                        EventFormSheet(
                            eventID: eventID,
                            clientID: clientID,
                            caseID: caseID,
                            initialDay: initialDay
                        )
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.emmaLayout, EmmaLayoutMetrics(width: EmmaMetrics.sheetMaxWidth))
                .overlay(alignment: .bottom) { ToastLayer(bottomPadding: 20) }

                if dependencies.voiceState.showsGlobalVoicePanel {
                    VoiceMiniPanel(
                        state: dependencies.voiceState,
                        onOpen: {
                            dependencies.dismissSheet()
                            dependencies.go(to: .emma)
                        },
                        onToggleMicrophone: { Task { await dependencies.toggleVoiceMicrophone() } },
                        onEnd: { Task { await dependencies.endVoiceSession() } }
                    )
                }
            }
        }
        .presentationDetents(sheet.detents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(EmmaRadii.sheet)
        .presentationBackground(EmmaTheme.sheetBackground)
    }
}

private extension AppSheet {
    /// Wysokości arkuszy. Trwałe wybory są niskie, formularze — wysokie.
    var detents: Set<PresentationDetent> {
        switch self {
        case .conversationOptions, .messageOptions, .emmaContextSelection, .resetDemo:
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
        .environmentObject(AuthStore(authenticator: PreviewBiometricAuthenticator(), defaults: UserDefaults(suiteName: "preview.shell")!))
}
