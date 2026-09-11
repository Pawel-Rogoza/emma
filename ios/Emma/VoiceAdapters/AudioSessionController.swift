#if canImport(UIKit)
import AVFoundation

// MARK: - Właściciel sesji audio
//
// Jeden właściciel zasobu audio dla rozmowy, dyktowania i odsłuchu (§5.3).
// Trzy tryby nie mogą jednocześnie walczyć o mikrofon ani o głośnik, dlatego
// każda zmiana trybu przechodzi przez ten obiekt.

@MainActor
public final class AudioSessionController {

    public enum Mode: String, Sendable {
        /// Rozmowa z Emmą: mikrofon i głośnik, możliwość przerwania.
        case conversation
        /// Dyktowanie: mikrofon włączony, odtwarzanie wyłączone.
        case dictation
        /// Odsłuch: tylko głośnik, mikrofon świadomie wyłączony.
        case playback
        case idle
    }

    public private(set) var mode: Mode = .idle
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    /// Zgłoszenie przerwania systemowego lub zmiany trasy — koordynator decyduje,
    /// co z tym zrobić, a nie warstwa audio.
    public var onInterruption: ((InterruptionReason) -> Void)?
    public var onRouteChange: ((AudioRoute) -> Void)?

    public init() {}

    public var isConfigured: Bool { mode != .idle }

    /// Ustawienie trybu pracy. Zwraca informację, czy sesja audio jest gotowa.
    @discardableResult
    public func activate(_ mode: Mode, speakerPreferred: Bool = true) -> Bool {
        guard mode != .idle else {
            deactivate()
            return true
        }
        do {
            let session = AVAudioSession.sharedInstance()
            switch mode {
            case .conversation, .dictation:
                try session.setCategory(
                    .playAndRecord,
                    mode: mode == .conversation ? .voiceChat : .measurement,
                    options: [.allowBluetooth, .defaultToSpeaker]
                )
            case .playback:
                // Odsłuch nie potrzebuje mikrofonu i nie może go otwierać.
                try session.setCategory(.playback, mode: .spokenAudio, options: [])
            case .idle:
                break
            }
            try session.setActive(true, options: [])
            self.mode = mode
            registerObserversIfNeeded()
            return true
        } catch {
            self.mode = .idle
            return false
        }
    }

    public func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        mode = .idle
    }

    /// Aktualna trasa audio w postaci zrozumiałej dla modelu stanu.
    public func currentRoute() -> AudioRoute {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let first = outputs.first else { return .unknown }
        switch first.portType {
        case .builtInReceiver: return .builtInReceiver
        case .builtInSpeaker: return .builtInSpeaker
        case .headphones, .headsetMic: return .headphones
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: return .bluetooth
        case .carAudio: return .carAudio
        case .airPlay: return .airPlay
        default: return .unknown
        }
    }

    private func registerObserversIfNeeded() {
        guard interruptionObserver == nil else { return }
        let center = NotificationCenter.default

        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                switch type {
                case .began:
                    self?.onInterruption?(.systemAudioInterruption)
                case .ended:
                    // Wznowienie po przerwaniu wymaga świadomej decyzji użytkownika;
                    // samo przerwanie nigdy nie wznawia sesji bez jego działania.
                    self?.onInterruption?(.systemAudioInterruption)
                @unknown default:
                    self?.onInterruption?(.unknown)
                }
            }
        }

        routeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.onRouteChange?(self.currentRoute())
            }
        }
    }

    deinit {
        let center = NotificationCenter.default
        if let interruptionObserver { center.removeObserver(interruptionObserver) }
        if let routeObserver { center.removeObserver(routeObserver) }
    }
}
#endif
