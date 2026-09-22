import Foundation

/// Timing model for half-duplex playback. The echo tail belongs to the end of
/// the queue, not to every network packet. `now` must use a monotonic clock.
public struct PlaybackSuppression: Sendable {
    public static let echoTail: TimeInterval = 0.25
    private var audioEndsAt: TimeInterval?

    public init() {}

    public mutating func schedule(seconds: TimeInterval, now: TimeInterval) {
        guard seconds.isFinite, seconds > 0 else { return }
        audioEndsAt = max(audioEndsAt ?? now, now) + seconds
    }

    public func isSuppressed(at now: TimeInterval) -> Bool {
        guard let audioEndsAt else { return false }
        return now < audioEndsAt + Self.echoTail
    }

    public mutating func release() { audioEndsAt = nil }
}
