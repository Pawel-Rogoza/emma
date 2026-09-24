import Foundation

// MARK: - Stan wczytywania ekranu
//
// Plik leżał w `App/`, choć nie ma w nim ani jednego odwołania do SwiftUI. Skutek był
// praktyczny: warstwa `App` jest wykluczona z pakietu kompilowanego na Linuksie, więc
// reguły „co pokazać i czy ponowienie ma sens” nie dało się przetestować — a to jest
// logika, nie wygląd. Teraz mieszka w rdzeniu, razem z zasadą `DomainError.isRetryable`.
//
// Każdy ekran ładuje dane przez jedno z trzech stanów. Dzięki temu „brak danych”
// nigdy nie wygląda jak „błąd”, a błąd nigdy jak „pusto” (§13).

public enum LoadPhase<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(LoadFailure)

    public var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Błąd wczytania razem z regułą ponowienia — nie sam tekst.
    public var failure: LoadFailure? {
        if case .failed(let failure) = self { return failure }
        return nil
    }

    public var errorMessage: String? { failure?.message }

    public var hasLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    /// Nieudane wczytanie według jednej zasady dla wszystkich ekranów.
    ///
    /// Review 24.09.2026: pociągnięcie w dół czasem kończyło się ekranem
    /// „Nie udało się wczytać dnia.” i trzeba było odświeżać drugi raz. Przyczyny
    /// były dwie: **anulowane** wczytanie (nakładające się odświeżenia — gest,
    /// powrót z tła, zapis w innym miejscu) było traktowane jak awaria, a nieudane
    /// odświeżenie zastępowało wczytane dane pełnoekranowym błędem.
    ///
    /// Teraz:
    ///   • anulowanie nie zmienia niczego — nowsze wczytanie jest już w drodze,
    ///   • nieudane **odświeżenie** zostawia dane na ekranie i zwraca komunikat
    ///     do pokazania w krótkim powiadomieniu,
    ///   • dopiero nieudane **pierwsze** wczytanie pokazuje stan błędu.
    ///
    /// - Returns: komunikat do pokazania, gdy dane zostały na ekranie; `nil`, gdy
    ///   nie ma czego pokazywać (anulowanie) albo błąd jest już stanem ekranu.
    @discardableResult
    public mutating func recordFailure(_ error: Error, fallback: String) -> String? {
        if ScreenLoad.isCancellation(error) { return nil }
        let failure = ScreenLoad.failure(for: error, fallback: fallback)
        if hasLoaded { return failure.message }
        self = .failed(failure)
        return nil
    }
}

extension LoadPhase: Equatable where Value: Equatable {}

// MARK: - Błąd wczytania

/// Co pokazać po nieudanym wczytaniu i **czy ponowienie ma sens**.
///
/// Powód istnienia osobnego typu: decyzja o ponowieniu należała wcześniej do ekranu.
/// Trzy ekrany pokazywały „Spróbuj ponownie” przy każdym błędzie — także przy konflikcie
/// wersji i braku uprawnień, gdzie domena mówi wprost, że ponowienie nic nie da
/// (`DomainError.isRetryable`, §4.4 i §7) — a dziewięć ekranów nie pokazywało go wcale,
/// więc przy zerwanej sieci użytkownik nie miał czym spróbować ponownie.
public struct LoadFailure: Equatable, Sendable {
    public let message: String
    public let isRetryable: Bool

    public init(message: String, isRetryable: Bool) {
        self.message = message
        self.isRetryable = isRetryable
    }
}

// MARK: - Tłumaczenie błędu na komunikat

/// Jedno miejsce, w którym decydujemy, co użytkownik zobaczy po nieudanym wczytaniu.
///
/// Powód istnienia: ten sam trójkąt `catch let error as DomainError { … } catch { … }`
/// powtarzał się w kilkunastu miejscach. Każda kopia to osobna okazja, żeby jeden
/// ekran zaczął mówić coś innego albo — gorzej — pokazał surowy błąd techniczny.
/// `DomainError` ma własny komunikat bezpieczny; wszystko inne dostaje tekst ekranu.
public enum ScreenLoad {
    /// Anulowanie to decyzja aplikacji (nowsze wczytanie zastąpiło starsze),
    /// a nie awaria — nie może trafić na ekran jako błąd.
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    public static func message(for error: Error, fallback: String) -> String {
        failure(for: error, fallback: fallback).message
    }

    /// Komunikat i reguła ponowienia z jednego miejsca.
    ///
    /// Błąd rozpoznany jako `DomainError` oddaje swoją regułę. Błąd nierozpoznany
    /// dostaje `isRetryable: true` świadomie: nieznany błąd jest zwykle przejściowy,
    /// a ukrycie przycisku odebrałoby jedyną drogę wyjścia z niego.
    public static func failure(for error: Error, fallback: String) -> LoadFailure {
        // Błędy backendu mają własny, bezpieczny komunikat („Sesja wygasła”,
        // treść walidacji z serwera, brak trasy). Wcześniej wszystkie kończyły
        // jako ogólny tekst ekranu i użytkownik nie wiedział, co poszło nie tak.
        if let backendError = error as? BackendRepositoryError {
            return LoadFailure(message: backendError.safeMessage, isRetryable: backendError.isRetryable)
        }
        guard let domainError = error as? DomainError else {
            return LoadFailure(message: fallback, isRetryable: true)
        }
        return LoadFailure(message: domainError.safeMessage, isRetryable: domainError.isRetryable)
    }
}
