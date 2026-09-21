import XCTest
@testable import Emma

// MARK: - Kontrakt sesji głosu: obaj dostawcy przez to samo repozytorium
//
// Backend wydaje token w dwóch różnych kształtach (ElevenLabs ma
// `conversation_id` bez `expires_at`, Gemini Live odwrotnie). Te testy pilnują,
// że **jedna** implementacja repozytorium czyta oba, a brak identyfikatora
// rozmowy nie jest mylony z błędem ani wypełniany pustym napisem.
//
// Nie ma tu sieci: `StubURLProtocol` odpowiada na żądania, a odpowiedź na
// otwarcie sesji odsyła `session_id` wygenerowany przez klienta — bo backend
// musi je potwierdzić, a aplikacja odrzuca niezgodność.

final class VoiceSessionContractTests: XCTestCase {

    private var baseURL: URL { URL(string: "https://advokat-varshava.pl")! }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeRepository() -> BackendVoiceSessionRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return BackendVoiceSessionRepository(
            baseURL: baseURL,
            accessTokenProvider: { "token-dostepu" },
            session: URLSession(configuration: configuration)
        )
    }

    private func request(installationID: String = "instalacja-glowa") -> CreateVoiceSession {
        CreateVoiceSession(
            userID: UserID("user-testowy"),
            context: AssistantContext(scope: .firm, version: Version(1)),
            assistantLanguage: .pl,
            installationID: installationID,
            requestedTransport: .webrtc
        )
    }

    /// Odpowiada na otwarcie sesji echem `session_id` z żądania, a na token —
    /// kształtem dostawcy. `session_id` w tokenie **musi** być ten sam: aplikacja
    /// odrzuca odpowiedź o innej sesji, niż sama otworzyła.
    private func stubVoiceFlow(tokenJSON: @escaping (String) -> String) {
        StubURLProtocol.respond { request, body in
            let path = request.url?.path ?? ""
            let sent = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let sessionID = (sent?["session_id"] as? String) ?? ""
            if path.hasSuffix("/voice/sessions") {
                let json = """
                {"id":"\(sessionID)","state":"active","context_version":1,
                 "installation_id":"instalacja-glowa","started_at":"2026-09-15T21:00:00.000Z",
                 "ended_at":null,"provider_conversation_id":null}
                """
                return (201, Data(json.utf8))
            }
            return (200, Data(tokenJSON(sessionID).utf8))
        }
    }

    // MARK: Gemini Live

    func testGeminiTokenShapeProducesUsableSessionWithoutConversationID() async throws {
        stubVoiceFlow { sessionID in
            """
            {"token":"auth_tokens/tok-live","provider":"gemini_live","model":"gemini-3.8-live",
             "expires_at":"2026-09-15T21:30:00.000Z","context_version":1,"session_id":"\(sessionID)"}
            """
        }

        let session = try await makeRepository().create(request())

        XCTAssertEqual(session.conversationToken, "auth_tokens/tok-live")
        // Live API nie wydaje identyfikatora rozmowy — nie wymyślamy go.
        XCTAssertNil(session.providerConversationID)
        // Czas wygaśnięcia jest przeniesiony, ale nie steruje żywotnością sesji.
        let expiry = try XCTUnwrap(session.expiresAt)
        // 2026-09-15T21:30:00Z — data z odpowiedzi backendu, nie z zegara telefonu.
        XCTAssertEqual(expiry.timeIntervalSince1970, 1_789_507_800, accuracy: 1)
        XCTAssertEqual(session.context.version, Version(1))
    }

    func testGeminiTokenWithoutExpiryIsStillUsable() async throws {
        // Free tier i zmiany po stronie dostawcy mogą nie dać `expires_at`;
        // brak daty znaczy „nieznana”, a nie „sesja nieważna”.
        stubVoiceFlow { sessionID in
            #"{"token":"auth_tokens/tok-2","provider":"gemini_live","context_version":1,"session_id":"\#(sessionID)"}"#
        }

        let session = try await makeRepository().create(request())
        XCTAssertEqual(session.conversationToken, "auth_tokens/tok-2")
        XCTAssertNil(session.expiresAt)
    }

    func testExpiryParsesBothISO8601Variants() {
        XCTAssertNotNil(BackendVoiceSessionRepository.parseExpiry("2026-09-15T21:30:00.000Z"))
        XCTAssertNotNil(BackendVoiceSessionRepository.parseExpiry("2026-09-15T21:30:00Z"))
        XCTAssertNil(BackendVoiceSessionRepository.parseExpiry(""))
        XCTAssertNil(BackendVoiceSessionRepository.parseExpiry(nil))
    }

    // MARK: ElevenLabs (ścieżka domyślna — bez regresji)

    func testElevenLabsShapeStillCarriesConversationID() async throws {
        stubVoiceFlow { sessionID in
            """
            {"token":"tk-eli","provider":"elevenlabs","conversation_id":"cx-777",
             "context_version":1,"session_id":"\(sessionID)"}
            """
        }

        let session = try await makeRepository().create(request())
        XCTAssertEqual(session.conversationToken, "tk-eli")
        XCTAssertEqual(session.providerConversationID, "cx-777")
        // Dostawca nie podaje czasu wygaśnięcia — aplikacja go nie wymyśla.
        XCTAssertNil(session.expiresAt)
    }

    func testMissingSessionIDSessionEchoIsRejected() async throws {
        // Backend, który nie potwierdzi `session_id`, otworzyłby rozmowę o innym
        // kontekście, niż myśli aplikacja. To ma być błąd, nie „udało się”.
        StubURLProtocol.respond(json: Data("""
        {"id":"inne-id","state":"active","context_version":1,"installation_id":"instalacja-glowa",
         "started_at":"2026-09-15T21:00:00.000Z","ended_at":null,"provider_conversation_id":null}
        """.utf8), status: 201)

        do {
            _ = try await makeRepository().create(request())
            XCTFail("Niezgodny session_id musi przerwać otwarcie sesji.")
        } catch {
            // Błąd domenowy z komunikatem z repozytorium; nie sprawdzamy brzmienia.
        }
    }
}
