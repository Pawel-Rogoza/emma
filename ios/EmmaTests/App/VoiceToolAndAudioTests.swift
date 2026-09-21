import AVFoundation
import XCTest
@testable import Emma

// MARK: - Ścieżka narzędzi Live API i konwersje audio
//
// Dwa miejsca, w których błąd widać dopiero na urządzeniu i tylko w rozmowie:
//   1. wywołanie narzędzia przez model — czy idzie właściwą trasą, z bearerem
//      użytkownika i czy odmowa backendu nie zamienia się w „sukces”,
//   2. konwersja PCM (16 kHz wejście, 24 kHz wyjście) — czy nie gubi próbek
//      i nie odwraca skali.
// Testy nie wołają sieci ani nie potrzebują mikrofonu.

@MainActor
final class VoiceToolAndAudioTests: XCTestCase {

    private var baseURL: URL { URL(string: "https://advokat-varshava.pl")! }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeExecutor(token: String? = "token-uzytkownika") -> BackendVoiceToolExecutor {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return BackendVoiceToolExecutor(
            baseURL: baseURL,
            accessToken: token,
            session: URLSession(configuration: configuration)
        )
    }

    // MARK: Narzędzia

    func testToolCallGoesToMobileRouteWithUserBearer() async throws {
        StubURLProtocol.respond(json: Data(#"{"tool":"get_today_overview","result":{"tasks":2}}"#.utf8), status: 200)

        let result = try await makeExecutor().execute(
            toolName: "get_today_overview",
            argumentsJSON: #"{"day":"2026-09-15"}"#
        )

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/mobile/v1/voice/tools/get_today_overview")
        XCTAssertEqual(request.httpMethod, "POST")
        // Autoryzacja jest użytkownika, nie usługi: rozmowa należy do zalogowanej osoby.
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-uzytkownika")
        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        XCTAssertEqual(body["day"] as? String, "2026-09-15")
        // Wynik wraca do modelu bez naszej interpretacji.
        XCTAssertTrue(result.contains("\"tasks\":2"))
    }

    func testForbiddenToolBecomesExplicitRefusalNotSuccess() async throws {
        StubURLProtocol.respond(
            json: Data(#"{"code":"forbidden","message":"Narzędzia zapisu są wyłączone."}"#.utf8),
            status: 403
        )

        do {
            _ = try await makeExecutor().execute(toolName: "propose_task", argumentsJSON: "{}")
            XCTFail("Odmowa backendu nie może wyglądać jak poprawny wynik narzędzia.")
        } catch let error as VoiceToolExecutionError {
            XCTAssertEqual(error, .forbidden("Narzędzia zapisu są wyłączone."))
            XCTAssertFalse(error.isRetryable)
        }
    }

    func testUnauthorizedIsNotRetriedBlindly() async throws {
        StubURLProtocol.respond(json: Data(#"{"code":"unauthorized"}"#.utf8), status: 401)
        do {
            _ = try await makeExecutor(token: nil).execute(toolName: "search_clients", argumentsJSON: "{}")
            XCTFail("Brak sesji musi przerwać wywołanie narzędzia.")
        } catch let error as VoiceToolExecutionError {
            XCTAssertEqual(error, .unauthorized)
            XCTAssertFalse(error.isRetryable)
        }
    }

    func testUnknownToolNameIsRejectedBeforeAnyRequest() async throws {
        StubURLProtocol.respond(json: Data("{}".utf8), status: 200)
        do {
            // Nazwa pochodzi od modelu, więc traktujemy ją jak dane niezaufane.
            _ = try await makeExecutor().execute(toolName: "../emma/tools/search_clients", argumentsJSON: "{}")
            XCTFail("Nazwa spoza formatu nie może trafić do adresu.")
        } catch let error as VoiceToolExecutionError {
            XCTAssertEqual(error, .unknownTool("../emma/tools/search_clients"))
            XCTAssertEqual(StubURLProtocol.requestCount, 0)
        }
    }

    func testMissingBackendFailsWithoutPretending() async throws {
        let executor = BackendVoiceToolExecutor(baseURL: nil, accessToken: "token")
        do {
            _ = try await executor.execute(toolName: "search_clients", argumentsJSON: "{}")
            XCTFail("Bez backendu nie ma z czego czytać danych kancelarii.")
        } catch let error as VoiceToolExecutionError {
            XCTAssertEqual(error, .failed(error.safeMessage))
        }
    }

    func testToolErrorPayloadIsValidJSON() {
        let payload = GeminiLiveTransport.errorJSON(#"Nie ma danych dla "Kowalska""#)
        let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        XCTAssertEqual(object?["error"] as? String, #"Nie ma danych dla "Kowalska""#)
    }

    // MARK: Konwersje audio

    func testOutputPCM16BecomesFloatBufferAtFullScale() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: GeminiLiveDefaults.outputSampleRate,
            channels: 1,
            interleaved: false
        ))
        var samples: [Int16] = [0, 32767, -32768, 16384]
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }

        let buffer = try XCTUnwrap(GeminiLiveTransport.floatBuffer(from: data, format: format))
        XCTAssertEqual(buffer.frameLength, 4)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertEqual(channel[0], 0, accuracy: 0.0001)
        XCTAssertEqual(channel[1], 0.99997, accuracy: 0.001)
        XCTAssertEqual(channel[2], -1, accuracy: 0.0001)
        XCTAssertEqual(channel[3], 0.5, accuracy: 0.0001)

        // Nieparzysta liczba bajtów nie może wywrócić konwersji.
        samples = [1, 2, 3]
        let odd = samples.withUnsafeBufferPointer { Data(buffer: $0) } + Data([0x7F])
        XCTAssertEqual(GeminiLiveTransport.floatBuffer(from: odd, format: format)?.frameLength, 3)
    }

    func testInputBufferIsResampledTo16kMonoInt16() throws {
        let inputFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let targetFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: GeminiLiveDefaults.inputSampleRate,
            channels: 1,
            interleaved: true
        ))
        let converter = try XCTUnwrap(AVAudioConverter(from: inputFormat, to: targetFormat))

        // 0,1 s sygnału 48 kHz → powinno wyjść ~1600 próbek 16 kHz.
        let frames: AVAudioFrameCount = 4800
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frames))
        input.frameLength = frames
        let channel = try XCTUnwrap(input.floatChannelData?[0])
        for index in 0..<Int(frames) {
            channel[index] = sinf(2 * .pi * 440 * Float(index) / 48_000)
        }

        let output = try XCTUnwrap(
            GeminiLiveTransport.convertToPCM16(input, converter: converter, targetFormat: targetFormat)
        )
        let produced = output.count / MemoryLayout<Int16>.size
        // Pierwsze wywołanie konwertera zjada priming filtra (ok. 400 próbek
        // wejścia), więc liczymy na stosunek, a nie na równość: 0,1 s sygnału
        // 48 kHz musi dać ~1600 próbek 16 kHz, nie 4800 i nie 480.
        let ratio = Double(produced) / 1600
        XCTAssertTrue(
            (0.8...1.02).contains(ratio),
            "Próbkowanie musi zejść do 16 kHz (otrzymano \(produced) próbek, stosunek \(ratio))."
        )

        // Sygnał nie może wyjść ciszą ani stałą wartością.
        let values = output.withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Int($0) }
        }
        XCTAssertGreaterThan(values.map { abs($0) }.max() ?? 0, 1000)
        XCTAssertGreaterThan(Set(values).count, 100, "Bufor musi nieść przebieg, nie stałą.")
    }

    // MARK: Wątek tapu mikrofonu

    /// Tap mikrofonu biegnie na wątku czasu rzeczywistego audio
    /// (`RealtimeMessenger.mServiceQueue`), a nie na głównym aktorze. Ten test
    /// woła **to samo domknięcie**, które dostaje AVFAudio — z kolejki w tle.
    ///
    /// Jeśli ktoś kiedyś zdejmie z niego `@Sendable`, domknięcie znów
    /// odziedziczy izolację `@MainActor` i Swift 6 zatrzyma tu proces na
    /// `_dispatch_assert_queue_fail` (EXC_BREAKPOINT/SIGTRAP) — dokładnie tak,
    /// jak na urządzeniu w raporcie `Emma-2026-09-15-231936.ips`, gdzie
    /// zamykało aplikację po dotknięciu „rozmawiaj”. Test nie potrzebuje
    /// mikrofonu ani sieci, więc łapie to także na symulatorze.
    func testInputTapBlockRunsOffMainThread() async throws {
        let inputFormat = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)
        )
        let targetFormat = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)
        )
        let converter = try XCTUnwrap(AVAudioConverter(from: inputFormat, to: targetFormat))
        let gate = MicrophoneGate()
        let (stream, continuation) = AsyncStream<Data>.makeStream()

        // 100 ms dźwięku przy 48 kHz — po konwersji na 16 kHz ma wyjść 1600 klatek.
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4800))
        buffer.frameLength = 4800
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = sin(Float(frame) * 0.05) * 0.5
        }

        let tap = GeminiLiveTransport.makeInputTapBlock(
            converter: converter,
            targetFormat: targetFormat,
            gate: gate,
            continuation: continuation
        )

        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                tap(buffer, AVAudioTime(hostTime: 0))
                done.resume()
            }
        }

        var iterator = stream.makeAsyncIterator()
        let next = await iterator.next()
        let pcm = try XCTUnwrap(next, "tap nie oddał danych z mikrofonu")
        let expected = 1600 * MemoryLayout<Int16>.size
        XCTAssertGreaterThan(pcm.count, expected / 2, "tap oddał za mało audio: \(pcm.count) B")
        XCTAssertLessThanOrEqual(pcm.count, expected + 8, "tap oddał ponad 100 ms audio: \(pcm.count) B")
        XCTAssertEqual(pcm.count % MemoryLayout<Int16>.size, 0, "PCM16 musi mieć parzystą liczbę bajtów")
    }

    // MARK: Półdupleks mikrofonu (pętla akustyczna)

    /// Emma nie może słyszeć samej siebie z głośnika, więc na czas odtwarzania
    /// mikrofon jest zamknięty. Testy pilnują trzech rzeczy, które łatwo zgubić:
    /// że bramka faktycznie zamyka się na czas kolejki, że liczy koniec kolejki
    /// (a nie „teraz”) i że przerwanie oddaje mikrofon natychmiast.
    func testPlaybackSuppressesMicrophoneAndThenReleases() {
        let gate = MicrophoneGate()
        XCTAssertFalse(gate.isMuted, "na starcie mikrofon ma być otwarty")

        gate.schedulePlayback(seconds: 0.2)
        XCTAssertTrue(gate.isMuted, "w trakcie odtwarzania mikrofon musi być zamknięty")

        // 0,2 s porcji + 0,25 s ogona na pogłos; czekamy z zapasem.
        let released = expectation(description: "bramka wraca do użytkownika")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertFalse(gate.isMuted, "po odtworzeniu i ogonie mikrofon musi wrócić")
            released.fulfill()
        }
        wait(for: [released], timeout: 2)
    }

    /// Porcje audio przychodzą z serwera szybciej niż realne odtwarzanie — koniec
    /// liczymy więc od końca kolejki. Gdyby liczyć od „teraz”, bramka otworzyłaby
    /// się w środku zdania Emmy i pętla wróciłaby.
    func testQueuedPlaybackExtendsSuppressionInsteadOfResettingIt() {
        let gate = MicrophoneGate()
        for _ in 0..<3 {
            gate.schedulePlayback(seconds: 0.2)
        }
        // Same porcje to 0,6 s. Po 0,5 s bramka musi być jeszcze zamknięta.
        let checked = expectation(description: "bramka wciąż zamknięta po 0,5 s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(gate.isMuted, "kolejka jeszcze gra, a mikrofon już się otworzył")
            checked.fulfill()
        }
        wait(for: [checked], timeout: 3)
    }

    /// Przerwanie czyści kolejkę odtwarzania, więc mikrofon musi wrócić od razu —
    /// inaczej użytkownik byłby niesłyszalny do końca wyliczonego ogona.
    func testInterruptReleasesMicrophoneImmediately() {
        let gate = MicrophoneGate()
        gate.schedulePlayback(seconds: 5)
        XCTAssertTrue(gate.isMuted)
        gate.releasePlayback()
        XCTAssertFalse(gate.isMuted, "po przerwaniu mikrofon wraca natychmiast")
    }

    /// Wyciszenie przez użytkownika jest nadrzędne i nie może zostać zdjęte
    /// przez zwolnienie bramki odtwarzania.
    func testUserMuteSurvivesPlaybackRelease() {
        let gate = MicrophoneGate()
        gate.setMuted(true)
        gate.releasePlayback()
        XCTAssertTrue(gate.isMuted)
        gate.setMuted(false)
        XCTAssertFalse(gate.isMuted)
    }
}
