import Foundation
import LocalAuthentication

// MARK: - Uwierzytelnianie biometryczne
//
// Jedno miejsce, które wie, czy urządzenie ma Face ID / Touch ID / hasło i umie
// poprosić o odblokowanie. Ekrany nie znają `LAContext` — dzięki temu logikę
// da się przetestować z podstawionym uwierzytelniaczem, bez biometrii.

enum BiometryKind: Equatable, Sendable {
    case faceID
    case touchID
    case passcode

    var displayName: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .passcode: return "hasło urządzenia"
        }
    }
}

enum BiometricAvailability: Equatable, Sendable {
    case available(BiometryKind)
    /// Urządzenie nie ma skonfigurowanej biometrii ani hasła (albo symulator
    /// bez włączonego Face ID). Powód trafia do interfejsu jako jawna informacja.
    case unavailable(String)

    var kind: BiometryKind? {
        if case .available(let kind) = self { return kind }
        return nil
    }
}

protocol BiometricAuthenticating: Sendable {
    func availability() -> BiometricAvailability
    func authenticate(reason: String) async -> Bool
}

/// Prawdziwy uwierzytelniacz systemowy. `deviceOwnerAuthentication` oznacza
/// Face ID z automatycznym zejściem do hasła urządzenia, gdy biometria zawiedzie.
struct LocalAuthenticationAuthenticator: BiometricAuthenticating {

    func availability() -> BiometricAvailability {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable(Self.message(for: error))
        }
        switch context.biometryType {
        case .faceID: return .available(.faceID)
        case .touchID: return .available(.touchID)
        default: return .available(.passcode)
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Użyj hasła"
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }

    private static func message(for error: NSError?) -> String {
        guard let error else {
            return "To urządzenie nie ma skonfigurowanego Face ID ani hasła."
        }
        switch LAError.Code(rawValue: error.code) {
        case .biometryNotEnrolled:
            return "Face ID nie jest skonfigurowane w tym urządzeniu."
        case .biometryNotAvailable:
            return "Face ID jest w tej chwili niedostępne."
        case .passcodeNotSet:
            return "Urządzenie nie ma ustawionego hasła."
        default:
            return "Odblokowanie biometryczne jest niedostępne."
        }
    }
}
