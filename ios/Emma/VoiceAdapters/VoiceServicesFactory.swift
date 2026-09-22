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
        // Gemini Live nie potrzebuje SDK — wystarczy backend, który wyda
        // krótkotrwałe poświadczenie sesji.
        return configuration.apiBaseURL != nil
    }

    /// Transport dla nowej sesji rozmowy.
    ///
    /// Wybór dostawcy jest **jawny** (`EMMA_VOICE_PROVIDER`), a nie „spróbujmy
    /// zapasowego, gdy główny zawiedzie”. Cicha zmiana dostawcy zmieniałaby też
    /// to, kto przetwarza treść rozmowy. Gdy wybrany dostawca jest niedostępny
    /// (brak backendu), zostaje deterministyczny mock Demo.
    ///
    /// - Parameters:
    ///   - configuration: konfiguracja aplikacji (Demo nie ma backendu).
    ///   - fixtureName: nazwa scenariusza mocka; używana wyłącznie w Demo.
    ///   - installationID: identyfikator instalacji; potrzebny tylko wtedy, gdy
    ///     transport musiałby sam poprosić backend o token rozmowy (ścieżka
    ///     awaryjna — normalnie token przychodzi już w konfiguracji sesji).
    ///   - tokens: źródło tokenu użytkownika z odnawianiem. Gdy go brak, transport
    ///     używa stałego `accessToken` (testy, podglądy).
    public static func makeTransport(
        configuration: AppConfiguration,
        fixtureName: String?,
        accessToken: String?,
        tokens: VoiceAccessTokenSource? = nil,
        installationID: String,
        mockScenarioName: String,
        audioSession: AudioSessionController? = nil
    ) -> VoiceTransport {
        if providerIsAvailable(configuration: configuration), let baseURL = configuration.apiBaseURL {
            let tokens = tokens ?? .fixed(accessToken)
            return GeminiLiveTransport(
                tokenProvider: BackendConversationTokenProvider(baseURL: baseURL),
                toolExecutor: BackendVoiceToolExecutor(baseURL: baseURL, tokens: tokens),
                tokens: tokens,
                installationID: installationID,
                model: configuration.voiceModel,
                audioSession: audioSession
            )
        }
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
    /// W Demo zostaje `MockSpeechPlaybackService`: zdarzenia odtwarzania są
    /// deterministyczne, więc testy nie zależą od tempa mowy. Poza Demo odsłuch
    /// jest **realny** — `SystemSpeechPlaybackService` mówi systemowym
    /// syntezatorem, więc „Odsłuchaj” faktycznie brzmi. Głosu Emmy z dostawcy
    /// nadal nie ma; interfejs tego nie udaje (F05).
    public static func makePlaybackService(
        configuration: AppConfiguration,
        audioSession: AudioSessionController
    ) -> SpeechPlaybackService {
        if configuration.usesMockServices {
            return MockSpeechPlaybackService()
        }
        return SystemSpeechPlaybackService(audioSession: audioSession)
    }
}
#endif
