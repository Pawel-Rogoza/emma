import Foundation

// MARK: - Konfiguracja środowiska
//
// Wartości pochodzą z `Info.plist`, który z kolei jest wypełniany z plików
// `.xcconfig` (Demo/Staging/Production). W repozytorium **nie ma żadnych
// sekretów**: `EMMA_API_BASE_URL` w Demo jest puste, a klucze dostawców
// (ElevenLabs, WhatsApp) nigdy nie trafiają do aplikacji — aplikacja otrzymuje
// wyłącznie token rozmowy wygenerowany przez backend (§5.1, §7.3).

public struct AppConfiguration: Sendable {

    public enum Environment: String, Sendable {
        case demo = "demo"
        case staging = "staging"
        case production = "production"

        public var displayName: String {
            switch self {
            case .demo: return "Demo"
            case .staging: return "Staging"
            case .production: return "Produkcja"
            }
        }
    }

    public let environment: Environment
    /// Adres backendu. Pusty w Demo — aplikacja działa wtedy w pełni lokalnie.
    public let apiBaseURL: URL?
    public let defaultLocale: String
    /// Czy korzystamy z danych przykładowych i mocków zamiast usług zewnętrznych.
    public var usesMockServices: Bool { apiBaseURL == nil }
    /// Czy wolno pokazywać ceny/poziomy/statusy dostawców, których nie zweryfikowano.
    public let showsUnverifiedProviderState: Bool

    public init(
        environment: Environment,
        apiBaseURL: URL?,
        defaultLocale: String,
        showsUnverifiedProviderState: Bool = false
    ) {
        self.environment = environment
        self.apiBaseURL = apiBaseURL
        self.defaultLocale = defaultLocale
        self.showsUnverifiedProviderState = showsUnverifiedProviderState
    }

    /// Odczyt z Info.plist z uwzględnieniem argumentów startowych.
    ///
    /// Argumenty rozpoznawane przy starcie (używane przez testy i podglądy):
    ///   `-EMMAEnvironment demo|staging|production`
    ///   `-EMMAApiBaseURL https://…`
    ///   `--fixture <nazwa>` — wybór zestawu danych demo
    public static func resolve(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppConfiguration {
        var environment = Environment(rawValue: (infoDictionary["EMMAEnvironment"] as? String) ?? "")
            ?? .demo
        var rawBaseURL = (infoDictionary["EMMAApiBaseURL"] as? String) ?? ""
        let locale = (infoDictionary["EMMADefaultLocale"] as? String) ?? "pl-PL"

        if let index = arguments.firstIndex(of: "-EMMAEnvironment"), index + 1 < arguments.count {
            environment = Environment(rawValue: arguments[index + 1]) ?? environment
        }
        if let index = arguments.firstIndex(of: "-EMMAApiBaseURL"), index + 1 < arguments.count {
            rawBaseURL = arguments[index + 1]
        }

        let trimmed = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Demo z adresem backendu jest błędem konfiguracji, nie powodem do awarii:
        // świadomie ignorujemy adres, aby demo nie wykonywało żadnych wywołań sieciowych.
        let baseURL = (environment == .demo || trimmed.isEmpty) ? nil : URL(string: trimmed)

        return AppConfiguration(
            environment: environment,
            apiBaseURL: baseURL,
            defaultLocale: locale,
            showsUnverifiedProviderState: environment != .production
        )
    }

    /// Zestaw danych demo wskazany argumentem `--fixture`.
    public static func fixtureName(arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let index = arguments.firstIndex(of: "--fixture"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Argument `--demo` wymusza dane przykładowe i dzień referencyjny (11.09.2026).
    public static func forcesDemoData(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains("--demo")
    }

    public static var current: AppConfiguration { resolve() }
}
