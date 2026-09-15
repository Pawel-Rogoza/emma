import Foundation

// MARK: - Zamiana zdarzeń Live API na zdarzenia naszego modelu
//
// Czysta logika bez sieci i audio: dzięki temu reguły tury (kiedy kończy się
// odtwarzanie, kiedy transkrypcja jest finalna, co robimy z przerwaniem) są
// testowalne bez telefonu. Transport dostarcza zdarzenia i odtwarza audio.

public struct GeminiLiveTurnOutcome: Sendable {
    /// Zdarzenia do wypchnięcia do koordynatora, w kolejności znaczenia.
    public var payloads: [VoiceEventPayload] = []
    /// Fragment audio do odtworzenia (PCM 16-bit mono 24 kHz).
    public var audio: Data?
    /// Wywołanie narzędzia do wykonania po stronie backendu.
    public var toolCall: GeminiLiveToolCall?
    /// Uchwyt wznowienia — zapisujemy go, żeby po `goAway` wrócić do tej samej sesji.
    public var resumptionHandle: String?
    /// Serwer zapowiedział zamknięcie połączenia; transport ma się przygotować.
    public var goAwayIn: TimeInterval?
    /// Połączenie padło bez `goAway` — trzeba wznowić sesję z uchwytem.
    public var shouldReconnect = false
}

/// Stan tury Emmy. Jedna instancja na połączenie — nie na sesję, bo po wznowieniu
/// liczy się to, co przyszło po ostatnim zdarzeniu, a nie historia procesu.
public struct GeminiLiveTurnTracker: Sendable {

    public private(set) var resumptionHandle: String?

    private var isSpeaking = false
    private var outputText = ""
    private var lastInputText: String?

    public init() {}

    public mutating func consume(_ event: GeminiLiveServerEvent) -> GeminiLiveTurnOutcome {
        var outcome = GeminiLiveTurnOutcome()

        switch event {
        case .setupComplete:
            outcome.payloads.append(.connectionChanged(.connected))
            outcome.payloads.append(.microphoneChanged(.capturing))

        case .audio(let data):
            outcome.audio = data
            if !isSpeaking {
                isSpeaking = true
                // Live API nie raportuje dokładnego końca odtwarzania; czas
                // odtworzenia znamy tylko z bufora, więc oznaczamy przybliżenie.
                outcome.payloads.append(.playbackStarted(approximate: true))
            }

        case .outputTranscription(let text):
            outputText += text
            outcome.payloads.append(.agentTextDelta(text))

        case .inputTranscription(let text):
            lastInputText = text
            outcome.payloads.append(.userTranscriptPartial(text))

        case .toolCall(let call):
            outcome.toolCall = call
            outcome.payloads.append(
                .toolProgress(ToolProgress(label: "Sprawdzam dane w kancelarii", toolName: call.name))
            )

        case .interrupted:
            // Przerwanie tury. Zgłaszamy je jako fakt tylko wtedy, gdy naprawdę
            // było co przerywać: `interrupted` bez trwającego odtwarzania nie
            // mówi użytkownikowi nic nowego, a udawanie zdarzenia zaciemnia stan.
            if isSpeaking {
                isSpeaking = false
                outcome.payloads.append(.interruption(.userBargeIn))
                outcome.payloads.append(.playbackStopped(reason: .interrupted))
            }
            // Transkrypcja użytkownika domyka się od razu: przerwanie oznacza, że
            // wypowiedź użytkownika już się skończyła, a tura Emmy została ucięta.
            if let input = lastInputText, !input.isEmpty {
                outcome.payloads.append(.userTranscriptFinal(input))
                lastInputText = nil
            }
            outputText = ""

        case .turnComplete:
            if isSpeaking {
                isSpeaking = false
                outcome.payloads.append(.playbackStopped(reason: .completed))
            }
            if !outputText.isEmpty {
                outcome.payloads.append(.agentTextFinal(outputText))
                outputText = ""
            }
            if let input = lastInputText, !input.isEmpty {
                outcome.payloads.append(.userTranscriptFinal(input))
                lastInputText = nil
            }

        case .resumptionHandle(let handle):
            resumptionHandle = handle
            outcome.resumptionHandle = handle

        case .goAway(let seconds):
            outcome.goAwayIn = seconds
            outcome.payloads.append(.connectionChanged(.reconnecting))
            outcome.payloads.append(.recoverableError(.tokenExpiring))

        case .unknown:
            // Nieznanego komunikatu sterującego nie interpretujemy. Milczenie jest
            // bezpieczniejsze niż zgadywanie, że „to na pewno nic ważnego”.
            break
        }

        return outcome
    }

    /// Utrata połączenia: domykamy to, co otwarte, i zgłaszamy potrzebę wznowienia.
    public mutating func connectionLost() -> GeminiLiveTurnOutcome {
        var outcome = GeminiLiveTurnOutcome()
        outcome.shouldReconnect = true
        if isSpeaking {
            isSpeaking = false
            outcome.payloads.append(.playbackStopped(reason: .failed))
        }
        if !outputText.isEmpty {
            outcome.payloads.append(.agentTextFinal(outputText))
            outputText = ""
        }
        lastInputText = nil
        outcome.payloads.append(.connectionChanged(.reconnecting))
        outcome.payloads.append(.recoverableError(.networkLost))
        return outcome
    }
}
