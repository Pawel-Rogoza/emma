import Foundation

// MARK: - Model odpowiedzi logowania mobilnego
//
// Kształt pochodzi wprost z kontraktu `docs/ios/api/emma-mobile-api.yaml`
// (`AuthSession`, `User`) i z realnej odpowiedzi backendu
// `POST /api/mobile/v1/auth/login`. Dekodujemy go własnymi kluczami, bo backend
// używa `snake_case`, a kod aplikacji `camelCase` — bez tego każda zmiana
// nazwy pola cicho psułaby logowanie.

public struct MobileAuthUser: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let initials: String
    public let interfaceLanguage: String
    public let assistantLanguage: String

    public init(
        id: String,
        displayName: String,
        initials: String,
        interfaceLanguage: String,
        assistantLanguage: String
    ) {
        self.id = id
        self.displayName = displayName
        self.initials = initials
        self.interfaceLanguage = interfaceLanguage
        self.assistantLanguage = assistantLanguage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case initials
        case interfaceLanguage = "interface_language"
        case assistantLanguage = "assistant_language"
    }
}

public struct MobileAuthSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let user: MobileAuthUser

    public init(accessToken: String, refreshToken: String, expiresAt: Date, user: MobileAuthUser) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.user = user
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case user
    }
}

// MARK: - Błędy

/// Kody błędów ze schematu `Error` kontraktu mobilnego. Trzymamy je jako
/// typ wyliczeniowy, żeby warstwa wyżej nie porównywała stringów.
public enum MobileAuthError: Error, Equatable, Sendable {
    case unauthorized(String?)
    case forbidden(String?)
    case notFound(String?)
    case validationFailed(String?)
    case rateLimited(retryAfterSeconds: Int?, message: String?)
    case providerUnavailable(String?)
    case server(status: Int, message: String?)
    case transport(String)
    case malformedResponse

    /// Komunikat dla użytkownika. Serwerowe komunikaty są po polsku i pochodzą
    /// z naszego backendu — używamy ich, gdy są; inaczej mówimy własnym zdaniem.
    public var userMessage: String {
        switch self {
        case .unauthorized(let message):
            return message ?? "Nieprawidłowy e-mail, hasło lub kod jednorazowy."
        case .forbidden(let message):
            return message ?? "To konto nie ma dostępu do aplikacji."
        case .notFound(let message):
            return message ?? "Nie znaleziono zasobu na serwerze kancelarii."
        case .validationFailed(let message):
            return message ?? "Serwer odrzucił dane logowania."
        case .rateLimited(_, let message):
            return message ?? "Zbyt wiele prób logowania. Odczekaj chwilę i spróbuj ponownie."
        case .providerUnavailable(let message):
            return message ?? "Usługa chwilowo niedostępna. Spróbuj ponownie za moment."
        case .server(_, let message):
            return message ?? "Serwer kancelarii nie odpowiedział poprawnie. Spróbuj ponownie."
        case .transport:
            return "Brak połączenia z serwerem kancelarii. Sprawdź sieć i spróbuj ponownie."
        case .malformedResponse:
            return "Odpowiedź serwera kancelarii ma nieznany format."
        }
    }

    /// Czy ponowienie ma sens: sieć, limit i błędy serwera — tak; błędne dane — nie.
    public var isRetryable: Bool {
        switch self {
        case .transport, .rateLimited, .providerUnavailable, .server:
            return true
        case .unauthorized, .forbidden, .notFound, .validationFailed, .malformedResponse:
            return false
        }
    }
}

// MARK: - Kontrakt klienta

/// Minimalny zakres, jakiego potrzebuje warstwa sesji. Dzięki protokołowi
/// testy logiki nie wykonują żadnego żądania sieciowego.
public protocol MobileAuthServicing: Sendable {
    func login(
        email: String,
        password: String,
        totp: String,
        installationID: String,
        deviceName: String
    ) async throws -> MobileAuthSession

    func refreshSession(refreshToken: String, installationID: String) async throws -> MobileAuthSession

    func revokeSession(accessToken: String, installationID: String, reason: String) async throws
}
