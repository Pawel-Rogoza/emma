# M2b — repozytorium HTTP: aplikacja czyta prawdziwą bazę kancelarii

Data: 2026-09-14
Zakres: `ios/Emma/Core/Data`, `AppDependencies`, `Package.swift`, `EmmaUITests/BackendLoginUITests.swift`
Backend, na którym to sprawdzono: `emma/m0-higiena`, build z 2026-09-14 (M0–M2c)

## 1. Co powstało

Do tej pory aplikacja czytała dane z `MockRepository` i tylko logowanie szło do
backendu (M1). Teraz warstwa danych ma drugą implementację tego samego protokołu:

| Plik | Rola |
| --- | --- |
| `Core/Data/BackendAPIClient.swift` | transport i dekodowanie JSON-a kontraktu (`/clients`, `/clients/{id}`, `/cases`, `/cases/{id}`, `/tasks`, `/events`, `/briefing`) |
| `Core/Data/BackendRepository.swift` | `EmmaRepository` na HTTP: mapowanie DTO → modele aplikacji |
| `App/AppDependencies.swift` | wybór implementacji: `staging` + `EMMA_API_BASE_URL` → `BackendRepository`, inaczej `MockRepository` |
| `Package.swift` | `Core/Data` dopisane do **jawnej** listy źródeł `EmmaCore` |

Zasada, która rządzi tą warstwą: **każda trasa, której kontrakt nie ma, rzuca
`notAvailableInBackend` z nazwą operacji**. Nie ma przypadku, w którym brak
danych zamieniamy na pustą listę udającą sukces. Dlatego:

- odczyt (klienci, sprawy, zadania, terminy, notatki, historia, briefing) — działa,
- zapis (nowy klient, zmiana, odhaczenie zadania, notatka, termin) — zgłasza brak trasy,
- wiadomości i głos — jw.

`MockRepository` **nie został usunięty**: tryb Demo nadal go używa, a oznaczenia
demo zostają, dopóki nie ma prawdziwego głosu i WhatsAppa.

## 2. Dowód, że to prawdziwa integracja, nie atrapa

| Dowód | Wynik |
| --- | --- |
| `swift test` (pakiet `EmmaCore`) | **289/289 PASS** |
| `xcodebuild test -only-testing:EmmaTests` | **359/359 PASS** |
| `xcodebuild test -only-testing:EmmaUITests` (Demo) | bez regresji |
| Test integracyjny `testRealBackendDataAppearsInClientsAndCard` | **PASS** (15,2 s) na backendzie z prawdziwą bazą |
| Backend `npx vitest run` | **875/875 PASS** (112 plików) |
| Backend `npx astro check` | 0 błędów, 0 ostrzeżeń |

Test integracyjny nie mógłby przejść na atrapie, bo dane w bazie zostały
**zmienione na takie, których nie ma żadna fikstura**:

```
UPDATE clients SET name='Zenon Backendowicz-Testowy' WHERE id=1;
UPDATE cases   SET signature='II K 999/26' WHERE id=1;
```

a test z tymi właśnie wartościami przeszedł: zakładka „Klienci” pokazała
`Zenon Backendowicz-Testowy`, a jego karta — sprawę `II K 999/26`.

Trzeci, niezależny dowód: po przebiegu aplikacja ma **własną sesję** w bazie,
utworzoną przez HTTP (a nie przez `curl`):

```
installation_id                        | device_name   | aktywna
8F7B66CC-A226-46DB-AE63-6EF5DBF885BE   | iPhone 17 Pro | 1
```

(`mobile_sessions`, `revoked_at IS NULL`). Sesji nie tworzy żadna atrapa.

## 3. Zrzuty ekranu (odczyt tekstu z obrazu)

Zrzuty pochodzą z przebiegu testu integracyjnego i zostały odczytane OCR
(polski + ukraiński), bo autor zmian nie odczytuje obrazów bezpośrednio.

**M2-01 — zakładka „Klienci” na danych z bazy:**
`BAZA KANCELARII | Klienci | Leady | Sprawy | Тарас Шевченко | Proszę o konsultację w sprawie wizy. | Termin do ustalenia | W kontakcie | ZB | 14 wrz, 10:30 | Ukraiński | Zenon Backendowicz-Testowy | Pytanie o termin w sprawie prawa jazdy.`

**M2-02 — karta klienta z bazy:**
`Karta klienta | ZB | Zenon Backendowicz-Testowy | Pytanie o termin w sprawie prawa jazdy. | W kontakcie | Ukraiński | WhatsApp | Notatka | Umów | Źródło | Formularz WWW | K 999/26 | Zatrzymanie prawa jazdy`

Na zrzutach widać dane, których w atrapach nie ma: lead z WhatsAppa
(„Тарас Шевченко”), termin 14 wrz 10:30 i sprawę `II K 999/26`. OCR zgubił
„II” w sygnaturze — w bazie i w odpowiedzi API jest `II K 999/26`.

## 4. Co musiałem poprawić po drodze

1. **Słownik terminów w repozytorium był o krok za kontraktem.** Kod dekodował
   `hearing`/`meeting`/`planned`, a backend po etapie M2 wysyła `consultation` /
   `case_deadline` i `to_confirm`. Poprawione; `all_day` i `place` są teraz
   dekodowane, a nie odgadywane.
2. **Model `ScheduledEvent` nie znał terminu całodniowego.** Doszło pole
   `isAllDay` z wartością domyślną `false` (nie łamie istniejących konstruktorów).
3. **Brakiem trasy `GET /cases` zablokowana była zakładka „Sprawy”.** Dodane:
   kontrakt (`/cases` → `get`) i backend (`listMobileCases` + trasa). Filtry:
   `status`, `client_id`, `limit`; nieznany status jest ignorowany, a nie zgadywany.
4. **`incoming_time` w kontrakcie nie dopuszczało `null`**, a backend musi je
   wysłać, gdy nie ma wiadomości. Pole jest nullowalne — inaczej trzeba by
   wpisać 00:00, czyli nieprawdę.
5. **Błąd w moim własnym teście:** w Swift surowy string wieloliniowy zaczyna
   treść w nowej linii, więc JSON w tej samej linii co `"""` doklejał dwa
   cudzysłowy do danych. Test przechodził na fiksturze, a tu zgłosił
   „The given data was not valid JSON”. Poprawione i opisane w komentarzu.

## 5. Ograniczenia (świadome, nierozwiązane)

- **Zapis nie działa.** Kontrakt opisuje `POST`/`PATCH`/`DELETE`, ale backend ich
  nie ma (to etap M4). Repozytorium rzuca `notAvailableInBackend`, a ekrany
  pokazują komunikat — nie udają zapisu.
- **Termin całodniowy pokaże godzinę 00:00.** Model zna już `isAllDay`, ale
  widoki jeszcze go nie używają: `ScheduledEvent.time` jest nieopcjonalne, więc
  przy `all_day: true` wchodzi północ jako „brak godziny”. Widać to na
  terminach z bazy produkcyjnej (1 z 20). To zmiana w widokach, nie w danych —
  czeka na decyzję, jak taki termin ma wyglądać.
- **Okno czasowe terminów jest wymagane.** Kontrakt ma `from`/`through`;
  aplikacja pyta zakresem, więc nie ma „wszystkich terminów klienta”.
- **Wiadomości i głos to nadal atrapy.** Backend nie ma wątków ani
  `/voice/conversation-token`; oznaczenia demo zostają.
- **Odczyt pojedynczego zadania i terminu** nie ma trasy, więc zgłasza brak.
- **Brak trasy listy spraw był realnym brakiem** — dodana, ale nie ma jeszcze
  `GET /tasks/{id}`, `GET /events/{id}` ani paginacji po kursorze
  (`next_cursor`/`has_more` w `/clients` liczy backend, aplikacja czyta pierwszą stronę).
- **Konto w produkcji:** 2 z 3 kont nie mają hasła (logowanie passkey), więc
  logowanie do aplikacji wymaga jeszcze etapu M1b.
