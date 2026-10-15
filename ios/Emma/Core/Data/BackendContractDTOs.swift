import Foundation

// MARK: - Kształty JSON-a kontraktu
//
// Typy są wewnętrzne: to nie model aplikacji, tylko wierny obraz odpowiedzi
// backendu. Mapowanie na `Client`, `TaskItem` itd. należy do `BackendRepository`,
// więc warstwy nie przeciekają do siebie.

struct BackendItems<T: Decodable>: Decodable {
    let items: [T]
}

struct BackendClientPage: Decodable {
    let items: [BackendClientDTO]
    let nextCursor: String?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

struct BackendClientDTO: Decodable {
    let id: String
    let displayName: String
    let initials: String
    let language: String
    let topic: String
    let stage: String
    let source: String
    let createdAt: LocalDate
    let briefing: String?
    let incomingMessage: String?
    let incomingTranslation: String?
    let incomingTime: String?
    let needsReply: Bool
    /// Rozszerzenie kontraktu (opcjonalne): dokładna chwila przyjęcia
    /// zgłoszenia, telefon i e-mail. Starszy backend ich nie wysyła — wtedy
    /// aplikacja liczy wiek leada z samej daty i nie proponuje dzwonienia.
    let receivedAt: String?
    let phone: String?
    let email: String?
    let version: Int
    /// Rozszerzenie 04.10.2026 (opcjonalne): rezerwacja konsultacji ze strony
    /// i gotowa odpowiedź na lead. Starszy backend ich nie wysyła.
    let consultation: BackendConsultationDTO?
    let replyTemplate: String?

    enum CodingKeys: String, CodingKey {
        case id, initials, language, topic, stage, source, briefing, version, phone, email, consultation
        case displayName = "display_name"
        case createdAt = "created_at"
        case incomingMessage = "incoming_message"
        case incomingTranslation = "incoming_translation"
        case incomingTime = "incoming_time"
        case needsReply = "needs_reply"
        case receivedAt = "received_at"
        case replyTemplate = "reply_template"
    }
}

struct BackendConsultationDTO: Decodable {
    let minutes: Int?
    let priceGrosze: Int?
    /// Termin w ISO UTC.
    let at: String?

    enum CodingKeys: String, CodingKey {
        case minutes, at
        case priceGrosze = "price_gr"
    }
}

struct BackendLegalCaseDTO: Decodable {
    let id: String
    let number: String
    let title: String
    let clientID: String
    let status: String
    let summary: String?
    let createdAt: LocalDate
    let version: Int
    /// Rozszerzenie kontraktu (backend 30.09.2026): sygnatura akt i sąd osobno.
    let signature: String?
    let court: String?
    /// Rozszerzenie kontraktu (01.10.2026): profil sprawy i pilnowane daty.
    /// Starszy serwer ich nie wysyła — wtedy wszystkie są `nil`.
    let kind: String?
    let stage: String?
    let clientRole: String?
    let custodyUntil: String?
    let legalStayUntil: String?

    enum CodingKeys: String, CodingKey {
        case id, number, title, status, summary, version, signature, court, kind, stage
        case clientID = "client_id"
        case createdAt = "created_at"
        case clientRole = "client_role"
        case custodyUntil = "custody_until"
        case legalStayUntil = "legal_stay_until"
    }
}

struct BackendTaskDTO: Decodable {
    let id: String
    let title: String
    let clientID: String?
    let caseID: String?
    let dueDate: String?
    let isDone: Bool
    let priority: String
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id, title, priority, version
        case clientID = "client_id"
        case caseID = "case_id"
        case dueDate = "due_date"
        case isDone = "is_done"
    }
}

struct BackendEventDTO: Decodable {
    let id: String
    /// Kontrakt wymaga klienta w terminie, ale baza kancelarii zna też terminy
    /// bez kartoteki (np. konsultację zapisaną z samego zgłoszenia). Pole jest
    /// więc opcjonalne, żeby jeden taki rekord **nie wywracał dekodowania całej
    /// odpowiedzi** — aplikacja pomija taki termin, zamiast gasić ekran.
    let clientID: String?
    let caseID: String?
    let title: String
    let day: LocalDate
    /// `null` przy terminie całodniowym — kontrakt nie niesie wtedy godziny.
    let time: String?
    /// `true` dla terminu całodniowego — wtedy `time` jest `null`.
    let allDay: Bool
    let durationMinutes: Int
    let kind: String
    let status: String
    let place: String?
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id, title, day, time, kind, status, place, version
        case clientID = "client_id"
        case caseID = "case_id"
        case allDay = "all_day"
        case durationMinutes = "duration_minutes"
    }
}

struct BackendNoteDTO: Decodable {
    let id: String
    let clientID: String
    let caseID: String?
    let text: String
    let authorID: String
    /// Pełny znacznik ISO (`2026-09-13T12:00:00.000Z`); aplikacja trzyma samą datę.
    let createdAt: String
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id, text, version
        case clientID = "client_id"
        case caseID = "case_id"
        case authorID = "author_id"
        case createdAt = "created_at"
    }
}

struct BackendActivityDTO: Decodable {
    let id: String
    let text: String
    let clientID: String?
    let caseID: String?
    let createdAt: String
    let authorID: String

    enum CodingKeys: String, CodingKey {
        case id, text
        case clientID = "client_id"
        case caseID = "case_id"
        case createdAt = "created_at"
        case authorID = "author_id"
    }
}

struct BackendClientCard: Decodable {
    let client: BackendClientDTO
    let legalCase: BackendLegalCaseDTO?
    let events: [BackendEventDTO]
    let tasks: [BackendTaskDTO]
    let notes: [BackendNoteDTO]
    let activity: [BackendActivityDTO]

    enum CodingKeys: String, CodingKey {
        case client, events, tasks, notes, activity
        case legalCase = "case"
    }
}

struct BackendCaseDetail: Decodable {
    let legalCase: BackendLegalCaseDTO
    let tasks: [BackendTaskDTO]
    let events: [BackendEventDTO]
    let notes: [BackendNoteDTO]
    let activity: [BackendActivityDTO]

    enum CodingKeys: String, CodingKey {
        case tasks, events, notes, activity
        case legalCase = "case"
    }
}

// MARK: - Kształty JSON-a zapisu

struct BackendEmptyBody: Encodable {}

struct BackendExpectedVersionBody: Encodable {
    let expectedVersion: Int
    enum CodingKeys: String, CodingKey { case expectedVersion = "expected_version" }
}

struct BackendTaskCreateBody: Encodable {
    let title: String
    let dueDate: String
    let priority: String
    let clientID: String?
    let caseID: String?

    enum CodingKeys: String, CodingKey {
        case title, priority
        case dueDate = "due_date"
        case clientID = "client_id"
        case caseID = "case_id"
    }
}

struct BackendTaskUpdateBody: Encodable {
    var expectedVersion: Int
    var title: String?
    var dueDate: String?
    var priority: String?
    var isDone: Bool?
    /// Zmiana klienta: `nil` — bez zmiany, `.some(nil)` — odpięcie (`null`).
    var clientID: String?? = nil

    enum CodingKeys: String, CodingKey {
        case title, priority
        case expectedVersion = "expected_version"
        case dueDate = "due_date"
        case isDone = "is_done"
        case clientID = "client_id"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(expectedVersion, forKey: .expectedVersion)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(isDone, forKey: .isDone)
        if let clientID {
            try container.encode(clientID, forKey: .clientID)
        }
    }
}

struct BackendEventCreateBody: Encodable {
    let title: String
    let day: String
    let time: String
    let durationMinutes: Int
    let kind: String
    /// `nil` — termin bez klienta (pole pomijane w JSON-ie).
    let clientID: String?
    let caseID: String?
    let place: String?

    enum CodingKeys: String, CodingKey {
        case title, day, time, kind, place
        case durationMinutes = "duration_minutes"
        case clientID = "client_id"
        case caseID = "case_id"
    }
}

struct BackendEventUpdateBody: Encodable {
    var expectedVersion: Int
    var status: String?
    var durationMinutes: Int?
    var day: String?
    var time: String?
    var title: String?
    var place: String?
    var kind: String?

    enum CodingKeys: String, CodingKey {
        case status, day, time, title, place, kind
        case expectedVersion = "expected_version"
        case durationMinutes = "duration_minutes"
    }
}

struct BackendCaseCreateBody: Encodable {
    let clientID: String
    let title: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case title, summary
        case clientID = "client_id"
    }
}

struct BackendCaseUpdateBody: Encodable {
    let expectedVersion: Int
    let title: String?
    let status: String?
    /// `nil` — bez zmiany; pusty tekst czyści pole na serwerze.
    var signature: String? = nil
    var court: String? = nil
    /// Profil sprawy: token albo pusty tekst (czyści pole); `nil` — bez zmiany.
    var kind: String? = nil
    var stage: String? = nil
    var clientRole: String? = nil
    /// Data `YYYY-MM-DD` albo pusty tekst (czyści datę); `nil` — bez zmiany.
    var custodyUntil: String? = nil
    var legalStayUntil: String? = nil

    enum CodingKeys: String, CodingKey {
        case title, status, signature, court, kind, stage
        case expectedVersion = "expected_version"
        case clientRole = "client_role"
        case custodyUntil = "custody_until"
        case legalStayUntil = "legal_stay_until"
    }
}

struct BackendNoteCreateBody: Encodable {
    let text: String
    let clientID: String
    let caseID: String?
    let authorID: String

    enum CodingKeys: String, CodingKey {
        case text
        case clientID = "client_id"
        case caseID = "case_id"
        case authorID = "author_id"
    }
}

// MARK: - Kształty JSON-a akcji

struct BackendActionContextBody: Encodable {
    let scope: String
    let version: Int
    let clientID: String?
    let caseID: String?
    let threadID: String?

    enum CodingKeys: String, CodingKey {
        case scope, version
        case clientID = "client_id"
        case caseID = "case_id"
        case threadID = "thread_id"
    }
}

struct BackendActionPrepareBody: Encodable {
    let kind: String
    let text: String
    let origin: String
    let actorUserID: String
    let taskDueDate: String?
    let context: BackendActionContextBody

    enum CodingKeys: String, CodingKey {
        case kind, text, origin, context
        case actorUserID = "actor_user_id"
        case taskDueDate = "task_due_date"
    }
}

struct BackendActionReviseBody: Encodable {
    let text: String
    let expectedVersion: Int
    enum CodingKeys: String, CodingKey {
        case text
        case expectedVersion = "expected_version"
    }
}

struct BackendActionConfirmBody: Encodable {
    let presentationID: String
    let expectedContextVersion: Int
    let voiceSessionID: String?

    enum CodingKeys: String, CodingKey {
        case presentationID = "presentation_id"
        case expectedContextVersion = "expected_context_version"
        case voiceSessionID = "voice_session_id"
    }
}

/// Propozycja akcji z backendu. `context_version` rośnie przy każdej korekcie
/// i pełni rolę wersji propozycji (`expected_version` w `PATCH`).
struct BackendActionDTO: Decodable {
    let id: String
    let kind: String
    let actorUserID: String
    let clientID: String?
    let caseID: String?
    let threadID: String?
    let text: String
    let payloadHash: String
    let contextVersion: Int
    let presentedAt: String
    let expiresAt: String
    let presentationID: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case id, kind, text, state
        case actorUserID = "actor_user_id"
        case clientID = "client_id"
        case caseID = "case_id"
        case threadID = "thread_id"
        case payloadHash = "payload_hash"
        case contextVersion = "context_version"
        case presentedAt = "presented_at"
        case expiresAt = "expires_at"
        case presentationID = "presentation_id"
    }
}

struct BackendActionExecutionDTO: Decodable {
    let actionID: String
    let state: String
    let outboxID: String
    let providerMessageID: String?
    let updatedAt: String
    let failureCode: String?

    enum CodingKeys: String, CodingKey {
        case state
        case actionID = "action_id"
        case outboxID = "outbox_id"
        case providerMessageID = "provider_message_id"
        case updatedAt = "updated_at"
        case failureCode = "failure_code"
    }
}

// MARK: - Kształty JSON-a sesji głosu (M5)

/// Odpowiedź na otwarcie/zmianę/odczyt sesji głosu. `ended_at` jest `null`,
/// dopóki sesja żyje, a `provider_conversation_id` — dopóki nie wydano tokenu.
struct BackendVoiceSessionDTO: Decodable {
    let id: String
    let state: String
    let contextVersion: Int
    let installationID: String
    let startedAt: String
    let endedAt: String?
    let providerConversationID: String?

    enum CodingKeys: String, CodingKey {
        case id, state
        case contextVersion = "context_version"
        case installationID = "installation_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case providerConversationID = "provider_conversation_id"
    }
}

/// Odpowiedź `POST /voice/conversation-token` dla Gemini Live. Live API nie
/// wydaje identyfikatora rozmowy; `expires_at` i `model` są opcjonalne, bo
/// backend może ich nie zwrócić w każdej wersji kontraktu.
struct BackendConversationTokenDTO: Decodable {
    let token: String
    let conversationID: String?
    let contextVersion: Int
    let sessionID: String
    /// Nazwa dostawcy, który wydał token. Musi być `gemini_live`, jeśli pole
    /// jest obecne.
    let provider: String?
    /// Model wskazany przez backend — aplikacja ma go odesłać w `setup`.
    let model: String?
    /// Czas wygaśnięcia **jako tekst ISO-8601**. Świadomie nie `Date`: wspólny
    /// dekoder klienta nie ma strategii dat, a jeden format daty dostawcy nie
    /// może zmieniać dekodowania wszystkich pozostałych odpowiedzi.
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case token
        case conversationID = "conversation_id"
        case contextVersion = "context_version"
        case sessionID = "session_id"
        case provider
        case model
        case expiresAt = "expires_at"
    }
}

struct BackendVoiceSessionCreateBody: Encodable {
    let sessionID: String
    let installationID: String
    let contextVersion: Int

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case installationID = "installation_id"
        case contextVersion = "context_version"
    }
}

struct BackendVoiceConversationTokenBody: Encodable {
    let sessionID: String
    let installationID: String
    let contextVersion: Int

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case installationID = "installation_id"
        case contextVersion = "context_version"
    }
}

struct BackendVoiceContextBody: Encodable {
    let contextVersion: Int

    enum CodingKeys: String, CodingKey {
        case contextVersion = "context_version"
    }
}

// MARK: Rozmowy WhatsApp

struct BackendMessageDTO: Decodable {
    let id: String
    let threadID: String
    let direction: String
    let authorID: String?
    let authorLabel: String?
    let providerMessageID: String?
    let kind: String
    /// Rozszerzenie kontraktu: rodzaj załącznika (image, document, audio…).
    let attachmentType: String?
    /// Rozszerzenie kontraktu (01.10.2026): nazwa pliku załącznika.
    let attachmentName: String?
    let text: String
    let translation: String?
    let sentAt: String
    let sequence: Int
    let transport: String
    let source: String
    /// Rozszerzenie kontraktu: customer, business_app, api, history.
    let origin: String?
    let version: Int
    /// Rozszerzenie 10.10.2026: temat maila (rozmowy e-mail).
    let subject: String?

    enum CodingKeys: String, CodingKey {
        case id, direction, kind, text, translation, sequence, transport, source, origin, version, subject
        case threadID = "thread_id"
        case authorID = "author_id"
        case authorLabel = "author_label"
        case providerMessageID = "provider_message_id"
        case attachmentType = "attachment_type"
        case attachmentName = "attachment_name"
        case sentAt = "sent_at"
    }
}

struct BackendThreadSummaryDTO: Decodable {
    let id: String
    /// `nil` tylko dla rozmowy bez osoby (`include_unassigned=1`).
    let clientID: String?
    let clientName: String?
    let preview: BackendMessageDTO?
    let unreadCount: Int
    let isPinned: Bool?
    let highWatermark: Int?
    // Rozszerzenia kontraktu: stan osoby w wątku bez osobnego zapytania.
    let readCursorSequence: Int?
    let manualUnread: Bool?
    let readStateVersion: Int?
    /// Do kiedy WhatsApp pozwala wysłać swobodny tekst (ISO) — `nil`, gdy okno zamknięte.
    let replyWindowUntil: String?
    /// Rozszerzenie 02.10.2026: numer rozmówcy i znacznik rozmowy bez osoby.
    let contactPhone: String?
    let isUnassigned: Bool?
    /// Rozszerzenie 10.10.2026: kanał (`whatsapp` / `email`) i adres rozmówcy.
    let channel: String?
    let contactEmail: String?

    enum CodingKeys: String, CodingKey {
        case id, preview, channel
        case contactEmail = "contact_email"
        case contactPhone = "contact_phone"
        case isUnassigned = "is_unassigned"
        case clientID = "client_id"
        case clientName = "client_name"
        case unreadCount = "unread_count"
        case isPinned = "is_pinned"
        case highWatermark = "high_watermark"
        case readCursorSequence = "read_cursor_sequence"
        case manualUnread = "manual_unread"
        case readStateVersion = "read_state_version"
        case replyWindowUntil = "reply_window_until"
    }
}

struct BackendAssistantMessageBody: Encodable {
    let message: String
    let conversationID: Int?
    let contextClientID: String?
    let contextName: String?
    /// `["app_tools"]` — aplikacja wykona działania `app_*` z odpowiedzi (Etap 2).
    var capabilities: [String]? = nil
    /// Ekran, z którego użytkownik pisze (karta, sprawa, rozmowa, dzień w kalendarzu).
    var screen: BackendScreenContextBody? = nil

    enum CodingKeys: String, CodingKey {
        case message
        case conversationID = "conversation_id"
        case contextClientID = "context_client_id"
        case contextName = "context_name"
        case capabilities
        case screen
    }
}

struct BackendScreenContextBody: Encodable, Equatable {
    let name: String
    let day: String?
    let clientID: String?
    let clientName: String?
    let caseID: String?
    let threadID: String?

    enum CodingKeys: String, CodingKey {
        case name
        case day
        case clientID = "client_id"
        case clientName = "client_name"
        case caseID = "case_id"
        case threadID = "thread_id"
    }
}

struct BackendAssistantReplyDTO: Decodable {
    let conversationID: Int
    let reply: String
    /// Działania aplikacji do wykonania po odpowiedzi; brak u starszego serwera.
    let appCalls: [BackendAppCallDTO]?

    enum CodingKeys: String, CodingKey {
        case reply
        case conversationID = "conversation_id"
        case appCalls = "app_calls"
    }
}

struct BackendAssistantFeedbackBody: Encodable {
    let conversationID: Int
    let rating: String

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case rating
    }
}

struct BackendOKDTO: Decodable {
    let ok: Bool?
}

struct BackendAssistantUsageDTO: Decodable {
    let turns: Int
    let avgSeconds: Double?
    let toolErrors: Int
    let thumbsUp: Int
    let thumbsDown: Int
    let dailyLimit: Int
    let turnsLastDay: Int

    enum CodingKeys: String, CodingKey {
        case turns
        case avgSeconds = "avg_seconds"
        case toolErrors = "tool_errors"
        case thumbsUp = "thumbs_up"
        case thumbsDown = "thumbs_down"
        case dailyLimit = "daily_limit"
        case turnsLastDay = "turns_last_day"
    }
}

struct BackendEmmaAlertsDTO: Decodable {
    let alerts: [BackendEmmaAlertDTO]
}

struct BackendEmmaAlertDTO: Decodable {
    let id: String
    let kind: String
    let priority: Int
    let title: String
    let body: String
    let prompt: String
    let clientID: String?
    let caseID: String?
    let threadID: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, priority, title, body, prompt
        case clientID = "client_id"
        case caseID = "case_id"
        case threadID = "thread_id"
    }
}

struct BackendAppCallDTO: Decodable {
    let name: String
    let argumentsJSON: String

    enum CodingKeys: String, CodingKey {
        case name
        case argumentsJSON = "arguments_json"
    }
}

struct BackendDraftReplyDTO: Decodable {
    let text: String
    let language: String?
}

struct BackendVoiceUsageDTO: Decodable {
    let monthCostUsd: Double
    let budgetUsd: Double
    let sessions: Int
    let minutes: Int

    enum CodingKeys: String, CodingKey {
        case sessions, minutes
        case monthCostUsd = "month_cost_usd"
        case budgetUsd = "budget_usd"
    }
}

struct BackendThreadList: Decodable {
    let items: [BackendThreadSummaryDTO]
    let unreadTotal: Int

    enum CodingKeys: String, CodingKey {
        case items
        case unreadTotal = "unread_total"
    }
}

struct BackendMessagePage: Decodable {
    let items: [BackendMessageDTO]
    let highWatermark: Int

    enum CodingKeys: String, CodingKey {
        case items
        case highWatermark = "high_watermark"
    }
}

struct BackendThreadUserStateDTO: Decodable {
    let threadID: String
    let userID: String
    let readCursorSequence: Int
    let manualUnread: Bool
    let isPinned: Bool
    let version: Int

    enum CodingKeys: String, CodingKey {
        case version
        case threadID = "thread_id"
        case userID = "user_id"
        case readCursorSequence = "read_cursor_sequence"
        case manualUnread = "manual_unread"
        case isPinned = "is_pinned"
    }
}

struct BackendOutgoingMessageBody: Encodable {
    let text: String
    let authorID: String
    let language: String

    enum CodingKeys: String, CodingKey {
        case text, language
        case authorID = "author_id"
    }
}

struct BackendReadStateBody: Encodable {
    let readCursorSequence: Int
    let manualUnread: Bool
    let isPinned: Bool
    let expectedVersion: Int

    enum CodingKeys: String, CodingKey {
        case readCursorSequence = "read_cursor_sequence"
        case manualUnread = "manual_unread"
        case isPinned = "is_pinned"
        case expectedVersion = "expected_version"
    }
}

/// Dokument z akt sprawy (`MobileDocument`).
struct BackendDocumentDTO: Decodable, Sendable {
    let id: String
    let caseID: String
    let name: String
    let mime: String
    let size: Int
    let folder: String
    let status: String?
    let uploadedAt: String
    let uploadedBy: String?

    enum CodingKeys: String, CodingKey {
        case id, name, mime, size, folder, status
        case caseID = "case_id"
        case uploadedAt = "uploaded_at"
        case uploadedBy = "uploaded_by"
    }
}
