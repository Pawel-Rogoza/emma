import Foundation

// MARK: - Odczyt pojedynczego rekordu jako `LoadPhase`
//
// Arkusze szczegółów (zadanie, termin, wiadomość) robiły `try?` i przy błędzie
// zostawiały `nil`, więc ekran pokazywał „Wczytuję…” bez końca (F16). Ta reguła
// mieszka w rdzeniu — jak `ScreenLoad` — żeby dała się przetestować bez SwiftUI
// i żeby „nie ma” (nieodwracalne) nie wyglądało jak „nie udało się” (ponawialne).

@MainActor
public enum RecordLoading {

    /// Wynik odczytu: rekord, jawny brak rekordu albo błąd z regułą ponowienia.
    ///
    /// - Parameters:
    ///   - missingMessage: komunikat, gdy odczyt się powiódł, ale rekordu nie ma.
    ///     Brak rekordu nie jest ponawialny — ponowienie nic nie zmieni.
    ///   - fallback: komunikat dla błędu nierozpoznanego; błędy domenowe oddają
    ///     własny `safeMessage` i własną regułę `isRetryable`.
    public static func phase<T>(
        missingMessage: String,
        fallback: String,
        fetch: () async throws -> T?
    ) async -> LoadPhase<T> {
        do {
            guard let value = try await fetch() else {
                return .failed(LoadFailure(message: missingMessage, isRetryable: false))
            }
            return .loaded(value)
        } catch {
            return .failed(ScreenLoad.failure(for: error, fallback: fallback))
        }
    }
}
