import Foundation

// MARK: - Profil sprawy
//
// Karnista myśli o sprawie trzema pytaniami: jaka to sprawa, na jakim jest
// etapie i kim jest w niej klient. Od odpowiedzi zależy, jakie terminy są
// w ogóle możliwe (podejrzany nie wnosi apelacji, cudzoziemiec nie ma
// aresztu, tylko koniec legalnego pobytu), więc profil jest danymi, a nie
// opisem w notatce.
//
// Wszystkie pola są opcjonalne: `nil` znaczy „nie ustalono” albo „serwer
// jeszcze tego nie zna”. Formularz pyta jednym dotknięciem (chipy), a każde
// pytanie pojawia się dopiero wtedy, gdy ma sens dla wybranego rodzaju.

/// Pola profilu, które formularz może wyczyścić (patrz `CaseRepository.updateCase`).
public enum CaseProfileField: String, Hashable, Sendable, CaseIterable {
    case kind, stage, clientRole, custodyUntil, legalStayUntil

    /// Pola wyczyszczone między wersją zapisaną a nową.
    public static func cleared(from old: LegalCase, to new: LegalCase) -> Set<CaseProfileField> {
        var result: Set<CaseProfileField> = []
        if old.kind != nil, new.kind == nil { result.insert(.kind) }
        if old.stage != nil, new.stage == nil { result.insert(.stage) }
        if old.clientRole != nil, new.clientRole == nil { result.insert(.clientRole) }
        if old.custodyUntil != nil, new.custodyUntil == nil { result.insert(.custodyUntil) }
        if old.legalStayUntil != nil, new.legalStayUntil == nil { result.insert(.legalStayUntil) }
        return result
    }

    /// Pola wpisane w formularzu, których serwer nie odesłał — znak, że
    /// backend jeszcze ich nie obsługuje (zapis nie może udawać sukcesu).
    public static func dropped(sent: LegalCase, returned: LegalCase) -> Set<CaseProfileField> {
        var result: Set<CaseProfileField> = []
        if sent.kind != nil, returned.kind == nil { result.insert(.kind) }
        if sent.stage != nil, returned.stage == nil { result.insert(.stage) }
        if sent.clientRole != nil, returned.clientRole == nil { result.insert(.clientRole) }
        if sent.custodyUntil != nil, returned.custodyUntil == nil { result.insert(.custodyUntil) }
        if sent.legalStayUntil != nil, returned.legalStayUntil == nil { result.insert(.legalStayUntil) }
        return result
    }
}

/// Rodzaj sprawy kancelarii.
public enum CaseKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case criminal
    case enforcement
    case residence
    case deportation
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .criminal: return "Karna"
        case .enforcement: return "Wykonawcza"
        case .residence: return "Pobytowa"
        case .deportation: return "Deportacyjna"
        case .other: return "Inna"
        }
    }

    /// Symbol SF dla chipa i plakietki.
    public var systemImage: String {
        switch self {
        case .criminal: return "building.columns"
        case .enforcement: return "door.left.hand.open"
        case .residence: return "person.text.rectangle"
        case .deportation: return "airplane.departure"
        case .other: return "folder"
        }
    }

    /// Etapy, które mają sens dla tego rodzaju — w tej kolejności pokazuje je formularz.
    public var stages: [CaseStage] {
        switch self {
        case .criminal: return [.preTrial, .firstInstance, .appeal, .cassation]
        case .enforcement: return [.firstInstance, .appeal]
        case .residence, .deportation: return [.adminFirst, .adminAppeal, .adminCourt]
        case .other: return []
        }
    }

    /// Role klienta, o które warto pytać. Pusta lista — pytania nie ma.
    public var roles: [ClientRole] {
        switch self {
        case .criminal: return [.suspect, .accused, .convicted, .victim]
        case .enforcement, .residence, .deportation, .other: return []
        }
    }

    /// Data, której trzeba pilnować w tym rodzaju sprawy.
    public var watchKinds: [CaseWatch.Kind] {
        switch self {
        case .criminal: return [.custody]
        case .residence, .deportation: return [.legalStay]
        case .enforcement, .other: return []
        }
    }
}

/// Etap postępowania.
public enum CaseStage: String, Codable, Sendable, CaseIterable, Identifiable {
    case preTrial = "pre_trial"
    case firstInstance = "first_instance"
    case appeal
    case cassation
    case adminFirst = "admin_first"
    case adminAppeal = "admin_appeal"
    case adminCourt = "admin_court"

    public var id: String { rawValue }

    /// Nazwa etapu w języku danego rodzaju sprawy („Wojewoda” w pobytowej,
    /// „Straż Graniczna” w deportacyjnej, „Sąd penitencjarny” w wykonawczej).
    public func displayName(in kind: CaseKind?) -> String {
        switch self {
        case .preTrial: return "Przygotowawcze"
        case .firstInstance: return kind == .enforcement ? "Sąd penitencjarny" : "Sąd I instancji"
        case .appeal: return kind == .enforcement ? "Zażalenie" : "Odwoławcze"
        case .cassation: return "Kasacja"
        case .adminFirst: return kind == .deportation ? "Straż Graniczna" : "Wojewoda"
        case .adminAppeal: return "Szef UdSC"
        case .adminCourt: return "WSA / NSA"
        }
    }

    /// Jak nazwać sygnaturę na tym etapie.
    public var signatureLabel: String {
        switch self {
        case .preTrial: return "Sygnatura prokuratury"
        case .adminFirst, .adminAppeal: return "Znak sprawy"
        default: return "Sygnatura akt"
        }
    }

    public var signaturePlaceholder: String {
        switch self {
        case .preTrial: return "np. PR 1 Ds. 123.2026"
        case .adminFirst, .adminAppeal: return "np. WSC-II-P.6151.123.2026"
        case .adminCourt: return "np. IV SA/Wa 123/26"
        default: return "np. II K 123/26"
        }
    }

    /// Jak nazwać organ prowadzący na tym etapie.
    public var authorityLabel: String {
        switch self {
        case .preTrial: return "Prokuratura"
        case .adminFirst, .adminAppeal: return "Organ"
        default: return "Sąd"
        }
    }

    public var authorityPlaceholder: String {
        switch self {
        case .preTrial: return "np. Prokuratura Rejonowa Warszawa-Śródmieście"
        case .adminFirst: return "np. Mazowiecki Urząd Wojewódzki"
        case .adminAppeal: return "Szef Urzędu do Spraw Cudzoziemców"
        case .adminCourt: return "np. WSA w Warszawie"
        default: return "np. Sąd Rejonowy dla Warszawy-Śródmieścia"
        }
    }
}

/// Kim jest klient w sprawie karnej.
public enum ClientRole: String, Codable, Sendable, CaseIterable, Identifiable {
    case suspect
    case accused
    case convicted
    case victim

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .suspect: return "Podejrzany"
        case .accused: return "Oskarżony"
        case .convicted: return "Skazany"
        case .victim: return "Pokrzywdzony"
        }
    }

    /// Rola, która zwykle wynika z etapu: w przygotowawczym klient jest
    /// podejrzanym, przed sądem — oskarżonym. Pokrzywdzony zostaje sobą
    /// (patrz `afterStageChange`).
    public static func suggested(for stage: CaseStage?) -> ClientRole? {
        switch stage {
        case .preTrial: return .suspect
        case .firstInstance, .appeal: return .accused
        case .cassation: return .convicted
        default: return nil
        }
    }

    /// Rola po zmianie etapu. Zmienia się sama tylko wtedy, gdy wynikała
    /// z poprzedniego etapu albo nie była ustalona — wybór „Pokrzywdzony”
    /// czy ręczna korekta nie są nadpisywane.
    public static func afterStageChange(current: ClientRole?, from old: CaseStage?, to new: CaseStage?) -> ClientRole? {
        guard current == nil || current == suggested(for: old) else { return current }
        return suggested(for: new) ?? current
    }
}

// MARK: - Pilnowane daty

/// Data, której przegapienie kończy się źle: koniec tymczasowego aresztowania
/// (sąd przedłuża albo klient wychodzi — obrońca chce o tym wiedzieć wcześniej)
/// albo koniec legalnego pobytu cudzoziemca (wniosek złożony później nie
/// chroni przed zobowiązaniem do powrotu).
public struct CaseWatch: Identifiable, Hashable, Sendable {

    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case custody
        case legalStay

        public var displayName: String {
            switch self {
            case .custody: return "Areszt"
            case .legalStay: return "Legalny pobyt"
            }
        }

        /// Etykieta pola w formularzu sprawy.
        public var fieldLabel: String {
            switch self {
            case .custody: return "Areszt do"
            case .legalStay: return "Legalny pobyt do"
            }
        }

        public var systemImage: String {
            switch self {
            case .custody: return "lock.fill"
            case .legalStay: return "person.text.rectangle.fill"
            }
        }

        /// Co zrobić, zanim data minie — jedno zdanie, bez wykładu.
        public var hint: String {
            switch self {
            case .custody: return "Sprawdź wniosek o przedłużenie i przygotuj stanowisko obrony."
            case .legalStay: return "Wniosek o pobyt trzeba złożyć przed tym dniem."
            }
        }
    }

    public enum Severity: Int, Comparable, Sendable {
        case calm, soon, critical, expired

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let caseID: CaseID
    public let clientID: ClientID
    public let kind: Kind
    public let until: LocalDate
    public let daysLeft: Int

    public var id: String { "\(caseID.rawValue).\(kind.rawValue)" }

    /// Od ilu dni przed końcem karta pojawia się na „Dzisiaj”.
    public static let showOnTodayDays = 30
    /// Od ilu dni przed końcem to alarm (czerwone), a nie zapowiedź.
    public static let criticalDays = 7
    /// Jak długo po upływie data jeszcze wisi (ktoś musi ją zaktualizować).
    public static let expiredLookbackDays = 14

    public var severity: Severity {
        if daysLeft < 0 { return .expired }
        if daysLeft <= Self.criticalDays { return .critical }
        if daysLeft <= Self.showOnTodayDays { return .soon }
        return .calm
    }

    /// „kończy się dziś”, „kończy się jutro”, „za 9 dni”, „minął 2 dni temu”.
    public var countdownText: String {
        switch daysLeft {
        case 0: return "kończy się dziś"
        case 1: return "kończy się jutro"
        case let days where days > 1: return "za \(EmmaPlural.days(days))"
        case -1: return "minął wczoraj"
        default: return "minął \(EmmaPlural.days(-daysLeft)) temu"
        }
    }

    /// Pilnowane daty jednej sprawy (tylko te, które mają sens dla jej rodzaju;
    /// sprawa bez rodzaju pokazuje każdą wpisaną datę).
    public static func items(for legalCase: LegalCase, today: LocalDate) -> [CaseWatch] {
        guard legalCase.status.isActive else { return [] }
        var result: [CaseWatch] = []
        let allowed = legalCase.kind?.watchKinds ?? Kind.allCases
        for kind in allowed {
            guard let until = legalCase.watchDate(kind) else { continue }
            result.append(CaseWatch(
                caseID: legalCase.id,
                clientID: legalCase.clientID,
                kind: kind,
                until: until,
                daysLeft: today.days(until: until)
            ))
        }
        return result
    }

    /// Daty do pokazania na „Dzisiaj”: najbliższe 30 dni i świeżo minione,
    /// najpilniejsze najpierw.
    public static func upcoming(cases: [LegalCase], today: LocalDate) -> [CaseWatch] {
        cases
            .flatMap { items(for: $0, today: today) }
            .filter { $0.daysLeft <= showOnTodayDays && $0.daysLeft >= -expiredLookbackDays }
            .sorted { $0.until == $1.until ? $0.id < $1.id : $0.until < $1.until }
    }
}

extension LegalCase {

    /// Data pilnowana w sprawie.
    public func watchDate(_ kind: CaseWatch.Kind) -> LocalDate? {
        switch kind {
        case .custody: return custodyUntil
        case .legalStay: return legalStayUntil
        }
    }

    /// „Karna · Przygotowawcze · Podejrzany” — linia profilu pod tytułem sprawy.
    public var profileText: String? {
        var parts: [String] = []
        if let kind { parts.append(kind.displayName) }
        if let stage { parts.append(stage.displayName(in: kind)) }
        if let clientRole, kind == nil || kind == .criminal { parts.append(clientRole.displayName) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Przypomnienia o pilnowanych datach

/// Powiadomienia przed końcem aresztu i legalnego pobytu: 14, 7, 3 i 1 dzień
/// przed oraz w sam dzień, o 8:30 (po porannym skrócie o 8:00).
public enum CaseWatchReminderPlan {

    public struct Item: Equatable, Sendable {
        public let identifier: String
        public let caseID: CaseID
        public let fireAt: Date
        public let title: String
        public let body: String
    }

    public static let identifierPrefix = "emma.watch."
    public static let daysBefore = [14, 7, 3, 1, 0]
    public static let hour = 8
    public static let minute = 30

    public static func items(
        watches: [CaseWatch],
        clientNames: [ClientID: String],
        dateText: (LocalDate) -> String,
        now: Date,
        timeZoneIdentifier: String = EmmaTime.referenceTimeZone
    ) -> [Item] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        var items: [Item] = []
        for watch in watches {
            let name = clientNames[watch.clientID] ?? Client.unknownDisplayName
            for offset in daysBefore {
                let day = watch.until.adding(days: -offset)
                guard let fireAt = calendar.date(from: DateComponents(
                    year: day.year, month: day.month, day: day.day, hour: hour, minute: minute
                )), fireAt > now else { continue }
                let when: String
                switch offset {
                case 0: when = "kończy się dziś"
                case 1: when = "kończy się jutro"
                default: when = "kończy się za \(EmmaPlural.days(offset))"
                }
                items.append(Item(
                    identifier: "\(identifierPrefix)\(watch.id).\(offset)",
                    caseID: watch.caseID,
                    fireAt: fireAt,
                    title: "\(watch.kind.displayName) — \(name)",
                    body: "\(when.prefix(1).uppercased())\(when.dropFirst()) (\(dateText(watch.until))). \(watch.kind.hint)"
                ))
            }
        }
        return items.sorted { $0.fireAt < $1.fireAt }
    }
}
