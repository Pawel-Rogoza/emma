import Foundation

// MARK: - Wykonanie narzędzia wywołanego przez model
//
// W Live API to **klient** odsyła wynik wywołania funkcji do modelu. Gdyby
// aplikacja wykonywała narzędzia sama, złamalibyśmy zasadę „narzędzia trafiają
// do wspólnego action engine na backendzie” (§5) — a przy zapisach także bramkę
// zgody. Dlatego transport nie zna żadnego narzędzia: przekazuje nazwę i JSON
// argumentów do tego portu, a implementacja (backend) decyduje i audytuje.

public protocol VoiceToolExecuting: Sendable {
    /// Zwraca wynik jako JSON (tekst), gotowy do odesłania modelowi.
    func execute(toolName: String, argumentsJSON: String) async throws -> String
}

public enum VoiceToolExecutionError: Error, Equatable, Sendable {
    /// Brak ważnej sesji użytkownika — rozmowa nie może działać po wylogowaniu.
    case unauthorized
    /// Backend odmówił wykonania (np. narzędzie zapisu bez bramki zgody).
    case forbidden(String)
    case unknownTool(String)
    /// Wynik niepewny: nie udajemy sukcesu i nie ponawiamy automatycznie.
    case failed(String)

    public var safeMessage: String {
        switch self {
        case .unauthorized:
            return "Sesja wygasła. Zaloguj się ponownie, aby Emma mogła korzystać z danych."
        case .forbidden(let reason):
            return reason
        case .unknownTool(let name):
            return "Emma próbowała użyć nieznanego narzędzia (\(name))."
        case .failed(let reason):
            return reason
        }
    }

    /// Czy powtórzenie ma sens (§4.4). Brak uprawnień i nieznane narzędzie — nie.
    public var isRetryable: Bool {
        switch self {
        case .failed: return true
        default: return false
        }
    }
}
