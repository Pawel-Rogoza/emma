import XCTest
@testable import Emma

final class PlaybackSuppressionTests: XCTestCase {
    func testEchoTailIsAddedOnceRegardlessOfPacketCount() {
        var one = PlaybackSuppression()
        var many = PlaybackSuppression()
        one.schedule(seconds: 2, now: 10)
        for _ in 0..<20 { many.schedule(seconds: 0.1, now: 10) }
        XCTAssertTrue(many.isSuppressed(at: 12.2))
        XCTAssertFalse(many.isSuppressed(at: 12.3))
        XCTAssertEqual(one.isSuppressed(at: 12.3), many.isSuppressed(at: 12.3))
    }

    func testNewAudioDuringEchoTailDoesNotQueueBehindTheTail() {
        var timing = PlaybackSuppression()
        timing.schedule(seconds: 1, now: 10)
        timing.schedule(seconds: 1, now: 11.1)
        XCTAssertTrue(timing.isSuppressed(at: 12.3))
        XCTAssertFalse(timing.isSuppressed(at: 12.4))
        timing.release()
        XCTAssertFalse(timing.isSuppressed(at: 11.2))
    }

    func testInvalidAudioDurationCannotPermanentlyMuteMicrophone() {
        var timing = PlaybackSuppression()
        for seconds in [Double.nan, .infinity, -1, 0] {
            timing.schedule(seconds: seconds, now: 10)
        }
        XCTAssertFalse(timing.isSuppressed(at: 10))
    }
}
