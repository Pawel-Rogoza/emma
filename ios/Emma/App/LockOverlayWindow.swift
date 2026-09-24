import SwiftUI
import UIKit

// MARK: - Blokada nad wszystkimi arkuszami
//
// Ekran blokady nie może być zwykłą warstwą `ZStack` w oknie aplikacji:
// formularze (notatka, szczegóły terminu, profil) są arkuszami `.sheet`, które
// UIKit prezentuje **nad** całą hierarchią widoków tego okna. Blokada leżała
// więc pod otwartym arkuszem — po powrocie z tła arkusz był widoczny
// i edytowalny bez Face ID, a dotknięcie powiadomienia o terminie otwierało
// szczegóły nad blokadą (audyt bezpieczeństwa 24.09.2026).
//
// Osobne okno na poziomie ponad alertami zasłania wszystko, co pokazuje
// aplikacja, i nie niszczy stanu pod spodem: po odblokowaniu otwarty arkusz
// i wpisywana notatka są tam, gdzie były.

@MainActor
final class LockOverlayWindow {

    private var window: UIWindow?
    private weak var previousKeyWindow: UIWindow?

    func show(auth: AuthStore) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
        else { return }

        let host = UIHostingController(
            rootView: LockScreen()
                .environmentObject(auth)
                .tint(EmmaTheme.accent)
                .preferredColorScheme(.light)
        )
        // Nieprzezroczyste tło od pierwszej klatki: zrzut do przełącznika
        // aplikacji nie może złapać danych spod blokady.
        host.view.backgroundColor = UIColor(EmmaTheme.bg)
        // VoiceOver nie czyta elementów z okna pod blokadą.
        host.view.accessibilityViewIsModal = true

        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = .alert + 1
        overlay.rootViewController = host
        overlay.makeKeyAndVisible()
        window = overlay
    }

    func hide() {
        guard let overlay = window else { return }
        overlay.isHidden = true
        overlay.rootViewController = nil
        window = nil
        previousKeyWindow?.makeKey()
        previousKeyWindow = nil
    }
}
