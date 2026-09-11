#if canImport(UIKit)
import Foundation

// MARK: - Wybór implementacji usług głosowych
//
// Jedno miejsce decydujące, czy mówimy z dostawcą, czy używamy mocków.
//
// Zasady:
//   • Demo (brak adresu backendu) **nigdy** nie tworzy transportu dostawcy —
//     nie ma tokenu, nie ma sieci, a mock jest deterministyczny (§6, §14).
//   • Adapter dostawcy powstaje dopiero, gdy backend jest skonfigurowany
//     i gdy SDK jest dostępne w buildzie.
//   • Aplikacja nie przechowuje klucza API w żadnym wariancie.

@MainActor
public enum VoiceServicesFactory {

    /// Czy w tym buildzie i konfiguracji można w ogóle użyć dostawcy.
    public static func providerIsAvailable(configuration: AppConfiguration) -> Bool {
        #if canImport(ElevenLabs)
        return configuration.apiBaseURL != nil
        #else
        return false
        #endif
    }

    /// Transport dla nowej sesji rozmowy.
    ///
    /// - Parameters:
    ///   - configuration: konfiguracja aplikacji (Demo nie ma backendu).
    ///   - fixtureName: nazwa scenariusza mocka; używana wyłącznie w Demo.
    public static func makeTransport(
        configuration: AppConfiguration,
        fixtureName: String?,
        accessToken: String?,
        mockScenarioName: String
    ) -> VoiceTransport {
        #if canImport(ElevenLabs)
        if providerIsAvailable(configuration: configuration), let baseURL = configuration.apiBaseURL {
            return ElevenLabsVoiceTransport(
                tokenProvider: BackendConversationTokenProvider(baseURL: baseURL),
                accessToken: accessToken
            )
        }
        #endif
        // Ścieżka domyślna: deterministyczny mock bez sieci i bez mikrofonu.
        return MockVoiceTransport(
            scenario: MockVoiceScenarios.named(mockScenarioName),
            delayProvider: { _ in }
        )
    }

    /// Serwis dyktowania. W Demo dyktowanie jest scenariuszowe, na urządzeniu
    /// korzysta z rozpoznawania mowy systemu.
    public static func makeDictationService(
        configuration: AppConfiguration,
        audioSession: AudioSessionController
    ) -> DictationService {
        if configuration.usesMockServices {
            return MockDictationService()
        }
        return AppleSpeechDictationService(audioSession: audioSession)
    }

    /// Odsłuch.
    ///
    /// Poza Demo odsłuch dostawcy **nie istnieje** — nie ma go w adapterze. Zwracamy
    /// więc mock w obu wariantach, ale mówimy to wprost, zamiast przyjmować parametr
    /// konfiguracji i go ignorować (co sugerowałoby wybór, którego nie ma).
    /// Docelowo odsłuch wskaże ten sam kontroler sesji audio co rozmowa (§5.3).
    public static func makePlaybackService() -> SpeechPlaybackService {
        MockSpeechPlaybackService()
    }
}
#endif
