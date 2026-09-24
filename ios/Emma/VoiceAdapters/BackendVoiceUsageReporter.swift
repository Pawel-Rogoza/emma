#if canImport(UIKit)
import Foundation

// MARK: - Zgłoszenie zużycia rozmowy
//
// Rozmowa idzie telefon ↔ Live API, więc tylko aplikacja widzi `usageMetadata`.
// Po zakończeniu rozmowy wysyłamy same liczby tokenów do backendu
// (`POST /api/mobile/v1/voice/sessions/{id}/usage`), który zapisuje je w audycie
// i liczy szacunek kosztu. Nieudane zgłoszenie niczego nie psuje — to pomiar.

struct BackendVoiceUsageReporter: Sendable {
    let baseURL: URL
    let tokens: VoiceAccessTokenSource
    var session: URLSession = .emmaAPI

    func report(sessionID: VoiceSessionID, usage: GeminiLiveUsage) async {
        guard !usage.isEmpty else { return }
        var request = URLRequest(
            url: baseURL.appendingPathComponent("api/mobile/v1/voice/sessions/\(sessionID.rawValue)/usage")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await tokens.current(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Int] = [
            "input_audio_tokens": usage.inputAudioTokens,
            "input_text_tokens": usage.inputTextTokens,
            "output_audio_tokens": usage.outputAudioTokens,
            "output_text_tokens": usage.outputTextTokens,
            "turns": usage.reports,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: request)
    }
}
#endif
