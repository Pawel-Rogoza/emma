import Foundation

// MARK: - Protokół Gemini Live API (warstwa czystej logiki)
//
// Ten plik nie zna sieci, AVFoundation ani UIKit. Koduje i dekoduje komunikaty
// Live API oraz zamienia je na zdarzenia naszego modelu. Dzięki temu:
//   • reguły protokołu da się przetestować bez telefonu i bez mikrofonu,
//   • transport (`VoiceAdapters/GeminiLiveTransport`) zostaje cienki: WebSocket
//     i audio, bez własnej interpretacji odpowiedzi modelu.
//
// Kontrakt pochodzi z dokumentacji Live API
// (https://ai.google.dev/gemini-api/docs/live-api) i jest sprawdzany spike'em
// po stronie backendu (`src/lib/crm/voice/gemini.live.test.ts`).

public enum GeminiLiveDefaults {
    /// Model przypięty do wersji stabilnej. Zmiana modelu to zmiana konfiguracji,
    /// nie ukryta stała w aplikacji — dlatego backend przysyła nazwę modelu w
    /// odpowiedzi na token i aplikacja ją odwzorowuje.
    public static let model = "gemini-3.8-live"
    /// Wejście audio dla Live API: PCM 16-bit, mono, 16 kHz.
    public static let inputSampleRate: Double = 16_000
    /// Wyjście audio z Live API: PCM 16-bit, mono, 24 kHz.
    public static let outputSampleRate: Double = 24_000
    public static let audioMimeType = "audio/pcm;rate=16000"
}

// MARK: - Komunikaty wychodzące

public enum GeminiRole: String, Sendable {
    case user
    case model
}

public enum GeminiLiveClientMessage: Equatable, Sendable {
    /// Pierwsza wiadomość po otwarciu gniazda. Reszta konfiguracji (instrukcja
    /// systemowa, narzędzia, transkrypcje) jest zablokowana w tokenie po stronie
    /// backendu, więc aplikacja nie może jej podmienić. `resumeHandle` wraca do
    /// tej samej sesji po zerwaniu połączenia (serwer zrywa je co ~10 minut).
    case setup(model: String, resumeHandle: String?)
    case textTurn(String)
    case clientContent(role: GeminiRole, text: String, turnComplete: Bool)
    /// Fragment mowy użytkownika. Puste `audio` nie jest wysyłane.
    case audio(Data)
    case toolResponse(id: String, name: String, resultJSON: String)
    /// Ręczne granice wypowiedzi, gdy VAD automatyczny jest wyłączony.
    case activityStart
    case activityEnd
}

// MARK: - Komunikaty przychodzące

public struct GeminiLiveToolCall: Equatable, Sendable {
    public var id: String
    public var name: String
    /// Argumenty jako JSON — nie interpretujemy ich tutaj. Wykonanie należy do
    /// backendu (wspólny action engine), a nie do aplikacji.
    public var argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public enum GeminiLiveServerEvent: Equatable, Sendable {
    case setupComplete
    case audio(Data)
    case inputTranscription(String)
    case outputTranscription(String)
    case turnComplete
    case interrupted
    case toolCall(GeminiLiveToolCall)
    case resumptionHandle(String)
    case goAway(TimeInterval?)
    /// Zdarzenie, którego nie znamy. Zachowujemy jego nazwę, ale nie udajemy,
    /// że je rozumiemy — nie wolno zgadywać znaczenia komunikatów sterujących.
    case unknown(kind: String)
}

// MARK: - Kodek

public enum GeminiLiveCodec {

    // MARK: Kodowanie

    public static func encode(_ message: GeminiLiveClientMessage) throws -> Data {
        let payload = body(for: message)
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw GeminiLiveProtocolError.encodingFailed("Nieprawidłowy obiekt JSON.")
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    static func body(for message: GeminiLiveClientMessage) -> [String: Any] {
        switch message {
        case .setup(let model, let resumeHandle):
            var setup: [String: Any] = ["model": "models/\(model)"]
            // Wznowienie trzeba włączyć **już w pierwszej ramce**: serwer
            // przysyła uchwyt tylko wtedy, gdy klient o niego poprosi. Bez tego
            // `goAway` nie ma do czego wrócić — a to jedyna droga, żeby długa
            // rozmowa przetrwała dziesięciominutowe zamknięcie połączenia.
            // Pusty obiekt znaczy „proszę o uchwyt”, a nie „wznów tę sesję”.
            if let resumeHandle, !resumeHandle.isEmpty {
                setup["sessionResumption"] = ["handle": resumeHandle]
            } else {
                setup["sessionResumption"] = [String: Any]()
            }
            return ["setup": setup]

        case .textTurn(let text):
            return [
                "clientContent": [
                    "turns": [["role": "user", "parts": [["text": text]]]],
                    "turnComplete": true,
                ]
            ]

        case .clientContent(let role, let text, let turnComplete):
            return [
                "clientContent": [
                    "turns": [["role": role.rawValue, "parts": [["text": text]]]],
                    "turnComplete": turnComplete,
                ]
            ]

        case .audio(let data):
            return [
                "realtimeInput": [
                    "audio": [
                        "data": data.base64EncodedString(),
                        "mimeType": GeminiLiveDefaults.audioMimeType,
                    ]
                ]
            ]

        case .toolResponse(let id, let name, let resultJSON):
            // `response` musi być obiektem; gdy backend zwrócił nieobiektowy JSON,
            // opakowujemy go, żeby nie wysłać nieprawidłowej ramki.
            let response = (try? JSONSerialization.jsonObject(with: Data(resultJSON.utf8))) as? [String: Any]
            return [
                "toolResponse": [
                    "functionResponses": [[
                        "id": id,
                        "name": name,
                        "response": response ?? ["result": resultJSON],
                    ]]
                ]
            ]

        case .activityStart:
            return ["realtimeInput": ["activityStart": [:]]]

        case .activityEnd:
            return ["realtimeInput": ["activityEnd": [:]]]
        }
    }

    // MARK: Dekodowanie

    /// Live API potrafi wysłać kilka obiektów JSON w jednej ramce (albo rozdzielić
    /// je znakiem nowej linii), więc dekodujemy strumień, nie pojedynczy obiekt.
    public static func decode(_ data: Data) -> [GeminiLiveServerEvent] {
        var events: [GeminiLiveServerEvent] = []
        for object in jsonObjects(in: data) {
            events.append(contentsOf: Self.events(from: object))
        }
        return events
    }

    static func events(from object: [String: Any]) -> [GeminiLiveServerEvent] {
        var events: [GeminiLiveServerEvent] = []
        for (key, value) in object {
            switch key {
            case "setupComplete":
                events.append(.setupComplete)
            case "serverContent":
                events.append(contentsOf: serverContentEvents(value))
            case "toolCall":
                events.append(contentsOf: toolCallEvents(value))
            case "sessionResumptionUpdate":
                if let update = value as? [String: Any],
                   let handle = update["newHandle"] as? String,
                   !handle.isEmpty {
                    events.append(.resumptionHandle(handle))
                }
            case "goAway":
                let seconds = (value as? [String: Any])?["timeLeft"] as? String
                events.append(.goAway(Self.duration(from: seconds)))
            default:
                events.append(.unknown(kind: key))
            }
        }
        return events
    }

    private static func serverContentEvents(_ value: Any) -> [GeminiLiveServerEvent] {
        guard let content = value as? [String: Any] else { return [] }
        var events: [GeminiLiveServerEvent] = []

        if let modelTurn = content["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                guard let inline = part["inlineData"] as? [String: Any],
                      let encoded = inline["data"] as? String,
                      let audio = Data(base64Encoded: encoded),
                      !audio.isEmpty else { continue }
                events.append(.audio(audio))
            }
        }
        if let input = content["inputTranscription"] as? [String: Any],
           let text = input["text"] as? String,
           !text.isEmpty {
            events.append(.inputTranscription(text))
        }
        if let output = content["outputTranscription"] as? [String: Any],
           let text = output["text"] as? String,
           !text.isEmpty {
            events.append(.outputTranscription(text))
        }
        if content["interrupted"] as? Bool == true {
            events.append(.interrupted)
        }
        if content["turnComplete"] as? Bool == true {
            events.append(.turnComplete)
        }
        return events
    }

    private static func toolCallEvents(_ value: Any) -> [GeminiLiveServerEvent] {
        guard let container = value as? [String: Any],
              let calls = container["functionCalls"] as? [[String: Any]] else { return [] }
        return calls.compactMap { call in
            guard let name = call["name"] as? String else { return nil }
            let id = (call["id"] as? String) ?? name
            let args = call["args"] as? [String: Any] ?? [:]
            let json = (try? JSONSerialization.data(withJSONObject: args))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return .toolCall(GeminiLiveToolCall(id: id, name: name, argumentsJSON: json))
        }
    }

    /// „10s”, „1.500s”, „250ms” → sekundy. Wartość nierozpoznana = brak wartości.
    static func duration(from text: String?) -> TimeInterval? {
        guard var raw = text?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        var scale: Double = 1
        if raw.hasSuffix("ms") {
            scale = 0.001
            raw.removeLast(2)
        } else if raw.hasSuffix("s") {
            raw.removeLast()
        }
        guard let value = Double(raw) else { return nil }
        return value * scale
    }

    private static func jsonObjects(in data: Data) -> [[String: Any]] {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return [object]
        }
        // Ramka złożona z kilku obiektów: rozbijamy nawiasowo, bo JSONSerialization
        // nie czyta strumienia. Linie nowej są tylko jednym z przypadków.
        var objects: [[String: Any]] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false
        let text = String(decoding: data, as: UTF8.self)
        for index in text.indices {
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let begin = start {
                    let slice = text[begin...index]
                    if let object = try? JSONSerialization.jsonObject(with: Data(slice.utf8)) as? [String: Any] {
                        objects.append(object)
                    }
                    start = nil
                }
            default:
                break
            }
        }
        return objects
    }
}

public enum GeminiLiveProtocolError: Error, Equatable, Sendable {
    case encodingFailed(String)
    case websocketFailed(String)
    case sessionEnded(code: Int, reason: String)
}
