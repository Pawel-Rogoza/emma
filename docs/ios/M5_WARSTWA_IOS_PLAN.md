# M5 — warstwa iOS głosu: plan wdrożenia (decyzje podjęte 2026-09-14)

Backend M5 jest wdrożony i sprawdzony na produkcji. Ten dokument opisuje
warstwę aplikacji, która ma się z nim połączyć. Decyzje użytkownika:
`EMMA_API_BASE_URL` przełączamy **teraz**, Qwen zostaje **w ElevenLabs**
(backend wydaje tylko token), build idzie przez **TestFlight wewnętrzny**.

## Ustalenia w kodzie

- `VoiceSessionRepository` (protokół) ma: `create`, `updateContext`,
  `fetchStatus`, `end` — **bez metody na token**.
- `VoiceSessionConfiguration` **już** niesie `conversationToken`
  („Krótkotrwałe poświadczenie wydane przez backend. **Nigdy** klucz API”)
  oraz `providerConversationID`.
- `VoiceSessionConfiguration.expiresAt` i `VoiceSessionStatus.expiresAt` są
  **nieopcjonalne** (`Date`) — a dostawca nie podaje potwierdzonego czasu
  wygaśnięcia. Trzeba je zmienić na `Date?`; inaczej kod musiałby wymyślać
  datę, czego zakazaliśmy.
- `BackendRepository` ma te cztery metody jako `notAvailableInBackend`.
- `AppDependencies` wybiera `BackendRepository` już teraz, gdy backend jest
  skonfigurowany; `EmmaApp` przekazuje `accessTokenProvider`
  z `AuthStore`. Blokadą był pusty `EMMA_API_BASE_URL`.

## Kolejność prac

1. **Klient HTTP zapisu**: dodać do `BackendAPIClient` metody `post`/`patch`/`delete`
   z `Idempotency-Key` i obsługą `409`/`422` kontraktu (dziś są tylko odczyty).
   Bez tego ani głos, ani zapisy nie mają czym gadać z backendem.
2. **`BackendVoiceSessionRepository`** (nowy plik), mapowanie 1:1 na kontrakt:
   | Metoda | Trasy |
   | --- | --- |
   | `create` | `POST /voice/sessions`, zaraz potem `POST /voice/conversation-token` |
   | `updateContext` | `PATCH /voice/sessions/{id}/context` |
   | `fetchStatus` | `GET /voice/sessions/{id}/status` |
   | `end` | `DELETE /voice/sessions/{id}` |
   `create` wydaje token od razu, bo `VoiceSessionConfiguration` go wymaga —
   kontrakt zostaje bez zmian (osobna trasa tokenu, nie pole w `create`).
3. **`expiresAt` → `Date?`** w obu typach i wszystkich miejscach użycia.
   Brak wartości znaczy „nieznany”; żywotność pilnuje stan sesji, nie zegar.
4. **`currentUser`**: przestać zwracać `nil`. Użytkownika bierze sesja
   mobilna z odpowiedzi logowania — trzeba potwierdzić jej kształt i zapisać go
   w `AuthStore` razem z tokenem.
5. **Podłączenie w `AppDependencies`**: dla trybu nie-Demo prawdziwe
   `BackendVoiceSessionRepository` (żadnego mocka w ścieżce transportu).
6. **`EMMA_API_BASE_URL = https://majkuny.pl`** w `Production.xcconfig`.
7. **Build TestFlight wewnętrzny** + lista kontrolna testu na urządzeniu.

## Czego nie ruszamy

- Oznaczenia **Demo zostają** do przejścia testu z punktu 8 (mikrofon, Qwen
  przez ElevenLabs, przerwanie, mute, zakończenie, logout, brak sekretów).
- Historia asystenta i action engine zostają kanoniczne — sesja transportu jest
  techniczna i nie tworzy drugiego systemu rozmów, zadań ani akcji.
