import Foundation

// MARK: - Propozycja działania
//
// UI i voice wykonują **tę samą wersjonowaną akcję backendową** (§1.10, §8.1).
// Zmiana treści, odbiorcy, kontekstu lub przerwanie odczytu unieważniają
// wcześniejsze uzbrojenie potwierdzenia głosowego.

public enum ActionKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case reply
    case note
    case task

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .reply: return "Wiadomość"
        case .note: return "Notatka"
        case .task: return "Zadanie"
        }
    }

    /// Etykieta przycisku zatwierdzenia.
    public var confirmLabel: String {
        switch self {
        case .reply: return "Zatwierdź wiadomość"
        case .note: return "Zapisz notatkę"
        case .task: return "Dodaj zadanie"
        }
    }
}

/// Stan zgody. Oddzielony od stanu wykonania (§8.1).
public enum ProposalState: String, Codable, Sendable {
    case proposed
    case superseded
    case rejected
    case expired
    case confirmed

    public var displayName: String {
        switch self {
        case .proposed: return "Do sprawdzenia"
        case .superseded: return "Zastąpione"
        case .rejected: return "Anulowano"
        case .expired: return "Wygasło"
        case .confirmed: return "Zatwierdzone"
        }
    }

    public var isActionable: Bool { self == .proposed }
}

/// Stan wykonania po stronie backendu/outboxa.
public enum ExecutionState: String, Codable, Sendable {
    case queued
    case claimed
    case dispatching
    /// Przyjęta przez API dostawcy. **Nie** znaczy dostarczona.
    case accepted
    case failed
    /// Wynik nieznany — bez automatycznego retry (§8.3).
    case unknown

    public var displayName: String {
        switch self {
        case .queued: return "W kolejce"
        case .claimed: return "Przyjęte do wysłania"
        case .dispatching: return "Wysyłanie"
        case .accepted: return "Przyjęta przez WhatsApp"
        case .failed: return "Błąd"
        case .unknown: return "Sprawdzamy status wysyłki"
        }
    }
}

/// Zamrożony, wersjonowany payload akcji.
public struct ActionProposal: Identifiable, Hashable, Codable, Sendable {
    public let id: ActionID
    public var kind: ActionKind
    public var version: Version
    public var actorUserID: UserID
    public var sessionID: VoiceSessionID?
    public var clientID: ClientID?
    public var caseID: CaseID?
    public var threadID: ThreadID?
    public var text: String
    /// Skrót treści i relacji. Zmiana czegokolwiek unieważnia wcześniejszą zgodę.
    public var payloadHash: String
    public var contextVersion: Version
    public var threadVersion: Version?
    public var presentedAt: Date
    public var expiresAt: Date
    /// Identyfikator prezentacji w interfejsie/głosie. Zgoda musi być związana z prezentacją.
    public var presentationID: String
    public var state: ProposalState
    /// Dodatkowe pola dla zadań.
    public var taskOwnerID: UserID?
    public var taskDueDate: LocalDate?

    public init(
        id: ActionID,
        kind: ActionKind,
        version: Version = .initial,
        actorUserID: UserID,
        sessionID: VoiceSessionID? = nil,
        clientID: ClientID? = nil,
        caseID: CaseID? = nil,
        threadID: ThreadID? = nil,
        text: String,
        payloadHash: String,
        contextVersion: Version,
        threadVersion: Version? = nil,
        presentedAt: Date,
        expiresAt: Date,
        presentationID: String,
        state: ProposalState = .proposed,
        taskOwnerID: UserID? = nil,
        taskDueDate: LocalDate? = nil
    ) {
        self.id = id
        self.kind = kind
        self.version = version
        self.actorUserID = actorUserID
        self.sessionID = sessionID
        self.clientID = clientID
        self.caseID = caseID
        self.threadID = threadID
        self.text = text
        self.payloadHash = payloadHash
        self.contextVersion = contextVersion
        self.threadVersion = threadVersion
        self.presentedAt = presentedAt
        self.expiresAt = expiresAt
        self.presentationID = presentationID
        self.state = state
        self.taskOwnerID = taskOwnerID
        self.taskDueDate = taskDueDate
    }

    public func isExpired(at now: Date) -> Bool { now >= expiresAt }
}

public struct ActionExecution: Identifiable, Hashable, Codable, Sendable {
    public var actionID: ActionID
    /// Wersja akcji, której dotyczy to wykonanie.
    public var proposalVersion: Version
    public var state: ExecutionState
    public var outboxID: String
    public var messageID: MessageID?
    public var providerMessageID: String?
    public var updatedAt: Date
    public var lastErrorCode: String?

    public var id: ActionID { actionID }

    public init(
        actionID: ActionID,
        proposalVersion: Version,
        state: ExecutionState,
        outboxID: String,
        messageID: MessageID? = nil,
        providerMessageID: String? = nil,
        updatedAt: Date,
        lastErrorCode: String? = nil
    ) {
        self.actionID = actionID
        self.proposalVersion = proposalVersion
        self.state = state
        self.outboxID = outboxID
        self.messageID = messageID
        self.providerMessageID = providerMessageID
        self.updatedAt = updatedAt
        self.lastErrorCode = lastErrorCode
    }
}

// MARK: - Silnik akcji (jedna implementacja dla UI i głosu)

public enum ActionEngineError: Error, Equatable, Sendable {
    case proposalNotFound
    case proposalNotActionable(ProposalState)
    case proposalExpired
    case emptyText
    case missingRecipient
    case stalePresentation(expected: String, received: String)
    case versionConflict(expected: Version, current: Version)
    case duplicateExecution
    case alreadyExecuting
    case supersededByRevision
    case confirmationNotBoundToCurrentPresentation

    public var safeMessage: String {
        switch self {
        case .proposalNotFound: return "Nie ma przygotowanego działania."
        case .proposalNotActionable(let state): return "Działanie jest w stanie: \(state.displayName)."
        case .proposalExpired: return "Propozycja wygasła. Przygotuj ją ponownie."
        case .emptyText: return "Treść nie może być pusta."
        case .missingRecipient: return "Wybierz klienta, do którego należy działanie."
        case .stalePresentation: return "Ta propozycja została już zastąpiona nowszą wersją."
        case .versionConflict(let expected, let current):
            return "Konflikt wersji: oczekiwano \(expected), aktualnie \(current)."
        case .duplicateExecution: return "To działanie zostało już wykonane."
        case .alreadyExecuting: return "To działanie jest już w trakcie wykonania."
        case .supersededByRevision: return "Zgoda dotyczyła wcześniejszej wersji treści."
        case .confirmationNotBoundToCurrentPresentation:
            return "Potwierdzenie nie dotyczy aktualnie pokazanej propozycji."
        }
    }
}

/// Deterministyczny silnik akcji używany w M1 z mockowym backendem.
/// W M2 ta sama struktura stanu jest odtwarzana przez odpowiedzi API;
/// logika przejść pozostaje identyczna.
public struct ActionEngine: Sendable {

    public struct State: Sendable {
        public var proposals: [ActionID: ActionProposal]
        public var executions: [ActionID: ActionExecution]
        /// Identyfikator prezentacji, której dotyczy uzbrojone potwierdzenie.
        public var armedPresentationID: String?

        public init(
            proposals: [ActionID: ActionProposal] = [:],
            executions: [ActionID: ActionExecution] = [:],
            armedPresentationID: String? = nil
        ) {
            self.proposals = proposals
            self.executions = executions
            self.armedPresentationID = armedPresentationID
        }

        public var activeProposal: ActionProposal? {
            proposals.values.first { $0.state == .proposed }
        }
    }

    public let confirmationWindow: TimeInterval

    public init(confirmationWindow: TimeInterval = 15 * 60) {
        self.confirmationWindow = confirmationWindow
    }

    /// Wylicza skrót payloadu. W live jest to hash/HMAC po stronie backendu;
    /// tu deterministyczna funkcja dostępna także na Linuksie.
    public static func payloadHash(
        kind: ActionKind,
        text: String,
        clientID: ClientID?,
        caseID: CaseID?,
        threadID: ThreadID?
    ) -> String {
        let parts = [
            kind.rawValue,
            text.trimmingCharacters(in: .whitespacesAndNewlines),
            clientID?.rawValue ?? "-",
            caseID?.rawValue ?? "-",
            threadID?.rawValue ?? "-"
        ]
        return FNV1a64.hex(of: parts.joined(separator: "\u{1F}"))
    }

    // MARK: Przygotowanie

    public func prepare(
        _ request: PrepareActionRequest,
        into state: inout State
    ) -> ActionProposal {
        // Nowa propozycja zastępuje poprzednią, nieaktywną jeszcze propozycję.
        if let existing = state.activeProposal, existing.id != request.actionID {
            var superseded = existing
            superseded.state = .superseded
            state.proposals[existing.id] = superseded
        }

        let proposal = ActionProposal(
            id: request.actionID,
            kind: request.kind,
            actorUserID: request.actorUserID,
            sessionID: request.sessionID,
            clientID: request.clientID,
            caseID: request.caseID,
            threadID: request.threadID,
            text: request.text,
            payloadHash: ActionEngine.payloadHash(
                kind: request.kind,
                text: request.text,
                clientID: request.clientID,
                caseID: request.caseID,
                threadID: request.threadID
            ),
            contextVersion: request.contextVersion,
            threadVersion: request.threadVersion,
            presentedAt: request.now,
            expiresAt: request.now.addingTimeInterval(confirmationWindow),
            presentationID: request.presentationID,
            taskOwnerID: request.taskOwnerID,
            taskDueDate: request.taskDueDate
        )
        state.proposals[proposal.id] = proposal
        // Nowa prezentacja rozbraja poprzednie uzbrojenie.
        state.armedPresentationID = nil
        return proposal
    }

    // MARK: Rewizja

    /// Korekta treści tworzy **nową wersję** propozycji i unieważnia starą zgodę (§1.10).
    public func revise(
        actionID: ActionID,
        newText: String,
        now: Date,
        into state: inout State
    ) throws -> ActionProposal {
        guard var proposal = state.proposals[actionID] else { throw ActionEngineError.proposalNotFound }
        guard proposal.state.isActionable else {
            throw ActionEngineError.proposalNotActionable(proposal.state)
        }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ActionEngineError.emptyText }

        let previous = proposal
        proposal.text = trimmed
        proposal.version = previous.version.next()
        proposal.payloadHash = ActionEngine.payloadHash(
            kind: proposal.kind,
            text: trimmed,
            clientID: proposal.clientID,
            caseID: proposal.caseID,
            threadID: proposal.threadID
        )
        proposal.presentedAt = now
        proposal.expiresAt = now.addingTimeInterval(confirmationWindow)
        proposal.presentationID = previous.presentationID + "#r\(proposal.version.value)"
        state.proposals[actionID] = proposal
        // Zgoda na poprzednią treść nie działa.
        state.armedPresentationID = nil
        return proposal
    }

    /// Zmiana odbiorcy lub kontekstu też unieważnia zgodę.
    public func changeContext(
        actionID: ActionID,
        clientID: ClientID?,
        caseID: CaseID?,
        threadID: ThreadID?,
        now: Date,
        into state: inout State
    ) throws -> ActionProposal {
        guard var proposal = state.proposals[actionID] else { throw ActionEngineError.proposalNotFound }
        guard proposal.state.isActionable else {
            throw ActionEngineError.proposalNotActionable(proposal.state)
        }
        proposal.clientID = clientID
        proposal.caseID = caseID
        proposal.threadID = threadID
        proposal.version = proposal.version.next()
        proposal.presentedAt = now
        proposal.expiresAt = now.addingTimeInterval(confirmationWindow)
        proposal.payloadHash = ActionEngine.payloadHash(
            kind: proposal.kind,
            text: proposal.text,
            clientID: clientID,
            caseID: caseID,
            threadID: threadID
        )
        state.proposals[actionID] = proposal
        state.armedPresentationID = nil
        return proposal
    }

    /// Uzbrojenie potwierdzenia głosowego dla **konkretnej prezentacji**.
    /// Samo „tak/да” nie wystarcza (§8.2).
    public func arm(
        actionID: ActionID,
        presentationID: String,
        into state: inout State
    ) throws {
        guard let proposal = state.proposals[actionID] else { throw ActionEngineError.proposalNotFound }
        guard proposal.state.isActionable else {
            throw ActionEngineError.proposalNotActionable(proposal.state)
        }
        guard proposal.presentationID == presentationID else {
            throw ActionEngineError.stalePresentation(expected: proposal.presentationID, received: presentationID)
        }
        state.armedPresentationID = presentationID
    }

    /// Rozbrojenie bez wykonania: przerwanie odczytu, nowa wiadomość klienta,
    /// reconnect, zmiana kontekstu (§8.2).
    public func disarm(into state: inout State) {
        state.armedPresentationID = nil
    }

    // MARK: Potwierdzenie

    public struct Confirmation: Sendable {
        public var actionID: ActionID
        public var expectedVersion: Version
        /// Dowód pochodzenia zgody: identyfikator prezentacji pokazanej użytkownikowi.
        public var presentationID: String
        /// Zgoda głosowa wymaga finalnej wypowiedzi uwierzytelnionego użytkownika.
        public var origin: Origin
        public var now: Date

        public enum Origin: String, Sendable {
            /// Bezpośrednie dotknięcie przycisku wysyłki/zatwierdzenia w UI.
            case directUIButton
            /// Finalna wypowiedź użytkownika w sesji głosowej.
            case authenticatedVoiceTurn
            /// Argument toola wygenerowany przez LLM. **Nie** jest dowodem (§8.2).
            case languageModelArgument
        }

        public init(
            actionID: ActionID,
            expectedVersion: Version,
            presentationID: String,
            origin: Origin,
            now: Date
        ) {
            self.actionID = actionID
            self.expectedVersion = expectedVersion
            self.presentationID = presentationID
            self.origin = origin
            self.now = now
        }
    }

    /// Potwierdzenie tworzy **jedno** wykonanie i unikalny wpis outboxa, atomowo (§8.1).
    public func confirm(
        _ confirmation: Confirmation,
        outboxID: String,
        into state: inout State
    ) throws -> ActionExecution {
        guard var proposal = state.proposals[confirmation.actionID] else {
            throw ActionEngineError.proposalNotFound
        }
        guard proposal.state.isActionable else {
            // Powtórne potwierdzenie zwraca istniejące wykonanie, nie tworzy drugiego.
            if let existing = state.executions[confirmation.actionID] {
                return existing
            }
            throw ActionEngineError.proposalNotActionable(proposal.state)
        }
        guard !proposal.isExpired(at: confirmation.now) else {
            proposal.state = .expired
            state.proposals[proposal.id] = proposal
            state.armedPresentationID = nil
            throw ActionEngineError.proposalExpired
        }
        guard proposal.version == confirmation.expectedVersion else {
            throw ActionEngineError.versionConflict(expected: confirmation.expectedVersion, current: proposal.version)
        }
        guard proposal.presentationID == confirmation.presentationID else {
            throw ActionEngineError.confirmationNotBoundToCurrentPresentation
        }
        // Zgoda wyłącznie z finalnej wypowiedzi użytkownika albo bezpośredniego przycisku.
        guard confirmation.origin != .languageModelArgument else {
            throw ActionEngineError.confirmationNotBoundToCurrentPresentation
        }
        if confirmation.origin == .authenticatedVoiceTurn {
            guard state.armedPresentationID == confirmation.presentationID else {
                throw ActionEngineError.confirmationNotBoundToCurrentPresentation
            }
        }
        let trimmed = proposal.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ActionEngineError.emptyText }
        if proposal.kind == .reply || proposal.kind == .note {
            guard proposal.clientID != nil else { throw ActionEngineError.missingRecipient }
        }

        // Jedno wykonanie na akcję: istniejące wykonanie blokuje drugie.
        // Wystarczy sprawdzenie obecności — treść wykonania nie jest tu potrzebna.
        if state.executions[confirmation.actionID] != nil {
            throw ActionEngineError.duplicateExecution
        }

        proposal.state = .confirmed
        state.proposals[proposal.id] = proposal
        state.armedPresentationID = nil

        let execution = ActionExecution(
            actionID: proposal.id,
            proposalVersion: proposal.version,
            state: .queued,
            outboxID: outboxID,
            updatedAt: confirmation.now
        )
        state.executions[proposal.id] = execution
        return execution
    }

    public func cancel(
        actionID: ActionID,
        now: Date,
        into state: inout State
    ) throws -> ActionProposal {
        guard var proposal = state.proposals[actionID] else { throw ActionEngineError.proposalNotFound }
        guard proposal.state.isActionable else {
            throw ActionEngineError.proposalNotActionable(proposal.state)
        }
        proposal.state = .rejected
        state.proposals[actionID] = proposal
        state.armedPresentationID = nil
        return proposal
    }

    /// Aktualizacja stanu wykonania z backendu. `accepted` nie awansuje na `delivered`
    /// bez zdarzenia dostawcy; `unknown` nie uruchamia ponownej próby (§8.3).
    public func applyExecutionState(
        actionID: ActionID,
        state newState: ExecutionState,
        now: Date,
        providerMessageID: String? = nil,
        into state: inout State
    ) -> ActionExecution? {
        guard var execution = state.executions[actionID] else { return nil }
        switch newState {
        case .accepted, .failed, .unknown, .claimed, .dispatching, .queued:
            execution.state = newState
        }
        if let providerMessageID { execution.providerMessageID = providerMessageID }
        execution.updatedAt = now
        state.executions[actionID] = execution
        return execution
    }

    /// Ponowna próba dozwolona wyłącznie dla jawnie nieudanego wykonania.
    /// `unknown` wymaga uzgodnienia, nie retry (§8.3).
    public static func mayRetry(_ execution: ActionExecution) -> Bool {
        execution.state == .failed
    }

    public static func requiresReconciliation(_ execution: ActionExecution) -> Bool {
        execution.state == .unknown
    }
}

public struct PrepareActionRequest: Sendable {
    public var actionID: ActionID
    public var kind: ActionKind
    public var actorUserID: UserID
    public var sessionID: VoiceSessionID?
    public var clientID: ClientID?
    public var caseID: CaseID?
    public var threadID: ThreadID?
    public var text: String
    public var contextVersion: Version
    public var threadVersion: Version?
    public var presentationID: String
    public var now: Date
    public var taskOwnerID: UserID?
    public var taskDueDate: LocalDate?

    public init(
        actionID: ActionID,
        kind: ActionKind,
        actorUserID: UserID,
        sessionID: VoiceSessionID? = nil,
        clientID: ClientID? = nil,
        caseID: CaseID? = nil,
        threadID: ThreadID? = nil,
        text: String,
        contextVersion: Version,
        threadVersion: Version? = nil,
        presentationID: String,
        now: Date,
        taskOwnerID: UserID? = nil,
        taskDueDate: LocalDate? = nil
    ) {
        self.actionID = actionID
        self.kind = kind
        self.actorUserID = actorUserID
        self.sessionID = sessionID
        self.clientID = clientID
        self.caseID = caseID
        self.threadID = threadID
        self.text = text
        self.contextVersion = contextVersion
        self.threadVersion = threadVersion
        self.presentationID = presentationID
        self.now = now
        self.taskOwnerID = taskOwnerID
        self.taskDueDate = taskDueDate
    }
}

/// Deterministyczny skrót dostępny bez CryptoKit (działa też na Linuksie).
public enum FNV1a64 {
    public static func hex(of string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(format: "%016llx", hash)
    }
}
