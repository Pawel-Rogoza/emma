#if canImport(UIKit)
import AVFoundation
import Foundation

// MARK: - Odsłuch przez syntezator mowy systemu
//
// „Odsłuchaj” ma realnie zabrzmieć, a nie tylko zmienić stan w interfejsie.
// Jedyną implementacją odsłuchu był wcześniej `MockSpeechPlaybackService`, który
// natychmiast raportował `started → progress → finished` i **nie wydawał dźwięku**
// (F05, etap 6). Ten adapter używa systemowego `AVSpeechSynthesizer`, więc odsłuch
// jest prawdziwym odtwarzaniem mowy: żadnych kont dostawców ani sieci nie potrzeba.
//
// Granice odpowiedzialności:
//   • To jest głos **systemowy**, nie głos Emmy od dostawcy. Interfejs mówi to
//     wprost i nie udaje speech-to-speech.
//   • Mikrofon jest wyłączony: tryb `.playback` w `AudioSessionController` nie
//     otwiera wejścia (§5.1).
//   • Zdarzenia odtwarzania pochodzą z delegata syntezatora, więc raportowane
//     rozpoczęcie i koniec są prawdziwe (`approximate: false`), a nie założone.
//
// Status środowiska: kod działa na symulatorze i urządzeniu (syntezator systemowy).
// Słyszalność na prawdziwym iPhone'ie wymaga człowieka przy urządzeniu — tego
// nie da się sprawdzić testem automatycznym i jest to zapisane jako ograniczenie.

@MainActor
public final class SystemSpeechPlaybackService: NSObject, SpeechPlaybackService {

    private let audioSession: AudioSessionController
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: AsyncStream<PlaybackEvent>.Continuation?
    private var current: SpeechPlaybackRequest?
    /// Czy to my włączyliśmy sesję audio. W trakcie rozmowy z dostawcą sesję
    /// trzyma WebRTC, więc nie przełączamy jej i nie dezaktywujemy.
    private var ownsAudioSession = false
    public init(audioSession: AudioSessionController) {
        self.audioSession = audioSession
        super.init()
        synthesizer.delegate = self
    }

    /// Czy syntezator mówi teraz. Czytane przez testy i przez stan odsłuchu —
    /// to fakt z syntezatora, nie nasza flaga.
    public var isSpeaking: Bool { synthesizer.isSpeaking }

    public func play(_ request: SpeechPlaybackRequest) async throws {
        // Nowe żądanie unieważnia poprzednie: mówienie dwóch tekstów naraz byłoby
        // jednoczesnym odsłuchen dwóch rzeczy.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        // W trakcie rozmowy z dostawcą sesję audio trzyma WebRTC. Przełączenie jej
        // na `.playback` i późniejsza dezaktywacja odebrałyby dźwięk oraz mikrofon
        // trwającej rozmowie, więc mówimy przez sesję dostawcy i nic nie zmieniamy.
        if audioSession.providerOwnsAudioSession {
            ownsAudioSession = false
        } else {
            _ = audioSession.activate(.playback)
            ownsAudioSession = true
        }
        current = request
        continuation?.yield(.started(sourceID: request.sourceID, approximate: false))

        let utterance = AVSpeechUtterance(string: request.text)
        utterance.voice = AVSpeechSynthesisVoice(language: request.language.speechLocaleIdentifier)
        // Tempo bliższe mowie niż domyślnemu czytaniu syntezatora.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        synthesizer.speak(utterance)
    }

    public func events() -> AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    public func stop() async {
        guard let current else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        continuation?.yield(.finished(sourceID: current.sourceID, reason: .interrupted))
        self.current = nil
        releaseAudioSessionIfOwned()
    }

    /// Zdarzenie dla odczytu, którego dotyczy — tylko dla bieżącego żądania.
    fileprivate func finish(_ reason: PlaybackStopReason) {
        guard let current else { return }
        continuation?.yield(.finished(sourceID: current.sourceID, reason: reason))
        self.current = nil
        releaseAudioSessionIfOwned()
    }

    /// Oddajemy sesję audio tylko wtedy, gdy sami ją włączyliśmy.
    ///
    /// Druga bariera: odsłuch mógł zacząć się **przed** rozmową, a skończyć już
    /// w jej trakcie. Wtedy sesję trzyma WebRTC dostawcy — dezaktywacja odebrałaby
    /// rozmowie mikrofon i dźwięk, mimo że to my włączyliśmy sesję dla odsłuchu.
    private func releaseAudioSessionIfOwned() {
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        guard !audioSession.providerOwnsAudioSession else { return }
        audioSession.deactivate()
    }

    fileprivate func reportProgress() {
        guard let current else { return }
        continuation?.yield(.progress(sourceID: current.sourceID))
    }
}

extension SystemSpeechPlaybackService: AVSpeechSynthesizerDelegate {

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        // Delegat syntezatora nie jest izolowany do aktora głównego, więc wracamy
        // na niego zadaniem zamiast zakładać wątek.
        Task { @MainActor [weak self] in self?.reportProgress() }
    }

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in self?.finish(.completed) }
    }

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in self?.finish(.interrupted) }
    }
}
#endif
