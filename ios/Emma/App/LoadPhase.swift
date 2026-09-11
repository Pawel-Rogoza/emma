import Foundation

// MARK: - Stan wczytywania ekranu
//
// Każdy ekran ładuje dane przez jedno z trzech stanów. Dzięki temu „brak danych”
// nigdy nie wygląda jak „błąd”, a błąd nigdy jak „pusto” (§13).

public enum LoadPhase<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    public var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }

    public var hasLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
}

extension LoadPhase: Equatable where Value: Equatable {}
