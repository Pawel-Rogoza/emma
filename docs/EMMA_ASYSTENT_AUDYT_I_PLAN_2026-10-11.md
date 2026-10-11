# Emma (asystent AI) — audyt wglądu w dane i plan rozwoju (11.10.2026)

Zakres: czy Emma działa poprawnie i czy „widzi” wszystkie sekcje aplikacji
(zadania, terminy, wiadomości, leady, klienci, sprawy), a potem plan usprawnień.
Przegląd kodu: iOS `master` 0.23.2 (`394d2d1`) i backend `main` (`c082957`).
Testy backendu Emmy (`src/lib/crm/assistant*`, `mobile/assistantChat`,
`mobile/voiceTools`, `mobile/threadDraft`, `voice/`): **133 zaliczone, 3 pominięte**.
Testów Swift nie uruchamiałem, bo na tym komputerze nie ma toolchaina Swifta.
Działania aplikacji opisane niżej wynikają z czytania kodu, nie z uruchomienia.

---

## 1. Jak Emma jest dziś zbudowana: cztery drogi zamiast jednej

| Droga | Gdzie | Model | Odczyt danych | Działania w aplikacji |
|---|---|---|---|---|
| **A. Emma głosem** | Gemini Live z telefonu | Gemini Live | 12 narzędzi CRM (`emma/tools.ts`, przycięte do 20 pozycji) | 11 narzędzi `app_*` (ekrany, karty, szkic WhatsApp, formularz terminu, kalkulator terminów, zmiana sprawy) |
| **B. Emma pisemnie** | `POST /mobile/v1/assistant/messages` | model tekstowy (domyślnie Gemini, `ASSISTANT_PROVIDER`) | te same 12 narzędzi, **bez przycięcia** | **żadnych** — instrukcja każe podać użytkownikowi polecenie do przepisania |
| **C. Lokalny parser iOS** | `AssistantIntentParser` + `AssistantStore` | brak (reguły `contains`) | repozytorium w telefonie | karty notatki/zadania/wiadomości, formularz spotkania, lokalny briefing, lokalne podsumowanie sprawy |
| **D. Czat w panelu CRM** | `assistant.ts` | ten sam co B | wszystkie narzędzia + `propose_*` + PDF | propozycje zadania/notatki, PDF |

Wpisany tekst trafia najpierw do **C**. Do **B** idzie tylko to, czego parser nie
rozpozna (`.unknown`). Kontekst rozmowy (klient, sprawa, ekran) każda droga
dostaje inaczej (§3.4).

---

## 2. Wgląd w sekcje aplikacji (macierz)

✓ widzi · ◐ częściowo · ✗ nie widzi

| Sekcja | Narzędzie | Ocena | Braki |
|---|---|---|---|
| **Dzisiaj / przegląd dnia** | `get_today_overview` | ◐ | Godziny w UTC (§3.2). Leady „bez odpowiedzi” liczone tylko z notatek, więc odpowiedź na WhatsAppie się nie liczy. Brak nieprzeczytanych rozmów. Lokalny briefing (C) liczy coś innego niż serwer. |
| **Zadania** | `list_tasks`, `get_case.tasks`, `list_agenda.tasks` | ◐ | Nie da się filtrować po kliencie, sprawie ani osobie („moje”). Najwyżej 30 pozycji. Wpisane pytanie o zadania przechwytuje parser (§3.1). |
| **Terminy / kalendarz** | `list_agenda`, `get_case.events` | ◐ | Godziny w UTC, a dzień liczony z daty UTC (§3.2). Terminy z `case_actions` (rozprawy i terminy procesowe z panelu) są niewidoczne (§3.6). |
| **Wiadomości WhatsApp** | `list_conversations`, `get_conversation` | ◐ | Tylko rozmowy przypisane do klienta albo leada. **Sekcja „Bez osoby w kartotece” i rozmowy e-mail są niewidoczne** (§3.5). Nie ma wyszukiwania po treści wiadomości („kto pisał o karcie pobytu?”). |
| **Leady** | `search_leads`, `get_lead` | ◐ | Brak filtra po źródle i dacie, więc Emma liczy inaczej niż ekran „Leady” (tam tylko strona i ręczne). Analiza AI leada (`assistant_lead_insights`) już istnieje, ale Emma jej nie widzi. Nie widzi też konsultacji (cena, termin) ani gotowej odpowiedzi PL/RU (`reply_template`). |
| **Klienci (karta)** | `search_clients` | ◐ | **Nie ma `get_client`.** Notatki klienta (`notes.parent_type='client'`), lista jego spraw, zadań i terminów: wszystko trzeba składać z kilku narzędzi albo jest nieosiągalne. |
| **Sprawy** | `search_cases`, `get_case`, `list_case_watches`, `list_case_documents` | ✓/◐ | Nie widzi „następnego kroku” (`case_next_actions`), `case_actions` ani treści dokumentów (tylko nazwy). |
| **Kalkulator terminów** | `app_compute_deadline` | ◐ | Działa tylko głosem. |
| **Zespół / przypisania** | — | ✗ | Brak listy użytkowników, więc „przypisz Tomkowi” nie zadziała. |
| **Czas pracy, finanse, wpłaty** | — | ✗ | Dane są w CRM (`time_entries`, `finance_entries`), Emma ich nie czyta. |

---

## 3. Znalezione błędy i ryzyka

### 3.1 [KRYTYCZNE] Lokalny parser przechwytuje wpisane pytania
`AssistantIntent.swift:182–209`: rodzaj polecenia ustala `contains` na
fragmentach słów („zadani”, „wiadomo”, „odpow”, „spotkani”, „spraw”, „termin”,
„dzień”). Nie sprawdza czasownika tworzenia ani tego, czy tekst jest pytaniem.
Do serwera trafia tylko `.unknown`. Przebieg z kodu:

| Wpisane pytanie | Co się dzieje | Co powinno |
|---|---|---|
| „Jakie mam zadania na jutro?” | `.task`: Emma pyta o treść **nowego** zadania | lista zadań z serwera |
| „Co pisała Olena w ostatniej wiadomości?” | `.reply`: otwiera szkic odpowiedzi do Oleny | streszczenie wątku |
| „Czy Kowalski odpowiedział?” | `.reply`: szkic wiadomości | odpowiedź tak/nie z wątku |
| „Jakie mam spotkania w piątek?” | `.event`: otwiera formularz nowego spotkania | lista terminów na piątek |
| „Jakie mam sprawy z aresztem?” | `.caseSummary`: „Wybierz klienta…” | `list_case_watches` |
| „Kiedy jest termin apelacji Kowalskiego?” | `.briefing`: lokalny plan dnia | `get_case` / `list_agenda` |
| „Jakie notatki ma Kowalski?” | `.note`: pyta o treść nowej notatki | notatki z karty |
| „Dzień dobry” | `.briefing`: plan dnia | powitanie |

Testy (`AssistantIntentTests`) sprawdzają tylko polecenia, a nie pytania z
tymi słowami. W praktyce **Emma pisemnie odpowiada tylko na pytania, w których
nie pada żadne z tych słów**.

### 3.2 [WYSOKIE] Godziny terminów w UTC
Terminy z godziną są zapisane w UTC (`warsawWallTimeToUtc`, `mobile/write.ts`).
Narzędzia (`toolListAgenda`, `toolGetTodayOverview`, `toolGetCase` w
`assistant.ts`) oddają modelowi surowe `starts_at` („…T07:00:00.000Z”), a
instrukcja nie mówi, że to UTC. Rozprawę o 9:00 Emma może podać jako „o siódmej”.
Do tego filtr dnia `substr(e.starts_at,1,10)` liczy dzień w UTC: terminy między
00:00 a 02:00 czasu polskiego trafiają na poprzedni dzień. `work.ts` robi to
dobrze (`warsawDateKey(new Date(startsAt))`), ale narzędzia Emmy już nie.

### 3.3 [WYSOKIE] Emma pisemnie nic nie umie zrobić
Kanał B ma tylko odczyt. Na prośbę „przygotuj Olenie odpowiedź, że dokumenty są
gotowe” Emma odpowiada tekstem: wpisz „Napisz do Oleny…”. Głos w tej samej
sytuacji otwiera wątek ze szkicem. Dwie Emmy o różnych umiejętnościach to
najbardziej mylące doświadczenie w aplikacji.

### 3.4 [ŚREDNIE] Kontekst ekranu jest niepełny
- Pisemnie wysyłany jest tylko klient (`context_client_id`, `context_name`).
  Sprawa, otwarty wątek i oglądany dzień w kalendarzu nie są przekazywane.
- Głos dostaje klienta i sprawę (`liveContextNote`), ale nie wie, jaki ekran
  jest otwarty (kalendarz, piątek, wątek z X).
- Przez to „co tu mam?” albo „odpowiedz mu” działają tylko na karcie klienta.

### 3.5 [ŚREDNIE] Niewidoczne rozmowy
`toolListConversations` woła `listMobileThreads(db, userId)` bez
`includeUnassigned` i `includeEmail`. W kodzie zostało wykluczone ok. 1470
wątków bez osoby w kartotece (sekcja z „Zrób leada”) i cała poczta IMAP
(migracja 049). Nowy klient, który napisał pierwszy raz, dla Emmy nie istnieje.

### 3.6 [ŚREDNIE, do sprawdzenia na serwerze] `case_actions` i `case_next_actions`
Panel CRM (`work.ts`, `assistantDeadlines.ts`) czyta terminy, rozprawy i
płatności z `case_actions` oraz „następny krok” z `case_next_actions`. Ani API
mobilne, ani narzędzia Emmy tych tabel nie czytają. Jeśli są w nich wpisy,
Emma i aplikacja ich nie pokażą. Sprawdzenie:
```sql
SELECT action_type, status, COUNT(*) FROM case_actions GROUP BY 1,2;
SELECT status, COUNT(*) FROM case_next_actions GROUP BY 1;
```

### 3.7 [NISKIE]
- **Dwa różne briefingi.** Lokalny `EmmaBriefing` (wpisane „plan na dziś”) nie
  zawiera aresztów, pobytów ani nieprzeczytanych wiadomości. Serwerowy
  `get_today_overview` (głos) je zawiera.
- **Pisemnie do modelu idą nieprzycięte wiersze.** `get_lead` zwraca `l.*`,
  `get_case` zwraca `cs.*` z telefonem i e-mailem klienta. Głos dostaje
  przyciętą wersję (`trimEmmaResult`), czat nie. To niespójna minimalizacja
  danych.
- **Brak sygnału jakości.** Nie ma 👍/👎, nie ma zestawu pytań kontrolnych, a
  audyt (`assistant.chat`) liczy tokeny, ale nie mierzy, czy odpowiedź była
  trafna.
- **Brak strumieniowania.** Odpowiedź pisemna przychodzi w całości (limit 45 s)
  i przy kilku rundach narzędzi czeka się długo.

### Co działa dobrze (zostawić)
- Bezpieczeństwo zapisów: model niczego nie zapisuje. Zapis następuje dopiero
  po przycisku „Zatwierdź” (`direct_ui_button`), a „tak” z głosu nie jest zgodą.
- Allowlista narzędzi w kodzie, walidacja argumentów, limity wyniku, CAS kontekstu.
- Data i godzina w instrukcji (`todaySentence`), zasada PL/RU (nigdy UA),
  traktowanie treści klientów jako danych, nie poleceń.
- Pilnowanie aresztów i pobytów (`list_case_watches`) oraz kalkulator terminów
  k.p.k./k.p.a./p.p.s.a.

---

## 4. Plan usprawnień

Kolejność wynika z rachunku „szkoda dla użytkownika ÷ koszt”. Każdy etap
kończy się testami i osobnym wydaniem (iOS: podbicie `MARKETING_VERSION`).

### Etap 0: naprawy poprawności (1–2 dni) → iOS 0.24.0 + backend

1. **Parser tylko dla poleceń, pytania idą do Emmy** (`AssistantIntent.swift`)
   - Nowa reguła: `.task/.note/.event/.reply` wymaga czasownika tworzenia
     („dodaj”, „zapisz”, „napisz do”, „wyślij”, „przypomnij”, „umów”…) albo
     dwukropka z treścią.
   - Pytanie (znak „?” albo początek „jakie/jaki/co/kto/kiedy/ile/czy/gdzie/
     pokaż/przypomnij mi co”) zawsze dostaje `.unknown` i trafia do serwera,
     gdy ten jest dostępny.
   - `.briefing` i `.caseSummary` lokalnie tylko w Demo i bez sieci. Z serwerem
     idą do Emmy pisemnie.
   - Testy: tabela z co najmniej 40 zdaniami (pytania z §3.1 i dotychczasowe
     polecenia) w `AssistantIntentTests`.
2. **Czas polski w narzędziach** (`assistant.ts`)
   - Każdy termin zwraca `day` (RRRR-MM-DD, Warszawa), `time` (GG:MM, Warszawa)
     i `all_day`. Surowe `starts_at` znika z wyniku dla modelu.
   - Filtr dnia przez `eventDayKey` / zakres UTC wyliczony z dnia warszawskiego,
     tak jak w `work.ts`.
   - Test: termin 01:30 czasu polskiego trafia na właściwy dzień, a 09:00 nie
     zmienia się w 07:00.
3. **Rozmowy bez osoby i e-mail w `list_conversations`**
   - `includeUnassigned` i `includeEmail` dla Emmy. W wyniku nowe pola
     `channel` (whatsapp/email), `thread_id` i `subject`.
   - `get_conversation` przyjmuje także `thread_id`.
   - Instrukcje: „rozmowa bez osoby w kartotece może być nowym leadem”.
4. **Przycinanie wyników także w czacie pisemnym**: `trimEmmaResult` dla
   kanału B, z hojniejszymi limitami (np. 30 pozycji, 800 znaków).
5. **Jedno źródło instrukcji**: wspólny rdzeń (zasady faktów, PL/RU, prawo,
   bezpieczeństwo) i dopiski kanału (głos: krótko; tekst: lista, bez Markdown).
   Dziś to trzy osobne teksty, które zaczynają się rozjeżdżać.

### Etap 1: pełny wgląd w dane (ok. 1 tydzień) → backend + drobne iOS

Nowe narzędzia odczytu (rejestr, `trimEmmaResult`, testy w `voice/tools.test.ts`):

| Narzędzie | Zwraca | Odpowiada na |
|---|---|---|
| `get_client` | dane karty, sprawy, ostatnie 10 notatek, otwarte zadania, najbliższe terminy, konsultacja, wątek (id, nieprzeczytane, okno 24 h) | „co wiemy o Kowalskim?”, „przygotuj mnie do spotkania” |
| `list_leads` | filtry: `source` (strona/ręczne/whatsapp), `status`, `since`, `unanswered` (bez notatki **i** bez naszej wiadomości w wątku) | „ile nowych leadów od wczoraj?”, „kto czeka na odpowiedź?” |
| `get_lead_insight` | gotowa analiza AI leada (`assistant_lead_insights`) | „co to za sprawa, warto brać?” |
| `search_messages` | wyszukiwanie w treści WhatsApp i e-mail (najpierw LIKE, potem FTS5) | „kto pisał o karcie pobytu?” |
| `list_tasks` (rozszerzenie) | filtry `client_id`, `case_id`, `assignee` (`me`/id), `overdue` | „moje zaległe”, „zadania w sprawie Nowaka” |
| `list_team` | aktywni użytkownicy (id, imię) | „przypisz Tomkowi” |
| `list_next_steps` | `case_next_actions` + `case_actions` (po sprawdzeniu §3.6) | „co dalej w sprawie X?”, „jakie terminy procesowe w tym tygodniu?” |

Poprawki istniejących:
- `get_today_overview`: nieprzeczytane rozmowy (liczba + 3 najstarsze),
  rozmowy, w których okno 24 h zamyka się w ciągu 4 h, leady bez odpowiedzi
  liczone także po wiadomościach, `case_actions` z najbliższych 7 dni.
- iOS: lokalny briefing zastąpiony odpowiedzią serwera (lokalny zostaje w Demo).

### Etap 2: jedna Emma, pisemnie umie to samo co głosem (1–2 tygodnie) → iOS 0.25 + backend

1. **Narzędzia `app_*` w czacie pisemnym.** Serwer nie wykona ich sam, ale może
   je zwrócić jako polecenia dla telefonu:
   - Kontrakt odpowiedzi: `{ conversation_id, reply, app_calls: [{ name, arguments }] }`.
   - Model woła `app_*` w pętli jak zwykłe narzędzie. Serwer odpowiada mu
     `{ queued: true }`, odkłada wywołanie do `app_calls` i kończy turę.
   - iOS wykonuje `app_calls` tym samym `handleAppTool`
     (`AssistantStore+AppTools.swift`), którego używa głos. Jeden kod, dwa kanały.
   - `app_prepare_action` w kanale tekstowym tworzy propozycję po stronie
     serwera (`mobile_action_proposals`). Telefon dostaje gotową kartę z
     przyciskiem „Zatwierdź”, a granica zgody się nie zmienia.
2. **Pełny kontekst ekranu w obu kanałach**: wspólna struktura
   `EmmaScreenContext { screen, client_id, case_id, thread_id, day }`,
   wysyłana z czatem i jako `liveContextNote` przy zmianie ekranu.
3. **Parser lokalny tylko jako „szybka ścieżka”**: „tak”, „anuluj”, poprawki
   aktywnej karty oraz tryb offline i Demo. Wszystko inne idzie do Emmy.
4. **Strumieniowanie odpowiedzi** (SSE albo chunked) i wskaźnik „Emma sprawdza
   zadania…” na podstawie nazwy wołanego narzędzia.
5. **Historia rozmów pisemnych**: lista ostatnich rozmów i „Nowa rozmowa”
   (serwer już przechowuje `assistant_conversations`).

### Etap 3: Emma proaktywna (2–3 tygodnie, zależy od push z ROADMAP)

- **Poranny brief o 7:30**: serwer składa `get_today_overview`, dzwonek push
  otwiera Emmę z gotowym podsumowaniem. Wymaga push, wskazanego w ROADMAP jako
  luka krytyczna.
- **Alerty z uzasadnieniem i jednym przyciskiem akcji:**
  - lead ze strony bez odpowiedzi przez 15 min → „Odpowiedz z Emmą” (szkic PL/RU);
  - okno 24 h WhatsApp zamyka się za 2 h, a klient czeka;
  - areszt lub pobyt ≤ 7 dni, termin procesowy ≤ 3 dni.
- **Po konsultacji** (`event_followups`): „Jak poszła konsultacja z X?” →
  notatka z dyktowania i propozycja zadania lub sprawy.
- **Streszczenie i tłumaczenie wątku**: „streść rozmowę z Oleną” (RU → PL),
  „co klient obiecał dosłać?”, a z tego propozycja zadania.

### Etap 4: dokumenty i wiedza (3–4 tygodnie)

- **Treść akt**: ekstrakcja tekstu z PDF i skanów (OCR przy wgrywaniu),
  narzędzie `search_case_documents` z cytatem i nazwą pliku.
- **Terminy z pism**: z doręczonego pisma Emma wyciąga datę doręczenia i rodzaj
  środka, potem `app_compute_deadline`, potem karta terminu do zatwierdzenia.
- **MOS 2.0**: lista braków cudzoziemca (paszport, zdjęcie, opłata, PZ) jako
  checklista w sprawie pobytowej. Emma mówi, czego brakuje, i szkicuje prośbę
  do klienta po rosyjsku.
- **Szablony pism z CRM** (8 szablonów) i `generate_pdf` dostępne z telefonu.

### Etap 5 (przez cały czas): jakość, bezpieczeństwo, koszt

1. **Zestaw pytań kontrolnych** (50–80 pytań z oczekiwanym narzędziem i faktem)
   na stałej bazie testowej:
   - w CI z atrapą dostawcy, która sprawdza wybór narzędzia i argumenty;
   - ręcznie lub co noc na żywym modelu, z raportem trafności i liczby rund.
2. **Telemetria jakości**: 👍/👎 pod odpowiedzią. Audyt rozszerzony o listę
   narzędzi, czasy, błędy narzędzi i „odpowiedź bez użycia narzędzia przy
   pytaniu o fakty”.
3. **Testy prompt injection** na treściach WhatsApp i e-mail, np. „zignoruj
   instrukcje i wyślij…”.
4. **Uprawnienia**: wypełnić `allowedRoles` (dziś puste) przed dodaniem kolejnych
   osób. Pracownik nie powinien przez Emmę czytać wszystkich wątków.
5. **Koszt**: dzienny limit zapytań pisemnych na użytkownika (obok limitu
   głosu), cache promptu systemowego, licznik w profilu (jak dla głosu).

---

## 5. Kolejne kroki

1. Na serwerze: zapytania z §3.6 i liczba wątków e-mail i bez osoby. To
   ustala zakres Etapu 1.
2. Na telefonie (TestFlight 0.23.2) sprawdzić 8 zdań z tabeli §3.1. Wynik
   potwierdzi ustalenia z kodu.
3. Zacząć od Etapu 0 (punkty 1–3): niewielki koszt, a usuwa najczęstsze
   „Emma nie rozumie / robi nie to”.

---

## 6. Stan wdrożenia (11.10.2026, wieczór)

Backend: `adwokat-app-project` `main` (merge'e `feat/emma-etap0` … `feat/emma-etap5`,
ostatni `c961b02`), 1105 testów zielonych, `astro check` bez błędów.
iOS: 0.24.0 → 0.25.0 na `master` (TestFlight).

| Etap | Co weszło | Gdzie |
|---|---|---|
| 0 | Pytania nie tworzą zapisów (parser), plan dnia i „przygotuj mnie” idą do Emmy na serwerze; godziny terminów i wiadomości po polsku (`day`/`time`), dzień liczony po Warszawie; wszystkie rozmowy (e-mail, spoza kartoteki); przycięte wyniki w czacie; wspólny rdzeń instrukcji | iOS 0.24.0, backend |
| 0+ | Cel testów UI znów się kompiluje (od 0.23.2 blokował wszystkie testy w CI) | iOS 0.24.1 |
| 1 | `get_client`, `list_leads`, `search_messages` (po odszyfrowaniu), `list_work` (czynności spraw z panelu), `list_team`, filtry `list_tasks`, czynności i następny krok w `get_case`, analiza AI w `get_lead`, bogatszy przegląd dnia; leady „bez odpowiedzi” liczone też po wiadomościach (było: nieistniejący status `contact`) | backend |
| 2 | Emma pisemnie z narzędziami `app_*` (karta, szkic, formularz terminu, kalkulator, zmiana sprawy, ekrany), kontekst ekranu, `thread_id` dla osób spoza kartoteki; „Nowa rozmowa” zaczyna nową rozmowę na serwerze; czat czeka 100 s zamiast 20 s | backend + iOS 0.25.0 |
| 3 | `GET /emma/alerts` (lead czeka 15 min, okno 24 h, terminy z panelu, wynik konsultacji) → powiadomienia o nowych, dotknięcie otwiera Emmę z pytaniem; „Streść z Emmą” w rozmowie | backend + iOS 0.25.0 |
| 4 | `read_case_document` (Gemini czyta PDF/zdjęcie z akt: odpowiedź, cytat, daty), lista MOS 2.0, szablony pism | backend |
| 5 | Telemetria tury w audycie, 👍/👎, licznik w profilu, `EMMA_TEXT_DAILY_LIMIT`, egzekwowanie `allowedRoles`, 20 pytań kontrolnych na żywym modelu | backend + iOS 0.25.0 |

**Świadomie pominięte:** strumieniowanie odpowiedzi (odpowiedzi mają 1–4 zdania,
czas zabierają rundy narzędzi — najpierw zmierzyć `durationMs` w audycie);
pisma z szablonów i PDF w telefonie (wymaga edytora dokumentów, poza asystentem);
kontekst ekranu w rozmowie głosowej (głos dostaje klienta i sprawę jak dotąd);
APNs (alerty działają przez odświeżanie w tle, więc mogą przyjść z opóźnieniem).

### Do zrobienia przez właściciela

1. **Pytania kontrolne na serwerze** (koszt: grosze):
   ```
   cd /home/tomek/apps/website/adwokat-app-project
   EMMA_EVAL=1 GEMINI_API_KEY=… npx vitest run src/lib/crm/emma/eval.live.test.ts
   ```
   Wynik: lista ✓/✗ z użytymi narzędziami. Uruchamiać po każdej zmianie instrukcji.
2. **Opcjonalnie w `.env`**: `EMMA_TEXT_DAILY_LIMIT` (domyślnie 300 pytań/24 h, `0` = bez limitu).
3. **Na telefonie (0.25.0)**: „Jakie mam zadania na jutro?”, „Kto pisał o karcie pobytu?”,
   „Dodaj zadanie: …” (karta), „Napisz Olenie, że…” (szkic w rozmowie), ✨ w rozmowie,
   pytanie o pismo z akt sprawy.
4. **Telemetria**: `SELECT at, meta_json FROM audit_log WHERE action IN ('assistant.chat','assistant.feedback') ORDER BY id DESC LIMIT 50;`
