import Foundation

// MARK: - Emma proaktywna (audyt 11.10.2026, Etap 3)
//
// Serwer liczy rzeczy, o których kancelaria powinna wiedzieć, zanim zapyta
// (`GET /api/mobile/v1/emma/alerts`): lead ze strony bez odpowiedzi od 15 min,
// zamykające się okno 24 h WhatsApp, terminy procesowe i rozprawy z panelu,
// konsultacje bez zapisanego wyniku. Telefon zamienia **nowe** pozycje
// w powiadomienia; dotknięcie otwiera Emmę z gotowym pytaniem.

public struct EmmaAlert: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case leadWaiting = "lead_waiting"
        case replyWindow = "reply_window"
        case caseActionDue = "case_action_due"
        case consultationFollowup = "consultation_followup"
        case other
    }

    public let id: String
    public let kind: Kind
    public let priority: Int
    public let title: String
    public let body: String
    /// Pytanie do Emmy po dotknięciu powiadomienia.
    public let prompt: String
    public let clientID: ClientID?
    public let caseID: CaseID?
    public let threadID: ThreadID?

    public init(
        id: String,
        kind: Kind,
        priority: Int,
        title: String,
        body: String,
        prompt: String,
        clientID: ClientID? = nil,
        caseID: CaseID? = nil,
        threadID: ThreadID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.priority = priority
        self.title = title
        self.body = body
        self.prompt = prompt
        self.clientID = clientID
        self.caseID = caseID
        self.threadID = threadID
    }
}

/// Które alerty zamienić w powiadomienie. Pierwsze sprawdzenie na tym telefonie
/// tylko zapamiętuje stan — inaczej instalacja zasypałaby ekran blokady
/// wszystkim, co już wisi. Potem powiadamiamy wyłącznie o nowych identyfikatorach,
/// najwyżej `limit` naraz (reszta jest w Emmie i na „Dzisiaj”).
public enum EmmaAlertPlan {

    public static let identifierPrefix = "emma.alert."
    /// Zapamiętujemy ograniczoną liczbę identyfikatorów (stare wypadają).
    public static let memory = 200

    public struct Outcome: Equatable, Sendable {
        public var notify: [EmmaAlert]
        public var known: [String]
    }

    public static func check(alerts: [EmmaAlert], known: [String]?, limit: Int = 3) -> Outcome {
        guard let known else {
            return Outcome(notify: [], known: Array(alerts.map(\.id).prefix(memory)))
        }
        let seen = Set(known)
        let fresh = alerts.filter { !seen.contains($0.id) }
        let notify = Array(fresh.sorted { $0.priority < $1.priority }.prefix(limit))
        // Nowe na początku, żeby przy obcięciu wypadały najstarsze.
        let merged = fresh.map(\.id) + known.filter { id in !fresh.contains { $0.id == id } }
        return Outcome(notify: notify, known: Array(merged.prefix(memory)))
    }
}

// MARK: - Emma pisemnie: użycie w miesiącu (Etap 5)

public struct EmmaTextUsage: Equatable, Sendable {
    public let turns: Int
    public let averageSeconds: Double?
    public let toolErrors: Int
    public let thumbsUp: Int
    public let thumbsDown: Int
    /// `0` — bez limitu.
    public let dailyLimit: Int
    public let turnsLastDay: Int

    public init(
        turns: Int,
        averageSeconds: Double?,
        toolErrors: Int,
        thumbsUp: Int,
        thumbsDown: Int,
        dailyLimit: Int,
        turnsLastDay: Int
    ) {
        self.turns = turns
        self.averageSeconds = averageSeconds
        self.toolErrors = toolErrors
        self.thumbsUp = thumbsUp
        self.thumbsDown = thumbsDown
        self.dailyLimit = dailyLimit
        self.turnsLastDay = turnsLastDay
    }
}
