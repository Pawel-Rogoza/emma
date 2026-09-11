# Kontrakt API — lista testów do wykonania

Status: **nieuruchomione.** Kontrakt (`emma-mobile-api.yaml`) jest propozycją
napisaną bez dostępu do backendu (`blocked_external`). Ten plik jest gotową listą
sprawdzeń dla etapu 07 — każde z nich wymaga działającego serwera.

Zasada: żadne pole nie jest uznane za uzgodnione, dopóki nie zostało sprawdzone
na serwerze. Kontrakt opisuje **wymagania aplikacji**, nie stan implementacji.

## A. Sesja i autoryzacja

| # | Sprawdzenie | Oczekiwany wynik |
| --- | --- | --- |
| A-1 | Logowanie poprawnymi danymi | `200`, para tokenów, `expires_at` w przyszłości |
| A-2 | Logowanie błędnym hasłem | `401`, komunikat bez zdradzania, czy konto istnieje |
| A-3 | Odnowienie tokenu | `200`, nowy token dostępu |
| A-4 | Użycie odnowionego tokenu | `200` |
| A-5 | Odwołanie sesji urządzenia (`/auth/revoke`) | `204`, a następne żądanie z tym tokenem daje `401` |
| A-6 | Zmiana konta na tym samym urządzeniu | Sesja głosowa zakończona, stan lokalny wyczyszczony, cudze odczyty niewidoczne |
| A-7 | Żądanie bez tokenu | `401`, a aplikacja przechodzi do logowania bez utraty szkiców |
| A-8 | Żądanie do zasobu bez uprawnienia | `403`, nie `404` (aplikacja odróżnia brak dostępu od braku danych) |

## B. Odczyt i paginacja

| # | Sprawdzenie | Oczekiwany wynik |
| --- | --- | --- |
| B-1 | `GET /briefing` | Jedno żądanie, brak N+1 (potwierdzone liczbą zapytań w logach) |
| B-2 | Paginacja klientów kursorem | Brak duplikatów i brak luk między stronami |
| B-3 | Ostatnia strona | `has_more: false`, `next_cursor: null` |
| B-4 | Historia rozmowy `before_sequence` | Wiadomości starsze, w kolejności rosnącej |
| B-5 | Limit większy niż dozwolony | `422` albo przycięcie do maksimum — zachowanie musi być udokumentowane |
| B-6 | Zapytanie o nieistniejący zasób | `404` |

## C. Zapis, wersje i idempotencja

| # | Sprawdzenie | Oczekiwany wynik |
| --- | --- | --- |
| C-1 | Zapis z aktualną wersją | `200`, wersja zwiększona o 1 |
| C-2 | Zapis ze starą wersją | `409` z `current_version`; **brak** cichego nadpisania |
| C-3 | Powtórzenie tego samego żądania z tym samym `Idempotency-Key` | Ten sam obiekt, brak drugiego |
| C-4 | Ten sam klucz idempotencji z inną treścią | Odrzucone (`409`), nie „wygrywa ostatni” |
| C-5 | Utworzenie drugiej sprawy dla tego samego klienta | Zwrócona istniejąca sprawa, nie druga |
| C-6 | Termin z kolizją prowadzącego | Odrzucone z czytelnym komunikatem |
| C-7 | Próba cofnięcia kursora odczytu | Odrzucone; kursor może się tylko przesuwać do przodu |

## D. Wiadomości i statusy

| # | Sprawdzenie | Oczekiwany wynik |
| --- | --- | --- |
| D-1 | Wysyłka wiadomości | `202`, stan `pending` (nie `delivered`) |
| D-2 | Powtórzona wysyłka z tym samym kluczem | Jedna wiadomość |
| D-3 | Status dostawcy przychodzący po `read` | Status się **nie** cofa |
| D-4 | Wiadomość ze znacznikiem w przyszłości | Odrzucone albo odrzucone przez serwer z jasnym kodem |
| D-5 | Przekroczenie limitu tempa | `429` z `Retry-After`, żądanie trafia do kolejki, nie ginie |

## E. Silnik akcji i zgoda

| # | Sprawdzenie | Oczekiwany wynik |
| --- | --- | --- |
| E-1 | Przygotowanie propozycji | `201`, stan `proposed`, brak jakiegokolwiek zapisu docelowego |
| E-2 | Potwierdzenie z `X-Emma-Consent: direct_ui_button` | `202`, jedno wykonanie |
| E-3 | Brak nagłówka zgody | Odrzucone — wykonanie nie może powstać bez dowodu zgody |
| E-4 | Nagłówek `language_model_argument` | Odrzucone wprost |
| E-5 | Powtórzone potwierdzenie tej samej prezentacji | To samo wykonanie (idempotencja), nie drugie |
| E-6 | Potwierdzenie po `expires_at` | `410`, wymagane przygotowanie od nowa |
| E-7 | Korekta propozycji po zgodzie | Zgoda unieważniona: nowy `presentation_id` i hash |
| E-8 | Dwa równoczesne potwierdzenia z dwóch urządzeń | Jedno wykonanie; drugie dostaje to samo albo `409` |
| E-9 | Przerwanie po wysłaniu do dostawcy | Stan `unknown`, `retryable: false` |
| E-10 | Odczyt wykonania po `unknown` | Stan rozstrzygnięty; aplikacja nie ponowiła sama |
| E-11 | Anulowanie po rozpoczęciu wykonania | `409`, jasny komunikat |

## F. Głos

| # | Sprawdzenie | Oczekiwany wynik |
| --- | --- | --- |
| F-1 | `POST /voice/conversation-token` | Zwraca tylko `token`; w odpowiedzi **nie ma** klucza dostawcy |
| F-2 | Token użyty po wygaśnięciu | Odrzucony przez dostawcę, aplikacja pokazuje błąd sesji |
| F-3 | Token z innego konta | Odrzucony |
| F-4 | `DELETE /voice/sessions/{id}` | Sesja zamknięta, mikrofon zwolniony |
| F-5 | Brak dostępności dostawcy | `503` i uczciwy komunikat, bez udawania połączenia |

## G. Synchronizacja i offline

| # | Sprawdzenie | Oczekiwany wynik |
| --- | --- | --- |
| G-1 | `GET /sync/changes` dwa razy z rzędu | Zakres ciągły, brak luki i brak duplikatów |
| G-2 | Powtórzone zdarzenie | Zignorowane po identyfikatorze dostawcy |
| G-3 | Znacznik starszy niż retencja | `410` i pełny odczyt |
| G-4 | Praca bez sieci | Aplikacja działa na danych lokalnych i pokazuje stan braku połączenia |
| G-5 | Powrót sieci po długiej przerwie | Brak luki, brak podwójnych wpisów |
| G-6 | Rejestracja i wyrejestrowanie tokenu push | `204`, po wyrejestrowaniu brak powiadomień |
| G-7 | Odmowa notyfikacji | Aplikacja działa bez push (dane dochodzą przez synchronizację) |

## Jak raportować wynik

Każde sprawdzenie kończy się jednym z trzech wpisów:

- **zgodne** — z dowodem (kod odpowiedzi, fragment payloadu, zapis z logu),
- **rozbieżne** — z opisem różnicy i decyzją, która strona się zmienia,
- **blocked_external** — brak dostępu do środowiska.

Wpis „wygląda dobrze” bez dowodu nie jest wynikiem testu.
