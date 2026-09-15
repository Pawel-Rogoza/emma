import Foundation

// MARK: - Możliwości transportu
//
// Nieobsługiwanej funkcji nie emulujemy etykietą sukcesu (§5.3).

public struct VoiceCapabilities: Hashable, Codable, Sendable {
    /// Czy transport dostarcza transkrypcje częściowe.
    public var partialTranscripts: Bool
    /// Czy można przerwać generację po stronie dostawcy.
    public var interruptGeneration: Bool
    /// Czy można zatrzymać lokalne odtwarzanie natychmiast.
    public var localPlaybackStop: Bool
    /// Czy dostawca raportuje faktyczne rozpoczęcie/zakończenie odtwarzania.
    public var reportsPlaybackEvents: Bool
    /// Czy raportuje wybór trasy audio.
    public var routeSelection: Bool
    /// Czy można zaktualizować kontekst w trakcie sesji.
    public var contextUpdate: Bool
    /// Czy SDK pozwala wysłać turę tekstową w aktywnej sesji.
    public var textTurn: Bool
    /// Czy dostawca podaje powód przerwania.
    public var reportsInterruptionReason: Bool

    public init(
        partialTranscripts: Bool,
        interruptGeneration: Bool,
        localPlaybackStop: Bool,
        reportsPlaybackEvents: Bool,
        routeSelection: Bool,
        contextUpdate: Bool,
        textTurn: Bool,
        reportsInterruptionReason: Bool
    ) {
        self.partialTranscripts = partialTranscripts
        self.interruptGeneration = interruptGeneration
        self.localPlaybackStop = localPlaybackStop
        self.reportsPlaybackEvents = reportsPlaybackEvents
        self.routeSelection = routeSelection
        self.contextUpdate = contextUpdate
        self.textTurn = textTurn
        self.reportsInterruptionReason = reportsInterruptionReason
    }

    /// Możliwości mocka: pełne, deterministyczne, bez mikrofonu i sieci.
    public static let mock = VoiceCapabilities(
        partialTranscripts: true,
        interruptGeneration: true,
        localPlaybackStop: true,
        reportsPlaybackEvents: true,
        routeSelection: false,
        contextUpdate: true,
        textTurn: true,
        reportsInterruptionReason: true
    )

    /// Konserwatywne założenie dla adaptera dostawcy przed spike'em.
    /// Wartości są nadpisywane po weryfikacji na koncie (§etap 09).
    public static let providerUnverified = VoiceCapabilities(
        partialTranscripts: true,
        interruptGeneration: true,
        localPlaybackStop: true,
        reportsPlaybackEvents: false,
        routeSelection: false,
        contextUpdate: true,
        textTurn: true,
        reportsInterruptionReason: false
    )
}

// MARK: - Konfiguracja sesji głosowej

public struct VoiceSessionConfiguration: Hashable, Codable, Sendable {
    public var sessionID: VoiceSessionID
    public var context: AssistantContext
    public var assistantLanguage: LanguageCode
    /// Krótkotrwałe poświadczenie wydane przez backend. **Nigdy** klucz API (§1.8).
    public var conversationToken: String
    /// Adres serwera transportu, jeśli backend go wskazuje.
    public var endpoint: String?
    public var transport: VoiceTransportKind
    /// Identyfikator rozmowy u dostawcy, jeśli backend go zna.
    public var providerConversationID: String?
    /// Czas wygaśnięcia poświadczenia, **jeśli** dostawca go podaje. `nil` znaczy
    /// „nieznany” — nie wymyślamy daty, a o żywotności sesji rozstrzyga backend
    /// (`GET /voice/sessions/{id}/status`).
    public var expiresAt: Date?
    public var capabilities: VoiceCapabilities

    public init(
        sessionID: VoiceSessionID,
        context: AssistantContext,
        assistantLanguage: LanguageCode,
        conversationToken: String,
        endpoint: String? = nil,
        transport: VoiceTransportKind = .webrtc,
        providerConversationID: String? = nil,
        expiresAt: Date?,
        capabilities: VoiceCapabilities
    ) {
        self.sessionID = sessionID
        self.context = context
        self.assistantLanguage = assistantLanguage
        self.conversationToken = conversationToken
        self.endpoint = endpoint
        self.transport = transport
        self.providerConversationID = providerConversationID
        self.expiresAt = expiresAt
        self.capabilities = capabilities
    }
}

// MARK: - Koperta zdarzenia (§5.4)
//
// Każde zdarzenie ma eventId, sessionId, connectionGeneration, opcjonalne turnId,
// contextVersion, kolejność źródłową, czas lokalnego odebrania i źródło.

public struct VoiceEventEnvelope<Payload: Sendable & Hashable>: Hashable, Sendable {
    public var eventID: String
    public var sessionID: VoiceSessionID
    /// Generacja konkretnego połączenia, nie „bieżąca globalna zmienna” (§5.4).
    public var connectionGeneration: ConnectionGeneration
    public var turnID: String?
    public var contextVersion: Version?
    /// Kolejność źródłowa, jeśli dostawca ją podaje.
    public var sourceSequence: Int?
    /// Czas lokalnego odebrania.
    public var receivedAt: Date
    public var source: VoiceEventSource
    public var payload: Payload

    public init(
        eventID: String,
        sessionID: VoiceSessionID,
        connectionGeneration: ConnectionGeneration,
        turnID: String? = nil,
        contextVersion: Version? = nil,
        sourceSequence: Int? = nil,
        receivedAt: Date,
        source: VoiceEventSource,
        payload: Payload
    ) {
        self.eventID = eventID
        self.sessionID = sessionID
        self.connectionGeneration = connectionGeneration
        self.turnID = turnID
        self.contextVersion = contextVersion
        self.sourceSequence = sourceSequence
        self.receivedAt = receivedAt
        self.source = source
        self.payload = payload
    }
}

public enum VoiceEventSource: String, Codable, Sendable {
    /// Deterministyczny symulator demo. Nie występuje w trybie live.
    case mockTransport
    case mockDictation
    case mockPlayback
    case providerTransport
    case providerDictation
    case providerPlayback
    case backendActionEngine
    case localPlaybackController
}

public enum VoiceEventPayload: Hashable, Sendable {
    // Połączenie
    case connectionChanged(ConnectionState)
    case microphoneChanged(MicrophoneState)
    case audioRouteChanged(AudioRoute)
    // Tura użytkownika
    case userSpeechStarted
    case userTranscriptPartial(String)
    case userTranscriptFinal(String)
    // Tura Emmy
    case agentTextDelta(String)
    case agentTextFinal(String)
    case playbackStarted(approximate: Bool)
    case playbackStopped(reason: PlaybackStopReason)
    // Narzędzia i akcje
    case toolProgress(ToolProgress)
    case proposalChanged(ProposalSnapshot)
    case executionChanged(ExecutionSnapshot)
    case contextAccepted(Version)
    // Problemy
    case interruption(InterruptionReason)
    case recoverableError(RecoverableErrorKind)
    case fatalError(FatalErrorKind)
}

public typealias VoiceEvent = VoiceEventEnvelope<VoiceEventPayload>

// MARK: - Stany (§5.5)

public enum ConnectionState: String, Codable, Sendable {
    case idle
    case requestingPermission
    case connecting
    case connected
    case reconnecting
    case failed
    case ended

    public var displayName: String {
        switch self {
        case .idle: return "Nieaktywna"
        case .requestingPermission: return "Uruchamiam mikrofon…"
        case .connecting: return "Łączę…"
        case .connected: return "Połączona"
        case .reconnecting: return "Odtwarzam połączenie…"
        case .failed: return "Połączenie nie powiodło się"
        case .ended: return "Zakończona"
        }
    }
}

/// Tura jest osobnym wymiarem stanu niż połączenie.
public enum TurnState: String, Codable, Sendable {
    case waiting
    case listening
    case thinking
    case speaking
    case interrupted

    public var displayName: String {
        switch self {
        case .waiting: return "Czekam na Ciebie"
        case .listening: return "Słucham…"
        case .thinking: return "Przygotowuję odpowiedź…"
        case .speaking: return "Emma mówi…"
        case .interrupted: return "Przerwane"
        }
    }
}

/// Wyciszony mikrofon **nie** oznacza rozłączenia (§5.5).
public enum MicrophoneState: String, Codable, Sendable {
    case unavailable
    case muted
    case capturing

    public var displayName: String {
        switch self {
        case .unavailable: return "Mikrofon niedostępny"
        case .muted: return "Mikrofon wyciszony"
        case .capturing: return "Mikrofon aktywny"
        }
    }
}

public enum AudioRoute: Hashable, Codable, Sendable {
    case unknown
    case builtInReceiver
    case builtInSpeaker
    case headphones
    case bluetooth
    case carAudio
    case airPlay

    public var displayName: String {
        switch self {
        case .unknown: return "Nieznana trasa audio"
        case .builtInReceiver: return "Słuchawka"
        case .builtInSpeaker: return "Głośnik"
        case .headphones: return "Słuchawki"
        case .bluetooth: return "Bluetooth"
        case .carAudio: return "Zestaw samochodowy"
        case .airPlay: return "AirPlay"
        }
    }

    /// Po odłączeniu słuchawek poufny odsłuch wstrzymujemy, a nie przenosimy
    /// automatycznie na głośnik (§5.7).
    public var isPrivate: Bool {
        switch self {
        case .headphones, .bluetooth, .carAudio: return true
        default: return false
        }
    }
}

public enum PlaybackStopReason: String, Codable, Sendable {
    case completed
    case interrupted
    case failed
    case routeChanged
    case sessionEnded
}

public enum InterruptionReason: String, Codable, Sendable {
    case userBargeIn
    case userRequested
    case agentTurnCancelled
    case systemAudioInterruption
    case routeChange
    case sessionEnded
    case unknown

    public var displayName: String {
        switch self {
        case .userBargeIn: return "Użytkownik zabrał głos"
        case .userRequested: return "Przerwano na polecenie"
        case .agentTurnCancelled: return "Tura Emmy anulowana"
        case .systemAudioInterruption: return "Przerwanie systemowe"
        case .routeChange: return "Zmiana trasy audio"
        case .sessionEnded: return "Sesja zakończona"
        case .unknown: return "Przerwanie"
        }
    }
}

public struct ToolProgress: Hashable, Codable, Sendable {
    /// Krótki opis bez surowych argumentów (§5.4).
    public var label: String
    public var toolName: String
    public var isFinished: Bool

    public init(label: String, toolName: String, isFinished: Bool = false) {
        self.label = label
        self.toolName = toolName
        self.isFinished = isFinished
    }
}

public struct ProposalSnapshot: Hashable, Codable, Sendable {
    public var proposal: ActionProposal

    public init(proposal: ActionProposal) { self.proposal = proposal }
}

public struct ExecutionSnapshot: Hashable, Codable, Sendable {
    public var execution: ActionExecution

    public init(execution: ActionExecution) { self.execution = execution }
}

public enum RecoverableErrorKind: String, Codable, Sendable {
    case networkLost
    case tokenExpiring
    case audioRouteLost
    case microphoneBusy
    case providerThrottled
    case echoCancellationUnavailable
    case unknown

    public var safeMessage: String {
        switch self {
        case .networkLost: return "Utracono sieć. Szkic zostaje, wznowienie wymaga połączenia."
        case .tokenExpiring: return "Poświadczenie sesji wkrótce wygaśnie."
        case .audioRouteLost: return "Zmieniła się trasa audio."
        case .microphoneBusy: return "Mikrofon jest używany przez inną aplikację."
        case .providerThrottled: return "Dostawca ogranicza tempo. Spróbuj ponownie za chwilę."
        case .echoCancellationUnavailable: return "Brak kasowania echa w tej konfiguracji audio — załóż słuchawki, żeby Emma nie słyszała siebie."
        case .unknown: return "Wystąpił problem techniczny."
        }
    }
}

public enum FatalErrorKind: String, Codable, Sendable {
    case microphonePermissionDenied
    /// Zgoda jest, ale tor mikrofonu nie powstał (np. mikrofon zajęty przez inną
    /// aplikację albo sesja audio nie oddała wejścia). Osobny przypadek, bo
    /// komunikat o uprawnieniach byłby wtedy mylący.
    case microphoneUnavailable
    case speechRecognitionPermissionDenied
    case authenticationFailed
    case sessionRevoked
    case providerUnavailable
    case unsupportedLanguage
    case audioSessionFailed
    case unknown

    public var safeMessage: String {
        switch self {
        case .microphonePermissionDenied:
            return "Brak dostępu do mikrofonu. Możesz pisać tekstem albo zmienić uprawnienia w Ustawieniach."
        case .microphoneUnavailable:
            return "Mikrofon nie przekazuje dźwięku. Sprawdź, czy nie używa go inna aplikacja, albo pisz tekstem."
        case .speechRecognitionPermissionDenied:
            return "Brak dostępu do rozpoznawania mowy. Możesz pisać tekstem."
        case .authenticationFailed:
            return "Sesja wygasła. Zaloguj się ponownie."
        case .sessionRevoked:
            return "Sesję przejęło inne urządzenie albo wylogowano konto."
        case .providerUnavailable:
            return "Rozmowa głosowa jest niedostępna. Możesz kontynuować tekstem."
        case .unsupportedLanguage:
            return "Wybrany język nie jest obsługiwany na tym urządzeniu."
        case .audioSessionFailed:
            return "Nie udało się uruchomić dźwięku. Możesz kontynuować tekstem."
        case .unknown:
            return "Rozmowa głosowa została zatrzymana. Możesz kontynuować tekstem."
        }
    }
}

// MARK: - Tryb aktywny
//
// Rozmowa, dyktowanie i odsłuch dzielą jeden zasób audio, ale są różnymi czynnościami (§5.1).

public enum VoiceMode: String, Codable, Sendable {
    case idle
    case conversation
    case dictation
    case playback

    public var displayName: String {
        switch self {
        case .idle: return "Bez aktywnego trybu"
        case .conversation: return "Rozmowa z Emmą"
        case .dictation: return "Dyktowanie do pola"
        case .playback: return "Odsłuch"
        }
    }

    /// Czy tryb używa mikrofonu. Odsłuch **nie** otwiera mikrofonu (§5.1).
    public var usesMicrophone: Bool {
        self == .conversation || self == .dictation
    }
}

// MARK: - Powód zakończenia

public enum VoiceEndReason: String, Codable, Sendable {
    case userRequested
    case sessionExpired
    case idleTimeout
    case applicationBackgrounded
    case userLoggedOut
    case accountSwitched
    case takenOverByAnotherDevice
    case providerError
    case transportFailure

    public var displayName: String {
        switch self {
        case .userRequested: return "Zakończono na polecenie użytkownika"
        case .sessionExpired: return "Sesja wygasła"
        case .idleTimeout: return "Brak aktywności"
        case .applicationBackgrounded: return "Aplikacja przeszła w tło"
        case .userLoggedOut: return "Wylogowano konto"
        case .accountSwitched: return "Zmieniono konto"
        case .takenOverByAnotherDevice: return "Sesję przejęło inne urządzenie"
        case .providerError: return "Błąd dostawcy"
        case .transportFailure: return "Utrata połączenia"
        }
    }
}

// MARK: - Żądania przerwania

public struct InterruptionRequest: Hashable, Codable, Sendable {
    public var reason: InterruptionReason
    public var turnID: String?
    /// Czy dodatkowo rozbroić prezentowaną propozycję.
    public var disarmPendingProposal: Bool

    public init(reason: InterruptionReason, turnID: String? = nil, disarmPendingProposal: Bool = true) {
        self.reason = reason
        self.turnID = turnID
        self.disarmPendingProposal = disarmPendingProposal
    }
}

// MARK: - Dyktowanie i odsłuch

public struct DictationRequest: Hashable, Codable, Sendable {
    /// Zamrożony cel tekstu. Zmiana wątku podczas STT **nie** przenosi wyniku (§12.2).
    public var target: DictationTarget
    /// Język dyktowania wybrany jawnie (§5.1).
    public var language: LanguageCode
    public var maxDuration: TimeInterval

    public init(target: DictationTarget, language: LanguageCode, maxDuration: TimeInterval = 45) {
        self.target = target
        self.language = language
        self.maxDuration = maxDuration
    }
}

/// Cel dyktowania. Identyfikator jest nieprzejrzysty i zamrożony na czas nagrania.
public enum DictationTarget: Hashable, Codable, Sendable {
    case threadDraft(threadID: ThreadID, draftVersion: Version)
    case caseNote(clientID: ClientID, caseID: CaseID?)
    case taskDescription(clientID: ClientID?)
    case assistantCommand

    public var displayName: String {
        switch self {
        case .threadDraft: return "wiadomości"
        case .caseNote: return "notatki"
        case .taskDescription: return "zadania"
        case .assistantCommand: return "polecenia dla Emmy"
        }
    }

    /// Dyktowanie do pola zapisuje tekst. **Nigdy** nie uruchamia toola (§5.1).
    public var executesCommands: Bool { false }

    public var threadID: ThreadID? {
        if case .threadDraft(let threadID, _) = self { return threadID }
        return nil
    }
}

public enum DictationEvent: Hashable, Sendable {
    case started(DictationTarget)
    case partialText(String)
    case finalText(String)
    case failed(DictationFailure)
    case cancelled

    public var target: DictationTarget? {
        if case .started(let target) = self { return target }
        return nil
    }
}

public enum DictationFailure: String, Codable, Sendable {
    case permissionDenied
    case noSpeechDetected
    case unsupportedLanguage
    case recognizerUnavailable
    case timedOut
    case unknown

    public var safeMessage: String {
        switch self {
        case .permissionDenied: return "Brak dostępu do mikrofonu. Wpisz tekst ręcznie."
        case .noSpeechDetected: return "Nie usłyszałam wypowiedzi. Spróbuj ponownie."
        case .unsupportedLanguage: return "Ten język nie jest obsługiwany w trybie lokalnym."
        case .recognizerUnavailable: return "Rozpoznawanie mowy jest niedostępne. Wpisz tekst."
        case .timedOut: return "Dyktowanie trwało zbyt długo i zostało zatrzymane."
        case .unknown: return "Nie udało się rozpoznać mowy. Wpisz tekst."
        }
    }
}

public struct SpeechPlaybackRequest: Hashable, Codable, Sendable {
    public var text: String
    public var language: LanguageCode
    /// Czy tekst jest streszczeniem. Odsłuch musi to nazwać (§5.2).
    public var isSummary: Bool
    /// Identyfikator odczytywanego zasobu, do korelacji ze stanem.
    public var sourceID: String

    public init(text: String, language: LanguageCode, isSummary: Bool = false, sourceID: String) {
        self.text = text
        self.language = language
        self.isSummary = isSummary
        self.sourceID = sourceID
    }
}

public enum PlaybackEvent: Hashable, Sendable {
    case started(sourceID: String, approximate: Bool)
    case progress(sourceID: String)
    case finished(sourceID: String, reason: PlaybackStopReason)
    case failed(sourceID: String, reason: PlaybackStopReason)
}
