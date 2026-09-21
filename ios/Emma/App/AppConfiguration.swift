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
    /// Który dostawca prowadzi rozmowę głosową. **Domyślnie ElevenLabs**:
    /// brak wartości w konfiguracji nie może przełączyć dostawcy, bo zmienia to
    /// także to, kto przetwarza treść rozmowy.
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
        case elevenlabs
        case geminiLive = "gemini_live"

        public var displayName: String {
            switch self {
            case .elevenlabs: return "ElevenLabs"
            case .geminiLive: return "Gemini Live"
            }
        }
    }

    public init(
        environment: Environment,
        apiBaseURL: URL?,
        defaultLocale: String,
        voiceProvider: VoiceProvider = .elevenlabs,
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

        if let index = arguments.firstIndex(of: "-EMMAEnvironment"), index + 1 < arguments.count {
            environment = Environment(rawValue: arguments[index + 1]) ?? environment
        }
        if let index = arguments.firstIndex(of: "-EMMAApiBaseURL"), index + 1 < arguments.count {
            rawBaseURL = arguments[index + 1]
        }
        // Pozwala porównać dostawców na jednym buildzie (A/B na urządzeniu) bez
        // przebudowywania konfiguracji.
        var rawVoiceProviderOverride = rawVoiceProvider
        if let index = arguments.firstIndex(of: "-EMMAVoiceProvider"), index + 1 < arguments.count {
            rawVoiceProviderOverride = arguments[index + 1]
        }

        // Nieznana wartość dostawcy nie przełącza rozmowy „na wszelki wypadek”:
        // zostaje ElevenLabs, a rozjazd z backendem wyjdzie na jaw przy tokenie.
        let voiceProvider = VoiceProvider(
            rawValue: rawVoiceProviderOverride.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ) ?? .elevenlabs

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
