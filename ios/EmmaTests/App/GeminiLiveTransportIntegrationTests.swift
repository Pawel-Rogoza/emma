import Foundation
import XCTest
@testable import Emma

// MARK: - Transport Gemini Live na prawdziwym gnieździe WebSocket
//
// Testy jednostkowe kodeka sprawdzają ramki, ale nie sprawdzają **sesji**: czy
// `setup` wychodzi po otwarciu gniazda, czy zdarzenia z serwera dochodzą do
// koordynatora, czy `toolCall` wraca jako `toolResponse` na trasę backendu i czy
// zapowiedziane zamknięcie faktycznie wznawia sesję z uchwytem.
//
// Gniazdo obsługuje atrapa Live API (`scripts/fake-live-api.mjs` w repo backendu).
// To **nie jest** prawdziwe API: atrapa nie waliduje konfiguracji ani nie zna VAD.
// Dowodzi naszej strony protokołu, a nie zachowania Google.
//
// Uruchomienie (atrapa na hoście, test w symulatorze):
//   node scripts/fake-live-api.mjs --port 8791
//   xcodebuild test … \
//     SIMCTL_CHILD_EMMA_FAKE_LIVE_BASE_URL=http://127.0.0.1:8791 \
//     SIMCTL_CHILD_EMMA_FAKE_LIVE_BASE_URL_GOAWAY=http://127.0.0.1:8792
// Bez tych zmiennych testy są pomijane — nigdy nie łączą się z prawdziwym API.

@MainActor
final class GeminiLiveTransportIntegrationTests: XCTestCase {

    private static let livePath = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    private func baseURL(env: String) throws -> URL {
        guard let value = ProcessInfo.processInfo.environment[env], let url = URL(string: value) else {
            throw XCTSkip("Brak atrapy Live API: ustaw \(env), np. http://127.0.0.1:8791")
        }
        return url
    }

    private func endpoint(from base: URL) throws -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.scheme = "ws"
        components?.path = Self.livePath
        return try XCTUnwrap(components?.url)
    }

    private func state(from base: URL) async throws -> FakeLiveState {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("state"))
        return try JSONDecoder().decode(FakeLiveState.self, from: data)
    }

    /// Zerowanie liczników atrapy. Odpowiedź nie ma kształtu stanu, więc jej nie czytamy.
    private func reset(_ base: URL) async throws {
        _ = try await URLSession.shared.data(from: base.appendingPathComponent("reset"))
    }

    /// Czekanie na stan po stronie serwera — bez zgadywania liczby `sleep`.
    private func wait(
        timeout: TimeInterval = 6,
        _ condition: () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 60_000_000)
        }
        XCTFail("Warunek nie został spełniony w \(timeout) s.")
    }

    private func makeSession(token: String) -> VoiceSessionConfiguration {
        VoiceSessionConfiguration(
            sessionID: VoiceSessionID("sesja-atrapa-1"),
            context: AssistantContext(scope: .firm, version: Version(1)),
            assistantLanguage: .pl,
            conversationToken: token,
            transport: .webrtc,
            expiresAt: nil,
            capabilities: .providerUnverified
        )
    }

    // MARK: Scenariusz podstawowy

    func testSessionHandshakeToolRoundTripAndAudioOverRealSocket() async throws {
        let base = try baseURL(env: "EMMA_FAKE_LIVE_BASE_URL")
        try await reset(base)

        let tools = RecordingToolExecutor()
        let box = EventBox()
        let transport = GeminiLiveTransport(
            // Token jest już w konfiguracji sesji, więc ten adres nie jest używany.
            tokenProvider: BackendConversationTokenProvider(baseURL: URL(string: "https://example.test")!),
            toolExecutor: tools,
            accessToken: "token-uzytkownika",
            installationID: "instalacja-testowa",
            model: "gemini-3.8-live",
            endpoint: try endpoint(from: base)
        )
        // Subskrypcja **przed** połączeniem: kolejność nie może gubić zdarzeń.
        let events = transport.events()
        let collector = Task { @MainActor in
            for await event in events { box.append(event.payload) }
        }
        defer { collector.cancel() }

        try await transport.connect(makeSession(token: "auth_tokens/atrapa"))

        // 1. Uścisk dłoni: `setup` z modelem i bez konfiguracji, którą blokuje token.
        try await wait { try await self.state(from: base).setups.count == 1 }
        let stateAfterSetup = try await state(from: base)
        let setup = try XCTUnwrap(stateAfterSetup.setups.first)
        XCTAssertEqual(setup.model, "models/gemini-3.8-live")
        XCTAssertNil(setup.handle, "Pierwsze połączenie nie ma jeszcze uchwytu wznowienia.")
        var seen = box.payloads
        XCTAssertTrue(seen.contains(.connectionChanged(.connected)))
        XCTAssertTrue(seen.contains(.microphoneChanged(.capturing)))

        // 2. Tura tekstowa: transkrypcja, audio i wywołanie narzędzia.
        try await transport.sendTextTurn(AssistantTextInput(
            text: "Ile mam dzisiaj zadań?",
            language: .pl,
            contextVersion: Version(1),
            inputID: "wejscie-1"
        ))

        try await wait { try await self.state(from: base).toolResponses.count == 1 }
        let stateAfterTurn = try await state(from: base)
        let response = try XCTUnwrap(stateAfterTurn.toolResponses.first)
        XCTAssertEqual(response.id, "call-1")
        XCTAssertEqual(response.name, "get_today_overview")
        // Wynik idzie do modelu dokładnie tak, jak wrócił z backendu.
        XCTAssertEqual(response.response?["result"]?["tasks"]?.value as? Double, 2)
        XCTAssertEqual(tools.calls.map(\.name), ["get_today_overview"])
        XCTAssertEqual(tools.calls.first?.argumentsJSON.contains("2026-09-15"), true)

        // 3. Zdarzenia tury docierają do koordynatora, w tym przybliżony start audio.
        // Snapshot, bo `box` należy do aktora głównego, a `XCTAssert` przyjmuje
        // wyrażenie bez `await`.
        seen = box.payloads
        XCTAssertTrue(seen.contains(.userTranscriptPartial("Ile mam dzisiaj zadań?")))
        XCTAssertTrue(seen.contains(.agentTextDelta("Sprawdzam dzień. ")))
        XCTAssertTrue(seen.contains(.playbackStarted(approximate: true)))
        XCTAssertTrue(seen.contains(.toolProgress(ToolProgress(
            label: "Sprawdzam dane w kancelarii",
            toolName: "get_today_overview",
            isFinished: true
        ))))
        XCTAssertTrue(seen.contains(.playbackStopped(reason: .completed)))
        XCTAssertFalse(seen.contains(.fatalError(.providerUnavailable)))

        await transport.disconnect(reason: .userRequested)
        // `disconnect` zamyka strumień, więc czekamy, aż zbieranie się skończy —
        // inaczej ostatnie zdarzenie wyścignie asercję.
        await collector.value
        XCTAssertTrue(box.payloads.contains(.connectionChanged(.ended)))
    }

    func testServerBargeInStopsLocalPlaybackImmediately() async throws {
        let base = try baseURL(env: "EMMA_FAKE_LIVE_BASE_URL")
        try await reset(base)

        let box = EventBox()
        let transport = GeminiLiveTransport(
            tokenProvider: BackendConversationTokenProvider(baseURL: URL(string: "https://example.test")!),
            toolExecutor: RecordingToolExecutor(),
            accessToken: "token-uzytkownika",
            installationID: "instalacja-testowa",
            model: "gemini-3.8-live",
            endpoint: try endpoint(from: base)
        )
        let events = transport.events()
        let collector = Task { @MainActor in
            for await event in events { box.append(event.payload) }
        }
        defer { collector.cancel() }

        try await transport.connect(makeSession(token: "auth_tokens/atrapa"))
        try await wait { try await self.state(from: base).setups.count == 1 }

        // Atrapa odpowiada audio, a potem zgłasza przerwanie tury (barge-in).
        try await transport.sendTextTurn(AssistantTextInput(
            text: "Przerwij to teraz",
            language: .pl,
            contextVersion: Version(1),
            inputID: "wejscie-2"
        ))
        try await wait { box.containsInterruption }

        let seen = box.payloads
        XCTAssertTrue(seen.contains(.interruption(.userBargeIn)))
        XCTAssertTrue(seen.contains(.playbackStopped(reason: .interrupted)))
        // Sedno: po barge-in lokalna kolejka audio jest wycofana, a nie tylko
        // odnotowana w stanie — inaczej Emma mówi dalej przez użytkownika.
        XCTAssertEqual(transport.localPlaybackStopCount, 1)

        await transport.disconnect(reason: .userRequested)
        await collector.value
    }

    // MARK: Wznowienie po zapowiedzianym zamknięciu

    func testGoAwayReconnectsWithResumptionHandleAndFreshToken() async throws {
        let base = try baseURL(env: "EMMA_FAKE_LIVE_BASE_URL_GOAWAY")
        try await reset(base)

        let box = EventBox()
        // Pusta konfiguracja tokenu wymusza pobranie nowego poświadczenia z trasy
        // backendu przy wznowieniu — dokładnie ta ścieżka, którą przechodzi produkcja.
        let transport = GeminiLiveTransport(
            tokenProvider: BackendConversationTokenProvider(baseURL: base),
            toolExecutor: RecordingToolExecutor(),
            accessToken: "token-uzytkownika",
            installationID: "instalacja-testowa",
            model: "gemini-3.8-live",
            endpoint: try endpoint(from: base)
        )
        let events = transport.events()
        let collector = Task { @MainActor in
            for await event in events { box.append(event.payload) }
        }
        defer { collector.cancel() }

        try await transport.connect(makeSession(token: ""))

        // Dwa `setup` znaczą, że po `goAway` transport otworzył nowe gniazdo,
        // a drugie z uchwytem — czyli sesja po stronie serwera jest ta sama.
        try await wait { try await self.state(from: base).setups.count == 2 }
        let afterReconnect = try await state(from: base)
        XCTAssertEqual(afterReconnect.setups[1].handle, "h-1")
        // Nowe poświadczenie pochodzi z trasy backendu z bearerem użytkownika.
        XCTAssertEqual(afterReconnect.tokenAuth, "Bearer token-uzytkownika")

        // Użytkownik ma zobaczyć, że rozmowa wraca, a nie że „coś się stało”.
        let seen = box.payloads
        XCTAssertTrue(seen.contains(.recoverableError(.tokenExpiring)))
        XCTAssertTrue(seen.contains(.connectionChanged(.reconnecting)))
        XCTAssertTrue(seen.contains(.connectionChanged(.connected)))
        XCTAssertFalse(seen.contains(.fatalError(.providerUnavailable)))

        await transport.disconnect(reason: .userRequested)
        collector.cancel()
    }
}

// MARK: - Atrapa: stan po stronie serwera

struct FakeLiveState: Decodable {
    struct Setup: Decodable {
        let model: String
        let handle: String?
    }

    struct ToolResponse: Decodable {
        let id: String
        let name: String
        /// `response` jest dowolnym JSON-em, więc czytamy go przez `JSONValue`.
        let response: JSONValue?
    }

    let connections: Int
    let setups: [Setup]
    let toolResponses: [ToolResponse]
    let tokenAuth: String?
    let lastError: String?
}

/// Minimalny czytnik dowolnego JSON-a — bez zależności od kształtu wyniku narzędzia.
enum JSONValue: Decodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        self = .null
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dictionary) = self { return dictionary[key] }
        return nil
    }

    var value: Any? {
        switch self {
        case .object(let dictionary): return dictionary
        case .array(let array): return array
        case .string(let text): return text
        case .number(let number): return number
        case .bool(let flag): return flag
        case .null: return nil
        }
    }
}

// MARK: - Atrapa narzędzi i zdarzeń

/// Narzędzie wykonuje backend — tutaj zapisujemy tylko, co model zażądał.
final class RecordingToolExecutor: VoiceToolExecuting, @unchecked Sendable {
    struct Call: Sendable {
        let name: String
        let argumentsJSON: String
    }

    private let lock = NSLock()
    private var recorded: [Call] = []

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func execute(toolName: String, argumentsJSON: String) async throws -> String {
        record(Call(name: toolName, argumentsJSON: argumentsJSON))
        return #"{"result":{"tasks":2,"first":"Spotkanie z klientem"}}"#
    }

    /// `NSLock` jest niedostępny w kontekście `async`, więc zapis robimy metodą
    /// synchroniczną — tak samo jak bramka mikrofonu w transporcie.
    private func record(_ call: Call) {
        lock.lock()
        recorded.append(call)
        lock.unlock()
    }
}

@MainActor
final class EventBox {
    private(set) var payloads: [VoiceEventPayload] = []
    func append(_ payload: VoiceEventPayload) { payloads.append(payload) }
    func contains(_ payload: VoiceEventPayload) -> Bool { payloads.contains(payload) }
    var containsInterruption: Bool { payloads.contains(.interruption(.userBargeIn)) }
}
