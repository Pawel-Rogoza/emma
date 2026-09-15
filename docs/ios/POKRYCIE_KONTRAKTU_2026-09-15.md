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

---

## Dodawanie zgłoszenia z aplikacji (POST /clients) — 2026-09-15

**Dlaczego:** przycisk „+” w nagłówku „Klienci” istniał, ale w produkcji kończył
się komunikatem „Backend nie udostępnia jeszcze…”. Repozytorium nie wołało trasy
`POST /api/mobile/v1/clients`, która **już istniała** w backendzie. To była praca
wyłącznie po stronie aplikacji — bez zmian w backendzie i bez wdrożenia.

**Kontrakt (`NewClient`):** `display_name`, `topic`, `language` (wymagane),
`stage`, `source`. Formularz „Nowy kontakt” pyta dodatkowo o **kontekst
zgłoszenia**, którego kontrakt nie zna — CRM trzyma w leadzie jeden wolny tekst
(`leads.message`, widoczny i przeszukiwalny w panelu). Kontekst jest więc
dokładany jako drugi akapit tej samej treści. Bez tego użytkownik wpisałby
kontekst, a on przepadłby po cichu.

**Źródło `Polecenie`:** `ClientSource.referral` nie ma odpowiednika w słowniku
kontraktu (`manual`/`web_form`/`whatsapp`/`import`). Zamiast sprowadzać je do
`manual` (kłamstwo w bazie) repozytorium zgłasza brak trasy, a **żądanie nie
powstaje wcale** — jest na to test.

**Weryfikacja końcowa — nie mock:**
1. Aplikacja (testy ze stubem): dokładne ciało żądania, ścieżka, metoda,
   `Idempotency-Key`; brak kontekstu = sam temat; `referral` bez żądania.
2. **Prawdziwy backend na tymczasowej bazie** (`astro dev`, `CRM_DATA_DIR` w `/tmp`,
   konto lokalne, hasło przez `scripts/mobile-set-password.mjs`), te same ciała
   żądań co aplikacja:
   - `POST /clients` → **201**, `lead-1`, etap `new`, źródło `manual`, język `pl`;
   - ten sam klucz idempotencji dwa razy → nadal **1** lead w tabeli;
   - `PATCH /clients/lead-1` z `stage: in_contact` → **200**, etap `in_contact`,
     wersja 2; licznik `stage=new` spadł do 0;
   - nieaktualny `expected_version` → **409** z `current_version` (blokada działa).
3. **Aplikacja przeciw prawdziwemu backendowi** (`EMMA_UI_BACKEND_URL` na lokalny
   serwer, test `testRealAddAndDeleteLeadRoundTrip`, bramkowany `EMMA_UI_ALLOW_WRITES=1`,
   żeby nigdy sam nie pisał do produkcji): po dodaniu kontaktu z formularza w bazie
   powstał `lead-2`: status `new`, źródło `manual`, treść
   `"Zgłoszenie z testu integracyjnego\n\nKontekst z testu."` — czyli kontekst
   dotarł na miejsce. `audit_log`: `lead.create` ×2, `lead.update` ×1.
4. Po weryfikacji: serwer zatrzymany, tymczasowa baza i schemat z hasłem usunięte.
   **Produkcja nie została tknięta żadnym zapisem.**

**Poprawka przy okazji:** konflikt wersji (409) nie jest `DomainError`, więc ekran
pokazywał bezradne „Nie udało się wykonać operacji.” mimo komunikatu backendu
(„Dane kontaktu zmieniły się od czasu odczytu. Odśwież i spróbuj ponownie.”).
Repozytorium tłumaczy teraz 409 na `DomainError.versionConflict`, więc użytkownik
dostaje komunikat, przy którym wie, co zrobić.

**Testy:** `BackendRepositoryTests` **20/20** (m.in. ciało `POST`, idempotencja,
`referral`, konflikt wersji), `ClientsLeadMenuUITests` **3/3** (domyślny filtr,
menu etapów, dodanie kontaktu do listy).

**Ograniczenia:**
- Test zapisu przez aplikację **nie** był uruchamiany przeciw produkcji — celowo:
  założyłby tam prawdziwe zgłoszenie. Produkcja jest sprawdzona odczytem
  (`testRealNewLeadsAreDefaultView`).
- `stage` w `POST` nie jest wysyłany z aplikacji: nowe zgłoszenie zawsze startuje
  jako `new`, a konwersję na kartotekę robi się świadomie z menu etapów.
- Formularz nie zbiera telefonu ani e-maila, choć tabela `leads` ma takie kolumny
  — kontrakt `NewClient` ich nie zna. Dodanie ich to zmiana kontraktu + backendu.

---

## Usuwanie zgłoszenia (DELETE /clients/{client_id}) — 2026-09-15

**Decyzja:** Tomasz poprosił o usuwanie leada z menu po przytrzymaniu.
Kontrakt mobilny nie znał takiej trasy, więc trzeba było dołożyć ją świadomie —
razem z backendem, bo trasa bez wdrożenia byłaby przyciskiem, który w produkcji
zawsze zawodzi.

**Zakres jest celowo węższy niż nazwa trasy:** usuwamy **tylko zgłoszenie**
(`lead-N`), nigdy kartotekę (`client-N`). Kartoteka ma sprawy, terminy
i dokumenty, a panel kancelarii też jej nie usuwa — aplikacja nie może być tu
furtką. Żądanie na `client-N` kończy się `422 validation_failed` z wyjaśnieniem,
a aplikacja w ogóle go nie wysyła (pozycja menu jest tylko dla zgłoszeń).

**Reguła usuwania jest wspólna z panelem.** Tombstone dla leada z rezerwacji
(`lead_tombstones`), kasowanie rekordu i audyt `lead.delete` wyjęte do
`deleteLeadRecord` w `src/lib/crm/leads.ts`; korzysta z niej trasa panelu
i warstwa mobilna. Bez tego panel i aplikacja mogłyby z czasem zacząć usuwać
inaczej. Po usunięciu leada z rezerwacji okienko na stronie jest zwalniane tą
samą decyzją co w panelu (`reject`, bez e-maila do klienta).

**Wymagane `expected_version`** w ciele — tak samo jak przy usuwaniu terminu:
dwa urządzenia widzą to samo zgłoszenie, jedno je usuwa, drugie nie może usunąć
czegoś, czego nie widziało. Nieaktualna wersja to `409 version_conflict`
z aktualnym numerem, a rekord **zostaje**.

**Aplikacja:** `DELETE` z kluczem idempotencji, tłumaczenie 409 na
`DomainError.versionConflict` (wspólne z `PATCH`), pozycja „Usuń zgłoszenie”
w menu po przytrzymaniu i pytanie o potwierdzenie z nazwą osoby — przy dwóch
podobnych zgłoszeniach łatwo skasować nie to.

**Weryfikacja:**
- Backend: **117 plików / 933 testy**, 0 porażek (4 nowe: usunięcie + tombstone
  + audyt, nieaktualna wersja, odmowa dla kartoteki, brak klucza idempotencji).
  `astro check`: 0 błędów. Cały zestaw panelu zielony po refaktorze reguły.
- Aplikacja: `BackendRepositoryTests` **22/22** (ciało `DELETE`, klucz, brak
  żądania dla kartoteki), `ClientsLeadMenuUITests` **4/4** (pełna droga:
  przytrzymanie → „Usuń zgłoszenie” → potwierdzenie → karta znika).
- **Prawdziwy backend** (tymczasowa baza w `/tmp`): `POST` → 201, `DELETE`
  z wersją → **204**, lista pusta, w bazie **0 leadów**, audyt `lead.delete`;
  lead z rezerwacją → **tombstone** `ref-usuwanie-1`, kartoteka nietknięta;
  nieaktualna wersja → **409** i rekord zostaje; `client-N` → **422**.
- **Aplikacja przeciw prawdziwemu backendowi** (`testRealAddAndDeleteLeadRoundTrip`,
  bramkowany `EMMA_UI_ALLOW_WRITES=1`): dodała zgłoszenie z formularza, usunęła
  je z menu po przytrzymaniu, a w bazie zostało `lead.delete` z
  `meta_json: {"channel_app":"ios"}` — czyli usunięcie naprawdę przyszło z iOS.
- Po weryfikacji: serwer zatrzymany, baza tymczasowa i schemat z hasłem usunięte.
  **Produkcja nietknięta.**

**Ograniczenia:**
- Trasa istnieje **tylko w repozytorium** do momentu wdrożenia backendu na VPS.
  Dopóki nie jest wdrożona, usuwanie w aplikacji produkcyjnej nie zadziała —
  dlatego instalacja nowego builda czeka na decyzję o wdrożeniu.
- Usunięcie jest twarde (kasuje wiersz). Historia w `audit_log` zostaje, ale
  w panelu nie ma kosza ani przywracania leada; lead z rezerwacji ma tylko
  tombstone chroniący przed ponownym importem.
- Telefon nie pojawia się w oknie „Wymaga odpowiedzi” ani inne znane braki
  kontraktu (`phone`, `email`) — bez zmian.
