import XCTest
@testable import Emma

// MARK: - Protokół Gemini Live API: kodek i reguły tury
//
// Te testy nie wołają sieci i nie potrzebują mikrofonu. Pilnują dwóch rzeczy,
// które łatwo zgubić przy zmianie dostawcy: że nasze ramki mają dokładnie ten
// kształt, którego oczekuje Live API, oraz że z odpowiedzi modelu powstają
// zdarzenia naszego modelu (a nie osobny, drugi model stanu).

final class GeminiLiveProtocolTests: XCTestCase {

    // MARK: Kodowanie

    func testSetupUsesModelsPrefixAndNothingElse() throws {
        let data = try GeminiLiveCodec.encode(.setup(model: "gemini-3.8-live", resumeHandle: nil))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let setup = try XCTUnwrap(object["setup"] as? [String: Any])
        XCTAssertEqual(setup["model"] as? String, "models/gemini-3.8-live")
        // Konfiguracja (instrukcja, narzędzia, transkrypcje) jest w tokenie
        // zablokowana po stronie backendu — aplikacja jej nie przysyła.
        XCTAssertNil(setup["generationConfig"])
        XCTAssertNil(setup["systemInstruction"])
        XCTAssertNil(setup["tools"])
        // Prosimy o wznowienie już na starcie: pusty obiekt to „daj mi uchwyt”,
        // a nie „wznów tę sesję”. Bez tej prośby serwer nie przysyła uchwytu
        // i `goAway` nie ma do czego wrócić (sprawdzone na żywym API).
        let resumption = try XCTUnwrap(setup["sessionResumption"] as? [String: Any])
        XCTAssertTrue(resumption.isEmpty)
    }

    func testSetupCarriesResumptionHandleWhenReconnecting() throws {
        let data = try GeminiLiveCodec.encode(.setup(model: "gemini-3.8-live", resumeHandle: "h-7"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let setup = try XCTUnwrap(object["setup"] as? [String: Any])
        let resumption = try XCTUnwrap(setup["sessionResumption"] as? [String: Any])
        XCTAssertEqual(resumption["handle"] as? String, "h-7")
    }

    func testAudioFrameCarriesBase64AndRate() throws {
        let pcm = Data([0x01, 0x02, 0x03, 0x04])
        let data = try GeminiLiveCodec.encode(.audio(pcm))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let realtime = try XCTUnwrap(object["realtimeInput"] as? [String: Any])
        let audio = try XCTUnwrap(realtime["audio"] as? [String: Any])
        XCTAssertEqual(audio["mimeType"] as? String, "audio/pcm;rate=16000")
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(audio["data"] as? String)), pcm)
    }

    func testTextTurnIsCompleteImmediately() throws {
        let data = try GeminiLiveCodec.encode(.textTurn("Ile mam zadań?"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let content = try XCTUnwrap(object["clientContent"] as? [String: Any])
        XCTAssertEqual(content["turnComplete"] as? Bool, true)
        let turns = try XCTUnwrap(content["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.first?["role"] as? String, "user")
    }

    func testToolResponseKeepsObjectShape() throws {
        let data = try GeminiLiveCodec.encode(
            .toolResponse(id: "call-1", name: "get_today_overview", resultJSON: #"{"tasks":1}"#)
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let response = try XCTUnwrap(object["toolResponse"] as? [String: Any])
        let responses = try XCTUnwrap(response["functionResponses"] as? [[String: Any]])
        XCTAssertEqual(responses.first?["id"] as? String, "call-1")
        XCTAssertEqual(responses.first?["name"] as? String, "get_today_overview")
        XCTAssertNotNil(responses.first?["response"] as? [String: Any])
    }

    // MARK: Dekodowanie

    func testDecodesAudioAndTranscriptionsFromOneFrame() {
        let frame = """
        {"serverContent":{"modelTurn":{"parts":[{"inlineData":{"data":"AAEC","mimeType":"audio/pcm;rate=24000"}}]},
        "outputTranscription":{"text":"Dzień dobry"},"turnComplete":true}}
        """
        let events = GeminiLiveCodec.decode(Data(frame.utf8))
        XCTAssertTrue(events.contains(.audio(Data([0, 1, 2]))))
        XCTAssertTrue(events.contains(.outputTranscription("Dzień dobry")))
        XCTAssertTrue(events.contains(.turnComplete))
    }

    func testDecodesSeveralConcatenatedObjects() {
        let frame = #"{"setupComplete":{}}"# + "\n" + #"{"sessionResumptionUpdate":{"newHandle":"h-1","resumable":true}}"#
        let events = GeminiLiveCodec.decode(Data(frame.utf8))
        XCTAssertEqual(events, [.setupComplete, .resumptionHandle("h-1")])
    }

    func testDecodesToolCallWithArgumentsAsJSON() throws {
        let frame = #"{"toolCall":{"functionCalls":[{"id":"c1","name":"search_clients","args":{"query":"Kowalski","limit":5}}]}}"#
        let events = GeminiLiveCodec.decode(Data(frame.utf8))
        guard case .toolCall(let call)? = events.first else {
            return XCTFail("Oczekiwano wywołania narzędzia, otrzymano \(events)")
        }
        XCTAssertEqual(call.id, "c1")
        XCTAssertEqual(call.name, "search_clients")
        let args = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual(args["query"] as? String, "Kowalski")
        XCTAssertEqual(args["limit"] as? Int, 5)
    }

    func testInterruptedAndTurnCompleteAreSeparateEvents() {
        let events = GeminiLiveCodec.decode(Data(#"{"serverContent":{"interrupted":true}}"#.utf8))
        XCTAssertEqual(events, [.interrupted])
        let complete = GeminiLiveCodec.decode(Data(#"{"serverContent":{"turnComplete":true}}"#.utf8))
        XCTAssertEqual(complete, [.turnComplete])
    }

    func testUnknownControlMessageIsNamedNotGuessed() {
        let events = GeminiLiveCodec.decode(Data(#"{"futureFeature":{"x":1}}"#.utf8))
        XCTAssertEqual(events, [.unknown(kind: "futureFeature")])
    }

    func testGoAwayDurationParsing() {
        XCTAssertEqual(GeminiLiveCodec.duration(from: "10s"), 10)
        XCTAssertEqual(GeminiLiveCodec.duration(from: "1.500s"), 1.5)
        XCTAssertEqual(GeminiLiveCodec.duration(from: "250ms"), 0.25)
        XCTAssertNil(GeminiLiveCodec.duration(from: "niedługo"))
        XCTAssertNil(GeminiLiveCodec.duration(from: nil))
    }
}

// MARK: - Reguły tury

final class GeminiLiveTurnTrackerTests: XCTestCase {

    func testSetupReportsConnectedAndMicrophone() {
        var tracker = GeminiLiveTurnTracker()
        let outcome = tracker.consume(.setupComplete)
        XCTAssertEqual(outcome.payloads, [.connectionChanged(.connected), .microphoneChanged(.capturing)])
    }

    func testPlaybackStartsOncePerTurnAndCompletesOnTurnComplete() {
        var tracker = GeminiLiveTurnTracker()
        let first = tracker.consume(.audio(Data([1])))
        XCTAssertEqual(first.payloads, [.playbackStarted(approximate: true)])
        let second = tracker.consume(.audio(Data([2])))
        XCTAssertTrue(second.payloads.isEmpty)

        _ = tracker.consume(.outputTranscription("Dzień"))
        _ = tracker.consume(.outputTranscription(" dobry"))
        let end = tracker.consume(.turnComplete)
        XCTAssertEqual(end.payloads, [
            .playbackStopped(reason: .completed),
            .agentTextFinal("Dzień dobry"),
        ])
    }

    func testInputTranscriptIsPartialThenFinal() {
        var tracker = GeminiLiveTurnTracker()
        XCTAssertEqual(
            tracker.consume(.inputTranscription("Ile mam")).payloads,
            [.userTranscriptPartial("Ile mam")]
        )
        let end = tracker.consume(.turnComplete)
        XCTAssertEqual(end.payloads, [.userTranscriptFinal("Ile mam")])
    }

    func testBargeInInterruptsPlaybackAndFinalizesUserTurnOnceOnly() {
        var tracker = GeminiLiveTurnTracker()
        _ = tracker.consume(.inputTranscription("Nie, poczekaj"))
        _ = tracker.consume(.audio(Data([1])))
        let interrupted = tracker.consume(.interrupted)
        XCTAssertEqual(interrupted.payloads, [
            .interruption(.userBargeIn),
            .playbackStopped(reason: .interrupted),
            .userTranscriptFinal("Nie, poczekaj"),
        ])

        // Powtórzone przerwanie w tej samej turze nie jest drugim faktem dla UI.
        _ = tracker.consume(.audio(Data([2])))
        let repeated = tracker.consume(.interrupted)
        XCTAssertEqual(repeated.payloads, [.interruption(.userBargeIn), .playbackStopped(reason: .interrupted)])
    }

    func testToolCallIsProgressNotExecution() {
        var tracker = GeminiLiveTurnTracker()
        let outcome = tracker.consume(.toolCall(GeminiLiveToolCall(id: "c1", name: "list_tasks", argumentsJSON: "{}")))
        XCTAssertEqual(outcome.toolCall?.name, "list_tasks")
        XCTAssertEqual(
            outcome.payloads,
            [.toolProgress(ToolProgress(label: "Sprawdzam dane w kancelarii", toolName: "list_tasks"))]
        )
    }

    func testResumptionHandleIsRemembered() {
        var tracker = GeminiLiveTurnTracker()
        let outcome = tracker.consume(.resumptionHandle("h-42"))
        XCTAssertEqual(outcome.resumptionHandle, "h-42")
        XCTAssertEqual(tracker.resumptionHandle, "h-42")
        XCTAssertTrue(outcome.payloads.isEmpty)
    }

    func testGoAwayAsksTransportToPrepareForReconnect() {
        var tracker = GeminiLiveTurnTracker()
        let outcome = tracker.consume(.goAway(9))
        XCTAssertEqual(outcome.goAwayIn, 9)
        XCTAssertEqual(outcome.payloads, [
            .connectionChanged(.reconnecting),
            .recoverableError(.tokenExpiring),
        ])
    }

    func testBargeInTellsTransportToDropBufferedAudio() {
        // `interrupted` znaczy, że użytkownik wszedł w słowo. Sama zmiana stanu nie
        // wystarczy: zbuforowane fragmenty muszą zostać wycofane, inaczej Emma mówi
        // dalej przez wypowiedź, którą rzekomo przerwała.
        var tracker = GeminiLiveTurnTracker()
        _ = tracker.consume(.audio(Data([1])))
        let outcome = tracker.consume(.interrupted)
        XCTAssertTrue(outcome.shouldStopPlayback)
        XCTAssertEqual(outcome.payloads, [
            .interruption(.userBargeIn),
            .playbackStopped(reason: .interrupted),
        ])
    }

    func testInterruptedWithoutAudioDoesNotClaimStoppingPlayback() {
        // Nie było odtwarzania, więc nie ma czego wycofywać — i nie udajemy,
        // że przerwaliśmy coś, co nie istniało.
        var tracker = GeminiLiveTurnTracker()
        let outcome = tracker.consume(.interrupted)
        XCTAssertFalse(outcome.shouldStopPlayback)
        XCTAssertFalse(outcome.payloads.contains(.interruption(.userBargeIn)))
    }

    func testConnectionLostClosesSpeakingTurnWithoutClaimingSuccess() {
        var tracker = GeminiLiveTurnTracker()
        _ = tracker.consume(.audio(Data([1])))
        _ = tracker.consume(.outputTranscription("Zaczęłam mówić"))
        let outcome = tracker.connectionLost()
        XCTAssertTrue(outcome.shouldReconnect)
        // Po zerwaniu też milkniemy: nie zostawiamy grania niedokończonej tury.
        XCTAssertTrue(outcome.shouldStopPlayback)
        XCTAssertEqual(outcome.payloads, [
            .playbackStopped(reason: .failed),
            .agentTextFinal("Zaczęłam mówić"),
            .connectionChanged(.reconnecting),
            .recoverableError(.networkLost),
        ])
    }

    func testUnknownEventChangesNothing() {
        var tracker = GeminiLiveTurnTracker()
        let outcome = tracker.consume(.unknown(kind: "futureFeature"))
        XCTAssertTrue(outcome.payloads.isEmpty)
        XCTAssertNil(outcome.audio)
        XCTAssertNil(outcome.toolCall)
    }
}
