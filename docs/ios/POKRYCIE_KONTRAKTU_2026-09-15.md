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
