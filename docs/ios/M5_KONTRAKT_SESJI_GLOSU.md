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
