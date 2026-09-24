import Foundation

// MARK: - Klient HTTP logowania mobilnego
//
// Jedyne miejsce w aplikacji, które wysyła e-mail, hasło i kod jednorazowy.
// Świadomie nie ma tu żadnych kluczy dostawców ani adresów innych niż baza
// backendu z konfiguracji (§5.1, §13).
//
// Adresy tras są w jednym miejscu jako `Endpoint`, żeby zmiana ścieżki w
// kontrakcie była jedną poprawką, a nie szukaniem stringów po plikach.

public struct MobileAuthClient: MobileAuthServicing {

    public enum Endpoint: String, Sendable, CaseIterable {
        case login = "api/mobile/v1/auth/login"
        case refresh = "api/mobile/v1/auth/refresh"
        case revoke = "api/mobile/v1/auth/revoke"
    }

    private let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval

    public init(baseURL: URL, session: URLSession = .emmaAPI, timeout: TimeInterval = 20) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    // MARK: Operacje

    public func login(
        email: String,
        password: String,
        totp: String,
        installationID: String,
        deviceName: String
    ) async throws -> MobileAuthSession {
        var body: [String: Any] = [
            "email": email,
            "password": password,
            "installation_id": installationID,
        ]
        if !totp.isEmpty { body["totp"] = totp }
        if !deviceName.isEmpty { body["device_name"] = deviceName }
        return try await send(.login, body: body, accessToken: nil)
    }

    public func refreshSession(refreshToken: String, installationID: String) async throws -> MobileAuthSession {
        try await send(
            .refresh,
            body: ["refresh_token": refreshToken, "installation_id": installationID],
            accessToken: nil
        )
    }

    public func revokeSession(accessToken: String, installationID: String, reason: String) async throws {
        let request = try makeRequest(
            .revoke,
            body: ["installation_id": installationID, "reason": reason],
            accessToken: accessToken
        )
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw MobileAuthError.malformedResponse }
        // Kontrakt: 204 bez treści. 401 oznacza, że sesji już nie ma — dla
        // wylogowania to stan docelowy, nie błąd.
        if http.statusCode == 204 || http.statusCode == 401 { return }
        throw Self.error(from: http, data: data)
    }

    // MARK: Wysyłka

    private func send(
        _ endpoint: Endpoint,
        body: [String: Any],
        accessToken: String?
    ) async throws -> MobileAuthSession {
        let request = try makeRequest(endpoint, body: body, accessToken: accessToken)
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw MobileAuthError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: http, data: data)
        }
        do {
            return try Self.decoder.decode(MobileAuthSession.self, from: data)
        } catch {
            throw MobileAuthError.malformedResponse
        }
    }

    private func makeRequest(
        _ endpoint: Endpoint,
        body: [String: Any],
        accessToken: String?
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.rawValue))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            // Zerwane połączenie i brak sieci to jedna, zrozumiała sytuacja dla
            // użytkownika; nie pokazujemy numeru błędu systemu.
            if error.code == .cancelled { throw CancellationError() }
            throw MobileAuthError.transport(error.localizedDescription)
        } catch {
            throw MobileAuthError.transport(error.localizedDescription)
        }
    }

    // MARK: Błędy i dekodowanie

    private struct ErrorBody: Decodable {
        let code: String
        let message: String
    }

    /// Mapowanie odpowiedzi błędu. Kod bierze się z ciała (`{code, message}`),
    /// a gdy ciała nie ma — z samego statusu. Nie zgadujemy przyczyny.
    static func error(from response: HTTPURLResponse, data: Data) -> MobileAuthError {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        let message = body?.message
        switch body?.code {
        case "unauthorized": return .unauthorized(message)
        case "forbidden": return .forbidden(message)
        case "not_found": return .notFound(message)
        case "validation_failed": return .validationFailed(message)
        case "rate_limited":
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            return .rateLimited(retryAfterSeconds: retryAfter, message: message)
        case "provider_unavailable": return .providerUnavailable(message)
        case "internal_error": return .server(status: response.statusCode, message: message)
        default:
            break
        }
        switch response.statusCode {
        case 401: return .unauthorized(message)
        case 403: return .forbidden(message)
        case 404: return .notFound(message)
        case 400, 422: return .validationFailed(message)
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            return .rateLimited(retryAfterSeconds: retryAfter, message: message)
        case 503: return .providerUnavailable(message)
        default: return .server(status: response.statusCode, message: message)
        }
    }

    /// Backend zwraca `expires_at` z dokładnością do milisekund
    /// (`2026-09-14T11:39:09.844Z`), a część bibliotek wysyła wariant bez nich.
    /// Akceptujemy oba, zamiast wywracać logowanie na formacie daty.
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseISO8601(raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Nieznany format daty: \(raw)"
            )
        }
        return decoder
    }

    /// Formater powstaje na jedno wywołanie: logowanie jest rzadkie, a dzięki
    /// temu nie trzymamy współdzielonej instancji klasy, która nie jest
    /// `Sendable` — w trybie Swift 6 to nie jest szczegół stylistyczny.
    static func parseISO8601(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
