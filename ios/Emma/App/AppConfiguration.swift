import Foundation

// MARK: - Konfiguracja środowiska
//
// Wartości pochodzą z `Info.plist`, który z kolei jest wypełniany z plików
// `.xcconfig` (Demo/Staging/Production). W repozytorium **nie ma żadnych
// sekretów**: `EMMA_API_BASE_URL` w Demo jest puste, a klucze dostawców
// Sekrety dostawcy i WhatsApp nigdy nie trafiają do aplikacji — aplikacja
// otrzymuje wyłącznie krótkotrwałe poświadczenie Gemini Live z backendu.

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
    /// Dostawca prowadzący rozmowę głosową. Emma używa wyłącznie Gemini Live.
    public let voiceProvider: VoiceProvider
    /// Model dostawcy głosu. Dla Gemini Live backend przypina model w tokenie,
    /// więc aplikacja musi wysłać w `setup` tę samą nazwę.
    public let voiceModel: String
    /// Czy korzystamy z danych przykładowych i mocków zamiast usług zewnętrznych.
    public var usesMockServices: Bool { apiBaseURL == nil }
    /// Czy wolno pokazywać ceny/poziomy/statusy dostawców, których nie zweryfikowano.
    public let showsUnverifiedProviderState: Bool

    /// Dostawca rozmowy głosowej. Wartości muszą zgadzać się z konfiguracją
    /// backendu (`EMMA_VOICE_PROVIDER`); rozjazd jest wykrywany po odpowiedzi
    /// backendu na token, a nie przemilczany.
    public enum VoiceProvider: String, Sendable {
        case geminiLive = "gemini_live"

        public var displayName: String {
            switch self {
            case .geminiLive: return "Gemini Live"
            }
        }
    }

    public init(
        environment: Environment,
        apiBaseURL: URL?,
        defaultLocale: String,
        voiceProvider: VoiceProvider = .geminiLive,
        voiceModel: String = "gemini-3.8-live",
        showsUnverifiedProviderState: Bool = false
    ) {
        self.environment = environment
        self.apiBaseURL = apiBaseURL
        self.defaultLocale = defaultLocale
        self.voiceProvider = voiceProvider
        self.voiceModel = voiceModel
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
        let rawVoiceProvider = (infoDictionary["EMMAVoiceProvider"] as? String) ?? ""
        let voiceModel = (infoDictionary["EMMAVoiceModel"] as? String) ?? ""

        // Nadpisania z argumentów startowych służą testom i podglądom. W buildzie
        // wydawniczym (TestFlight, App Store) ich nie ma: adres backendu, do
        // którego trafiają hasło i token, pochodzi wyłącznie z konfiguracji.
        #if DEBUG || EMMA_DEMO
        let overrides = arguments
        #else
        let overrides: [String] = []
        #endif
        if let index = overrides.firstIndex(of: "-EMMAEnvironment"), index + 1 < overrides.count {
            environment = Environment(rawValue: overrides[index + 1]) ?? environment
        }
        if let index = overrides.firstIndex(of: "-EMMAApiBaseURL"), index + 1 < overrides.count {
            rawBaseURL = overrides[index + 1]
        }
        // Pozwala porównać dostawców na jednym buildzie (A/B na urządzeniu) bez
        // przebudowywania konfiguracji.
        var rawVoiceProviderOverride = rawVoiceProvider
        if let index = overrides.firstIndex(of: "-EMMAVoiceProvider"), index + 1 < overrides.count {
            rawVoiceProviderOverride = overrides[index + 1]
        }

        // Nieznana lub pusta wartość nie może uruchomić innego dostawcy.
        // Jedyną ścieżką głosową Emmy jest Gemini Live.
        let voiceProvider = VoiceProvider(
            rawValue: rawVoiceProviderOverride.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ) ?? .geminiLive

        let trimmed = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Demo z adresem backendu jest błędem konfiguracji, nie powodem do awarii:
        // świadomie ignorujemy adres, aby demo nie wykonywało żadnych wywołań sieciowych.
        let baseURL = (environment == .demo || trimmed.isEmpty) ? nil : URL(string: trimmed)

        return AppConfiguration(
            environment: environment,
            apiBaseURL: baseURL,
            defaultLocale: locale,
            voiceProvider: voiceProvider,
            voiceModel: voiceModel.isEmpty ? "gemini-3.8-live" : voiceModel,
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
