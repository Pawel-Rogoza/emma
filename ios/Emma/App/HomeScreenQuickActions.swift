import SwiftUI
import UIKit

// MARK: - Szybkie akcje z ikony aplikacji
//
// Audyt 28.09.2026 („bez pierdolenia się”): przytrzymanie ikony Emmy daje trzy
// wejścia — nowy termin, nowe zadanie, rozmowa z Emmą. Lista jest statyczna
// (`UIApplicationShortcutItems` w Info.plist), tu jest tylko jej obsługa.
//
// SwiftUI nie przekazuje skrótu wprost, więc delegat sceny odkłada go
// w `HomeScreenQuickActions.pending`, a powłoka wykonuje po odblokowaniu
// (Face ID) — skrót nie może ominąć blokady.

enum HomeScreenQuickAction: String {
    case newEvent = "pl.emma.quick.event"
    case newTask = "pl.emma.quick.task"
    case talkToEmma = "pl.emma.quick.voice"
}

@MainActor
final class HomeScreenQuickActions: ObservableObject {
    static let shared = HomeScreenQuickActions()

    /// Skrót czekający na wykonanie (aplikacja mogła być zablokowana).
    @Published var pending: HomeScreenQuickAction?

    func receive(_ item: UIApplicationShortcutItem) -> Bool {
        guard let action = HomeScreenQuickAction(rawValue: item.type) else { return false }
        pending = action
        return true
    }

    /// Wykonuje odłożony skrót. Wywoływane przez powłokę, gdy jest widoczna.
    func consume(_ dependencies: AppDependencies) {
        guard let action = pending else { return }
        pending = nil
        switch action {
        case .newEvent:
            dependencies.present(.eventForm(editing: nil, clientID: nil, caseID: nil, initialDay: nil))
        case .newTask:
            dependencies.present(.taskForm(editing: nil, clientID: nil, caseID: nil))
        case .talkToEmma:
            dependencies.openEmma(clientID: nil, startVoice: true)
        }
    }
}

/// Delegat aplikacji — jedynie po to, żeby podpiąć delegata sceny, który
/// odbiera skróty (SwiftUI `WindowGroup` robi resztę).
final class EmmaAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Zimny start ze skrótu: skrót przychodzi w opcjach połączenia sceny.
        if let item = options.shortcutItem {
            MainActor.assumeIsolated { _ = HomeScreenQuickActions.shared.receive(item) }
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = EmmaSceneDelegate.self
        return configuration
    }
}

final class EmmaSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Skrót, gdy aplikacja już działa w tle.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let handled = MainActor.assumeIsolated { HomeScreenQuickActions.shared.receive(shortcutItem) }
        completionHandler(handled)
    }
}
