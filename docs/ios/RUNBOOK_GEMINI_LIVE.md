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

> **Stan na 2026-09-15 23:12 (produkcja).** Przełącznik jest **włączony**:
> `EMMA_VOICE_PROVIDER=gemini_live` w `/home/tomek/apps/website/adwokat-app-project/.env`
> (kopia przed zmianą: `.env.bak-20260915-231200`, prawa 600). Klucz `GEMINI_API_KEY`
> był tam już wcześniej i jest ten sam co lokalnie. Po restarcie proces ma
> `EMMA_VOICE_PROVIDER=gemini_live`, wydanie `releases/f92634a3cb0b` zawiera kod
> Gemini. Rollback to jedno słowo (`elevenlabs`) plus `sudo systemctl restart adwokat-app`.
> Uwaga: przełącznik jest **globalny** — obejmuje wszystkich użytkowników aplikacji.

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
| **Model odpowiada na żywym kluczu** (transkrypcja, audio, tool call, polski) | spike `GEMINI_LIVE_SPIKE=1 npx vitest run src/lib/crm/voice/gemini.live.test.ts` — 3/3 przechodzi; szczegóły i czasy poniżej |
| **Aplikacja nie zamyka się po dotknięciu „rozmawiaj”** | raporty awarii `Emma-2026-09-15-231859/231915/231936.ips` (identyczny podpis) → naprawa `@Sendable` w tle tapu + test `testInputTapBlockRunsOffMainThread` |
| Rozmowa na urządzeniu brzmi dobrze | **brak dowodu** — wymaga iPhone'a i uszu człowieka |

### Dlaczego aplikacja zamykała się przy „rozmawiaj” (naprawione 2026-09-15)

Trzy raporty awarii z 23:18–23:19 mają **ten sam podpis**, więc to jeden błąd, a nie
trzy:

```
EXC_BREAKPOINT (SIGTRAP) → _dispatch_assert_queue_fail   (Swift Concurrency)
  closure #1 in GeminiLiveTransport.startAudio()
  ← AVAudioNodeTap::TapMessage::RealtimeMessenger_Perform()   (wątek audio)
```

Tap mikrofonu biegnie na wątku czasu rzeczywistego (`RealtimeMessenger.mServiceQueue`).
Domknięcie tapu było tworzone wewnątrz metody `@MainActor`, więc **dziedziczyło
izolację aktora** — Swift 6 sprawdzał wykonawcę przy pierwszym buforze i zatrzymywał
proces. Samo nietykanie `self` w domknięciu nie wystarcza; liczy się izolacja samego
domknięcia.

Naprawa: domknięcie dostaje jawne `@Sendable` (to zdejmuje izolację) i powstaje
w `nonisolated static func makeInputTapBlock(...)`, żeby dało się je wywołać z wątku
tła w teście. **Ta sama pułapka została naprawiona dzień wcześniej w dyktowaniu
tekstu** (`AppleSpeechDictationService`, raporty z 12:46 i 15:05) — wniosek z tamtej
naprawy nie został wtedy zastosowany do nowego transportu.

Dwie rzeczy warte zapamiętania:

- **Symulator tego nie odtwarza.** Tam tap trafia na kolejkę główną, więc testy
  integracyjne przechodziły, a telefon się zamykał. Wniosek: ścieżkę audio
  weryfikujemy na urządzeniu, nie tylko w symulatorze.
- **Guard działa w symulatorze**, bo `dispatch_assert_queue` pyta o wykonawcę,
  a nie o platformę: `testInputTapBlockRunsOffMainThread` woła to samo domknięcie
  z kolejki w tle. Sprawdzone doświadczalnie — po przywróceniu `@MainActor` na
  fabryce zestaw przestaje się kompilować (`main actor-isolated static method …
  cannot be called from outside of the actor`).

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

### Co potwierdził żywy klucz (2026-09-15)

Spike z prawdziwym kluczem (`GEMINI_LIVE_SPIKE=1 … gemini.live.test.ts`) przechodzi
w trzech punktach. Wysyła w `setup` dokładnie to, co aplikacja (model +
`sessionResumption: {}`), więc dowodzi tej samej ścieżki, którą pójdzie telefon:

- `auth_tokens` przyjmuje blokadę sesji razem z `systemInstruction` i `tools`
  (~0,5 s), czyli persona Emmy naprawdę jest zablokowana po stronie serwera,
- tura tekstowa wraca jako polska transkrypcja **i** audio 24 kHz
  („Jestem Emma, asystentka w kancelarii adwokackiej. W czym mogę Ci dzisiaj
  pomóc?” + 250 562 B) — **pierwsze audio po 652 ms**,
- model wywołuje prawdziwe narzędzie (`get_today_overview`) i po
  `FunctionResponse` odpowiada głosem („Na dzisiaj masz zaplanowane spotkanie
  z klientem o godzinie dziesiątej trzydzieści.” + 253 442 B, pierwsze audio
  po 717 ms).

Trzy rzeczy, które przechodziły wszystkie testy i atrapę, a **nie działały** na
prawdziwym API (opis napraw i źródeł: `docs/emma/GEMINI_LIVE_KONTRAKT.md`
w repo backendu):

1. blokada jedzie w `bidiGenerateContentSetup` + `fieldMask`, a nie
   w `liveConnectConstraints` — bieżące `v1beta` nie zna tego drugiego pola,
2. schematy narzędzi muszą mieścić się w polach `Schema` z v1beta
   (`additionalProperties` z JSON Schema kończy się `400`),
3. `properties` trzeba konwertować jako mapę nazwa → schemat, inaczej `required`
   wskazuje nieistniejące pola i sesja zamyka się kodem `1007` **przed**
   `setupComplete` (z telefonu wygląda to jak „serwer milczy”).

Do tego dwie rzeczy, które wynikają z protokołu i są już odzwierciedlone w kodzie:

- aplikacja łączy się ze ścieżką **`BidiGenerateContentConstrained`**
  i parametrem **`access_token`** (nie `key` — tym posługuje się klucz API);
  test integracyjny sprawdza to na atrapie bez klucza,
- o wznowienie trzeba **poprosić w pierwszym `setup`** (`sessionResumption: {}`),
  bo serwer przysyła uchwyt tylko na życzenie; dlatego `sessionResumption` jest
  poza maską tokenu — uchwyt zna tylko aplikacja.

Uruchomienie spike'u z **celowo nieprawidłowym** kluczem
(`GEMINI_API_KEY=INVALID_KEY_PROBE`) nadal jest przydatne jako próba harnessu:

- sieć do `generativelanguage.googleapis.com` działa (HTTP 400 `API_KEY_INVALID`,
  nie 404 — czyli ścieżka i host są właściwe),
- spike kończy się w ~1,3 s czytelnym błędem (`Gemini API odrzuciło żądanie
  poświadczenia (status 400)`), a nie zawieszeniem,
- w komunikacie nie ma klucza ani treści odpowiedzi dostawcy,
- bez `GEMINI_LIVE_SPIKE=1` testy są pomijane, więc `npm test` nie woła sieci.

### Czego jeszcze nie wiemy (jawne ryzyka)

1. **Blokada konfiguracji w tokenie — rozstrzygnięte.** `systemInstruction`
   i `tools` są przyjmowane i faktycznie obowiązują: spike dostał odpowiedź
   w osobie Emmy, choć aplikacja nie wysyła ani instrukcji, ani narzędzi.
   Persona zostaje „tylko z serwera”.
2. **Wznowienie z uchwytem — częściowo rozstrzygnięte.** Serwer przysyła
   `sessionResumptionUpdate` z uchwytem, gdy klient o niego poprosi w `setup`
   (sprawdzone na żywym API). Sama **podmiana** uchwytu po `goAway` jest
   sprawdzona tylko na atrapie (`GeminiLiveTransportIntegrationTests`) — na
   żywym API wymaga dziesięciu minut rozmowy i jest w punkcie 5.7.
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

Czego **nie** sprawdzi spike: jakości polskiego głosu w słuchawce, latencji
odczuwanej w rozmowie, pracy mikrofonu i wznowienia po dziesięciu minutach.
To wymaga telefonu i ucha człowieka — poniżej lista.

1. Start rozmowy: czy `setupComplete` przychodzi i stan zmienia się na „połączono”
   (na żywym API `setupComplete` przychodzi ~0,8 s po otwarciu gniazda; spike to
   potwierdza, telefon musi potwierdzić, że słychać to samo).
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
