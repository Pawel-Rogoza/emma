import Foundation

// MARK: - Słownik kontraktu mobilnego
//
// Typy aplikacji mają polskie wartości (`ClientStage.inContact` = „W kontakcie”),
// a kontrakt — tokeny druciane (`in_contact`). Audyt 16.10.2026: tłumaczenie było
// rozsiane po trzech miejscach — etap klienta zapisywał klient HTTP i, osobno,
// repozytorium, a odczytywała trzecia tabela. Każda kopia to okazja, żeby zapis
// i odczyt rozjechały się po cichu.
//
// Teraz każdy typ ma **jedną** tabelę (`contractToken`), a odczyt powstaje z niej
// sam (`init?(contractToken:)`), więc token zapisany zawsze da się odczytać.
// Źródło klienta (`ClientSource`) zostaje poza tym schematem świadomie: kontrakt
// zna `import`, którego aplikacja nie rozróżnia, a „Polecenie” nie ma tokenu.

protocol ContractTokenRepresentable: CaseIterable {
    /// Wartość w słowniku kontraktu mobilnego.
    var contractToken: String { get }
}

extension ContractTokenRepresentable {
    /// Wartość z tokenu kontraktu; `nil` dla tokenu spoza słownika.
    init?(contractToken raw: String) {
        guard let match = Self.allCases.first(where: { $0.contractToken == raw }) else { return nil }
        self = match
    }
}

extension ClientStage: ContractTokenRepresentable {
    var contractToken: String {
        switch self {
        case .new: return "new"
        case .inContact: return "in_contact"
        case .client: return "client"
        }
    }
}

extension CaseStatus: ContractTokenRepresentable {
    var contractToken: String {
        switch self {
        case .inProgress: return "in_progress"
        case .awaitingClient: return "awaiting_client"
        case .closed: return "closed"
        }
    }
}

extension TaskPriority: ContractTokenRepresentable {
    var contractToken: String {
        switch self {
        case .normal: return "normal"
        case .urgent: return "urgent"
        }
    }
}

extension TaskFilter.Scope: ContractTokenRepresentable {
    var contractToken: String {
        switch self {
        case .open: return "open"
        case .done: return "done"
        case .all: return "all"
        }
    }
}

/// Słownik **kontraktu**, nie CRM: `consultation` / `case_deadline`. Backend
/// mapuje swoje cztery rodzaje na te dwie wartości, więc aplikacja nie musi
/// znać `hearing` ani `meeting`.
extension EventKind: ContractTokenRepresentable {
    var contractToken: String {
        switch self {
        case .consultation: return "consultation"
        case .caseDeadline: return "case_deadline"
        }
    }
}

/// Stan terminu: CRM go nie prowadzi i wysyła `to_confirm`, ale gdy panel
/// zacznie zapisywać stan, aplikacja odczyta go bez zmiany.
extension EventStatus: ContractTokenRepresentable {
    var contractToken: String {
        switch self {
        case .toConfirm: return "to_confirm"
        case .confirmed: return "confirmed"
        case .finished: return "finished"
        }
    }
}

extension BackendRepository {

    /// Odczyt tokenu kontraktu. Wartość spoza słownika jest błędem, a nie cichą
    /// wartością domyślną: użytkownik zobaczyłby etap „Nowy” albo priorytet
    /// „Zwykłe” dla danych, których wcale tak nie opisano.
    static func decodeToken<Value: ContractTokenRepresentable>(
        _ raw: String,
        as _: Value.Type = Value.self,
        _ what: String
    ) throws -> Value {
        guard let value = Value(contractToken: raw) else {
            throw BackendRepositoryError.decoding("\(what): \(raw)")
        }
        return value
    }
}
