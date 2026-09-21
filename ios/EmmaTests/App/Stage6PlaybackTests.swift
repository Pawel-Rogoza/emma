import AVFoundation
import XCTest
@testable import Emma

// MARK: - Etap 6: realny odsłuch zamiast samego stanu (F05)
//
// Do etapu 5 jedynym odsłuchom był `MockSpeechPlaybackService`, który natychmiast
// raportował `started → progress → finished` i **nie wydawał dźwięku**. Ten plik
// sprawdza, że `SystemSpeechPlaybackService` naprawdę uruchamia syntezator mowy
// i raportuje koniec z delegata, a nie z założenia.
//
// Czego ten test **nie** dowodzi: że dźwięk jest słyszalny i zrozumiały na
// urządzeniu. To wymaga człowieka przy iPhonie i jest zapisane jako ograniczenie.

@MainActor
final class Stage6PlaybackTests: XCTestCase {

    private var service: SystemSpeechPlaybackService!

    override func setUp() {
        super.setUp()
        service = SystemSpeechPlaybackService(audioSession: AudioSessionController())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    /// Zbiera zdarzenia aż do końca odsłuchu **albo** do upływu czasu. Bez tego
    /// brak zdarzenia zawiesiłby test zamiast go oblać.
    private func firstEvents(_ stream: AsyncStream<PlaybackEvent>, timeout: TimeInterval) async -> [PlaybackEvent] {
        await withTaskGroup(of: [PlaybackEvent].self) { group in
            group.addTask {
                var collected: [PlaybackEvent] = []
                for await event in stream {
                    collected.append(event)
                    if case .finished = event { break }
                    if case .failed = event { break }
                }
                return collected
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return []
            }
            let first = await group.next() ?? []
            group.cancelAll()
            return first
        }
    }

    /// Prawdziwy odsłuch: syntezator startuje i kończy, a koniec pochodzi z delegata.
    func testRealPlaybackStartsAndFinishes() async throws {
        let stream = service.events()
        try await service.play(
            SpeechPlaybackRequest(text: "Dzień dobry.", language: .pl, isSummary: false, sourceID: "playback-1")
        )

        let events = await firstEvents(stream, timeout: 15)
        guard case .started(let sourceID, let approximate)? = events.first else {
            return XCTFail("Brak zdarzenia rozpoczęcia odsłuchu: \(events)")
        }
        XCTAssertEqual(sourceID, "playback-1")
        XCTAssertFalse(approximate, "Syntezator raportuje prawdziwe zdarzenia, nie przybliżone")

        guard case .finished(let finishedID, let reason)? = events.last else {
            return XCTFail("Syntezator nie zgłosił końca odsłuchu: \(events)")
        }
        XCTAssertEqual(finishedID, "playback-1")
        XCTAssertEqual(reason, .completed)
        XCTAssertTrue(events.contains { if case .progress = $0 { return true } else { return false } })
    }

    /// Przerwanie zatrzymuje syntezator i kończy odsłuch powodem „interrupted”.
    func testStopInterruptsPlayback() async throws {
        let long = String(repeating: "Sprawa Oleny Kowalenko. ", count: 30)
        let stream = service.events()
        try await service.play(
            SpeechPlaybackRequest(text: long, language: .pl, isSummary: false, sourceID: "playback-2")
        )
        // Krótka chwila, żeby syntezator zdążył zacząć, i przerwanie.
        try await Task.sleep(nanoseconds: 300_000_000)
        await service.stop()

        let events = await firstEvents(stream, timeout: 10)
        guard case .finished(let sourceID, let reason)? = events.last else {
            return XCTFail("Brak zdarzenia końca po przerwaniu: \(events)")
        }
        XCTAssertEqual(sourceID, "playback-2")
        XCTAssertEqual(reason, .interrupted)
        XCTAssertFalse(service.isSpeaking)
    }

    /// Mock zostaje w Demo: testy i zrzuty nie mogą zależeć od tempa mowy.
    func testDemoKeepsDeterministicMock() {
        let demo = AppConfiguration(environment: .demo, apiBaseURL: nil, defaultLocale: "pl-PL")
        let service = VoiceServicesFactory.makePlaybackService(
            configuration: demo,
            audioSession: AudioSessionController()
        )
        XCTAssertTrue(service is MockSpeechPlaybackService)
    }
}
