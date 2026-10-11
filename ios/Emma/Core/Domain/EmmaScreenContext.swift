import Foundation

// MARK: - Kontekst ekranu dla Emmy pisemnie (audyt 11.10.2026, Etap 2)
//
// Emma jest osobną zakładką, więc „ten klient”, „ta sprawa”, „tu” odnoszą się
// do ekranu, z którego użytkownik do niej przyszedł: karta osoby, sprawa,
// rozmowa, dzień w kalendarzu. Wcześniej serwer dostawał tylko wybranego
// klienta — pytanie z kalendarza albo z rozmowy traciło sens.

public struct EmmaScreenContext: Equatable, Sendable {

    /// Nazwy ekranów zgodne z backendem (`SCREEN_LABELS` w `assistantChat.ts`).
    public enum Screen: String, Equatable, Sendable {
        case today
        case tasks
        case calendar
        case clients
        case client
        case legalCase = "case"
        case messages
        case thread
        case emma
    }

    public var screen: Screen
    public var clientID: ClientID?
    public var clientName: String?
    public var caseID: CaseID?
    public var threadID: ThreadID?
    /// Dzień oglądany w kalendarzu.
    public var day: LocalDate?

    public init(
        screen: Screen,
        clientID: ClientID? = nil,
        clientName: String? = nil,
        caseID: CaseID? = nil,
        threadID: ThreadID? = nil,
        day: LocalDate? = nil
    ) {
        self.screen = screen
        self.clientID = clientID
        self.clientName = clientName
        self.caseID = caseID
        self.threadID = threadID
        self.day = day
    }
}

/// Działanie aplikacji, które Emma pisemnie zleciła w odpowiedzi (`app_*`).
/// Telefon wykonuje je tym samym kodem co w rozmowie głosowej.
public struct EmmaAppCall: Equatable, Sendable {
    public var name: String
    public var argumentsJSON: String

    public init(name: String, argumentsJSON: String) {
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// Odpowiedź Emmy pisemnie.
public struct EmmaWrittenReply: Equatable, Sendable {
    public var conversationID: Int
    public var reply: String
    public var appCalls: [EmmaAppCall]

    public init(conversationID: Int, reply: String, appCalls: [EmmaAppCall] = []) {
        self.conversationID = conversationID
        self.reply = reply
        self.appCalls = appCalls
    }
}
