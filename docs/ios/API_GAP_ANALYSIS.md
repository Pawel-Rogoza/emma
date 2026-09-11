# Analiza luk: co aplikacja wymaga od backendu i dostawców

Ten dokument spisuje **kontrakt**, którego aplikacja iOS potrzebuje od świata zewnętrznego,
oraz uczciwie oznacza, co jest już spełnione, a co zablokowane. Powstał, ponieważ
repozytorium backendu jest prywatne i nie było dostępne w tym środowisku
(`blocked_external`) — historycznego opisu backendu z poprzedniego planu **nie potwierdzono**
na żadnym SHA i nie przepisano bezkrytycznie.

Legenda: **Gotowe** (aplikacja to obsługuje) · **Wymagane** (potrzebne od backendu) ·
**Blocked** (wymaga konta/dostępu/decyzji).

## 1. Konfiguracja i tożsamość

| Element | Stan | Uwaga |
| --- | --- | --- |
| Adres backendu z konfiguracji builda | Gotowe | `EMMA_API_BASE_URL` z `.xcconfig`, brak wartości w Demo |
| Brak sekretów w aplikacji | Gotowe | żadnego klucza API w kodzie, w `Info.plist` ani w repozytorium |
| Token dostępu użytkownika | Wymagane | aplikacja umie go przekazać, backend musi go wydać |
| Logowanie / sesja użytkownika | Blocked | brak kontraktu; dziś użytkownik demo jest wybierany lokalnie |
| Przełączenie użytkownika w Demo | Gotowe | `switchUser(to:)` czyści stan głosu i odczytów |

## 2. Głos

| Element | Stan | Uwaga |
| --- | --- | --- |
| Token rozmowy | Gotowe (klient) / Wymagane (backend) | `GET` lub `POST v1/voice/conversation-token` → pole `token` + wygaśnięcie |
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
| Jeden silnik akcji dla UI i głosu | Gotowe (klient) / Wymagane (backend) | ten sam kontrakt po obu stronach |
| Klucz idempotencji | Gotowe | powtórzenie żądania nie tworzy drugiego zapisu |
| Blokada optymistyczna (`Version`) | Gotowe | konflikt wersji jest zgłaszany, nie nadpisywany po cichu |
| Trwały outbox | Wymagane | przetrwanie restartu aplikacji po stronie backendu |
| Niepewny wynik bez ponowienia | Gotowe | `ExecutionState.unknown` nigdy nie jest raportowany jako sukces |
| Rozstrzyganie niepewnych wykonań | Wymagane | endpoint do sprawdzenia stanu akcji po identyfikatorze |

## 4. Wiadomości i WhatsApp

| Element | Stan | Uwaga |
| --- | --- | --- |
| Wysyłka wiadomości | Gotowe (klient) / Wymagane (backend) | idempotencja po kluczu |
| Statusy dostarczenia | Gotowe (model) / Blocked | brak realnego dostawcy; demo mówi o tym w interfejsie |
| Odbiór wiadomości (webhook) | Wymagane | podpis `X-Hub-Signature-256`, deduplikacja po identyfikatorze dostawcy |
| Koegzystencja z WhatsApp Business | Blocked | wymaga Solution Partnera / Tech Providera i Embedded Signup |
| Zachowanie numeru właściciela | Wymóg | **nie zmieniać ani nie wyrejestrowywać używanego numeru** w trakcie implementacji |

Szczegóły i ograniczenia: `docs/ios/research/whatsapp-coexistence.md`
oraz `docs/ios/WHATSAPP_ONBOARDING.md`.

## 5. Asystent językowy (Qwen)

| Element | Stan | Uwaga |
| --- | --- | --- |
| Kontrakt wywołania | Blocked | brak dostępu do backendu — kształt żądania i odpowiedzi niepotwierdzony |
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
| Wersjonowanie i konflikty | Gotowe | `DomainError.versionConflict` z czytelnym komunikatem |

## 7. Bezpieczeństwo i prywatność

| Wymóg | Stan |
| --- | --- |
| Brak kluczy dostawców w aplikacji | spełnione |
| Uprawnienia mikrofonu i mowy opisane w `Info.plist` | spełnione |
| Rozpoznawanie mowy na urządzeniu, gdy dostępne | spełnione (`requiresOnDeviceRecognition`) |
| Brak logowania treści rozmów | do potwierdzenia przy podłączeniu backendu |
| Prawo do usunięcia danych klienta | Wymagane — brak kontraktu |

## 8. Podsumowanie luk

**Do zrobienia po stronie backendu (wymagane, nie zablokowane technicznie):**
token rozmowy, sesja użytkownika, trwały outbox, rozstrzyganie niepewnych wykonań,
webhook wiadomości z podpisem, zapytania zakresowe, prawo do usunięcia danych.

**Zablokowane zewnętrznie:**
konto dostawcy głosu, koegzystencja WhatsApp (Tech Provider + Embedded Signup),
potwierdzenie kontraktu Qwen na działającym backendzie, dostęp do repozytorium backendu.

Żadna z pozycji `Blocked` nie jest powodem do porzucenia pracy niezależnej od kont —
i żadna nie jest opisywana jako działająca, dopóki nie zostanie udowodniona.
