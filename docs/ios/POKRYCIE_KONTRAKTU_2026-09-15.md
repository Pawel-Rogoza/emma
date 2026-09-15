# Pokrycie kontraktu mobilnego — stan na 2026-09-15

Dokument jest **dowodem**, nie planem: pokazuje, które trasy z
`docs/ios/api/emma-mobile-api.yaml` mają odpowiednik w kodzie backendu, a które
nie. Wygenerowane porównaniem specyfikacji z plikami w
`src/pages/api/mobile/v1/` (trasy dynamiczne normalizowane: `[client_id]` =
`{client_id}`).

## Wynik

**23 z 28 tras pokrytych. Brakuje 5.**

| Trasa | Stan |
| --- | --- |
| `/auth/login`, `/auth/refresh`, `/auth/revoke` | pokryte |
| `/briefing` | pokryte |
| `/clients`, `/clients/{client_id}` | pokryte |
| `/cases`, `/cases/{case_id}` | pokryte |
| `/tasks`, `/tasks/{task_id}` | pokryte |
| `/events`, `/events/{event_id}` | pokryte |
| `/notes` | pokryte |
| `/actions`, `/actions/{action_id}`, `/confirm`, `/execution`, `/cancel` | pokryte (commit `1a9a735`, **niewdrożone**) |
| `/voice/sessions`, `/conversation-token`, `/{id}`, `/{id}/context`, `/{id}/status` | pokryte |
| `/threads`, `/threads/{id}/messages`, `/threads/{id}/read-state` | **brak** |
| `/sync/changes`, `/push/devices` | **brak** |

## Dlaczego brakuje tych pięciu

- **`/threads` (3 trasy)** — brak kanału WhatsApp Business: nie ma konta,
  numeru telefonu ani tabeli z treścią wiadomości. Wątki bez treści byłyby
  pustym ekranem udającym funkcję, dlatego ich nie ma. Zablokowane zewnętrznie,
  nie technicznie.
- **`/sync/changes`, `/push/devices`** — poza zakresem celu, który wyliczał
  logowanie, leady/klientów/sprawy/zadania/zdarzenia, pliki, akcje i
  `/voice/conversation-token`. Do zrobienia, gdy pojawi się synchronizacja
  przyrostowa i powiadomienia (APNs wymaga klucza `p8`, Key ID i Team ID).

## „Leady" — pokryte inaczej, niż sugeruje nazwa

Kontrakt **nie ma** trasy `/leads` i to jest celowe: warstwa mobilna scala
leady i kartotekę w jedną listę etapów (`mergeClients` w
`src/lib/crm/mobile/read.ts`), a etap bierze z najdalej posuniętego aktywnego
leada. Klient bez leadów jest klientem. Dzięki temu aplikacja nie pokazuje
dwóch wpisów dla tej samej osoby — jedna osoba, jedna pozycja.

## „Pliki" — jedyna pozycja celu bez odpowiednika

Cel wymienia pliki, ale **kontrakt ich nie definiuje** (pliki występują w nim
tylko jako rodzaj załącznika w wiadomości: `kind: attachment`). W kodzie
aplikacji typ encji `'file'` jest zadeklarowany (`dto.ts:28`), lecz **nikt go
nie produkuje**, a klient HTTP aplikacji nie ma ani jednego wywołania plików.
Backend ma natomiast gotowy podsystem dla panelu: tabele `files` + `file_meta`
(foldery, grupy wersji, `version_number`, `is_current`), logikę `fileMeta.ts`
i trasy `/api/crm/files/[id]`.

Wniosek: to nie zepsuta funkcja, a **niedomknięty zakres** — brakuje decyzji
o kształcie odpowiedzi, bo nie ma go skąd wziąć. Gdy zdecydujesz, wystawienie
listy plików dla sprawy to kilka tras korzystających z istniejącej logiki,
a nie nowy magazyn.

## Weryfikacja, na której opiera się ten dokument

- Pełny zestaw backendu: **116 plików / 924 testy, 0 porażek**.
- Panel CRM **nie jest złamany** przez warstwę mobilną: `npm run test:e2e`
  → **65/65 testów przechodzi** (przebieg po dodaniu akcji mobilnych, które
  korzystają ze wspólnego przebiegu zapisu).
- `npx astro check`: **0 błędów**.
- `npm run build`: przechodzi.
- Migracja `045` na istniejącej bazie: 44 → 45, tabele akcji powstały;
  powtórne uruchomienie zatrzymuje się na 45.
- Aplikacja iOS na urządzeniu: rozmowa dwukierunkowa działa, narzędzia agenta
  wołane w trakcie rozmowy (audyt: `get_today_overview`, `search_clients` — 200).

## Naprawa listy klientów: ucięta lista i brak kursora (2026-09-15)

Zgłoszenie: „lista klientów ma działać, leady mają być zaciągane ze strony, gdy
ktoś zarezerwuje konsultację".

**Potwierdzone w kodzie i na produkcji — droga rezerwacji działa:** publiczny
formularz (`src/components/islands/BookingRequest.tsx`) strzela w
`/api/booking/request`, a ta trasa woła `recordPublicLead` → `createLead` ze
statusem `new` i `booking_ref`. W bazie produkcyjnej jest **21 leadów
z rezerwacji** (7 nowych, 7 w kontakcie, 6 klientów, 1 zamknięty), najnowszy
z 2026-09-15 13:09. Leady **są** więc zaciągane.

**Błąd był w liście:** trasa `/clients` oddawała `has_more: true` razem
z `next_cursor: null`, a aplikacja pobierała pierwsze 30 pozycji i ignorowała
resztę. Na produkcji lista ma 37 pozycji, więc **7 z 21 klientów było
niewidocznych** (nowi i w kontakcie mieścili się w limicie). Drugie, głębsze
źródło tego samego błędu: funkcja listy pobierała z każdego źródła tylko
`limit * 3` wierszy, a filtr etapu działał dopiero po scaleniu — oba te miejsca
uniemożliwiały poprawne stronicowanie (przy `limit = 1` lista urywała się na
12 z 37 pozycji).

**Naprawa:**
- `src/lib/crm/mobile/read.ts` — parametr `offset`, pobranie `offset + limit`
  z obu źródeł, filtr etapu przeniesiony do SQL, kartoteka czytana tylko dla
  etapu `client`.
- `src/pages/api/mobile/v1/clients/index.ts` — `cursor`, `next_cursor`
  i `has_more` liczone z pobrania o jedną pozycję więcej, niż oddajemy.
- iOS `BackendRepository.clients` — domyka stronicowanie (do 10 stron, czyli
  300 kontaktów), więc pełny zbiór dostają wszystkie ekrany, nie tylko lista.

**Wynik testów:** backend 117 plików / **928 testów, 0 porażek** (w tym 4 nowe
testy stronicowania przechodzące wszystkie strony kursorami bez braków
i duplikatów); `astro check` 0 błędów / 0 ostrzeżeń; panel 65/65 e2e; iOS
`Emma-Demo` — **TEST SUCCEEDED**.

**Wdrożone i potwierdzone na produkcji (2026-09-15):** push `main`
`5fd657b..e576cca` (fast-forward) uruchomił wdrożenie; zaraz po nim produkcja
zaczęła oddawać `next_cursor` przy 30 pozycjach, a przejście wszystkich stron
kursorami dało **37 pozycji, 37 unikalnych** — zero braków i duplikatów.
Aplikacja Production z tą poprawką zainstalowana na telefonie.

**Ograniczenie:** kolumna `next_cursor` działa jako przesunięcie w scalonej
liście, więc kolejność musi być deterministyczna między zapytaniami. Jest
(etap, potem data), ale przy rosnącej bazie warto rozważyć prawdziwy kursor
oparty na kluczu, gdyby doszło jednoczesne dodawanie rekordów w trakcie
przewijania. Ostatnia strona listy mogła się przy tym przesunąć o nowy wpis —
to znany kompromis przesunięcia liczbowego, nie błąd danych.

**Odkrycie operacyjne i stan po pushu:** `origin/main` **nie zawierał
warstwy mobilnej** (`src/pages/api/mobile/v1/...` nie istniał na `origin/main`),
mimo że produkcja ją obsługiwała — wdrożenie poszło ręcznym wyzwoleniem
`deploy.yml` (`workflow_dispatch`), a nie pushem do `main`. Lokalny `main` był
23 commity przed `origin/main` i **0 za**, więc push był fast-forwardem.
**Rozjazd zamknięty:** `origin/main` wskazuje teraz `e576cca`, czyli warstwa
mobilna, akcje i poprawka listy są wreszcie w repozytorium, nie tylko na dysku.
Osobno została gałąź `feat/akcje-mobilne` (`1a9a735`) jako punkt cofnięcia
samych akcji.

## „Nie udało się wczytać bazy kancelarii" — termin bez klienta (2026-09-15)

Zgłoszenie po wdrożeniu poprawki listy: zakładka „Klienci" pokazuje
„Nie udało się wczytać bazy kancelarii." z przyciskiem „Spróbuj ponownie",
choć inne ekrany działają.

**Jak to zostało ustalone (dowody, nie domysły):**
1. Log serwera (`/var/log/nginx/advokat-varshava_access.log`) pokazał żądania
   z telefonu (`Emma/1 CFNetwork…`): `/clients?limit=30`,
   `/clients?limit=30&cursor=30`, `/cases`, `/tasks`, `/events` — **wszystkie
   200**. Czyli serwer był zdrowy, a mimo to ekran pokazywał błąd.
2. Skoro odpowiedzi były 200, winne było dekodowanie po stronie aplikacji.
3. Uruchomienie istniejącego testu integracyjnego
   (`BackendLoginUITests.testRealBackendDataAppearsInClientsAndCard`) przeciw
   produkcji **odtworzyło błąd co do znaku** — na zrzucie ekranu (odczytanym
   OCR-em) widać było dokładnie ten komunikat.
4. Kontrola danych: w oknie terminów ±3 lata jest **20 terminów, z czego jeden
   bez `client_id`** (konsultacja zapisana z samego zgłoszenia, zanim powstała
   kartoteka). `events.client_id` w bazie jest opcjonalne, a kontrakt mobilny
   (`NewEvent`/`Event`) wymaga go — więc backend wysyłał dane niezgodne
   z kontraktem, a aplikacja deklarowała `clientID: String` (wymagane), więc
   **JSON całej odpowiedzi się nie dekodował** i gasł cały ekran.
5. Dlaczego „Dzisiaj" działało: ten ekran pyta o wąskie okno jednego dnia,
   w którym feralnego terminu nie ma. „Klienci" pytają o ±3 lata.

**Naprawa:**
- Backend `listMobileEvents`: odsiewa `e.client_id IS NULL`. Panel nadal widzi
  taki termin — mobilna warstwa nie wysyła tylko danych niezgodnych
  z kontraktem. Test: termin bez klienta nie pojawia się, a każdy zwrócony ma
  niepuste `client_id`.
- Aplikacja: `BackendEventDTO.clientID` jest opcjonalne, a repozytorium
  **pomija** termin bez klienta (`compactMap`) zamiast rzucać. Jeden rekord nie
  ma prawa gasić całego ekranu — to obrona przed każdym przyszłym naruszeniem
  kontraktu, nie tylko tym jednym.
- Test integracyjny zamyka systemowe okno „Zachować hasło?", które
  przechwytywało pierwszy tap po zalogowaniu i dawało fałszywy wynik
  (na zrzucie widać było zakładkę „Dzisiaj" mimo próby wejścia w „Klienci").

**Weryfikacja:** po poprawce aplikacji ten sam test przeciw **produkcji**
(która wciąż wysyła feralny termin) wchodzi w „Klienci" i pokazuje realne
wiersze: nagłówek „BAZA KANCELARII", filtry „Wszystkie / Nowe / W kontakcie"
i prawdziwe zgłoszenia (w tym jedno po ukraińsku) — bez komunikatu błędu.
Backend: 117 plików / 929 testów, 0 porażek.

**Ograniczenie:** termin bez kartoteki nadal istnieje w bazie i w panelu, ale
w aplikacji go nie widać — nie ma go do kogo przypiąć (model aplikacji wiąże
termin z klientem i sprawą). Gdyby kancelaria chciała widzieć konsultacje osób
będących jeszcze tylko leadami, trzeba najpierw rozstrzygnąć, czy w terminie
mobilnym `client_id` może być puste (zmiana kontraktu + modelu aplikacji).

---

## Lista leadów: domyślny filtr, liczniki i menu po przytrzymaniu (2026-09-15)

**Zgłoszenie:** „trzeba przerobić leady, tak by domyślnie pokazywały się tylko
nowe, plus ogólnie usprawnić cały ten widok klientów/leadów | aktualnie apka
pokazuje zbyt wiele nowych, wydaje mi się, że aż tyle nie ma i coś się zbugowało
z tym statusem | fajnie jakby można było przytrzymać palcem lead i pojawiła się
opcja edycji/usunięcia”.

**Czy status jest zbugowany — sprawdzone w bazie produkcyjnej (odczyt):**

| etap | leady |
|---|---|
| `new` | 8 |
| `consultation` | 8 |
| `client` | 8 |
| `closed_lost` | 1 |

Osiem zgłoszeń `new` pochodzi z 31.08–15.09.2026, **każde ma `client_id IS NULL`
i zero terminów**. Wniosek: mapowanie statusów jest poprawne, a stos „nowych” to
naprawdę nieprzerobione zapytania ze strony — nie błąd. Ekran pokazywał wszystkie
25 kontaktów naraz, więc te 8 ginęło w tłumie; stąd wrażenie „za dużo nowych”.

**Zmiany w aplikacji (`ios/`):**
1. Ekran „Klienci” otwiera się na filtrze **Nowe** (wcześniej „Wszystkie”),
   a przełączenie Leady/Sprawy wraca do niego.
2. Filtry pokazują **liczniki** („Nowe 8”, „W kontakcie 8”) — policzone z danych
   już wczytanych, bez dodatkowych zapytań.
3. Karta leada bez terminu pokazuje **datę zgłoszenia** („Zgłoszono dzisiaj”,
   „Zgłoszono 13 wrz”) zamiast mylącego „Termin do ustalenia”.
4. Przytrzymanie karty otwiera menu: przeniesienie między etapami
   (nowe / w kontakcie / klient) oraz zmianę nazwy. Wejście na etap „klient”
   jest w backendzie **konwersją zgłoszenia w kartotekę** — dlatego jest osobną
   pozycją menu, a nie skutkiem ubocznym.
5. Karta ma `accessibilityIdentifier("lead-card")`, bo etykieta dla VoiceOver
   niesie treść i nie da się po niej stabilnie trafić w testach.

**Zapis:** `PATCH /api/mobile/v1/clients/{client_id}` (trasa istniała w backendzie,
aplikacja jej nie używała). Repozytorium wysyła **tylko pola, które różnią się
od stanu z serwera** — nazwę i/lub etap — razem z `expected_version` (blokada
optymalizacyjna) i `Idempotency-Key`. Brak różnic = brak żądania zapisu.
Zgodność nazw sprawdzona w kodzie obu stron: backend czyta `display_name`,
`stage`, `expected_version` oraz nagłówek `idempotency-key`.

**Usuwania nie ma i nie udajemy, że jest.** Kontrakt mobilny ma `DELETE` tylko
dla `/events/{event_id}`, `/voice/sessions/{session_id}` i `/push/devices`.
Panel kancelarii umie usunąć leada (`src/pages/api/crm/leads/[id]/index.ts`),
więc dodanie `DELETE /clients/{client_id}` do kontraktu + trasy mobilnej jest
wykonalne — czeka na decyzję, bo to operacja nieodwracalna i zmienia kontrakt.

**Weryfikacja:**
- Aplikacja: 3 nowe testy repozytorium (etap+`expected_version`+klucz; brak zmian
  = brak zapisu; nazwa bez etapu) — razem **17/17** w `BackendRepositoryTests`.
- Nowy plik `EmmaUITests/ClientsLeadMenuUITests.swift`: domyślny filtr „Nowe”
  oraz pełne przeniesienie leada po przytrzymaniu (menu → etap → zgłoszenie
  znika z filtra „Nowe”). 2/2 przechodzą.
- Produkcja (odczyt, bez zapisu): test `testRealNewLeadsAreDefaultView` po
  zalogowaniu na `advokat-varshava.pl` — filtr „Nowe” zaznaczony domyślnie,
  na zrzucie liczniki **Wszystkie 16 / Nowe 8 / W kontakcie 8** i realne wiersze
  „Zgłoszono dzisiaj”, „Zgłoszono 13 wrz”. Licznik „Nowe 8” zgadza się co do
  jednego z odczytem z bazy — to zamyka pytanie o zbugowany status.
- Test `testRealBackendDataAppearsInClientsAndCard` szukał klienta na liście,
  licząc na domyślne „Wszystkie”; teraz wybiera ten filtr **jawnie**, żeby zmiana
  domyślnego widoku nie robiła z niego fałszywego alarmu.

**Ograniczenia:**
- Liczniki pokazują tylko to, co aplikacja ma wczytane. Lista schodzi po
  kursorach do 10 stron po 30 pozycji; przy większej bazie licznik „Wszystkie”
  policzy mniej, niż jest w kancelarii.
- Przeniesienie etapu na „klient” **zakłada kartotekę** i jest nieodwracalne
  z aplikacji (kontrakt nie zna etapu wstecz).
- Menu nie ma „Wymaga odpowiedzi”, choć backend to pole przyjmuje — czeka na
  decyzję, czy to ma być element listy, czy osobna akcja.

**Zrzuty:** `docs/ios/screenshots/leady-2026-09-15/` — `produkcja-nowe-zgloszenia.png`
(prawdziwe dane: liczniki i „Zgłoszono …”), `menu-po-przytrzymaniu.png` (menu etapów)
oraz `demo-lista-nowe.png`.
