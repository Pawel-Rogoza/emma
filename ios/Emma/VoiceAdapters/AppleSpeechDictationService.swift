#if canImport(UIKit)
import AVFoundation
import Foundation
import Speech

// MARK: - Dyktowanie przez framework mowy systemu
//
// Dyktowanie to osobny tryb od rozmowy z Emmą: mikrofon jest używany krótko,
// wynik trafia wyłącznie do tekstu, a celem jest **zamrożony** `DictationTarget`.
// Ten serwis nigdy nie wykonuje akcji i nie tworzy propozycji (§5.2).
//
// Status: kod przygotowany pod urządzenie. Nie został uruchomiony ani zweryfikowany
// na iPhonie — w tym środowisku nie ma macOS/Xcode (patrz BUILD_AND_DEVICE_STATUS.md).

@MainActor
public final class AppleSpeechDictationService: DictationService {

    private let audioSession: AudioSessionController
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<DictationEvent>.Continuation?
    private var currentRequest: DictationRequest?
    private var timeoutTask: Task<Void, Never>?

    public init(audioSession: AudioSessionController) {
        self.audioSession = audioSession
    }

    // MARK: Cykl życia

    public func start(_ request: DictationRequest) async throws {
        currentRequest = request

        guard await requestSpeechAuthorization() else {
            throw DictationStartError.permissionDenied
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: Self.localeIdentifier(for: request.language))),
              recognizer.isAvailable else {
            throw DictationStartError.recognizerUnavailable
        }
        guard audioSession.activate(.dictation) else {
            throw DictationStartError.audioSessionFailed
        }

        self.recognizer = recognizer
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        // Na urządzeniu wynik zostaje na urządzeniu, jeśli system to obsługuje.
        recognitionRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = recognitionRequest

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        engine.prepare()
        try engine.start()

        continuation?.yield(.started(request.target))

        task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        // Wynik końcowy jest jedynym zdarzeniem, które przekazuje tekst
                        // do celu. Nic nie jest zapisywane ani wysyłane samo.
                        self.continuation?.yield(.finalText(text))
                        await self.stopResources()
                    } else {
                        self.continuation?.yield(.partialText(text))
                    }
                }
                if error != nil {
                    self.continuation?.yield(.failed(.noSpeechDetected))
                    await self.stopResources()
                }
            }
        }

        // Twardy limit czasu: dyktowanie nie może trzymać mikrofonu bez końca.
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(request.maxDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.continuation?.yield(.failed(.timedOut)) }
            await self?.stopResources()
        }
    }

    public func events() -> AsyncStream<DictationEvent> {
        let stream = AsyncStream<DictationEvent>.makeStream()
        continuation = stream.continuation
        return stream.stream
    }

    public func finish() async {
        request?.endAudio()
        task?.finish()
        await stopResources()
    }

    public func cancel() async {
        task?.cancel()
        await stopResources()
        // Anulowanie nie przekazuje tekstu: użytkownik przerwał, więc nic nie trafia
        // do pola formularza.
        continuation?.yield(.cancelled)
    }

    // MARK: Zasoby

    private func stopResources() async {
        timeoutTask?.cancel()
        timeoutTask = nil
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        currentRequest = nil
        continuation?.finish()
        continuation = nil
        // Oddanie zasobu audio należy do właściciela sesji, nie do rozpoznawania mowy.
        audioSession.deactivate()
    }

    private func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }

    private static func localeIdentifier(for language: LanguageCode) -> String {
        switch language {
        case .pl: return "pl-PL"
        case .uk: return "uk-UA"
        case .ru: return "ru-RU"
        }
    }
}

public enum DictationStartError: Error, LocalizedError, Sendable {
    case permissionDenied
    case recognizerUnavailable
    case audioSessionFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Brak zgody na rozpoznawanie mowy. Możesz wpisać tekst ręcznie."
        case .recognizerUnavailable:
            return "Rozpoznawanie mowy jest chwilowo niedostępne dla tego języka."
        case .audioSessionFailed:
            return "Nie udało się uruchomić mikrofonu. Spróbuj ponownie albo wpisz tekst."
        }
    }
}
#endif
