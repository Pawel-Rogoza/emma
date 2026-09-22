import Foundation

// MARK: - Wykonanie narzędzia wywołanego przez model
//
// W Live API to **klient** odsyła wynik wywołania funkcji do modelu. Gdyby
// aplikacja wykonywała narzędzia sama, złamalibyśmy zasadę „narzędzia trafiają
// do wspólnego action engine na backendzie” (§5) — a przy zapisach także bramkę
// zgody. Dlatego transport nie zna żadnego narzędzia: przekazuje nazwę i JSON
// argumentów do tego portu, a implementacja (backend) decyduje i audytuje.

public protocol VoiceToolExecuting: Sendable {
    /// Zwraca wynik jako JSON (tekst), gotowy do odesłania modelowi.
    func execute(toolName: String, argumentsJSON: String) async throws -> String
}

public enum VoiceToolExecutionError: Error, Equatable, Sendable {
    /// Brak ważnej sesji użytkownika — rozmowa nie może działać po wylogowaniu.
    case unauthorized
    /// Backend odmówił wykonania (np. narzędzie zapisu bez bramki zgody).
    case forbidden(String)
    case unknownTool(String)
    /// Wynik niepewny: nie udajemy sukcesu i nie ponawiamy automatycznie.
    case failed(String)

    public var safeMessage: String {
        switch self {
        case .unauthorized:
            return "Sesja wygasła. Zaloguj się ponownie, aby Emma mogła korzystać z danych."
        case .forbidden(let reason):
            return reason
        case .unknownTool(let name):
            return "Emma próbowała użyć nieznanego narzędzia (\(name))."
        case .failed(let reason):
            return reason
        }
    }

    /// Czy powtórzenie ma sens (§4.4). Brak uprawnień i nieznane narzędzie — nie.
    public var isRetryable: Bool {
        switch self {
        case .failed: return true
        default: return false
        }
    }
}

// MARK: - Token użytkownika dla warstwy głosu

/// Skąd transport głosu i wykonawca narzędzi biorą token dostępu użytkownika.
///
/// Wcześniej oba typy dostawały **migawkę** tokenu z chwili startu rozmowy.
/// Token dostępu żyje 30 minut, a rozmowa Live API do dwóch godzin (z `goAway`
/// co ~10 minut), więc po pół godzinie wznowienie gniazda i każde wywołanie
/// narzędzia kończyły się 401. Źródło pyta sesję przy każdym użyciu, a po 401
/// może raz wymusić odnowienie — ta sama reguła co w `BackendAPIClient`.
public struct VoiceAccessTokenSource: Sendable {
    /// Ważny (w razie potrzeby odnowiony z wyprzedzeniem) token albo `nil`.
    public let current: @Sendable () async -> String?
    /// Wymuszone odnowienie po 401. `nil` = brak odnowienia (testy, podglądy).
    public let refresh: (@Sendable () async -> String?)?

    public init(
        current: @escaping @Sendable () async -> String?,
        refresh: (@Sendable () async -> String?)? = nil
    ) {
        self.current = current
        self.refresh = refresh
    }

    /// Stały token bez odnawiania — podglądy, testy i ścieżki bez sesji.
    public static func fixed(_ token: String?) -> VoiceAccessTokenSource {
        VoiceAccessTokenSource(current: { token })
    }
}
