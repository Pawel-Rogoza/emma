# Audyt aplikacji iOS Emma — 23.09.2026 (wersja 0.2.1)

Pierwszy audyt wykonany **na Macu z Xcode**: kompilacja, pełne testy w symulatorze
i test end-to-end z prawdziwym backendem (`adwokat-app-project`, `origin/main`)
uruchomionym lokalnie na jednorazowej bazie. Wcześniejsze wersje (do 0.2.0) nie
były kompilowane w Xcode — patrz `REVIEW_2026-09-23.md`, pkt 6.

## Wynik testów

| Zestaw | Wynik |
| --- | --- |
| Kompilacja (Swift 6.3, Xcode 26.6, iOS 26.5) | bez błędów |
| Testy jednostkowe `EmmaTests` | 474 zielone (4 pominięte bez atrapy głosu; 3 nowe) |
| Testy transportu Gemini Live na atrapie (`fake-live-api.mjs`) | 4/4 — wcześniej zawsze pomijane |
| Testy interfejsu `EmmaUITests` (Demo) | wszystkie zielone (1 nieaktualny test poprawiony, 1 nowy) |
| Testy z lokalnym backendem (`BackendLoginUITests`) | 6/6 (1 nowy, 1 nieaktualny poprawiony) |

Nowe testy przechodzą na wersji po poprawkach i **padają na 0.2.0** — to dowód,
że wykrywają naprawione błędy, a nie tylko „świecą na zielono”.

## Naprawione błędy

| # | Błąd (wersja z backendem = TestFlight) | Skutek | Poprawka |
| --- | --- | --- | --- |
| A1 | Szczegół zadania i terminu rzucał „backend nie udostępnia” | Kliknięcie zadania lub „Szczegóły” terminu kończyło się błędem | `BackendRepository.task(id:)` / `event(id:)` szukają rekordu na liście |
| A2 | „Edytuj” zadanie/termin przy nieudanym odczycie otwierało pusty formularz | Zapis **zakładał duplikat** zamiast zmienić rekord | Formularz edycji pokazuje błąd i blokuje zapis |
| A3 | Zadania bez terminu były pomijane | Część zadań z panelu nie istniała w aplikacji | Termin opcjonalny, grupa „Bez terminu” |
| A4 | `GET /events` oddaje max 200 pozycji od najstarszej, a aplikacja pytała o ±3 lata | Przyszłe terminy znikały z karty klienta, sprawy i listy | Terminy klienta filtrowane na serwerze (`client_id`), węższe okna |
| A5 | Zmiana nazwy/miejsca terminu i klienta zadania były po cichu ignorowane przez backend | „Zapisano”, ale bez zmiany | Jasny komunikat, co trzeba zmienić w panelu |
| A6 | Komunikaty błędów backendu nie docierały do ekranu | Zawsze „Nie udało się wykonać operacji.” | `ScreenLoad` pokazuje komunikat backendu (sesja, konflikt, walidacja) |
| A7 | Klient kancelarii bez sprawy był nieosiągalny z zakładki „Klienci” | Nie dało się go znaleźć nawet wyszukiwarką | Wyszukiwanie obejmuje wszystkie zgłoszenia i klientów |
| A8 | Wyjście do innej aplikacji niszczyło powłokę (blokada zamiast niej) | Po Face ID znikał otwarty formularz i pisana notatka | Blokada zasłania powłokę; po powrocie dane się odświeżają |
| A9 | „Rozpocznij prowadzenie sprawy” i ustawienia sprawy na backendzie zawsze kończyły się błędem | Formularz do wypełnienia bez szans na zapis | Poza Demo zamiast przycisku informacja o panelu |
| A10 | Historia rozmowy z Emmą przeżywała wylogowanie | Kolejna osoba widziała poprzednią rozmowę | Czyszczenie przy końcu sesji |
| A11 | Portret Emmy na „Dzisiaj” czytał nieobserwowany stan głosu | Nie reagował na mówienie Emmy | Czyta publikowany `voiceState` |
| A12 | Sprawa wczytywała 5 zapytań po kolei | Wolniejsze wejście w sprawę | Zapytania równolegle |

## Do zrobienia po stronie backendu / właściciela

1. **`EMMA_MOBILE_ACTIONS_EXECUTE=true` na serwerze.** Bez tej zmiennej notatka
   i zadanie zatwierdzone u Emmy trafiają tylko do kolejki — w CRM nic nie
   powstaje (aplikacja uczciwie mówi „zapis jest symulowany”). W konfiguracji
   wdrożenia (`deploy/`) tej zmiennej nie ma.
2. `PATCH /events` bez `title`, `location`, `kind`; `PATCH /tasks` bez `client_id`
   — aplikacja mówi teraz wprost, że trzeba to zmienić w panelu.
3. `GET /tasks/{id}` i `GET /events/{id}` — dziś aplikacja szuka rekordu na
   listach (działa, ale kosztuje 1–3 zapytania).
4. `POST /cases` i `PATCH /cases` — bez nich nie da się założyć ani zmienić
   sprawy z telefonu.
5. `GET /events` bez parametru `limit` i z porządkiem od najstarszego — przy
   szerokim zakresie gubi przyszłe terminy (aplikacja omija to węższymi oknami).
6. Z `REVIEW_2026-09-23.md`: `received_at`, `phone`, `email` w leadach,
   `PATCH` etapu dla `client-N`, push o nowym leadzie.

## Jak odtworzyć test z backendem

`RUNBOOK_BACKEND_LOKALNIE.md`, a dodatkowo zmienne nowego testu
`testRealTaskAndEventDetailsOpenAndEditLoadsRecord`:
`EMMA_UI_EXPECT_TASK`, `EMMA_UI_EXPECT_UNDATED_TASK`, `EMMA_UI_EXPECT_EVENT`,
`EMMA_UI_EXPECT_FUTURE_EVENT` (z przedrostkiem `TEST_RUNNER_`). Testy transportu
głosu: `node scripts/fake-live-api.mjs --port 8791` i `--port 8792 --scenario goaway`
w repo backendu, potem `TEST_RUNNER_EMMA_FAKE_LIVE_BASE_URL=http://127.0.0.1:8791`
i `TEST_RUNNER_EMMA_FAKE_LIVE_BASE_URL_GOAWAY=http://127.0.0.1:8792`.
