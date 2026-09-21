# Audyt: Gemini Live jako transport głosu w Emmie (stan 2026-09-15/16, noc)

Ten dokument jest **materiałem do audytu zewnętrznego**. Zawiera stan faktyczny,
dowody, otwarte błędy i komendy do ich odtworzenia. Nie zawiera żadnych sekretów
(klucze, hasła, tokeny) — celowo, bo dokument ma trafić do innego modelu.

## 1. Co budujemy i po co

Aplikacja „Emma” (kancelaria adwokacka) ma warstwę głosu za protokołem
`VoiceTransport`. Do tej pory działał jeden dostawca: **ElevenLabs** (przez SDK
LiveKit/WebRTC) plus osobny „mózg” tekstowy (Qwen/OpenAI) po stronie backendu.
Cel zmiany: dołożyć **drugi transport — Gemini Live (speech-to-speech)** tak, żeby:

- przełączenie w obie strony było **jedną zmianą konfiguracji**,
- ElevenLabs + Qwen zostały jako domyślna, w pełni działająca ścieżka i backup,
- klucz dostawcy nigdy nie trafiał do aplikacji (backend wydaje krótkotrwałe
  poświadczenie — ephemeral token).

**Ważne rozróżnienie:** Gemini Live nie zastępuje „mózgu”. To dwa niezależne
przełączniki:

| Przełącznik | Wartości | Co zmienia |
| --- | --- | --- |
| `EMMA_VOICE_PROVIDER` | `elevenlabs` (domyślnie) / `gemini_live` | kto mówi i słucha (transport) |
| `ASSISTANT_PROVIDER` | `openai` / `qwen` | kto myśli (tekst) |

Rozjazd przełączników (backend wydaje token jednego dostawcy, aplikacja oczekuje
drugiego) jest dziś możliwy i **zgłaszany niejasnym błędem** — to jedna z rzeczy
do naprawy (punkt 5.3).

## 2. Co jest wdrożone i gdzie

### 2.1 Backend — `github.com/Pawel-Rogoza/adwokat-app-project`

- gałąź `main`, HEAD **`29324c4`**, wypchnięte, **wdrożone na produkcję**
  (release `29324c4153ff`, usługa `adwokat-app` aktywna, strona `200`).
- wcześniejsze commity tej funkcji: `4df2250`, `ed4f8ad`, `cbc6c17`, `44ea204`,
  `6e31650`, `0e83dad` (warstwa Gemini), `f92634a` (triaż gitleaks), `29324c4`
  (naprawa atrapy Live API).
- kluczowe pliki: `src/lib/crm/voice/gemini.ts` (token, `fieldMask`, `setup`,
  schematy narzędzi), `src/lib/crm/voice/config.ts`, `src/lib/crm/mobile/voice.ts`,
  `src/pages/api/mobile/v1/voice/conversation-token.ts`,
  `src/pages/api/mobile/v1/voice/tools/[tool].ts`, `scripts/fake-live-api.mjs`.

### 2.2 Aplikacja iOS — `github.com/Pawel-Rogoza/emma`

- gałąź **`feat/gemini-live-voice`**, HEAD **`6d378f0`**, wypchnięta (nowa gałąź).
  Commity: `f998da3` (zamknięcie aplikacji), `41c3f26` (AEC — wycofane
  funkcjonalnie w `6d378f0`), `6d378f0` (półdupleks).
- kluczowe pliki: `ios/Emma/VoiceAdapters/GeminiLiveTransport.swift`,
  `ios/Emma/Core/Voice/GeminiLiveProtocol.swift`,
  `ios/Emma/Core/Voice/GeminiLiveTurnTracker.swift`,
  `ios/Emma/Core/Data/BackendAPIClient.swift` (`BackendVoiceSessionDTO`,
  `BackendConversationTokenDTO`),
  `ios/Emma/VoiceAdapters/BackendConversationTokenProvider.swift`.

### 2.3 Produkcja na VPS (stan faktyczny, sprawdzony)

| Fakt | Wartość |
| --- | --- |
| Host | `s1.sudormrf.pl` = `178.104.190.220`, port SSH **2137** |
| Konto do pracy | **`captain`** (nie `tomek`), klucz `~/.ssh/sudormrf_ed25519`, `sudo -n` działa |
| Katalog źródeł i `.env` | `/home/tomek/apps/website/adwokat-app-project` |
| Katalog wydań | `/home/tomek/apps/website/adwokat-releases` (`current` → `releases/<hash>`) |
| Usługa | `adwokat-app` (systemd, `User=tomek`, nasłuch `127.0.0.1:4321`) |
| Baza CRM | `/home/tomek/apps/website/crm-data/crm.sqlite3` (SQLite, WAL) |
| Przełącznik głosu | `EMMA_VOICE_PROVIDER=gemini_live` **włączony** (`.env`, linia 59) |
| Kopia `.env` przed zmianą | `.env.bak-20260915-231200` (prawa `600`) |
| Rollback | `EMMA_VOICE_PROVIDER=elevenlabs` (lub usunięcie linii) + `sudo systemctl restart adwokat-app` |

Klucz Gemini **już był** w `.env` na VPS (ten sam co lokalnie, zweryfikowane
skrótem SHA-256) i działa — `POST /v1beta/auth_tokens` zwraca `200`.

**Uwaga operacyjna:** przełącznik jest **globalny** — obejmuje wszystkich
użytkowników aplikacji, nie tylko osobę testującą. To ma skutki opisane w 5.2.

## 3. Co jest udowodnione (z dowodami)

| Twierdzenie | Dowód |
| --- | --- |
| Kontrakt `setup`/`fieldMask`/schematów narzędzi jest zgodny z v1beta | spike na żywym kluczu: `GEMINI_LIVE_SPIKE=1 npx vitest run src/lib/crm/voice/gemini.live.test.ts` → 3/3 |
| Model odpowiada głosem po polsku | spike: „Jestem Emma, asystentka w kancelarii adwokackiej…”, audio 24 kHz (~250 kB) |
| Narzędzia działają (function calling) | spike: `get_today_overview` → po `FunctionResponse` odpowiedź głosem |
| Czas do pierwszego audio | **652 ms** (tura tekstowa), **717 ms** (po `FunctionResponse`) |
| Żądanie poświadczenia ma właściwą ścieżkę i nagłówek | `npm test` → `gemini.authTokens.http.test.ts` |
| Aplikacja łączy się ze ścieżką `BidiGenerateContent**Constrained**` i parametrem `access_token` | testy integracyjne na atrapie + kontrola stanu atrapy |
| Transport prowadzi całą sesję po prawdziwym WS | `xcodebuild test -only-testing:EmmaTests/GeminiLiveTransportIntegrationTests` → 3/3 (uścisk dłoni, obieg narzędzia, barge-in, wznowienie po `goAway`) |
| Testy logiki aplikacji | `xcodebuild test -only-testing:EmmaTests` → **433/433**, 3 pominięte (integracyjne bez env) |
| Testy backendu | `npm test` → 955/0 (+3 pominięte); `astro check` 0 błędów/0 ostrzeżeń |
| Sesja na urządzeniu z Gemini faktycznie się otworzyła | `audit_log`: `mobile.voice_session_open` + `mobile.voice_token {"provider":"gemini_live","model":"gemini-3.8-live"}` (21:30:37Z), sesja zamknięta czysto 21:30:54Z |

## 4. Trzy błędy znalezione i naprawione dzisiaj

### 4.1 Aplikacja zamykała się po dotknięciu „rozmawiaj”

Trzy raporty awarii z tego samego wieczoru (`Emma-2026-09-15-231859.ips`,
`…231915.ips`, `…231936.ips`) mają **identyczny podpis**:

```
EXC_BREAKPOINT (SIGTRAP) → _dispatch_assert_queue_fail   (Swift Concurrency)
  closure #1 in GeminiLiveTransport.startAudio()
  ← AVAudioNodeTap::TapMessage::RealtimeMessenger_Perform()   (wątek audio)
```

Przyczyna: domknięcie tapu mikrofonu powstawało w metodzie `@MainActor`, więc
**dziedziczyło izolację aktora**; Swift 6 sprawdzał wykonawcę przy pierwszym
buforze i zatrzymywał proces. Nietykanie `self` w domknięciu nie wystarcza.
**Ten sam błąd naprawiono dzień wcześniej w dyktowaniu tekstu**
(`AppleSpeechDictationService`, raporty `Emma-2026-09-15-124650.ips` i `…150540.ips`).

Naprawa (`f998da3`): jawne `@Sendable` + `nonisolated static makeInputTapBlock(...)`.
Guard: `testInputTapBlockRunsOffMainThread` woła to samo domknięcie z kolejki w tle;
przy przywróceniu `@MainActor` zestaw **nie kompiluje się** (sprawdzone).
Symulator tego błędu **nie odtwarza** (tam tap trafia na kolejkę główną).

### 4.2 Pętla akustyczna (Emma słyszała samą siebie)

Po naprawie 4.1 rozmowa ruszyła, ale model słyszał własny głos z głośnika
i odpowiadał sam sobie. Pierwsza próba naprawy — systemowe kasowanie echa
(`engine.inputNode.setVoiceProcessingEnabled(true)`, commit `41c3f26`) — została
**wycofana**, bo na urządzeniu `VoiceProcessingIO`:

- wyciął mowę użytkownika („w ogóle nie notuje mojego dźwięku”),
- zdegradował głos modelu („odpowiada robotycznie”).

Rozwiązanie przyjęte (`6d378f0`): **półdupleks w `MicrophoneGate`** — mikrofon
zamknięty na czas odtwarzania + 250 ms ogona; koniec odtwarzania liczony od
**końca kolejki** (porcje przychodzą szybciej niż realne odtwarzanie);
`releasePlayback()` przy przerwaniu oddaje mikrofon natychmiast; wyciszenie
użytkownika nadrzędne. 4 testy jednostkowe bramki.

**Koszt nazwany wprost:** nie da się przerwać Emmy głosem w połowie jej zdania.
To świadomy kompromis — pełny dupleks (AEC) wymaga najpierw pomiaru z urządzenia,
czy tap dostarcza próbki i jaki jest poziom (patrz 6.1).

### 4.3 Test-zombie w atrapie (nie dotyczy produktu)

`scripts/fake-live-api.mjs` miał wpisaną na sztywno
`expires_at: '2026-09-15T21:30:00.000Z'`, więc po 23:30 test wznowienia zaczął
failować z `expiresInPast`, mimo że kod był bez zmian. Naprawione (`29324c4`):
atrapa liczy czas względny.

## 5. OTWARTY BŁĄD (najważniejszy punkt tego audytu)

### 5.1 Objaw

Użytkownik na telefonie zobaczył komunikat (sens):

```
Nie udało się odczytać danych z backendu: …
DecodingError.keyNotFound "conversation_id" not found in keyed decoding container
```

Komunikat pochodzi z mapowania błędów w `ios/Emma/Core/Data/BackendAPIClient.swift:46`.

### 5.2 Analiza (fakty, nie domysły)

1. W **obecnym źródle** aplikacji `conversation_id` jest w
   `BackendConversationTokenDTO` polem **opcjonalnym**
   (`ios/Emma/Core/Data/BackendAPIClient.swift:826-849`), a kontrakt obu
   dostawców ma testy: `VoiceSessionContractTests` (kształt ElevenLabs z
   `conversation_id` bez `expires_at`; kształt Gemini z `expires_at` bez
   `conversation_id`). **Build z obecnego źródła nie może wygenerować tego błędu.**
2. Wniosek: komunikat pochodzi z **innego binarium** niż obecne źródło — bardzo
   prawdopodobnie ze **starszej, produkcyjnej aplikacji** (`pl.kancelaria.emma`,
   widoczna na telefonie obok nowej) zbudowanej przed pracami nad Gemini, w której
   dekoder wymagał `conversation_id` na sztywno. Zainstalowana jest obok nowej
   aplikacji testowej `pl.kancelaria.emma.staging` (nazwa na ekranie: „Emma Gemini”).
3. Dlaczego to wyszło **teraz**: przełącznik `EMMA_VOICE_PROVIDER=gemini_live` jest
   **globalny**, więc backend wydaje teraz token Gemini każdemu klientowi —
   także starszej aplikacji, która oczekuje tokenu ElevenLabs z `conversation_id`.
   To dokładnie ryzyko „globalnego przełącznika” z punktu 2.3.
4. Dodatkowo w aplikacji **nie ma walidacji zgodności dostawcy**: token DTO niesie
   `provider`/`model`, ale `BackendVoiceSessionRepository.create()` ich nie
   porównuje z wybranym transportem, więc rozjazd objawia się jako surowy błąd
   dekodowania/kolejki zamiast czytelnego komunikatu.

### 5.3 Co sprawdzić i naprawić (propozycja dla audytu)

- Potwierdzić, z którego binarium pochodzi błąd: który bundle dotknięto
  (`pl.kancelaria.emma` vs `pl.kancelaria.emma.staging`) — np. przez odtworzenie
  żądania i porównanie z historią źródeł:
  `git log -S 'conversation_id' --oneline -- ios/Emma/Core/Data/BackendAPIClient.swift`.
- Odtworzyć odpowiedź backendu (komenda niżej) i porównać z dekoderem.
- Zaproponowana naprawa docelowa: **walidacja dostawcy po stronie klienta**
  (`provider` z tokenu ≠ wybrany transport → czytelny błąd), plus decyzja
  produktowa: czy stary klient ma dalej działać (wersjonowanie kontraktu /
  utrzymanie `conversation_id` w odpowiedzi także dla Gemini jako `null`),
  czy wymagamy aktualizacji aplikacji.
- Natychmiastowy środek zaradczy (jeśli starsi klienci mają działać):
  rollback VPS na `elevenlabs` (jedna linia + restart) albo równoległe wydawanie
  obu tokenów — do decyzji właściciela.

### 5.4 Komendy do odtworzenia (bez sekretów; hasło i klucz ma właściciel)

```bash
# 1. Login (hasło właściciela w zmiennej środowiskowej, nie w historii powłoki)
TOKEN=$(printf '{"email":"…","password":"%s","installation_id":"audyt-1"}' "$PASS" \
  | curl -s -X POST https://advokat-varshava.pl/api/mobile/v1/auth/login \
      -H 'Content-Type: application/json' --data @- | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

# 2. Sesja głosu — UWAGA: zapis wymaga klucza idempotencji
SID=$(python3 -c 'import uuid;print(uuid.uuid4())')
printf '{"session_id":"%s","installation_id":"audyt-1","context_version":1}' "$SID" \
  | curl -s -X POST https://advokat-varshava.pl/api/mobile/v1/voice/sessions \
      -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
      -H "Idempotency-Key: audyt-$SID" --data @- | python3 -m json.tool | head -20

# 3. Poświadczenie rozmowy — porównać KLUCZE odpowiedzi z dekoderem
printf '{"session_id":"%s","installation_id":"audyt-1","context_version":1}' "$SID" \
  | curl -s -X POST https://advokat-varshava.pl/api/mobile/v1/voice/conversation-token \
      -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
      -H "Idempotency-Key: audyt-$SID" --data @- \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(sorted(d.keys()));print(d.get("provider"),d.get("model"))'
```

(Uwaga z sesji diagnostycznej: pierwsze wywołanie bez nagłówka
`Idempotency-Key` kończy się `422`, a kolejne `404` — dlatego klucz jest w
komendach.)

## 6. Otwarte tematy (poza błędem 5)

1. **Pełny dupleks / AEC** — wrócić tylko z pomiarem z urządzenia: czy tap
   dostarcza próbki i jaki jest poziom, z AEC i bez. Symulator tego nie pokaże.
2. **Wznowienie po ~10 minutach** (`goAway` + uchwyt) — sprawdzone na atrapie i na
   żywym API tylko w części (serwer przysyła uchwyt); pełna rozmowa 10-minutowa
   jeszcze nie odbyta.
3. **Dobór głosu Gemini** — backend **nie ustawia** `speechConfig`, więc leci głos
   domyślny. Można wybrać głos przez
   `generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName`.
   To najprawdopodobniej główne źródło wrażenia „robotyczności” (obok jakości
   24 kHz mono w porównaniu z ElevenLabs).
4. **Tier darmowy Gemini** używa treści do ulepszania produktów Google —
   na produkcji z danymi kancelarii to wymaga decyzji (płatny tier).
5. **Bramka Security (gitleaks)** — fałszywe trafienie w testach triażowane
   (`f92634a`), ale pozostaje czerwone `npm audit` w prod deps (7 podatności,
   `npm audit fix`).
6. **Higiena sekretów** — klucz Gemini pojawił się w transkrypcie jednej sesji
   (wypisany przez `grep`), zalecana rotacja po testach. Hasło testowe konta
   `pawrogozas@gmail.com` zostało ustawione skryptem `scripts/mobile-set-password.mjs`
   (wpis `mobile.password_set` w `audit_log`) — do zmiany po testach.

## 7. Jak odtworzyć środowisko testowe

### 7.1 Aplikacja na urządzeniu

```bash
cd ios
# UWAGA: build na urządzenie wymaga schematu Emma-Staging i BEZ -configuration Debug
xcodebuild build -project Emma.xcodeproj -scheme Emma-Staging \
  -destination 'id=<UDID iPhone 16 Pro>' \
  -derivedDataPath /tmp/emma-device-staging -allowProvisioningUpdates
xcrun devicectl device install app --device <UDID> \
  /tmp/emma-device-staging/Build/Products/Staging-iphoneos/Emma.app
```

Konfiguracja lokalna (gitignored): `ios/Config/Local.xcconfig` —
`EMMA_API_BASE_URL = https:/$()/advokat-varshava.pl`,
`EMMA_VOICE_PROVIDER = gemini_live`, `EMMA_DEVELOPMENT_TEAM = QZ25N94YZ8`.

### 7.2 Testy integracyjne transportu (atrapy Live API)

```bash
# repo backendu
node scripts/fake-live-api.mjs --port 8791 &
node scripts/fake-live-api.mjs --port 8792 --scenario goaway &
xcrun simctl spawn booted launchctl setenv EMMA_FAKE_LIVE_BASE_URL http://127.0.0.1:8791
xcrun simctl spawn booted launchctl setenv EMMA_FAKE_LIVE_BASE_URL_GOAWAY http://127.0.0.1:8792
cd ios && xcodebuild test -project Emma.xcodeproj -scheme Emma-Demo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:EmmaTests/GeminiLiveTransportIntegrationTests
```

### 7.3 Zrzut raportów awarii z urządzenia

```bash
xcrun devicectl device copy from --device <UDID> \
  --domain-type systemCrashLogs --source . --destination /tmp/crashlogs
```

## 8. Czego ten dokument nie rozstrzyga

- **Czy głos Gemini da się doprowadzić do jakości ElevenLabs** — prawdopodobnie nie
  w pełni (24 kHz mono, model zoptymalizowany pod opóźnienie). Wymaga decyzji:
  czy akceptujemy gorsze brzmienie za prostszą architekturę i polskiego
  speech-to-speech.
- **Czy półdupleks jest akceptowalny produktowo** (brak przerywania głosem).
- **Czy stary klient ma dalej działać** przy globalnym przełączniku (punkt 5.3).
