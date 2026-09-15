# Runbook: Gemini Live jako drugi dostawca rozmowy (i powrót do ElevenLabs)

Stan na 2026-09-15. Dokument opisuje **przełącznik**, nie marketing: co jest
wdrożone, co jest udowodnione, a czego jeszcze nie wiemy.

## 1. Co zostało wdrożone

Dwa repozytoria, jedna umowa: backend wydaje krótkotrwałe poświadczenie,
aplikacja łączy się z Live API bezpośrednio i nie zna żadnego klucza.

**Backend** (`adwokat-app-project`, gałąź `feat/gemini-live-voice`):

| Plik | Rola |
| --- | --- |
| `src/lib/crm/voice/config.ts` | `EMMA_VOICE_PROVIDER`, `GEMINI_API_KEY`, `GEMINI_LIVE_MODEL`, TTL poświadczenia |
| `src/lib/crm/voice/gemini.ts` | instrukcja systemowa Emmy, deklaracje narzędzi, `GeminiLiveClient` (ephemeral token) |
| `src/lib/crm/mobile/voice.ts` | przełącznik dostawcy w `POST /api/mobile/v1/voice/conversation-token` |
| `src/pages/api/mobile/v1/voice/tools/[tool].ts` | wykonanie narzędzia czytającego dla sesji Live API (bearer użytkownika) |
| `.env.example` | opis zmiennych i ostrzeżenie o tierze Free |

**iOS** (`emma`, gałąź `feat/gemini-live-voice`):

| Plik | Rola |
| --- | --- |
| `ios/Emma/Core/Voice/GeminiLiveProtocol.swift` | kodek Live API (bez sieci i UIKit — testowalny) |
| `ios/Emma/Core/Voice/GeminiLiveTurnTracker.swift` | reguły tury → zdarzenia naszego modelu |
| `ios/Emma/Core/Voice/VoiceToolExecuting.swift` | port wykonania narzędzia (implementuje backend) |
| `ios/Emma/VoiceAdapters/GeminiLiveTransport.swift` | WebSocket + AVAudioEngine, jeden adapter dostawcy |
| `ios/Emma/VoiceAdapters/BackendVoiceToolExecutor.swift` | wywołanie narzędzia z bearerem użytkownika |
| `ios/Emma/App/AppConfiguration.swift` | `EMMAVoiceProvider`, `EMMAVoiceModel`, nadpisanie argumentem startu |
| `ios/Emma/VoiceAdapters/VoiceServicesFactory.swift` | jawny wybór dostawcy (bez cichego fallbacku) |

Zasady, które przełącznik zachowuje (te same co dla ElevenLabs):

- **Klucz API tylko na serwerze.** Aplikacja dostaje ephemeral token.
- **Narzędzia wykonuje backend.** Live API zwraca `toolCall`, aplikacja odsyła go
  na `/api/mobile/v1/voice/tools/{tool}`; allowlista, limity i audyt są wspólne.
- **Zapis bez zmian.** `propose_*` kończy się `403` — zapis czeka na bramkę zgody.
- **Instrukcja systemowa i narzędzia w tokenie.** `liveConnectConstraints`
  blokuje model, tryb audio, transkrypcje, instrukcję i deklaracje funkcji.

## 2. Jak włączyć

Backend (`.env` na serwerze lub lokalnie):

```
EMMA_VOICE_PROVIDER=gemini_live
GEMINI_API_KEY=<klucz>
GEMINI_LIVE_MODEL=gemini-3.8-live
```

iOS — jedno z dwóch:

- `ios/Config/Local.xcconfig`: `EMMA_VOICE_PROVIDER = gemini_live`
- albo argument startu w schemacie: `-EMMAVoiceProvider gemini_live`
  (pozwala porównać dostawców na jednym buildzie, bez przebudowy)

**Oba przełączniki muszą wskazywać to samo.** Backend wydaje token wybranego
dostawcy; rozjazd kończy się jawnym błędem (`provider_unavailable` /
nieudane otwarcie gniazda), a nie cichym przełączeniem.

## 3. Jak wrócić (rollback)

```
# backend
EMMA_VOICE_PROVIDER=elevenlabs
# iOS: Config/Local.xcconfig
EMMA_VOICE_PROVIDER = elevenlabs
```

Brak wartości też znaczy `elevenlabs` po obu stronach — usunięcie zmiennej jest
poprawnym rollbackiem. Kod ElevenLabs, SDK, kontrakt `conversation-token`
i trasa narzędzi usługi **nie zostały zmienione**; ścieżka Gemini jest dopisana
obok, nie zamiast.

## 4. Co jest udowodnione, a co nie (stan 2026-09-15)

| Twierdzenie | Dowód |
| --- | --- |
| Kodek wysyła i czyta ramki Live API zgodnie z kontraktem | `swift test` — 20 testów `GeminiLive*`, 0 błędów |
| Reguły tury (przerwanie, transkrypcje, narzędzie) są spójne | tamże, `GeminiLiveTurnTrackerTests` |
| **Transport prowadzi całą sesję po prawdziwym gnieździe WebSocket** | `xcodebuild test` — `GeminiLiveTransportIntegrationTests` (2 testy) przeciw atrapie Live API: uścisk dłoni, tura, obieg narzędzia, wznowienie z uchwytem |
| Kontrakt tokenu czyta oba kształty dostawców (bez `conversation_id` dla Gemini) | `swift test` — `VoiceSessionContractTests` (5 testów) |
| Wywołanie narzędzia idzie trasą mobilną z bearerem użytkownika i nie udaje sukcesu przy odmowie | `xcodebuild test` — `VoiceToolAndAudioTests` (8 testów) |
| Konwersja PCM (16 kHz wejście, 24 kHz wyjście) nie gubi i nie odwraca skali | tamże |
| Przełącznik domyślnie zostaje na ElevenLabs i umie wrócić | `xcodebuild test` — `VoiceProviderSelectionTests` |
| Backend domyślnie zostaje przy ElevenLabs, bez klucza nie woła Gemini | `npm test` — `voice.test.ts` (4 nowe przypadki) |
| Narzędzia Live API są tylko czytające i audytowane | `npm test` — `voiceTools.test.ts` (6 testów) |
| Projekt Xcode się kompiluje z nowym transportem | `xcodebuild build` → `** BUILD SUCCEEDED **` |
| **Po barge-in lokalne audio jest wycofywane** (a nie tylko odnotowane) | `xcodebuild test` — `testServerBargeInStopsLocalPlaybackImmediately` + 2 testy reguł tury |
| Żądanie `auth_tokens` ma właściwą ścieżkę, nagłówek i konfigurację | `npm test` — `gemini.authTokens.http.test.ts` (prawdziwe HTTP do atrapy) |
| **Model odpowiada na żywym kluczu** (transkrypcja, audio, tool call, polski) | **brak dowodu** — spike `GEMINI_LIVE_SPIKE=1 npx vitest run src/lib/crm/voice/gemini.live.test.ts` nie został uruchomiony (brak klucza w `.env`) |
| Rozmowa na urządzeniu brzmi dobrze | **brak dowodu** — wymaga iPhone'a i uszu człowieka |

### Jak uruchomić testy integracyjne transportu

```bash
# 1. atrapy Live API (repo backendu, tam jest `ws`) — jedna zwykła, jedna z goAway
node scripts/fake-live-api.mjs --port 8791
node scripts/fake-live-api.mjs --port 8792 --scenario goaway

# 2. zmienne widoczne dla procesu w symulatorze
xcrun simctl spawn booted launchctl setenv EMMA_FAKE_LIVE_BASE_URL http://127.0.0.1:8791
xcrun simctl spawn booted launchctl setenv EMMA_FAKE_LIVE_BASE_URL_GOAWAY http://127.0.0.1:8792

# 3. testy (bez tych zmiennych same się pomijają — nigdy nie wołają prawdziwego API)
cd ios && xcodebuild test -project Emma.xcodeproj -scheme Emma-Demo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:EmmaTests/GeminiLiveTransportIntegrationTests
```

Atrapa **nie jest** emulatorem Live API i nie zwalnia z punktu 4: dowodzi naszej
strony protokołu, nie zachowania Google.

### Co jeszcze zostało sprawdzone bez klucza

Uruchomienie spike'u z **celowo nieprawidłowym** kluczem (`GEMINI_API_KEY=INVALID_KEY_PROBE`)
potwierdza, że harness jest sprawny, a nie że rozmowa działa:

- sieć do `generativelanguage.googleapis.com` działa (HTTP 400 `API_KEY_INVALID`,
  nie 404 — czyli ścieżka i host są właściwe),
- spike kończy się w ~1,3 s czytelnym błędem (`Gemini API odrzuciło żądanie
  poświadczenia (status 400)`), a nie zawieszeniem,
- w komunikacie nie ma klucza ani treści odpowiedzi dostawcy,
- bez `GEMINI_LIVE_SPIKE=1` testy są pomijane, więc `npm test` nie woła sieci.

### Czego jeszcze nie wiemy (jawne ryzyka)

1. **Blokada konfiguracji w tokenie.** Czy Live API przyjmie `systemInstruction`
   i `tools` wewnątrz `liveConnectConstraints` w kształcie, który wysyłamy —
   rozstrzygnie spike. Jeśli nie, instrukcja i narzędzia przeniosą się do `setup`
   po stronie aplikacji (osobna decyzja, bo osłabia „persona tylko z serwera”).
2. **Wznowienie z uchwytem.** Przy zerwaniu łączymy się ponownie z
   `sessionResumption.handle`, ale token ma zablokowane `sessionResumption: {}`.
   Jeśli serwer odrzuci uchwyt, wznowienie padnie i zobaczymy
   `recoverableError(.networkLost)` + `fatalError(.providerUnavailable)`.
3. **Transkrypcje.** Zakładamy przyrostowe `inputTranscription`/
   `outputTranscription`. Jeśli przyjdą tylko finalne, UI pokaże mniej niż
   obiecuje `capabilities.partialTranscripts` — wtedy trzeba to zmienić na `false`
   (nie udawać).
4. **Przerwanie.** Live API nie ma klientowego „anuluj turę”; zatrzymujemy
   lokalne odtwarzanie i czekamy na `interrupted` z VAD serwera.
   Rozstrzygnięte po naszej stronie: strumień zdarzeń żyje całą sesję (jedna
   kolejka, zdarzenia z `connect` są buforowane), a `goAway` wznawia sesję od
   razu nowym gniazdem z uchwytem i nowym poświadczeniem z backendu.
5. **Tier Free** używa treści do ulepszania produktów Google. Do rozmów z danymi
   klientów wyłącznie tier płatny.

## 4b. Dwa przełączniki: kto mówi i kto myśli

To dwie **niezależne** osie i warto ich nie mieszać:

| Pytanie | Przełącznik | Wartości | Domyślnie |
| --- | --- | --- | --- |
| Kto prowadzi rozmowę głosem? | `EMMA_VOICE_PROVIDER` | `elevenlabs` \| `gemini_live` | `elevenlabs` |
| Kto myśli nad tekstem (agent, briefing)? | `ASSISTANT_PROVIDER` | `openai` \| `qwen` | `openai` |

Włączenie Gemini Live **nie zmienia mózgu tekstowego** — i odwrotnie. Pilnuje tego
test `przełącznik głosu nie przestawia mózgu tekstowego` w backendzie.

Konsekwencja dla pytania „czy Gemini może być mózgiem kancelarii”: na dziś nie,
bo `ASSISTANT_PROVIDER` zna tylko `openai` i `qwen`. Gemini Live jest dostawcą
**głosu**. Żeby zrobić z niego mózg, trzeba osobnej zmiany (nowy provider tekstowy
+ dobór modelu i limitów) — to nie jest przełączenie tej samej flagi.

Co pozostaje wspólne dla obu ścieżek: **dane**. Rozmowa Gemini Live i agent
tekstowy czytają przez ten sam rejestr narzędzi (`emmaReadToolDefinitions`),
z tą samą allowlistą tylko czytającą i tym samym audytem. Fakty o kancelarii są
identyczne niezależnie od tego, kto mówi.

## 5. Co sprawdzić na urządzeniu (pierwsze uruchomienie)

1. Start rozmowy: czy `setupComplete` przychodzi i stan zmienia się na „połączono”.
2. Powiedz „Ile mam dzisiaj zadań?” — czy Emma odpowiada głosem i czy transkrypcja
   pojawia się na bieżąco.
3. Przerwij w połowie zdania — czy dźwięk urywa się natychmiast (barge-in
   po stronie serwera wycofuje lokalną kolejkę audio; sprawdzone testem).
4. Wycisz mikrofon — czy Emma przestaje słyszeć i nie kończy sesji.
5. Poczekaj ~10 minut — czy widać `recoverableError` i czy rozmowa wraca.
6. Nazwiska i sygnatury: „I C 123/26”, „Rogoża”, „Kowalska-Nowak”.
7. Wyłącz i włącz ponownie mikrofon oraz przełącz na AirPods.
8. Po zakończeniu sprawdź, czy odsłuch i dyktowanie znowu działają (sesja audio
   wróciła do aplikacji).

## 6. Koszt (do porównania z rachunkiem ElevenLabs)

Gemini 3.8 Live, tier płatny: audio wejście `$0,005/min`, audio wyjście
`$0,018/min` → **≈ $0,023/min ≈ $1,38/h** plus żetony tekstowe (instrukcja
i kontekst sprawy). Cennik ElevenLabs z Waszego planu podstawić obok — spike
mierzony na Free tierze nie mówi nic o rachunku.
