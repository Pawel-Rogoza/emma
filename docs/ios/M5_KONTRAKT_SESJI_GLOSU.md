# M5 — wiążąca specyfikacja sesji głosu (od użytkownika, 2026-09-14)

Osiem punktów poniżej jest **wymaganiem**, nie propozycją. Każdy ma: treść
wymagania, ustalenie w kodzie i stan.

## 1. Routing: żadnej trasy bez prefiksu

**Wymaganie:** iOS wywołuje `api/mobile/v1/voice/...`. Nie może powstać
przypadkiem `/voice/conversation-token` bez prefiksu.

**Ustalenie w kodzie (potwierdzone):**

- iOS składa adresy jako `baseURL.appendingPathComponent(path)`
  (`BackendAPIClient.makeRequest`), a `Endpoint` ma wartości w rodzaju
  `api/mobile/v1/clients`. Czyli `EMMA_API_BASE_URL` to **sam host**.
- Kontrakt deklarował bazę `https://api.example.invalid/v1` ze ścieżkami
  `/clients` — czyli `…/v1/clients`, czego aplikacja **nigdy nie wywoła**.
  To była realna rozbieżność, nie kosmetyka.

**Zrobione:** `servers:` w kontrakcie to teraz
`https://majkuny.pl/api/mobile/v1` z opisem, że ścieżki są względne, a trasa
backendu **musi** leżeć w `src/pages/api/mobile/v1/…` (plik wyżej tworzy
`/api/voice/…`, którego nginx nie przepuszcza i aplikacja nie woła).

## 2. Pełny cykl sesji

**Wymaganie:** `POST /voice/sessions`, `POST /voice/conversation-token`,
`PATCH /voice/sessions/{id}/context`, `GET /voice/sessions/{id}/status`,
`DELETE /voice/sessions/{id}`.

**Zrobione:** wszystkie pięć są w kontrakcie (28 ścieżek, 35 operacji,
34 schematy, wszystkie `$ref` rozwiązane). `POST /voice/sessions` jest
idempotentny po `session_id` z aplikacji (201 nowa, 200 powtórzona).
`PATCH …/context` **nie pozwala cofnąć wersji** — wersja może tylko rosnąć.

## 3. Własność sesji i kontekstu

**Wymaganie:** sesja należy do uwierzytelnionego użytkownika i instalacji;
każda operacja sprawdza ownership, kontekst sprawy i `context_version`.

**Zrobione w kontrakcie:** `403`, gdy sesja należy do innej instalacji lub
innego użytkownika; `404` dla nieistniejącej; `409` przy niezgodnej wersji
kontekstu w `conversation-token`. **Do zrobienia:** implementacja i testy —
to nie może zostać na poziomie opisu.

## 4. Powiązanie sesji z rozmową, bez sekretów

**Wymaganie:** przy wydaniu tokenu zapisz `mobile_voice_session_id ↔
ElevenLabs conversation_id`. Nie zapisuj ani nie loguj tokenu i `xi-api-key`.

**Do zrobienia:** tabela techniczna sesji transportu z kolumną
`provider_conversation_id`, hash tokenu aplikacji (nie token), bez kolumny na
token dostawcy. Test: po wydaniu tokenu w bazie **nie ma** ciągu tokenu ani
klucza API; logi nie zawierają nagłówka.

## 5. Kształt odpowiedzi tokenu

**Wymaganie:** `{token, conversation_id, context_version}`; bez wymyślania
`expires_at`, bo dostawca nie podaje potwierdzonego czasu (w iOS opcjonalny).

**Ustalenie na żywym API (2026-09-14):** `GET /v1/convai/conversation/token`
zwraca dokładnie `{token, conversation_id}` — **bez** `expires_at`.

**Zrobione:** schemat `ConversationToken` wymaga `token`, `conversation_id`,
`context_version`; `expires_at` jest opcjonalny z opisem, że brak wartości
znaczy „nieznany”, a żywotność pilnuje stan sesji, nie zegar.

## 6. Żadnego mocka w ścieżce transportu

**Wymaganie:** poza Demo aplikacja ma prawdziwe `VoiceSessionRepository`,
realny access token i backendową sesję użytkownika.

**Ustalenie w kodzie — z korektą do Twojego opisu:**

- `AppDependencies` **już** wybiera `BackendRepository`, gdy
  `!configuration.usesMockServices` (`AppDependencies.swift:132`). Mock jest
  wybierany dlatego, że `EMMA_API_BASE_URL` jest **puste** — nie dlatego, że
  brakuje gałęzi.
- `EmmaApp.swift:27` **już** przekazuje `accessTokenProvider:
  { authStore?.accessToken }`. Token jest pusty, bo nie ma zalogowanej sesji
  backendowej (`AuthStore.accessToken` ustawia się dopiero z wyniku logowania).
- `currentUser: { nil }` — **to jest realna luka**: repozytorium nie zna
  użytkownika, więc nie może poprawnie podpisać notatki ani zweryfikować
  własności sesji.
- Protokół `VoiceSessionRepository` istnieje, ale **nie ma metody na token**
  (`create`, `updateContext`, `fetchStatus`, `end`); trzeba ustalić, czy token
  wraca z `create`, czy dochodzi osobna metoda. Nazwy `CreateVoiceSession`
  i `VoiceSessionConfiguration` nie zostały znalezione — protokół odwołuje się
  do typów, które trzeba potwierdzić przy implementacji.

## 7. Tabela techniczna, nie drugi system

**Wymaganie:** nowa tabela jest dopuszczalna jako techniczna tabela sesji
transportu głosu, ale nie tworzy drugiego systemu rozmów, zadań ani akcji.
Historia asystenta i action engine pozostają kanoniczne.

**Zasada:** tabela trzyma wyłącznie: id sesji aplikacji, użytkownika,
instalację, `context_version`, stan, `provider_conversation_id`, znaczniki czasu.
Żadnych treści rozmowy, żadnych zadań, żadnych wniosków o akcje.

## 8. Bramka zdejmowania oznaczeń Demo

**Wymaganie:** nie zdejmować oznaczeń Demo po samym wdrożeniu endpointu.
Dopiero po udanym teście **na urządzeniu**: prawdziwy mikrofon, odpowiedź Qwen
przez ElevenLabs, przerwanie wypowiedzi, mute, zakończenie sesji, logout,
brak sekretów w logach.

**Zasada:** osiem warunków, każdy z dowodem z urządzenia. Do tego czasu
oznaczenia Demo zostają, a M5 nie jest „gotowe” — jest „zaimplementowane”.

---

# Stan wdrożenia (2026-09-14)

## Co jest zrobione — z dowodem

Migracja `044_mobile_voice_sessions.sql` (tabela techniczna: sesja aplikacji,
użytkownik, instalacja, `context_version`, stan, `provider_conversation_id`,
znaczniki czasu; **bez kolumny na token dostawcy**) i pięć tras dokładnie pod
`src/pages/api/mobile/v1/voice/`:

| Trasa | Plik |
| --- | --- |
| `POST /voice/sessions` | `sessions/index.ts` |
| `POST /voice/conversation-token` | `conversation-token.ts` |
| `PATCH /voice/sessions/{id}/context` | `sessions/[session_id]/context.ts` |
| `GET /voice/sessions/{id}/status` | `sessions/[session_id]/status.ts` |
| `DELETE /voice/sessions/{id}` | `sessions/[session_id].ts` |

**Dowód z żywego serwera** (lokalnie, sobowtór dostawcy zamiast prawdziwego
klucza — żeby nie zużywać konta i nie mieszać danych produkcyjnych):

- `POST /api/mobile/v1/voice/sessions` → **201**, `state: active`, wersja 1.
- `POST /api/mobile/v1/voice/conversation-token` → **200**
  `{token, conversation_id: cx-lokalny-1, context_version: 1, session_id}`,
  **bez `expires_at`**.
- `GET …/status` → `active`, rozmowa `cx-lokalny-1`.
- `PATCH …/context` wersja 2 → **200**; cofnięcie na 1 → **409**
  `version_conflict` z `current_version: 2`.
- `DELETE` → **204**; token po zamknięciu → **409**.
- `POST /api/voice/conversation-token` i `/voice/conversation-token` → **404**
  (nie istnieje trasa bez prefiksu — sprawdzone, nie założone).
- W plikach bazy (`crm.sqlite3`, `-wal`, `-shm`) **0** wystąpień tokenu
  i klucza API; w logach aplikacji **0**.
- Wiersz sesji: `ended`, wersja 2, `provider_conversation_id = cx-lokalny-1`.
- Audyt: `mobile.voice_session_open`, `mobile.voice_token`,
  `mobile.voice_context_change`, `mobile.voice_session_end` — metadane bez tokenu
  i bez `conversation_id`.

Testy: `src/lib/crm/mobile/voice.test.ts` → **10/10** (własność: cudzy
użytkownik 403, inna instalacja 403, brak sesji 404; rosnąca wersja; zamknięcie
idempotentne; brak tokenu w bazie i audycie; 503 przy wyłączonym głosie,
awarii dostawcy i braku `conversation_id`). `npx astro check` → 0 błędów.

## Czego jeszcze NIE ma (i nie udaję, że jest)

1. **Warstwa iOS** (punkt 6): `VoiceSessionRepository` nie ma jeszcze metody na
   token; brak realnego `currentUser` w repozytorium; `EMMA_API_BASE_URL` nadal
   puste, więc aplikacja działa na mocku.
2. **Test na urządzeniu** (punkt 8): prawdziwy mikrofon, odpowiedź Qwen przez
   ElevenLabs, przerwanie wypowiedzi, mute, zakończenie sesji, logout, brak
   sekretów w logach. Do tego czasu **oznaczenia Demo zostają**, a M5 jest
   „zaimplementowane”, nie „gotowe”.
3. **Rozmowa naprawdę przez WebRTC** — sprawdziliśmy, że backend wydaje token
   i zapisuje powiązanie; nie sprawdziliśmy jeszcze, że aplikacja wchodzi z nim
   do pokoju i że Emma odpowiada głosem.

---

# Wymagania dodatkowe (od użytkownika, 2026-09-14)

1. **Repozytorium sesji głosu ma pokrywać pełny lifecycle**: `create`
   (otwarcie sesji + token), `updateContext` (zmiana kontekstu), `fetchStatus`
   (stan) i `end` (zakończenie) — wszystkie wołane z realnej ścieżki aplikacji,
   nie jako nieużywane metody.
2. **`EMMA_API_BASE_URL` wyłącznie z `.xcconfig`**, nigdy jako literał w Swift:
   `Local.xcconfig` (w `.gitignore`, dla dewelopera) i `Staging.xcconfig`,
   `Production.xcconfig` dla builda produkcyjnego. `AppConfiguration` tylko
   odczytuje wartość wstrzykniętą.
3. **Test na urządzeniu dopiero po prawdziwym tokenie zalogowanego
   użytkownika.** `accessToken = nil` ani ciche zejście na dane demo nie są
   rozwiązaniem produkcyjnym: brak sesji ma być widoczny jako błąd.
4. **Oznaczenie Demo zostaje** do potwierdzenia przez użytkownika na urządzeniu:
   głos Qwen, polski STT/TTS, przerwanie wypowiedzi, mute, zakończenie sesji,
   brak kluczy w aplikacji i logach. Agent nie może tego potwierdzić za
   użytkownika — raport musi rozdzielać „sprawdzone przeze mnie" od „do
   sprawdzenia na urządzeniu".

---

# Wynik testu na urządzeniu (2026-09-14, iPhone 16 Pro)

Potwierdzone realnym użyciem — nie mockiem:

- Aplikacja wydała `POST /voice/sessions` → **201** i `POST /voice/conversation-token` → **200**;
  backend zapisał powiązanie z prawdziwymi rozmowami u dostawcy
  (`conv_6801m2gxd9cyfb0s49h877pwv6f6`, `conv_8701m2gxd91fe6ar7jr1m9qt7wty`).
- Użytkownik **słyszy głos Emmy** — czyli mikrofon → token → ElevenLabs → odpowiedź działa
  end-to-end. To pierwszy moment, w którym wolno mówić o realnym głosie.
- Log serwera: `GET /clients`, `/tasks`, `/events`, `/cases` → **200** z prawdziwą datą
  `2026-09-14` (wcześniej błędnie `2026-09-11` z `DemoClock`).
- `installation_id` jest jeden i trwały (`620A227E-1F35-41E4-8DAE-987CC3532340`) — 403 zniknął.

Nadal niepotwierdzone (do sprawdzenia przez użytkownika): polskie STT/TTS, przerwanie
wypowiedzi, mute oraz **zakończenie sesji** — obie sesje w bazie pozostają `active`,
brak wpisu `mobile.voice_session_end`. Oznaczenia Demo zostają do czasu potwierdzenia
tych punktów.

## Czego brakuje do „Jarvira"

Agent ElevenLabs nie ma narzędzi podłączonych do backendu, dlatego odpowiada, że nie ma
dostępu do funkcji kancelarii. Kierunek: **jedno kanoniczne narzędziowe źródło prawdy**
(ten sam rejestr narzędzi i ten sam action engine, którego używa panel) wystawione
agentowi jako narzędzia serwerowe (webhooki), z uwierzytelnieniem usługowym
(`EMMA_GATEWAY_SERVICE_SECRET`) i bez kopiowania danych do promptu.

Etapy: (1) odczyt — klienci, sprawy, zadania, terminy, notatki, wątki; (2) działanie —
wnioski o akcję z potwierdzeniem człowieka, idempotencją i audytem; (3) kontekst sprawy
w rozmowie (już mamy `context_version` w sesji).
