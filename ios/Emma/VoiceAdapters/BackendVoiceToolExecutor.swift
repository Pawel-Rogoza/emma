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
    private let accessToken: String?
    private let session: URLSession
    private let timeout: TimeInterval

    init(baseURL: URL?, accessToken: String?, session: URLSession = .shared, timeout: TimeInterval = 15) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.session = session
        self.timeout = timeout
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

        var request = URLRequest(url: baseURL.appendingPathComponent("api/mobile/v1/voice/tools/\(toolName)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = Data(argumentsJSON.utf8)
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

    private nonisolated func message(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String,
              !message.isEmpty else { return nil }
        return message
    }
}
#endif
