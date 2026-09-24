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
    /// Czy na wejściu silnika wisi nasz tap. `removeTap(onBus:)` zawołane drugi
    /// raz (albo bez wcześniejszego `installTap`) kończy się wyjątkiem ObjC i
    /// zamknięciem procesu, więc stan tapu musimy znać, a nie zakładać.
    private var tapInstalled = false
    /// Ostatni tekst częściowy. Gdy rozpoznawanie nie odda wyniku końcowego
    /// (np. „brak mowy” po zakończeniu nagrania), to on trafia do pola —
    /// użytkownik widział go już na ekranie, więc nie może przepaść.
    private var lastPartial = ""

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
        if audioSession.providerOwnsAudioSession {
            // Trwa rozmowa: sesję audio trzyma WebRTC dostawcy (playAndRecord).
            // Świadomie nie przełączamy jej na `.measurement`, bo zmiana kategorii
            // w trakcie rozmowy odbiera dźwięk i mikrofon Emmie.
        } else {
            guard audioSession.activate(.dictation) else {
                throw DictationStartError.audioSessionFailed
            }
        }

        self.recognizer = recognizer
        lastPartial = ""
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        // Na urządzeniu wynik zostaje na urządzeniu, jeśli system to obsługuje.
        recognitionRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = recognitionRequest

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Format wejścia bywa niepoprawny (0 Hz albo 0 kanałów), dopóki sesja
        // audio nie jest w pełni aktywna. Instalowanie tapu na takim formacie
        // kończy się wyjątkiem i zamknięciem aplikacji — dlatego sprawdzamy go
        // jawnie, zamiast zakładać, że sesja zdążyła się uruchomić.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            await stopResources()
            throw DictationStartError.audioSessionFailed
        }
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        // Tap wykonuje się na wątku czasu rzeczywistego audio, a nie na głównym
        // aktorze. Bez jawnego `@Sendable` domknięcie dziedziczy izolację
        // `@MainActor` z otaczającej metody i Swift 6 zatrzymuje proces na
        // sprawdzeniu wykonawcy (EXC_BREAKPOINT/SIGTRAP) już przy pierwszym
        // buforze. To była faktyczna przyczyna zamknięcia aplikacji przy
        // „dyktuj tekst" (raporty Emma-2026-09-14-234523…234843, 09-15-*).
        nonisolated(unsafe) let tapRequest = recognitionRequest
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            tapRequest.append(buffer)
        }
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            await stopResources()
            throw DictationStartError.audioSessionFailed
        }

        continuation?.yield(.started(request.target))

        task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                // Po zwolnieniu zasobów spóźnione wywołania nie mają dokąd trafić.
                guard self.continuation != nil else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        // Wynik końcowy jest jedynym zdarzeniem, które przekazuje tekst
                        // do celu. Nic nie jest zapisywane ani wysyłane samo.
                        self.continuation?.yield(.finalText(text))
                        await self.stopResources()
                        return
                    } else {
                        self.lastPartial = text
                        self.continuation?.yield(.partialText(text))
                    }
                }
                if error != nil {
                    // Rozpoznawanie potrafi zakończyć się błędem już po tym, jak
                    // pokazało tekst (np. po zakończeniu nagrania). Wtedy oddajemy
                    // to, co było widać, zamiast komunikatu „nie usłyszałam”.
                    if self.lastPartial.isEmpty {
                        self.continuation?.yield(.failed(.noSpeechDetected))
                    } else {
                        self.continuation?.yield(.finalText(self.lastPartial))
                    }
                    await self.stopResources()
                }
            }
        }

        // Twardy limit czasu: dyktowanie nie może trzymać mikrofonu bez końca.
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(request.maxDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // Limit czasu kończy nagranie jak „Zakończ” — z tekstem, który już
            // był widoczny, a nie z samym komunikatem o przekroczeniu czasu.
            await self?.finish()
        }
    }

    public func events() -> AsyncStream<DictationEvent> {
        let stream = AsyncStream<DictationEvent>.makeStream()
        continuation = stream.continuation
        return stream.stream
    }

    /// Zakończenie nagrania **z wynikiem**.
    ///
    /// Review 24.09.2026: po „Zakończ dyktowanie” tekst nie trafiał do pola.
    /// Zasoby (razem ze strumieniem zdarzeń) były zwalniane zaraz po `endAudio()`,
    /// zanim rozpoznawanie zdążyło oddać wynik końcowy — więc wynik nie miał już
    /// dokąd trafić. Teraz zatrzymujemy mikrofon, a na wynik czekamy do 2 s;
    /// gdy nie przyjdzie, do pola trafia ostatni tekst częściowy.
    public func finish() async {
        stopCapture()
        request?.endAudio()
        let deadline = Date().addingTimeInterval(2)
        while continuation != nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard continuation != nil else { return }
        if !lastPartial.isEmpty {
            continuation?.yield(.finalText(lastPartial))
        } else {
            continuation?.yield(.failed(.noSpeechDetected))
        }
        task?.cancel()
        await stopResources()
    }

    /// Zatrzymanie mikrofonu bez zamykania rozpoznawania.
    private func stopCapture() {
        if engine.isRunning {
            engine.stop()
        }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    public func cancel() async {
        task?.cancel()
        // Zdarzenie musi wyjść **przed** zwolnieniem zasobów: `stopResources()`
        // kończy strumień i zeruje `continuation`, więc `.cancelled` wysłane po
        // nim nigdy nie docierało do koordynatora.
        continuation?.yield(.cancelled)
        await stopResources()
        // Anulowanie nie przekazuje tekstu: użytkownik przerwał, więc nic nie trafia
        // do pola formularza.
    }

    // MARK: Zasoby

    private func stopResources() async {
        timeoutTask?.cancel()
        timeoutTask = nil
        // Zdejmujemy tap tylko wtedy, gdy naprawdę wisi. Drugie `removeTap`
        // (np. po już zakończonym rozpoznaniu) to wyjątek ObjC, nie no-op.
        stopCapture()
        request = nil
        task = nil
        currentRequest = nil
        continuation?.finish()
        continuation = nil
        // Oddanie zasobu audio należy do właściciela sesji, nie do rozpoznawania
        // mowy. W trakcie rozmowy sesji **nie** dezaktywujemy: należy do WebRTC
        // dostawcy i wyłączenie jej ubiłoby dźwięk oraz mikrofon rozmowy.
        if !audioSession.providerOwnsAudioSession {
            audioSession.deactivate()
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                // TCC woła to domknięcie z własnej kolejki, nie z głównego aktora.
                // Bez `@Sendable` domknięcie dziedziczy izolację `@MainActor`
                // i Swift 6 zatrzymuje proces na sprawdzeniu wykonawcy zaraz po
                // decyzji użytkownika (raport Emma-2026-09-14-233721).
                SFSpeechRecognizer.requestAuthorization { @Sendable status in
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

extension DictationStartError: DictationStartFailureMapping {
    /// Rodzaj błędu pokazywany użytkownikowi. `audioSessionFailed` nie ma
    /// własnego przypadku w `DictationFailure`, więc mówimy `.unknown` (ogólny
    /// komunikat dyktowania), a nie udajemy problem z rozpoznawaniem mowy.
    public var dictationFailure: DictationFailure {
        switch self {
        case .permissionDenied: return .permissionDenied
        case .recognizerUnavailable: return .recognizerUnavailable
        case .audioSessionFailed: return .unknown
        }
    }
}
#endif
