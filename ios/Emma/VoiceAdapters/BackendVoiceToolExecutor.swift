#if canImport(UIKit)
import Foundation

// MARK: - Wykonanie narzędzia na backendzie
//
// Live API nie wykonuje narzędzi za nas: to klient odsyła wynik wywołania
// funkcji do modelu. Ten typ nie zawiera jednak żadnej logiki narzędzia —
// przekazuje nazwę i argumenty do backendu, który ma allowlistę, wspólny action
// engine i audyt. Aplikacja nie ma ścieżki zapisu.
//
// Autoryzacja to bearer **użytkownika** (rozmowa zalogowanej osoby), nie sekret
// usługi. Sekret Gemini pozostaje wyłącznie po stronie backendu.

actor BackendVoiceToolExecutor: VoiceToolExecuting {

    private let baseURL: URL?
    private let tokens: VoiceAccessTokenSource
    private let session: URLSession
    private let timeout: TimeInterval

    /// Token pobierany przy każdym wywołaniu: rozmowa trwa dłużej niż token dostępu.
    init(
        baseURL: URL?,
        tokens: VoiceAccessTokenSource,
        session: URLSession = .shared,
        timeout: TimeInterval = 15
    ) {
        self.baseURL = baseURL
        self.tokens = tokens
        self.session = session
        self.timeout = timeout
    }

    /// Stały token — testy i podglądy.
    init(baseURL: URL?, accessToken: String?, session: URLSession = .shared, timeout: TimeInterval = 15) {
        self.init(baseURL: baseURL, tokens: .fixed(accessToken), session: session, timeout: timeout)
    }

    nonisolated func execute(toolName: String, argumentsJSON: String) async throws -> String {
        guard let baseURL else {
            throw VoiceToolExecutionError.failed("Brak adresu backendu — Emma nie może sprawdzić danych kancelarii.")
        }
        // Nazwa narzędzia pochodzi od modelu, więc traktujemy ją jak dane
        // niezaufane: tylko małe litery i podkreślenia, bez ścieżek.
        guard toolName.range(of: "^[a-z_]{1,48}$", options: .regularExpression) != nil else {
            throw VoiceToolExecutionError.unknownTool(toolName)
        }

        let url = baseURL.appendingPathComponent("api/mobile/v1/voice/tools/\(toolName)")
        var (data, http) = try await post(url: url, body: argumentsJSON, token: await tokens.current())
        // Token wygasł w trakcie rozmowy: jedno odnowienie i jedno ponowienie,
        // jak w `BackendAPIClient`. Drugie 401 to już koniec sesji.
        if http.statusCode == 401, let refresh = tokens.refresh,
           let refreshed = await refresh(), !refreshed.isEmpty {
            (data, http) = try await post(url: url, body: argumentsJSON, token: refreshed)
        }
        switch http.statusCode {
        case 200...299:
            break
        case 401:
            throw VoiceToolExecutionError.unauthorized
        case 403:
            throw VoiceToolExecutionError.forbidden(
                message(from: data) ?? "Emma nie ma uprawnień do tej informacji."
            )
        case 404:
            throw VoiceToolExecutionError.unknownTool(toolName)
        default:
            throw VoiceToolExecutionError.failed(
                message(from: data) ?? "Backend nie zwrócił danych (HTTP \(http.statusCode))."
            )
        }

        // Odsyłamy modelowi dokładnie to, co zwrócił backend — bez własnej
        // interpretacji i bez rozszerzania zakresu danych.
        return String(decoding: data, as: UTF8.self)
    }

    private nonisolated func post(url: URL, body: String, token: String?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw VoiceToolExecutionError.failed("Nie udało się sprawdzić danych w kancelarii.")
        }
        guard let http = response as? HTTPURLResponse else {
            throw VoiceToolExecutionError.failed("Nieprawidłowa odpowiedź backendu.")
        }
        return (data, http)
    }

    private nonisolated func message(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String,
              !message.isEmpty else { return nil }
        return message
    }
}
#endif
