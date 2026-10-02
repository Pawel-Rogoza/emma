#if canImport(UIKit)
import Foundation

// MARK: - Token rozmowy z backendu
//
// Aplikacja **nie zawiera klucza Gemini**. Klucz żyje wyłącznie na backendzie,
// a urządzenie otrzymuje krótkotrwałe poświadczenie rozmowy (§5.1). Ten plik jest jedynym
// miejscem, w którym aplikacja prosi o taki token.
//
// Kontrakt backendu:
//   `POST /api/mobile/v1/voice/conversation-token`
//   → `{ "token": …, "model": "gemini-3.8-live", "context_version": …, "session_id": … }`
//
// Kontrakt może zwracać `expires_at`; gdy go nie ma, aplikacja nie wymyśla czasu.
// Prefiks `/api/mobile/v1` jest
// obowiązkowy — trasa bez niego nie istnieje i nginx jej nie przepuszcza.
//
// Ścieżka normalna prowadzi przez `BackendVoiceSessionRepository` (`create` wydaje
// token razem z sesją). Ten typ istnieje wyłącznie po to, by transport umiał
// domknąć brak tokenu, i sam nigdy nie używa klucza API.
//
// Token jest krótkotrwałym poświadczeniem Gemini Live i nigdy nie jest logowany.

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
    /// Serwer odmówił z czytelnym powodem (np. wyczerpany miesięczny limit).
    case refused(message: String)
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
        case .refused(let message):
            return message
        case .malformedResponse:
            return "Odpowiedź backendu nie zawierała tokenu rozmowy."
        case .expiresInPast:
            return "Token rozmowy wygasł przed rozpoczęciem sesji."
        }
    }
}

extension ConversationTokenError: UserFacingVoiceError {
    var userMessage: String? {
        if case .refused(let message) = self { return message }
        return nil
    }
}

/// Pobranie tokenu rozmowy z backendu. Bez kluczy, bez sekretów w aplikacji.
actor BackendConversationTokenProvider {

    private let baseURL: URL?
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL?, session: URLSession = .emmaAPI) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
        // Nie `.iso8601`: ta strategia odrzuca ułamki sekund, a backend wysyła
        // `expires_at` z milisekundami (`…09.844Z`). Całe dekodowanie kończyło
        // się wtedy `malformedResponse`, czyli nieudanym wznowieniem po `goAway`.
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = MobileAuthClient.parseISO8601(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Nieznany format expires_at: \(raw)"
                )
            }
            return date
        }
    }

    /// Czy dostawca głosu może w ogóle zostać użyty w tej konfiguracji.
    var isConfigured: Bool { baseURL != nil }

    func fetchToken(
        sessionID: VoiceSessionID,
        contextVersion: Version,
        installationID: String,
        accessToken: String?
    ) async throws -> BackendConversationToken {
        guard let baseURL else { throw ConversationTokenError.backendNotConfigured }

        var request = URLRequest(
            url: baseURL.appendingPathComponent("api/mobile/v1/voice/conversation-token")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Zapis wymaga klucza idempotencji; pochodny od sesji, operacji i wersji.
        request.setValue(
            "emma-voice-token-\(sessionID.rawValue)-v\(contextVersion.value)",
            forHTTPHeaderField: "Idempotency-Key"
        )
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(
            TokenRequest(
                sessionID: sessionID.rawValue,
                contextVersion: contextVersion.value,
                installationID: installationID
            )
        )
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConversationTokenError.malformedResponse }

        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw ConversationTokenError.unauthorized
        case 429:
            // Wyczerpany miesięczny limit rozmów: serwer mówi po polsku, co dalej.
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw message.map { ConversationTokenError.refused(message: $0) }
                ?? ConversationTokenError.server(status: http.statusCode)
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
        let installationID: String

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case contextVersion = "context_version"
            case installationID = "installation_id"
        }
    }
}
#endif
