#if canImport(UIKit)
import Foundation

// MARK: - Token rozmowy z backendu
//
// Aplikacja **nie zawiera klucza ElevenLabs**. Klucz żyje wyłącznie na backendzie,
// a urządzenie otrzymuje krótkotrwały token rozmowy (§5.1). Ten plik jest jedynym
// miejscem, w którym aplikacja prosi o taki token.
//
// Kontrakt backendu (zweryfikowany na SDK 3.3.1):
//   `GET /v1/voice/conversation-token` → `{ "token": "<conversation token>", "expiresAt": "<ISO-8601>" }`
//
// Sam ElevenLabs wystawia `GET https://api.elevenlabs.io/v1/convai/conversation/token`,
// którego pole `token` trafia do LiveKit jako `participantToken`. Nasz backend jest
// pośrednikiem: przechowuje klucz API, wiąże sesję z użytkownikiem i sprawdza
// kontekst sprawy przed wydaniem tokenu.
//
// Status: **niezweryfikowane na koncie produkcyjnym** (`blocked_external` — brak
// konta dostawcy). Kod nie deklaruje, że integracja działa; patrz
// docs/ios/PROVIDER_CONTRACT_TESTS.md.

/// Pojedynczy token rozmowy wydany przez backend.
struct BackendConversationToken: Decodable, Sendable {
    let token: String
    let expiresAt: Date?
    /// Kontekst, który backend uznał za obowiązujący dla tej sesji.
    let contextVersion: Int?

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case contextVersion = "context_version"
    }
}

enum ConversationTokenError: Error, LocalizedError, Sendable {
    case backendNotConfigured
    case unauthorized
    case server(status: Int)
    case malformedResponse
    case expiresInPast

    var errorDescription: String? {
        switch self {
        case .backendNotConfigured:
            return "Nie skonfigurowano adresu backendu. Głos dostawcy jest niedostępny w trybie Demo."
        case .unauthorized:
            return "Sesja wygasła. Zaloguj się ponownie, aby kontynuować rozmowę."
        case .server(let status):
            return "Backend nie wydał tokenu rozmowy (HTTP \(status))."
        case .malformedResponse:
            return "Odpowiedź backendu nie zawierała tokenu rozmowy."
        case .expiresInPast:
            return "Token rozmowy wygasł przed rozpoczęciem sesji."
        }
    }
}

/// Pobranie tokenu rozmowy z backendu. Bez kluczy, bez sekretów w aplikacji.
actor BackendConversationTokenProvider {

    private let baseURL: URL?
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// Czy dostawca głosu może w ogóle zostać użyty w tej konfiguracji.
    var isConfigured: Bool { baseURL != nil }

    func fetchToken(
        sessionID: VoiceSessionID,
        contextVersion: Version,
        accessToken: String?
    ) async throws -> BackendConversationToken {
        guard let baseURL else { throw ConversationTokenError.backendNotConfigured }

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/voice/conversation-token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(
            TokenRequest(sessionID: sessionID.rawValue, contextVersion: contextVersion.value)
        )
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConversationTokenError.malformedResponse }

        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw ConversationTokenError.unauthorized
        default:
            throw ConversationTokenError.server(status: http.statusCode)
        }

        guard let token = try? decoder.decode(BackendConversationToken.self, from: data),
              !token.token.isEmpty else {
            throw ConversationTokenError.malformedResponse
        }
        if let expiresAt = token.expiresAt, expiresAt <= Date() {
            throw ConversationTokenError.expiresInPast
        }
        return token
    }

    private struct TokenRequest: Encodable {
        let sessionID: String
        let contextVersion: Int
    }
}
#endif
