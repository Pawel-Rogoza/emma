import SwiftUI

// MARK: - Gest powrotu przy ukrytym systemowym przycisku
//
// F12 audytu: ekran szczegółu ma **jeden** sposób powrotu. Żeby tak było, każdy
// wypychany ekran chowa systemowy przycisk (`.navigationBarBackButtonHidden(true)`)
// i pokazuje własny w `DetailHeader`. Ukrycie systemowego przycisku wyłącza jednak
// także gest przesunięcia od krawędzi — a audyt wymaga, żeby gest został.
//
// Ten modyfikator przywraca gest: ustawia delegata, który zezwala na przeciągnięcie
// tylko wtedy, gdy na stosie jest więcej niż jeden ekran (na ekranie głównym gest
// nie może nic przewrócić). To jedyne miejsce z taką wiedzą o UIKit.

public extension View {
    /// Zachowuje gest powrotu po ukryciu systemowego przycisku powrotu.
    func emmaPreservesSwipeBack() -> some View {
        background(SwipeBackRestorer())
    }
}

private struct SwipeBackRestorer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        SwipeBackProbe()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? SwipeBackProbe)?.restore()
    }
}

private final class SwipeBackProbe: UIViewController, UIGestureRecognizerDelegate {
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        restore()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restore()
    }

    /// Przywraca gest, jeśli ekran należy do stosu nawigacji.
    ///
    /// Świadomie miękko: gdy hierarchia jeszcze nie zna `UINavigationController`,
    /// nic nie robimy. Brak gestu jest mniej szkodliwy niż twarde odwołanie do
    /// widoku, którego może nie być.
    func restore() {
        guard let navigation = navigationController,
              let gesture = navigation.interactivePopGestureRecognizer else { return }
        gesture.delegate = self
        gesture.isEnabled = true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}
