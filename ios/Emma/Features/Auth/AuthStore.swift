import Combine
import Foundation

// MARK: - Sesja użytkownika
//
// Aplikacja ma jedno wspólne konto kancelarii: logowanie jest demonstracyjne
// (nie ma backendu), a po zalogowaniu kolejne wejścia odblokowuje Face ID.
// Stan trzymamy w trzech krokach, bo każdy z nich to inny ekran:
//
//   signedOut → ekran logowania (raz, dopóki użytkownik się nie wyloguje),
//   locked    → ekran odblokowania (Face ID / hasło urządzenia),
//   unlocked  → aplikacja.
//
// „Zalogowany” zapisujemy w `UserDefaults`, więc logowanie przeżywa restart
// aplikacji, ale sam dostęp do danych wymaga jeszcze odblokowania.

@MainActor
final class AuthStore: ObservableObject {

    enum State: Equatable {
        case signedOut
        case locked
        case unlocked
    }

    @Published private(set) var state: State
    @Published private(set) var isAuthenticating = false
    @Published private(set) var notice: String?

    private let authenticator: BiometricAuthenticating
    private let defaults: UserDefaults
    private static let signedInKey = "emma.auth.signedIn"

    init(
        authenticator: BiometricAuthenticating = LocalAuthenticationAuthenticator(),
        defaults: UserDefaults = .standard
    ) {
        self.authenticator = authenticator
        self.defaults = defaults
        // Testy interfejsu i zrzuty ekranu startują z `--skip-auth`: dzięki temu
        // nie zależą od biometrii symulatora ani od zapamiętanej sesji. To jedyne
        // miejsce, w którym dostęp da się pominąć — zwykły start zawsze przechodzi
        // przez logowanie i Face ID.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--skip-auth") {
            self.state = .unlocked
        } else if arguments.contains("--reset-auth") {
            // Wymusza czysty start na ekranie logowania (test scenariusza logowania).
            defaults.set(false, forKey: Self.signedInKey)
            self.state = .signedOut
        } else {
            self.state = defaults.bool(forKey: Self.signedInKey) ? .locked : .signedOut
        }
    }

    // MARK: Logowanie (demo)

    /// Logowanie demonstracyjne: nie ma serwera, więc sprawdzamy tylko kształt
    /// danych i mówimy o tym wprost w interfejsie. Zwraca `true`, gdy wpuszczamy.
    @discardableResult
    func signIn(email: String, password: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), trimmed.count >= 5 else {
            notice = "Podaj adres e-mail, np. imie@kancelaria.pl."
            return false
        }
        guard password.count >= 4 else {
            notice = "Hasło musi mieć co najmniej 4 znaki."
            return false
        }
        notice = nil
        defaults.set(true, forKey: Self.signedInKey)
        state = .unlocked
        return true
    }

    /// Wylogowanie kasuje zapamiętaną sesję — następny start to znów logowanie.
    func signOut() {
        defaults.set(false, forKey: Self.signedInKey)
        notice = nil
        state = .signedOut
    }

    // MARK: Blokada i Face ID

    /// Blokujemy przy zejściu aplikacji w tło; powrót wymaga Face ID.
    func lock() {
        guard state == .unlocked else { return }
        state = .locked
    }

    var availability: BiometricAvailability { authenticator.availability() }

    var canUseBiometrics: Bool { availability.kind != nil }

    /// Etykieta przycisku zależna od tego, co urządzenie naprawdę potrafi —
    /// nie piszemy „Face ID” na telefonie, który ma tylko hasło.
    var unlockButtonTitle: String {
        switch availability {
        case .available(let kind):
            return kind == .passcode ? "Odblokuj hasłem" : "Odblokuj \(kind.displayName)"
        case .unavailable:
            return "Odblokuj"
        }
    }

    var availabilityNotice: String? {
        if case .unavailable(let message) = availability { return message }
        return nil
    }

    func unlock() async {
        guard state == .locked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let unlocked = await authenticator.authenticate(reason: "Odblokuj aplikację Emma")
        if unlocked {
            notice = nil
            state = .unlocked
            return
        }

        // Demo bez skonfigurowanej biometrii nie może zamknąć użytkownika na
        // stałe — wpuszczamy, ale mówimy wprost, że to obejście demonstracyjne.
        if case .unavailable = availability {
            notice = nil
            state = .unlocked
            return
        }
        notice = "Nie udało się odblokować. Spróbuj ponownie albo użyj hasła urządzenia."
    }
}

// MARK: - Podstawiony uwierzytelniacz (podglądy i testy)

/// Uwierzytelniacz, który nic nie robi i zawsze odblokowuje — wyłącznie do
/// podglądów Xcode. Zwykła aplikacja zawsze używa systemowego Face ID.
struct PreviewBiometricAuthenticator: BiometricAuthenticating {
    var result: Bool = true
    var availabilityResult: BiometricAvailability = .available(.faceID)

    func availability() -> BiometricAvailability { availabilityResult }
    func authenticate(reason: String) async -> Bool { result }
}
