import Foundation

// MARK: - Kontekst asystenta
//
// Kontekst jest wersjonowany. Zmiana kontekstu jest oddzielną, wersjonowaną
// czynnością (§5.2) i unieważnia wcześniejszą zgodę (§1.10).

public enum AssistantScope: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Cała kancelaria.
    case firm
    case client
    case legalCase
    case thread

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .firm: return "Cała kancelaria"
        case .client: return "Klient"
        case .legalCase: return "Sprawa"
        case .thread: return "Rozmowa"
        }
    }
}

public struct AssistantContext: Hashable, Codable, Sendable {
    public var scope: AssistantScope
    public var clientID: ClientID?
    public var caseID: CaseID?
    public var threadID: ThreadID?
    public var version: Version
    /// Numer wersji wątku zamrożony w kontekście — chroni przed odpowiedzią
    /// do nieaktualnej historii (§3.3 pkt 8, §8.1).
    public var threadVersion: Version?

    public init(
        scope: AssistantScope,
        clientID: ClientID? = nil,
        caseID: CaseID? = nil,
        threadID: ThreadID? = nil,
        version: Version = .initial,
        threadVersion: Version? = nil
    ) {
        self.scope = scope
        self.clientID = clientID
        self.caseID = caseID
        self.threadID = threadID
        self.version = version
        self.threadVersion = threadVersion
    }

    public static let firm = AssistantContext(scope: .firm)

    public var displayLabel: String {
        switch scope {
        case .firm: return "Cała kancelaria"
        case .client, .legalCase, .thread: return "Wybrany klient"
        }
    }

    /// Kontekst z konkretnym klientem i opcjonalną sprawą.
    public static func client(_ clientID: ClientID, caseID: CaseID? = nil) -> AssistantContext {
        AssistantContext(scope: caseID == nil ? .client : .legalCase, clientID: clientID, caseID: caseID)
    }

    /// Kontekst rozmowy: klient **i** wątek z jego wersją.
    public static func thread(
        _ threadID: ThreadID,
        clientID: ClientID,
        caseID: CaseID?,
        threadVersion: Version
    ) -> AssistantContext {
        AssistantContext(
            scope: .thread,
            clientID: clientID,
            caseID: caseID,
            threadID: threadID,
            threadVersion: threadVersion
        )
    }

    /// Walidacja relacji: sprawa musi należeć do wskazanego klienta, wątek do klienta.
    /// Backend odrzuca niespójny kontekst; robimy to też lokalnie, żeby błąd był widoczny wcześnie.
    public static func validate(
        _ context: AssistantContext,
        clients: [Client],
        cases: [LegalCase],
        threads: [ConversationThread]
    ) -> ContextValidation {
        if let caseID = context.caseID {
            guard let legalCase = cases.first(where: { $0.id == caseID }) else {
                return .rejected("Sprawa nie istnieje.")
            }
            if let clientID = context.clientID, legalCase.clientID != clientID {
                return .rejected("Sprawa należy do innego klienta.")
            }
        }
        if let threadID = context.threadID {
            guard let thread = threads.first(where: { $0.id == threadID }) else {
                return .rejected("Wątek nie istnieje.")
            }
            if let clientID = context.clientID, thread.clientID != clientID {
                return .rejected("Wątek należy do innego klienta.")
            }
        }
        if context.scope != .firm, context.clientID == nil {
            return .rejected("Kontekst klienta wymaga wskazania klienta.")
        }
        return .accepted
    }

    public enum ContextValidation: Equatable, Sendable {
        case accepted
        case rejected(String)
    }
}

// MARK: - Tury asystenta

public struct AssistantTextInput: Hashable, Codable, Sendable {
    public var text: String
    /// Język wypowiedzi użytkownika. Nie zakładamy języka klienta (§5.1).
    public var language: LanguageCode
    public var contextVersion: Version
    public var inputID: String
    /// Czy tekst pochodzi z finalnej transkrypcji wypowiedzi adwokata.
    public var origin: Origin

    public enum Origin: String, Codable, Sendable {
        case typedText
        case dictation
        case authenticatedVoiceTurn
    }

    public init(
        text: String,
        language: LanguageCode,
        contextVersion: Version,
        inputID: String,
        origin: Origin = .typedText
    ) {
        self.text = text
        self.language = language
        self.contextVersion = contextVersion
        self.inputID = inputID
        self.origin = origin
    }
}

public enum AssistantTurnRole: String, Codable, Sendable {
    case user
    /// Emma. `agentTextFinal` nie oznacza końca TTS (§5.4).
    case assistant
}

// MARK: - Żądania repozytoriów (kontrakt §5.3)

public struct CreateVoiceSession: Sendable {
    public var userID: UserID
    public var context: AssistantContext
    /// Język rozmowy z Emmą (§5.1). Domyślnie rosyjski, konfigurowalny per użytkownik.
    public var assistantLanguage: LanguageCode
    public var installationID: String
    public var requestedTransport: VoiceTransportKind

    public init(
        userID: UserID,
        context: AssistantContext,
        assistantLanguage: LanguageCode,
        installationID: String,
        requestedTransport: VoiceTransportKind = .webrtc
    ) {
        self.userID = userID
        self.context = context
        self.assistantLanguage = assistantLanguage
        self.installationID = installationID
        self.requestedTransport = requestedTransport
    }
}

public enum VoiceTransportKind: String, Codable, Sendable {
    case webrtc
    case websocketTextOnly
}

public struct UpdateVoiceContext: Sendable {
    public var sessionID: VoiceSessionID
    public var context: AssistantContext
    public var expectedContextVersion: Version

    public init(sessionID: VoiceSessionID, context: AssistantContext, expectedContextVersion: Version) {
        self.sessionID = sessionID
        self.context = context
        self.expectedContextVersion = expectedContextVersion
    }
}

public struct VoiceSessionStatus: Hashable, Codable, Sendable {
    public var sessionID: VoiceSessionID
    public var isActive: Bool
    public var context: AssistantContext
    /// Czas wygaśnięcia, jeśli dostawca go podaje. `nil` to „nieznany”, nie „brak
    /// terminu” — o żywotności sesji rozstrzyga backend, a nie lokalny zegar.
    public var expiresAt: Date?
    public var providerConversationID: String?

    public init(
        sessionID: VoiceSessionID,
        isActive: Bool,
        context: AssistantContext,
        expiresAt: Date?,
        providerConversationID: String? = nil
    ) {
        self.sessionID = sessionID
        self.isActive = isActive
        self.context = context
        self.expiresAt = expiresAt
        self.providerConversationID = providerConversationID
    }
}

public struct PrepareAction: Sendable {
    public var request: PrepareActionRequest
    public init(_ request: PrepareActionRequest) { self.request = request }
}

public struct ReviseAction: Sendable {
    public var actionID: ActionID
    public var expectedVersion: Version
    public var newText: String
    public var now: Date

    public init(actionID: ActionID, expectedVersion: Version, newText: String, now: Date) {
        self.actionID = actionID
        self.expectedVersion = expectedVersion
        self.newText = newText
        self.now = now
    }
}

public struct RescheduleAction: Sendable {
    public var actionID: ActionID
    public var expectedVersion: Version
    public var dueDate: LocalDate?
    public var now: Date

    public init(actionID: ActionID, expectedVersion: Version, dueDate: LocalDate?, now: Date) {
        self.actionID = actionID
        self.expectedVersion = expectedVersion
        self.dueDate = dueDate
        self.now = now
    }
}

public struct ChangeActionContext: Sendable {
    public var actionID: ActionID
    public var expectedVersion: Version
    public var clientID: ClientID?
    public var caseID: CaseID?
    public var threadID: ThreadID?
    public var now: Date

    public init(
        actionID: ActionID,
        expectedVersion: Version,
        clientID: ClientID?,
        caseID: CaseID?,
        threadID: ThreadID?,
        now: Date
    ) {
        self.actionID = actionID
        self.expectedVersion = expectedVersion
        self.clientID = clientID
        self.caseID = caseID
        self.threadID = threadID
        self.now = now
    }
}

public struct ConfirmAction: Sendable {
    public var confirmation: ActionEngine.Confirmation
    /// Klucz idempotencji; ten sam przy ponowieniu tego samego potwierdzenia.
    public var idempotencyKey: String

    public init(confirmation: ActionEngine.Confirmation, idempotencyKey: String) {
        self.confirmation = confirmation
        self.idempotencyKey = idempotencyKey
    }
}

public struct CancelAction: Sendable {
    public var actionID: ActionID
    public var now: Date
    public init(actionID: ActionID, now: Date) {
        self.actionID = actionID
        self.now = now
    }
}
