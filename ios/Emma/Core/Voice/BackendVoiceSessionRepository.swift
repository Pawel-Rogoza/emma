import Foundation

// MARK: - Repozytorium sesji głosu na prawdziwym backendzie (M5)
//
// Dlaczego osobny typ, a nie implementacja w `BackendRepository`:
//   • `BackendRepository` obsługuje *dane kancelarii* (klienci, sprawy, zadania…)
//     i celowo rzuca `notAvailableInBackend` dla tras, których kontrakt nie ma.
//     Sesja głosu ma własny, krótki cykl życia i własne pojęcie idempotencji,
//     więc trzymanie jej osobno nie miesza dwóch odpowiedzialności w jednym pliku.
//   • `VoiceSessionRepository` jest wąskim protokołem z `Core/Voice`; ten typ jest
//     jego pełną implementacją dla trybu nie-Demo, a mock (`MockRepository`)
//     pozostaje implementacją dla Demo.
//
// Zasady, które rządzą tym plikiem:
//   • Klucz API dostawcy nigdy tu nie trafia — dostajemy wyłącznie token rozmowy.
//   • `expiresAt` zostaje `nil`: backend świadomie go nie wysyła.
//   • `session_id` powstaje raz (UUID) i jest używany w obu żądaniach otwarcia:
//     `POST /voice/sessions`, a zaraz potem `POST /voice/conversation-token`.
//   • `Idempotency-Key` jest pochodny (operacja + sesja + wersja kontekstu), więc
//     powtórka tego samego logicznego żądania po utracie sieci nie stworzy
//     drugiej sesji. Unikalność zapewnia UUID sesji.

public struct BackendVoiceSessionRepository: VoiceSessionRepository, Sendable {

    private let api: BackendAPIClient

    public init(
        baseURL: URL,
        accessTokenProvider: @escaping @Sendable () async -> String?,
        session: URLSession = .shared,
        timeout: TimeInterval = 20
    ) {
        self.api = BackendAPIClient(
            baseURL: baseURL,
            accessToken: accessTokenProvider,
            session: session,
            timeout: timeout
        )
    }

    /// Inicjalizacja dla testów i miejsc, które składają klienta HTTP same.
    public init(client: BackendAPIClient) {
        self.api = client
    }

    // MARK: VoiceSessionRepository

    /// Otwarcie sesji i wydanie tokenu rozmowy. Oba żądania dzielą jeden
    /// `session_id`; token jest wymagany przez `VoiceSessionConfiguration`.
    public func create(_ request: CreateVoiceSession) async throws -> VoiceSessionConfiguration {
        let sessionID = VoiceSessionID(UUID().uuidString.lowercased())
        let version = max(request.context.version.value, Version.initial.value)

        let opened = try await call {
            try await api.createVoiceSession(
                sessionID: sessionID,
                installationID: request.installationID,
                contextVersion: version,
                idempotencyKey: Self.idempotencyKey(
                    operation: "session",
                    sessionID: sessionID,
                    version: version
                )
            )
        }
        try Self.verifySessionID(opened.id, matches: sessionID)

        let issued = try await call {
            try await api.voiceConversationToken(
                sessionID: sessionID,
                installationID: request.installationID,
                contextVersion: opened.contextVersion,
                idempotencyKey: Self.idempotencyKey(
                    operation: "token",
                    sessionID: sessionID,
                    version: opened.contextVersion
                )
            )
        }
        try Self.verifySessionID(issued.sessionID, matches: sessionID)

        // Kontrakt nie niesie pełnego kontekstu — tylko jego wersję. Bierzemy
        // kontekst, o który prosiliśmy, ale z wersją potwierdzoną przez backend,
        // żeby dalsze `PATCH` rosło od stanu faktycznego, a nie od założenia.
        var confirmedContext = request.context
        confirmedContext.version = Version(opened.contextVersion)

        return VoiceSessionConfiguration(
            sessionID: sessionID,
            context: confirmedContext,
            assistantLanguage: request.assistantLanguage,
            conversationToken: issued.token,
            endpoint: nil,
            transport: request.requestedTransport,
            providerConversationID: issued.conversationID,
            // Backend nie wysyła `expires_at`, więc nie wymyślamy daty.
            expiresAt: nil,
            capabilities: .providerUnverified
        )
    }

    /// `PATCH /voice/sessions/{id}/context`. Wersja może tylko rosnąć, więc nowa
    /// wersja to `expectedContextVersion.next()` — chyba że kontekst przyszedł
    /// już z wyższą wersją (wtedy nie cofamy się poniżej niej).
    public func updateContext(_ request: UpdateVoiceContext) async throws -> AssistantContext {
        let newVersion = max(
            request.expectedContextVersion.next().value,
            request.context.version.value
        )
        let updated = try await call {
            try await api.updateVoiceContext(
                sessionID: request.sessionID,
                contextVersion: newVersion,
                idempotencyKey: Self.idempotencyKey(
                    operation: "context",
                    sessionID: request.sessionID,
                    version: newVersion
                )
            )
        }
        try Self.verifySessionID(updated.id, matches: request.sessionID)

        var confirmed = request.context
        confirmed.version = Version(updated.contextVersion)
        return confirmed
    }

    /// `GET /voice/sessions/{id}/status`. Kontrakt zwraca wyłącznie
    /// `context_version`, nie cały kontekst, więc budujemy kontekst firmowy
    /// z faktyczną wersją. Jedyne pole, po które sięga koordynator, to
    /// `isActive` — reszta jest wypełniona, żeby nie udawać danych klienta.
    public func fetchStatus(sessionID: VoiceSessionID) async throws -> VoiceSessionStatus {
        let dto = try await call { try await api.voiceSessionStatus(sessionID: sessionID) }
        try Self.verifySessionID(dto.id, matches: sessionID)
        return VoiceSessionStatus(
            sessionID: sessionID,
            isActive: dto.state == "active",
            context: AssistantContext(scope: .firm, version: Version(dto.contextVersion)),
            expiresAt: nil,
            providerConversationID: dto.providerConversationID
        )
    }

    /// `DELETE /voice/sessions/{id}`. Powtórzenie jest bezpieczne (backend
    /// zwraca 204 także dla już zamkniętej sesji).
    public func end(sessionID: VoiceSessionID) async throws {
        try await call {
            try await api.endVoiceSession(
                sessionID: sessionID,
                idempotencyKey: Self.idempotencyKey(
                    operation: "end",
                    sessionID: sessionID,
                    version: nil
                )
            )
        }
    }

    // MARK: Idempotencja i błędy

    /// Klucz pochodny, nie losowy: powtórka tego samego logicznego żądania
    /// niesie identyczną wartość, więc backend nie założy drugiej sesji ani nie
    /// wykona zapisu dwa razy. UUID w `session_id` daje unikalność między sesjami.
    static func idempotencyKey(operation: String, sessionID: VoiceSessionID, version: Int?) -> String {
        if let version {
            return "emma-voice-\(operation)-\(sessionID.rawValue)-v\(version)"
        }
        return "emma-voice-\(operation)-\(sessionID.rawValue)"
    }

    /// Odpowiedź musi dotyczyć tej samej sesji, o którą pytaliśmy. Rozbieżność
    /// to niezgodność kontraktu, a nie sytuacja do cichego zaakceptowania.
    private static func verifySessionID(_ raw: String, matches sessionID: VoiceSessionID) throws {
        guard raw == sessionID.rawValue else {
            throw DomainError.validationFailed(
                "Backend zwrócił sesję \(raw), a oczekiwano \(sessionID.rawValue)."
            )
        }
    }

    /// Wywołanie z mapowaniem błędów backendu na błędy domenowe. Dzięki temu
    /// koordynator pokazuje polskie `safeMessage` z `BackendRepositoryError`,
    /// zamiast zastępować je własnym, ogólnym komunikatem transportu.
    private func call<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as BackendRepositoryError {
            throw Self.domainError(from: error)
        }
    }

    static func domainError(from error: BackendRepositoryError) -> DomainError {
        switch error {
        case .unauthorized:
            return .unauthorized
        case .notFound:
            return .notFound(resource: "sesja głosowa", id: "")
        case .transport:
            return .transportFailure(error.safeMessage)
        case .forbidden, .conflict, .server, .notAvailableInBackend, .decoding:
            // Te przypadki niosą zdanie z backendu (albo zdanie tego pliku),
            // którego domena nie modeluje osobno — przekazujemy je bez zmian.
            return .backend(error.safeMessage)
        }
    }
}
