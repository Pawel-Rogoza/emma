# Analiza luk: co aplikacja wymaga od backendu i dostawców

Ten dokument spisuje **kontrakt**, którego aplikacja iOS potrzebuje od świata zewnętrznego,
oraz uczciwie oznacza, co jest już spełnione, a co zablokowane.

**Aktualizacja 2026-09-14 — repozytorium backendu jest już dostępne.** Backend to
`github.com/Pawel-Rogoza/adwokat-app-project` (nazwa pakietu `advokat-varshava`,
Astro 7 + adapter Node + SQLite, produkcja: panel `majkuny.pl`, strona
`advokat-varshava.pl`). Potwierdzone na SHA `029444a`: `npm test` = **110 plików /
836 testów PASS**, `npx astro check` = 7 błędów, 110 tras API, 40 migracji.
Pełna analiza luki i plan etapów M0–M6: `docs/emma/MOBILE_API_GAP_2026-09-14.md`
w repozytorium backendu. Poniższe tabele zaktualizowano tam, gdzie stan kodu
przeczy wcześniejszemu „brak dostępu".

Legenda: **Gotowe** (aplikacja to obsługuje) · **Wymagane** (potrzebne od backendu) ·
**Blocked** (wymaga konta/dostępu/decyzji).

## 1. Konfiguracja i tożsamość

| Element | Stan | Uwaga |
| --- | --- | --- |
| Adres backendu z konfiguracji builda | Gotowe | `EMMA_API_BASE_URL` z `.xcconfig`, brak wartości w Demo |
| Brak sekretów w aplikacji | Gotowe | żadnego klucza API w kodzie, w `Info.plist` ani w repozytorium |
| Token dostępu użytkownika | Gotowe (klient) / Gotowe (backend) | aplikacja pobiera i przechowuje parę tokenów (`MobileSessionKeeper`, kluczyk), backend wydaje ją przez `/api/mobile/v1/auth/login`; token trafia do `AppDependencies.accessToken` |
| Logowanie / sesja użytkownika | Gotowe (klient) / Gotowe (backend, M1) | backend: `POST /api/mobile/v1/auth/login\|refresh\|revoke` (bearer, rotacja z oknem propagacji, rewokacja per urządzenie, TOTP gdy konto go ma — migracja 041, `docs/emma/MOBILE_API_M1_LOGIN.md`); aplikacja: `AuthStore` + `MobileAuthClient` + kluczyk. Po zalogowaniu dane pochodzą z backendu (`BackendRepository`, M2b) |
| Przełączenie użytkownika w Demo | Gotowe | `switchUser(to:)` czyści stan głosu i odczytów |
| Klienci i leady (`/clients`, `/clients/{id}`) | Gotowe (backend, M2) / **Gotowe (iOS, M2b)** | backend scala leady z kartoteką w jeden ciąg etapów (`new`/`in_contact`/`client`), karta klienta zawiera sprawę, terminy, zadania, notatki i aktywność z dziennika audytu; `incoming_message`/`needs_reply` są puste do M6 (`docs/emma/MOBILE_API_M2_READ.md` w repo backendu) |
| Sprawy, zadania, terminy (`/cases`, `/cases/{id}`, `/tasks`, `/events`) | Gotowe (backend, M2/M2c) / **Gotowe (iOS, M2b)** | `version` z migracji 042, priorytet `high`→`urgent`, godziny w strefie kancelarii, termin całodniowy bez godziny; lista spraw doszła w M2c, bo bez niej zakładka „Sprawy” nie miała skąd czytać. Ograniczenie: termin całodniowy pokazuje 00:00, bo widoki nie używają jeszcze `isAllDay` |
| Briefing dnia (`/briefing`) | Częściowo (backend, M2) / **Gotowe (iOS, M2b)** | backend składa zdanie z policzonych faktów (terminy + zadania, w tym po terminie); prawdziwe streszczenie asystenta wymaga modelu i kontekstu sprawy (M5) |
| Zapis: kontakt, zadanie, termin, notatka | **Gotowe (backend, M4a)** / Wymagane (iOS) | `POST /clients`, `PATCH /clients/{id}`, `POST|PATCH /tasks`, `POST|PATCH|DELETE /events`, `POST /notes` — wersjonowanie (`expected_version` → 409 z `current_version`) i idempotencja (`Idempotency-Key`, migracja 043). Aplikacja jeszcze ich nie woła: `BackendRepository` nadal rzuca `notAvailableInBackend` przy zapisie — podłączenie w następnym kroku. Dowód: `docs/emma/MOBILE_API_M4_WRITES.md` |
| Zapis: sprawy (`POST/PATCH /cases`) | Wymagane | kontrakt opisuje `POST /cases`, trasy jeszcze nie ma (M4b) |
| Akcje z potwierdzeniem (`/actions`, `X-Emma-Consent`) | Wymagane | zgoda może powstać wyłącznie z dotknięcia przycisku albo uwierzytelnionej tury rozmowy (M4b) |
| Dowód integracji iOS ↔ backend | Gotowe (M2b) | test `testRealBackendDataAppearsInClientsAndCard` przeszedł na danych istniejących **tylko** w bazie (`Zenon Backendowicz-Testowy`, `II K 999/26`), a aplikacja zostawiła własną sesję w `mobile_sessions` (`docs/ios/M2B_REPOZYTORIUM_HTTP.md`) |

## 2. Głos

| Element | Stan | Uwaga |
| --- | --- | --- |
| Token rozmowy | Gotowe (klient) / Częściowo (backend) | backend ma `POST /api/crm/assistant/voice/session` (token aplikacyjny + signed URL ElevenLabs, tabela `voice_sessions`, granty z 040); brak jeszcze wariantu mobilnego o kształcie `ConversationToken{token, expires_at, session_id, capabilities}` |
| Adapter oficjalnego SDK | Gotowe | `#if canImport(ElevenLabs)`, wersja przypięta 3.3.1 |
| Brak klucza dostawcy w iOS | Gotowe | klucz wyłącznie po stronie backendu |
| Weryfikacja na koncie | Blocked | brak konta u dostawcy |
| Wykonywanie akcji przez narzędzia dostawcy | Wymagane | narzędzia muszą trafiać do **wspólnego** action engine na backendzie, nie do klienta |
| Kontekst sprawy po stronie backendu | Wymagane | backend waliduje spójność klienta i sprawy przed zapisem |

**Zasada, która nie może zostać zniesiona:** zgoda na wykonanie akcji płynie wyłącznie
z dotknięcia przycisku w interfejsie albo z uwierzytelnionej tury rozmowy. Argument
podany modelowi językowemu **nie jest** zgodą — aplikacja odrzuca taką próbę
(`Confirmation.Origin.languageModelArgument`).

## 3. Action engine i outbox

| Element | Stan | Uwaga |
| --- | --- | --- |
| Jeden silnik akcji dla UI i głosu | Gotowe (klient) / Wymagane (backend) | backend ma `actions` i `assistant_actions`, ale **bez** wersji, `payload_hash`, `presentation_id` i terminu ważności — zgoda na zmienioną treść jest dziś nierozróżnialna od zgody na treść aktualną |
| Klucz idempotencji | Gotowe (klient) / Wymagane (backend) | kontrakt ma schemat `IdempotencyKey`; w backendzie `case_actions` nie ma kolumny wersji ani klucza idempotencji |
| Blokada optymistyczna (`Version`) | Gotowe (klient) / Częściowo (backend, M2) | `clients/cases/tasks/events/notes` mają `version` z triggerem (migracja 042), ale `case_actions` (037) nadal nie ma kolumny ani klucza idempotencji |
| Trwały outbox | Wymagane | backend nie ma tabeli outboxu ani stanów wykonania (`queued/claimed/dispatching/accepted/failed/unknown`) |
| Niepewny wynik bez ponowienia | Gotowe | `ExecutionState.unknown` nigdy nie jest raportowany jako sukces |
| Rozstrzyganie niepewnych wykonań | Wymagane | brak trasy `GET /actions/{id}/execution` po stronie backendu |

## 4. Wiadomości i WhatsApp

| Element | Stan | Uwaga |
| --- | --- | --- |
| Wysyłka wiadomości | Gotowe (klient) / Wymagane (backend) | w backendzie WhatsApp istnieje wyłącznie jako powiadomienie wychodzące (`sendWhatsAppLeadNotification`, fire-and-forget, bez `wamid` i statusu) |
| Wątki i wiadomości (`/threads`) | Wymagane | brak jakiejkolwiek trasy i tabeli wątków/wiadomości klienta — `assistant_messages` to historia czatu Emmy, nie korespondencja |
| Statusy dostarczenia | Gotowe (model) / Blocked | brak realnego dostawcy; demo mówi o tym w interfejsie |
| Odbiór wiadomości (webhook) | Wymagane | brak webhooka; wymagany podpis `X-Hub-Signature-256` i deduplikacja po identyfikatorze dostawcy |
| Koegzystencja z WhatsApp Business | Blocked | wymaga Solution Partnera / Tech Providera i Embedded Signup |
| Zachowanie numeru właściciela | Wymóg | **nie zmieniać ani nie wyrejestrowywać używanego numeru** w trakcie implementacji |

Szczegóły i ograniczenia: `docs/ios/research/whatsapp-coexistence.md`
oraz `docs/ios/WHATSAPP_ONBOARDING.md`.

## 5. Asystent językowy (Qwen)

| Element | Stan | Uwaga |
| --- | --- | --- |
| Kontrakt wywołania | Częściowo potwierdzony | w backendzie istnieje abstrakcja providerów `openai.ts` / `qwen.ts` (+ testy), więc aplikacja nie woła modelu bezpośrednio; **brak** potwierdzenia na koncie dostawcy |
| Wynik jako propozycja | Gotowe | cokolwiek zwróci model, trafia do propozycji wymagającej zgody |
| Zakaz wykonywania z modelu | Gotowe | model nie ma ścieżki wykonania |

Aplikacja jest przygotowana na to, że model zwróci **propozycję** — i tylko propozycję.
Dopóki kontrakt Qwen nie zostanie potwierdzony na działającym backendzie, każda
integracja z nim pozostaje `blocked_external` i nie jest opisywana jako działająca.

## 6. Dane i synchronizacja

| Element | Stan | Uwaga |
| --- | --- | --- |
| Repozytorium demo | Gotowe | jedno źródło danych dla Demo, działa bez sieci |
| Zapytania zakresowe (terminy klienta) | Wymagane | demo używa okna ±3 lata (odstępstwo D-08) |
| Zdalne repozytorium | Wymagane | ten sam protokół co `MockRepository`, podmiana w jednym miejscu |
| Synchronizacja przyrostowa (`/sync/changes`) | Wymagane | brak trasy po stronie backendu; bez niej nie da się odróżnić „brak zmian" od „nie udało się pobrać" |
| Push na iOS (APNs) | Wymagane | backend ma wyłącznie web-push (VAPID) dla panelu; brak tokenu urządzenia i klucza APNs |
| Wersjonowanie i konflikty | Gotowe | `DomainError.versionConflict` z czytelnym komunikatem |

## 7. Bezpieczeństwo i prywatność

| Wymóg | Stan |
| --- | --- |
| Brak kluczy dostawców w aplikacji | spełnione |
| Uprawnienia mikrofonu i mowy opisane w `Info.plist` | spełnione |
| Rozpoznawanie mowy na urządzeniu, gdy dostępne | spełnione (`requiresOnDeviceRecognition`) |
| Brak logowania treści rozmów | do potwierdzenia przy podłączeniu backendu |
| Prawo do usunięcia danych klienta | backend ma `clients/{id}/anonymize`, `clients/{id}/export`, `clients/{id}/merge` i `retention.ts`; brakuje mobilnej trasy i potwierdzenia, że aplikacja korzysta z tej samej ścieżki |

## 8. Podsumowanie luk

**Do zrobienia po stronie backendu (wymagane, nie zablokowane technicznie):**
logowanie bearer (access + refresh + rewokacja per urządzenie), mobilne DTO
(`Client`/`Task`/`Event`/`Note`/`Case`/`Briefing` + `version`), pliki w kontrakcie
(upload/download z ACL), wersje i `payload_hash` w silniku akcji, trwały outbox
ze stanami wykonania, `GET /actions/{id}/execution`, `GET /sync/changes`.
Szczegółowe mapowanie 29 operacji i plan etapów M0–M6:
`docs/emma/MOBILE_API_GAP_2026-09-14.md` w repozytorium backendu.

**Zablokowane zewnętrznie:**
konto dostawcy głosu (ElevenLabs), koegzystencja WhatsApp (Tech Provider +
Embedded Signup), klucz APNs, potwierdzenie kontraktu Qwen na koncie dostawcy.
Dostęp do repozytorium backendu **nie jest już** blokerem — uzyskano go 2026-09-14.

Żadna z pozycji `Blocked` nie jest powodem do porzucenia pracy niezależnej od kont —
i żadna nie jest opisywana jako działająca, dopóki nie zostanie udowodniona.
