# Emma iOS — realizacja planu z audytu UX i głosu (13.09.2026)

Dokument postępu dla planu z §7 `docs/ios/UX_VOICE_AUDIT_2026-09-13.md`.
Prowadzony etapami. Każdy etap ma: potwierdzenie ustalenia w kodzie, zakres zmian,
wynik testów i jawne ograniczenia. Nie wpisujemy tu deklaracji bez dowodu.

Kod bazowy audytu: `8495ca0` (gałąź `codex/emma-avatar`). Praca: gałąź
`codex/emma-ux-voice`, która zawiera audyt i jego bazę.

---

## Etap 1 — Wiarygodność: wybór dnia, prawda o danych, natychmiastowa edycja, wyszukiwanie, arkusze

Zakres z §7: F01, F02, F03, F10, F11, F16.

### Potwierdzenie ustaleń w kodzie (przed zmianą)

| ID | Potwierdzenie w kodzie bazowym |
| --- | --- |
| F01 | `CalendarStore.load` ustawiał `phase = .loading` **przed** `configure(today:)`, a `configure` sprawdzał `phase.hasLoaded`. `.loading` nigdy nie ma `hasLoaded`, więc każde `select` / `shiftWeek` / odświeżenie cofało wybór do `dependencies.today`. |
| F02 | `AssistantStore.briefing()` czytał zdarzenia i zadania przez `try?` i podstawiał `[]`. Awaria kalendarza dawała zdanie „Dzisiaj w zespole: 0 wydarzeń”. |
| F03 | `EmmaActionCard` wołał `onConfirm()` bez szkicu; `AssistantStore.confirm(actionID:)` zatwierdzał ostatnią wersję znaną koordynatorowi. Odroczona rewizja (700 ms) mogła nie zdążyć, więc szybkie „Zapisz” wykonywało starą treść. Odsłuch czytał `proposal.text`, nie szkic. |
| F10 | `DateField` / `TimeField` po cichu ignorowały niepoprawny tekst (zostawała poprzednia wartość); `eventForm` nie miał `initialDay`, więc „Dodaj termin na ten dzień” otwierał formularz z dniem bieżącym. |
| F11 | `MessagesStore.applyLocalFilter` filtrował `model.rows`, czyli wynik poprzedniego filtrowania; wyczyszczenie zapytania nie odtwarzało listy. |
| F16 | `TaskDetailSheet`, `EventDetailSheet`, `ConversationOptionsSheet`, `MessageOptionsSheet`, `NewConversationSheet` używały `try?` i przy błędzie zostawiały `nil` — ekran pokazywał „Wczytuję…” bez końca; `NewConversationSheet` nie odróżniał pustej bazy od wczytywania. |

### Zmiany

- **F01** `CalendarScreen.swift`: jednorazowa inicjalizacja `didConfigure`; odświeżenie nie resetuje `selectedDay` / `weekStart` i nie chowa wczytanej listy.
- **F02** `Core/Domain/EmmaBriefing.swift`: `events` i `tasks` są opcjonalne — `nil` znaczy „nie udało się sprawdzić”, `[]` znaczy „sprawdzone, puste”. `AssistantStore.briefing()` korzysta z tej jednej reguły zamiast własnej kopii z `try?`.
- **F03** `EmmaActionCard`: `onConfirm(text)` i `onSpeak(text)` dostają bieżący szkic; `AssistantStore.confirm(actionID:text:)` przy różnicy treści najpierw wysyła rewizję i zatwierdza dokładnie ją (nowa wersja i nowa prezentacja), `speakAction(actionID:text:)` czyta bieżący szkic.
- **F10** `AppRoute.eventForm` ma `initialDay`; `EventFormSheet` bierze dzień z trasy, a `DateField` / `TimeField` mają jawną walidację (`isValid`), komunikat błędu i **blokują zapis**, gdy tekst jest niepoprawny. „Dodaj termin na ten dzień” przekazuje `store.selectedDay`.
- **F11** `MessagesStore.Model` ma `allRows`; filtrowanie liczone jest zawsze z pełnego zbioru.
- **F16** Nowy `Core/Domain/RecordLoading.swift` zamienia odczyt rekordu na `LoadPhase`, rozróżniając brak (nieodwracalny) od błędu (z regułą ponowienia). Używają go `TaskDetailSheet`, `EventDetailSheet`, `MessageOptionsSheet`. `ConversationOptionsSheet` ma pełny stan `LoadPhase`; `NewConversationSheet` rozróżnia pustą bazę (stan pusty) od błędu oraz dostał wyszukiwanie kontaktu.

Wizerunek Emmy, polskie nazewnictwo, pojedynczy `VoiceSessionCoordinator` i kontrola zgód
(`.directUIButton` / `.authenticatedVoiceTurn`) nie zostały zmienione. Oznaczenia demo
pozostały bez zmian — nie było realnej integracji, więc nie było czego zdejmować.

### Testy

| Test | Wynik |
| --- | --- |
| `swift test` (logika, w tym nowe reguły briefingu i `RecordLoading`) | **191 / 0** (bazowo 182; +5 briefing, +4 `RecordLoading`) |
| `xcodebuild test`, schemat `Emma-Demo`, iPhone 17 Pro, iOS 26.5 | **`TEST SUCCEEDED`** — `210 / 0` testów jednostkowych, `11 / 0` XCUITest |
| Nowe testy Xcode (`EmmaTests/App/Stage1ReliabilityTests.swift`) | wybór dnia i tygodnia przetrwa odświeżenie; wyczyszczenie wyszukiwania odtwarza listę; natychmiastowe zatwierdzenie po edycji wykonuje nową wersję |
| Zrzuty ekranu (`ScreenshotCaptureUITests`) | 14 scen zapisanych, w tym nowe 12–14; raport bez pozycji „NIE UDAŁO SIĘ” |

Bilans testów jednostkowych: 194 (baseline) + 5 briefing + 4 `RecordLoading` + 7 etap 1 = 210.

### Zrzuty i ocena wzrokowa

Zrzuty w `docs/ios/screenshots/stage1-2026-09-13/` (01–14). Zmienione ekrany:
Kalendarz (06), Rozmowy (07), Emma — briefing (10) oraz nowe formularze/arkusze
(12 termin, 13 zadanie, 14 nowa rozmowa).

**Model wdrażający nie ma wejścia obrazowego**, więc nie obejrzał zrzutów wzrokowo — ten
sam limit, który audyt odnotował u poprzedniego autora. Zrzuty sprawdzono dwiema metodami
pomiarowymi, nie wzrokowymi: OCR (Apple Vision, pl/en/ru/uk) i analiza pikseli geometrii.
Potwierdzono m.in. tytuły „Nowy termin” / „Nowe zadanie” / „Nowa rozmowa”, pole „Data”
= `2026-09-11`, pole wyszukiwania „Szukaj osoby”, zaznaczony piątek 11 w pasku tygodnia
(ciemnogranatowe wypełnienie) oraz brak ucięć/nachodzenia w geometrii ramek tekstu.
Nierozstrzygnięte bez wglądu wzrokowego: kontrast kontrolki zamknięcia (×) w nagłówkach
arkuszy, pusta dolna połowa formularza zadania (krótki formularz — oczekiwane) oraz
„Zwykłe/Zwykte” (OCR myli „ł” z „t”; najpewniej renderowane „Zwykłe”). Ocena układu
i kontrastu pozostaje dla człowieka albo modelu z obsługą obrazu.

### Ograniczenia

- Testy F03 dowodzą, że zatwierdzenie dotyczy **nowej wersji propozycji** (`proposalVersion`
  równa wersji poprawionej). Nie dowodzą treści zapisanej po stronie dostawcy — w demo
  potwierdzenie trafia do outboxa i nie jest wysyłane. To nie jest dowód realnego wysłania.
- F10 weryfikowano przez jawną walidację i blokadę zapisu; nie wprowadzono natywnego
  `DatePicker`. Widoczny tekst niepoprawny nie jest zapisywany, bo zapis jest zablokowany.
- Naprawy arkuszy (F16) dotyczą stanu wczytywania/błędu. Nie odtwarzano realnej awarii
  repozytorium na urządzeniu; pokrywa je test reguły `RecordLoading`, nie test UI awarii.
- Bez zmian: prawdziwe speech-to-speech, WhatsApp, backend, fizyczny iPhone, VoiceOver,
  największy Dynamic Type. Te bramki należą do etapów 5–6 i pozostają `blocked_external`.

---

## Etap 2 — Czytelność: jedna skala, kontrast, jeden powrót, kolumna licznika

Zakres z §7: F09, F12, F13.

### Potwierdzenie ustaleń w kodzie (przed zmianą)

| ID | Potwierdzenie w kodzie bazowym |
| --- | --- |
| F09 | 20 tokenów tekstowych miało kontrast poniżej 4,5:1 wobec swojego tła; pomiar sRGB dał m.in. `dockStatusText` 2,68:1, `dockActionText` 2,83:1, `emmaStatusText` 2,84:1, `taskDateText` 3,00:1, `contextStripText` 3,37:1. Osiem stylów nazwanych miało 10–11 pt, a w widokach było **73** miejsca z własnym `ui(10…)`/`ui(11…)`/`ui(12…)`. |
| F12 | `ClientCardScreen` pokazywał systemowy powrót **i** własny w `DetailHeader` (dwa powroty). `TasksScreen` łączył systemowy powrót z własnym `ScreenHeader` i osobnym wierszem „+”, co dawało podwójną, pustą strefę u góry. Tylko `CaseScreen` i `ThreadScreen` chowały systemowy powrót. |
| F13 | `ConversationRow` rysował `UnreadBadge` jako nakładkę `overlay(alignment: .trailing)` z `padding(.trailing, 54)` i bez wyrównania w pionie — licznik lądował na dwuliniowym podglądzie wiadomości. |

### Zmiany

- **F09 — kontrast.** 20 tokenów tekstowych w `EmmaTheme` ma ciemniejsze wartości
  (np. `mutedSoft` `#7A8492` → `#5F6D7D` = 4,89:1, `taskDateText` → `#66768B` = 4,64:1,
  `contextStripText` → `#526F91`, `dockStatusText` → `#5F6D7D`). Każda nowa wartość
  **występuje już w regułach referencji**, więc kontrola tokenów nadal widzi 0 kolorów
  spoza wzorca.
- **F09 — jedna skala.** Nowy `EmmaTypography.caption(_:)` (12 pt) jest najniższym
  dopuszczalnym stopniem tekstu; 73 ad-hoc rozmiary w 22 plikach zamieniono na ten styl.
  Style nazwane poniżej 12 pt podniesiono do 12 pt, a `button` z 13 na 16 pt.
- **F09 — duży tekst.** Po pierwszym przebiegu przy `Accessibility XXXL` OCR wykazał
  realne przycinanie: etykiety zakładek nachodziły na siebie („DzisiKlien Em Roz Kale”),
  filtry zawijały się w trzy linie, a nazwisko „Maria Sokołowa” ucinało się do „Maria…”.
  Poprawki: pasek zakładek i filtr segmentowy mają ograniczoną skalę (`…accessibility1`)
  plus `minimumScaleFactor`, a nazwa w wierszu rozmowy zawija się do dwóch linii
  i zmniejsza zamiast ucinać.
- **F12 — jeden powrót.** `ClientCardScreen` i `TasksScreen` chowają systemowy przycisk
  powrotu; `TasksScreen` używa `DetailHeader` (powrót + tytuł + „+”) zamiast dwóch
  nagłówków. Nowy `EmmaSwipeBack` przywraca gest krawędzi, który ukrycie systemowego
  przycisku domyślnie wyłącza.
- **F13 — kolumna licznika.** Czas, licznik, pinezka i menu tworzą osobną kolumnę
  w układzie wiersza; podgląd nie wchodzi w jej prostokąt.

Odstępstwa zarejestrowane w `docs/ios/DESIGN_DEVIATIONS.md` jako D-20…D-23.
Wizerunek Emmy, polskie nazewnictwo, pojedynczy `VoiceSessionCoordinator` i kontrola
zgód bez zmian. Oznaczeń demo nie ruszano.

### Testy

| Test | Wynik |
| --- | --- |
| `swift test` (logika) | **191 / 0** |
| `xcodebuild test`, cały zestaw, iPhone 17 Pro | **`TEST SUCCEEDED`** — **210 / 0** jednostkowych, **17 / 0** XCUITest |
| `Stage2LayoutUITests` (4 testy) | brak systemowego powrotu na karcie klienta i Zadaniach, działający gest krawędzi, licznik nie koliduje z menu |
| `Stage2ScreenshotUITests` (2 metody, 6 scen) na iPhone 17 Pro i iPhone SE (3 gen) | `TEST SUCCEEDED` na obu ekranach; raporty bez pozycji „NIE UDAŁO SIĘ” |
| `swift test` + 9 kroków `verify-linux-logic.sh` | kroki 1–7 bez zastrzeżeń; **krok 8 jest czerwony z powodów sprzed tego etapu** (patrz ograniczenia) |
| `check-readability.py` (nowy krok 9/9) | 64 pliki ekranów, 20 tokenów: jedna skala (brak tekstu <12 pt) i wszystkie tokeny ≥4,5:1. **Sprostowanie (etap 3):** skrypt przerywał pracę na czerwonym kroku 8, więc krok 9 nie wykonał się w tym przebiegu — kontrola została uruchomiona osobno. Skrypt naprawiono w etapie 3. |
| `design-token-diff.py` | kolory spoza referencji: **0** |

### Zrzuty i ocena

`docs/ios/screenshots/stage2-2026-09-13/duzy-ekran/` i `.../maly-ekran/` — po 6 scen:
karta klienta, Zadania, Rozmowy (F12/F13) oraz te same ekrany przy największym tekście
dostępności (F09). Rozmiar sprawdzony programowo; treść przez OCR (Apple Vision, pl/en/ru/uk).

Zmierzony wynik, nie wrażenie: w scenie rozmów licznik „2” ma `x ≈ 0,88`, a podgląd
kończy się na `x ≈ 0,58` — kolumna znaczników jest osobna. Po poprawkach przy `XXXL` OCR
czyta „Wszystkie Nieprzeczytane Przypięte” w jednej linii, pełne „Maria Sokołowa”
i „Olena Kovalenko”, a etykiety zakładek w jednej linii.

### Ograniczenia

- **Model wdrażający nie ma wejścia obrazowego.** Zrzuty oceniono metodami pomiarowymi
  (OCR + geometria ramek), nie wzrokowo. Kontrast, ucięcia i nachodzenia grafiki wymagają
  człowieka albo modelu z obsługą obrazu.
- **Krok 8 `verify-linux-logic.sh` jest czerwony i był czerwony przed tym etapem.**
  `check-dead-code.py` wskazuje `VoiceSessionCoordinator.handleAccountSwitched` jako
  publiczne API bez wywołania. Zweryfikowane: funkcja istnieje już w bazie audytu
  `f1e1d34`, a `git grep` nie znajduje po niej wywołania ani w `f1e1d34`, ani w `HEAD`.
  Nie usunąłem jej: to zabezpieczenie cyklu życia głosu (przełączenie konta), a aplikacja
  ma dziś jedno wspólne konto (D-17). Wpięcie albo usunięcie należy do etapu 4–5, gdzie
  dotykamy cyklu życia sesji — usunięcie „na teraz” osłabiłoby zabezpieczenie, którego
  audyt broni.
- Pasek zakładek i filtr segmentowy mają **ograniczoną skalę** Dynamic Type
  (`…accessibility1`). To świadomy kompromis: pięć stałych kolumn nie mieści etykiet przy
  `XXXL`, a nakładające się napisy są gorsze niż mniejszy tekst nawigacji. Treść rośnie
  bez ograniczeń.
- Podgląd wiadomości w wierszu rozmowy ma `lineLimit(2)` (jak w referencji), więc bardzo
  długa cyrylica jest ucinana wielokropkiem — to nie jest kolizja ani utrata treści:
  pełny tekst jest w wątku, a etykieta dostępności zawiera całość.
- Inicjały awatara mają rozmiar proporcjonalny do średnicy koła, nie do Dynamic Type
  (koło jest stałe, więc skalowanie tekstu w nim ucinałoby znak).
- Bez zmian: VoiceOver na urządzeniu, dark mode (P2), klawiatura przy dużym tekście,
  prawdziwy głos i WhatsApp. To etapy 4–6 / `blocked_external`.

---

## Etap 3 — Dzień i listy: pierwszy widok, grupowanie zadań, linki do rekordów

Zakres z §7: F08, grupowanie zadań, kompaktowe nagłówki, linki do powiązanych rekordów.

### Potwierdzenie ustaleń w kodzie (przed zmianą)

| ID | Potwierdzenie w kodzie bazowym |
| --- | --- |
| F08 | `TodayScreen.loaded` zaczynał się od pełnej sceny `emmaStage` (orb `.stage` 148 pt na poświacie, „Jestem Emma”, zdanie wyjaśnienia i dwa przyciski), a dopiero pod nią szło „Dziś w kalendarzu” i „Zadania”. Audyt §4 wymaga karty 80–100 pt z portretem 48–64 pt. Nie było sekcji „Najbliższy termin” ani licznika zaległych zadań, a lista wydarzeń stała **przed** zadaniami — pilne zadanie lądowało pod listą spotkań. |
| Grupowanie zadań | `TasksScreen.list` i `TodayScreen` rysowały jedną płaską listę `model.tasks`. Zaległe zadanie z zeszłego tygodnia wyglądało tak samo jak zadanie na dziś. |
| Kompaktowe nagłówki | `SectionHeader` miał stałe `sectionHeaderMinHeight` + `sectionTop`/`sectionBottom`; cztery sekcje dnia zajmowały ~4 × 46 pt samych odstępów. |
| Linki do rekordów | Ekran „Dzisiaj” nie wczytywał spraw (`TodayStore` brał tylko klientów, terminy i zadania), więc numeru sprawy nie było gdzie pokazać. `TaskRow` pokazywał klienta jako tekst; jedyne przejście do rekordu prowadziło przez szczegóły zadania („Karta klienta”). |
| Listy przy odświeżeniu | `TasksStore.load` i `CaseStore.load` ustawiały `phase = .loading` przy **każdym** wczytaniu, więc odświeżenie po zapisie zdejmowało listę z ekranu. `TodayStore` miał zabezpieczenie z etapu 1 (`if !phase.hasLoaded`). |

### Zmiany

- **F08 — kolejność i ciężar.** `TodayScreen` ma nowy układ: nagłówek dnia → kompaktowa
  karta Emmy (`EmmaOrb.Size.compact`, 52 pt) z „Porozmawiaj z Emmą”, zdaniem
  „Zapytaj o dzień, terminy lub wiadomości.”, mikrofonem 44 pt i „Napisz” → „Najbliższy
  termin” → „Zadania” → „Dalej dziś” → zwijana sekcja „Minione terminy”. Pełna scena
  Emmy została w zakładce „Emma”. Zdanie „Zapytam o dzień” zastąpione zdaniem
  z perspektywy użytkownika (F11 z etapu 1 dotyczył wyszukiwania; tutaj chodzi o slogan).
- **Reguły w rdzeniu.** Nowy `DayAgenda.split(events:now:)` dzieli dzień na najbliższy
  termin, dalsze i minione (termin trwający jest nadal najbliższy); nowy `TaskGrouping`
  dzieli zadania na zaległe, dzisiejsze i późniejsze i liczy podsumowanie
  (`EmmaPlural.overdueTasks`). Oba ekrany — „Dzisiaj” i „Zadania” — korzystają z tej
  samej reguły.
- **Najbliższy termin.** Karta pokazuje godzinę, czas trwania, status, tytuł, miejsce,
  **linki do klienta i sprawy** (`openPerson` / `openCase`) oraz „Przygotuj mnie”
  (`openEmma(clientID:action:.prepareCase)`) i „Szczegóły”. Brak przyszłych terminów ma
  jawny pusty stan: „Nie masz już dziś zaplanowanych terminów.”
- **Zadania.** Nagłówek sekcji ma licznik (`3 zadania do wykonania · 1 zaległe zadanie`)
  i wejście „Wszystkie zadania” w jednym dotknięciu; wewnątrz karty zadania są
  pogrupowane nagłówkami `ZALEGŁE` / `NA DZIŚ` / `PÓŹNIEJ`. Na ekranie „Zadania” ten
  sam podział działa dla zakresów „Otwarte” i „Wszystkie”; „Wykonane” zostaje płaskie.
- **Kompaktowe nagłówki.** `SectionHeader` dostał wariant `compact:` (30 pt zamiast 38 pt
  wysokości i mniejsze odstępy) używany na „Dzisiaj”, gdzie liczy się każdy punkt nad
  zgięciem ekranu. Pozostałe ekrany bez zmian (wartość domyślna).
- **Odświeżenie nie cofa listy.** `TasksStore.load` i `CaseStore.load` mają ten sam
  warunek co `TodayStore`: `if !phase.hasLoaded { phase = .loading }`.

Odstępstwa zarejestrowane jako D-24 (układ dnia, uchylenie punktu 1 decyzji D-19) i
D-25 (pionowy układ wiersza zadania i karty Emmy przy dużym tekście). Wizerunek Emmy,
polskie nazewnictwo, pojedynczy `VoiceSessionCoordinator` i kontrola zgód bez zmian.
Oznaczeń demo nie ruszano.

### Testy

| Test | Wynik |
| --- | --- |
| `swift test` (logika) | **201 / 0** (+10: `DayAgendaTests`, `TaskGroupingTests`) |
| `xcodebuild test`, cały zestaw, iPhone 17 Pro | **`TEST SUCCEEDED`** — **223 / 0** jednostkowych, **23 / 0** XCUITest |
| `Stage3ReloadTests` (`EmmaTests/App`, 3 testy) | odświeżenie nie cofa `TodayStore`, `TasksStore` i `CaseStore` do stanu ładowania |
| `Stage3LayoutUITests` (4 testy) na iPhone 17 Pro i iPhone SE (3 gen) | najbliższy termin i „Wszystkie zadania” **widoczne bez przewijania** (`isHittable`), 1 dotknięcie otwiera listę zadań, grupa `NA DZIŚ` istnieje, link „Olena Kovalenko” otwiera kartę klienta |
| `Stage3ScreenshotUITests` (2 metody, 5 scen) na obu ekranach | `TEST SUCCEEDED`; raporty bez pozycji „NIE UDAŁO SIĘ” |
| `verify-linux-logic.sh` | kroki 1–7 i 9 bez zastrzeżeń; **krok 8 czerwony z powodów sprzed tego etapu** (patrz ograniczenia) |
| `check-readability.py` (krok 9/9) | 66 plików ekranów, 20 tokenów: bez tekstu <12 pt i wszystkie tokeny ≥4,5:1 |
| `design-token-diff.py` | kolory spoza referencji: **0** |

Test `Stage3ReloadTests.testTasksReloadKeepsLoadedList` został sprawdzony odwrotnie:
po tymczasowym przywróceniu `phase = .loading` w `TasksStore` **failuje**
(„Odświeżenie cofnęło listę do stanu ładowania”), a po przywróceniu warunku przechodzi.
To dowód, że test mierzy tę regułę, a nie tylko ją opisuje.

### Zrzuty i ocena

`docs/ios/screenshots/stage3-2026-09-13/duzy-ekran/` i `.../maly-ekran/` — po 5 scen:
pierwszy widok dnia, dalsze terminy po przewinięciu, grupowanie na liście zadań oraz ten
sam dzień i lista przy największym tekście dostępności. Treść oceniona przez OCR (Apple
Vision, pl/en/ru/uk) i geometrię ramek, nie wzrokowo.

Zmierzony wynik, nie wrażenie:

- **Duży ekran (402 pt):** „Najbliższy termin” `y ≈ 0,67`, karta terminu 10:30–„Przygotuj
  mnie” `y ≈ 0,61–0,45`, „Zadania” i „Wszystkie zadania” `y ≈ 0,38`, licznik
  „3 zadania do wykonania” `y ≈ 0,32`, `NA DZIŚ` `y ≈ 0,29`, dwa wiersze zadań
  `y ≈ 0,25` i `0,17`. Wszystko powyżej paska zakładek (`y ≈ 0,04`).
- **Mały ekran (375 × 667 pt):** najbliższy termin `y ≈ 0,63–0,35`, „Zadania” i
  „Wszystkie zadania” `y ≈ 0,25`, licznik `y ≈ 0,17`, `NA DZIŚ` `y ≈ 0,13` — nadal nad
  zgięciem. Wiersze zadań zaczynają się dokładnie na zgięciu; to zgodne z warunkiem
  („wejście do zadań”, nie „pełna lista zadań”).
- **Kolejność:** po przewinięciu „Dalej dziś” pokazuje 12:00 i 14:00, czyli lista
  spotkań jest **pod** zadaniami — pilne „Oddzwonić w sprawie zatrzymania” (`Pilne`)
  widać w pierwszym widoku.
- **Grupowanie:** na liście zadań OCR czyta filtr „Otwarte | Wszystkie | Wykonane”
  w jednej linii i grupę `NA DZIŚ`. Grupy `ZALEGŁE` nie widać w zrzucie, bo dane demo
  mają wszystkie trzy zadania na dzień referencyjny — pokrywa ją test rdzenia
  (`TaskGroupingTests.testGroupsSplitOverdueTodayAndLaterKeepingOrder`).
- **Duży tekst:** pierwszy przebieg wykazał łamanie wyrazów w środku („Porozm / awiaj z /
  Emmą”, „zatrzyma / nia”). Po poprawce (D-25) OCR czyta „Porozmawiaj” i „z Emmą” oraz
  „Oddzwonić w / sprawie / zatrzymania” w całości. Przy `XXXL` pierwszy widok mieści
  nagłówek i kartę Emmy; terminy i zadania wymagają przewinięcia (patrz ograniczenia).

### Ograniczenia

- **Model wdrażający nie ma wejścia obrazowego.** Zrzuty oceniono metodami pomiarowymi
  (OCR + geometria ramek), nie wzrokowo — tak jak w etapie 2.
- **Przy `Accessibility XXXL` pierwszy widok nie mieści najbliższego terminu.** Na 402 pt
  nagłówek dnia i karta Emmy zajmują cały ekran. Warunek etapu („najbliższy termin i
  wejście do zadań na pierwszym widoku”) jest sprawdzony i spełniony przy tekście
  standardowym; przy największym dostępnościowym skala tekstu rośnie szybciej niż ekran.
  Test na `XXXL` sprawdza tylko, że elementy istnieją — nie że są nad zgięciem.
- **Pozycja listy przy odświeżeniu** jest sprawdzona deterministycznie na poziomie sklepów
  (`Stage3ReloadTests`), a nie pomiarem pikseli w UI. Próba pomiaru pozycji wiersza na
  ekranie „Zadania” okazała się bezwartościowa: dane demo mają trzy zadania, które mieszczą
  się bez przewijania, więc test przechodził także **bez** poprawki. Nie zostawiłem takiego
  testu, bo dawał fałszywe poczucie ochrony.
- **`check-dead-code.py` (krok 8) jest czerwony i był czerwony przed tym etapem** —
  `VoiceSessionCoordinator.handleAccountSwitched`. Bez zmian względem etapu 2: to
  zabezpieczenie cyklu życia głosu przy przełączeniu konta, a aplikacja ma jedno wspólne
  konto (D-17). Usunięcie „na teraz” osłabiłoby zabezpieczenie, którego broni audyt.
  Przy okazji naprawiłem skrypt: krok 8 przerywał pracę przed krokiem 9, więc raport etapu 2
  twierdził, że kontrola czytelności się wykonała, choć tak nie było. Teraz kroki 8 i 9 są
  niezależne, wynik zbierany jest do końca, a błąd zwracany raz — po kroku 9.
- **„Kompaktowe nagłówki”** zrealizowane jako wariant `SectionHeader(compact:)` na
  „Dzisiaj”. Nie zmniejszałem nagłówków na kartach klienta i sprawy, żeby nie wracać do
  układu pisanego w etapie 2 (F12) bez nowego zrzutu.
- **Linki do rekordów** na „Dzisiaj” prowadzą do klienta i sprawy najbliższego terminu;
  wiersze zadań nadal pokazują klienta jako tekst, a przejście do rekordu jest w
  szczegółach zadania („Karta klienta”). Rozszerzenie tego na wiersz zadania wymaga
  zagnieżdżonego celu dotknięcia i osobnego sprawdzenia trafień — do rozważenia w etapie 4.
- Bez zmian: VoiceOver na urządzeniu, dark mode (P2), prawdziwy głos i WhatsApp —
  etapy 4–6 / `blocked_external`.

---

## Etap 4 — Globalny panel sesji i prawda w docku (F06, F07)

### Potwierdzenie ustaleń w kodzie (przed zmianą)

Sprawdzone w kodzie z commita `de06a96` (koniec etapu 3), nie z opisów:

- **F06.** `VoiceDock` był rysowany tylko w `AssistantScreen` (zakładka „Emma”).
  `RootShell` nie miał żadnego paska sesji, a `SheetHost` — żadnego widoku nad treścią
  arkusza. Rozmowa uruchomiona z „Dzisiaj” (karta Emmy) zostawała bez sterowania po
  przejściu na inną zakładkę albo po otwarciu formularza.
- **Powłoka nie miała z czego czytać stanu.** `AppDependencies` subskrybował koordynator
  (`observeSessionEnd()`), ale trzymał wynik lokalnie; na zewnątrz nie było ani stanu
  `VoiceUIState`, ani metod sterujących. `AssistantStore` wołał `dependencies.voice.end(...)`
  bezpośrednio.
- **F07.** `VoiceDock` rysował linię `"Połączenie: \(connection) · Mikrofon: \(microphone) ·
  Tryb: \(mode)"` **bezwarunkowo**, więc bez sesji dock pokazywał jednocześnie „Rozmowa
  głosowa”, „Połączenie: Nieaktywna”, „Mikrofon niedostępny” i „Tryb: Bezczynny”.
  Kompozytor `AssistantScreen` miał trzy ikony o równej wadze (mikrofon 43 pt, pole,
  dyktowanie, wysłanie) i **aktywne** wysłanie przy pustym polu (`sendComposer()` czyścił
  pole i kończył bez efektu, więc przycisk wyglądał na działający).
- Panel sterowania na ekranie Emmy nie ma być dublowany (§4 audytu), a nad arkuszem ma
  zostać widoczny, gdy rozmowa trwa pod spodem.

### Zmiany

- **`ios/Emma/Features/Shared/VoiceMiniPanel.swift`** (nowy): pasek z małym `EmmaOrb`,
  stanem z rdzenia, wyciszeniem (44 pt) i „Zakończ rozmowę” (44 pt); dotknięcie treści
  wraca do rozmowy. Czyta `VoiceUIState` z zależności, nie tworzy własnej subskrypcji.
- **`ios/Emma/Core/Voice/VoiceStateReducer.swift`**: `VoiceUIState` dostał
  `showsGlobalVoicePanel` (widoczny, dopóki sesja istnieje — także wyciszona i po
  nieudanym połączeniu), `sessionHeadline` (jeden stan bez żargonu, wspólny dla docku
  i panelu) oraz `isCapturingMicrophone`.
- **`ios/Emma/App/AppDependencies.swift`**: `@Published voiceState` aktualizowany przez
  **istniejącego** obserwatora koordynatora; `toggleVoiceMicrophone()` i
  `endVoiceSession()` jako jedyne ścieżki sterowania dla docku i panelu.
- **`ios/Emma/App/RootShell.swift`**: panel nad paskiem zakładek z rezerwacją miejsca
  w układzie, gdy `showsGlobalVoicePanel && tab != .emma && sheet == nil`; w `SheetHost`
  panel jest **w układzie** arkusza (VStack nad treścią), więc klawiatura wypycha go
  w górę, a nie zasłania.
- **`ios/Emma/Features/Shared/VoiceDock.swift`**: linia techniczna tylko przy istniejącej
  sesji, `stateLabel` z rdzenia, wyciszenie w docku, „Zakończ” zamiast „Zakończ rozmowę”
  (pełna nazwa została w panelu).
- **`ios/Emma/Features/Assistant/AssistantStore.swift`**: `endSession()` i nowe
  `toggleMicrophone()` delegują do zależności; `canSendComposer` (puste pole nie wysyła).
- **`ios/Emma/Features/Assistant/AssistantScreen.swift`**: kompozytor z jednym
  „Rozmawiaj” (56 pt), trybem pisania z „Dyktuj tekst” i nieaktywnym wysłaniem pustego
  pola; `EmmaMetrics.emmaVoiceButtonSize = 56`.
- **Poprawka czytelności przy `Accessibility XXXL`** (znaleziona przy przeglądzie zrzutów
  etapu 4): karta Emmy na „Dzisiaj” kładzie portret nad tytułem, a tytuł i podpis zajmują
  pełną szerokość karty (D-25, uzupełnienie); mini-panel chowa podpis „Wróć do rozmowy”
  i daje stanowi dwa wiersze zamiast urywać tekst.

### Testy

| Test | Wynik |
| --- | --- |
| `swift test` (logika) | **210 / 0** (+9: `VoicePanelStateTests`) |
| `xcodebuild test`, cały zestaw, iPhone 17 Pro | **`TEST SUCCEEDED`** — **235 / 0** jednostkowych, **29 / 0** XCUITest |
| `Stage4VoicePanelTests` (`EmmaTests/App`, 3 testy) | lustro `voiceState` w powłoce; wyciszenie i zakończenie idą jedną sesją (identyfikator sesji bez zmian) |
| `Stage4VoicePanelUITests` (4 testy) na iPhone 17 Pro i iPhone SE (3 gen) | panel widoczny i dotykalny w innej zakładce; brak duplikatu na ekranie Emmy; wyciszenie nie kończy sesji, zakończenie usuwa panel; nad arkuszem z klawiaturą `panelEnd.maxY ≤ keyboard.minY` |
| `Stage4ScreenshotUITests` (2 metody, 5 scen) na obu ekranach | `TEST SUCCEEDED`; raporty bez pozycji „NIE UDAŁO SIĘ” |
| `verify-linux-logic.sh` | kroki 1–7 i 9 bez zastrzeżeń; **krok 8 czerwony z powodów sprzed etapu 3** (patrz ograniczenia) |
| `check-readability.py` (krok 9/9) | 67 plików ekranów, 20 tokenów: wszystkie tokeny ≥4,5:1 |
| `design-token-diff.py` | kolory spoza referencji: **0** |

Test klawiatury jest sprawdzony **na prawdziwej klawiaturze programowej**, nie na
założeniu: zmierzone ramki w symulatorze iPhone 17 Pro to panel `y = 489…533`, klawiatura
`y = 583…816` (ekran 402 × 874 pt), więc zakończenie rozmowy jest w całości nad
klawiaturą. Gdy symulator nie rysuje klawiatury (podłączona klawiatura sprzętowa),
`application.keyboards.firstMatch` ma ramkę **poza ekranem** (`y = 952`), a test kończy
się `XCTSkip` z podanym powodem — świadomie nie daje zielonego wyniku bez sprawdzenia
układu.

### Zrzuty i ocena

`docs/ios/screenshots/stage4-2026-09-13/duzy-ekran/` i `.../maly-ekran/` — po 5 scen:
kompozytor Emmy w spoczynku, dock z żywą sesją, mini-panel na „Dzisiaj”, mini-panel nad
arkuszem z klawiaturą oraz mini-panel przy największym tekście dostępności. Ocena przez
OCR (Apple Vision, pl/en/ru/uk) i geometrię ramek, nie wzrokowo.

Zmierzony wynik, nie wrażenie:

- **Kompozytor (26):** „Rozmawiaj” `y ≈ 0,22`, „Dyktuj tekst” `y ≈ 0,14`, pole
  „Napisz do Emmy…” `y ≈ 0,06`, pasek zakładek `y ≈ 0,04`. Nad kompozytorem dock mówi
  **„Gotowa do rozmowy”** (`y ≈ 0,28`) — bez sesji nie ma już ani „Połączenia:
  Nieaktywna”, ani „Mikrofon niedostępny” (sedno F07).
- **Dock z sesją (27)** i **mini-panel na „Dzisiaj” (28):** panel na dużym ekranie
  `y ≈ 0,13–0,17`, na małym `y ≈ 0,11–0,14`, pasek zakładek `y ≈ 0,01–0,05`. OCR czyta
  „Emma czeka” i „Wróć do rozmowy”, obok widzi ikonę mikrofonu i „×”. Panel jest **nad**
  paskiem zakładek i nie dubluje się z dockiem (na ekranie Emmy OCR nie znajduje
  „Wróć do rozmowy”).
- **Klawiatura (29):** na obu ekranach panel leży nad klawiaturą — na dużym ekranie
  ramki `panelEnd.maxY = 533 ≤ keyboard.minY = 583`; OCR czyta „QWE”/„123” pod panelem,
  a arkusz „Nowe zadanie” nad nim.
- **Duży tekst (30):** po poprawce OCR czyta „Porozmawiaj” i „z Emmą” w całości na obu
  ekranach (przed poprawką: „Porozmawi / aj z Emmą” na 375 pt), a panel pokazuje stan
  „Emma / czeka” w dwóch wierszach bez urywania.

### Ograniczenia

- **Model wdrażający nie ma wejścia obrazowego.** Zrzuty oceniono metodami pomiarowymi
  (OCR + geometria ramek), nie wzrokowo — tak jak w etapach 2 i 3.
- **Klawiatura wymaga narysowanej klawiatury programowej.** W środowisku prowadzącym
  działa to po uruchomieniu `Simulator.app` i wyłączeniu sprzętowej klawiatury
  (`defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false`).
  Przy `xcodebuild` uruchomionym bez `Simulator.app` klawiatura jest zgłaszana poza
  ekranem, a test jest pomijany (`XCTSkip`) — nie jest to wtedy dowód, że układ nad
  klawiaturą działa. Na urządzeniu z klawiaturą sprzętową panel i tak jest w układzie
  arkusza, więc nie powinien się schować — tego wariantu **nie zmierzyłem**.
- **„Zakończone” połączenie nadal nie jest dowodem realnego głosu.** Sesja w panelu to
  ta sama sesja mocka co w docku (`MockVoiceTransport`); panel dowodzi sterowania jedną
  sesją, a nie speech-to-speech. Prawdziwa integracja pozostaje w etapie 6
  (`blocked_external`).
- **Zakładki inne niż „Emma” sprawdzone na dwóch ekranach**, ale nie na każdym z pięciu
  („Klienci”, „Rozmowy”, „Kalendarz”) — panel jest rysowany w `RootShell` dla wszystkich
  zakładek poza „Emma”, a testy pokrywają „Dzisiaj” i arkusz. Pozostałe zakładki mają ten
  sam warunek widoczności, więc nie ma tam osobnej ścieżki kodu.
- **`check-dead-code.py` (krok 8) nadal czerwony** — `VoiceSessionCoordinator.handleAccountSwitched`,
  bez zmian względem etapów 2 i 3 (jedno wspólne konto, D-17).
- Bez zmian: VoiceOver na urządzeniu, dark mode (P2), prawdziwy głos i WhatsApp —
  etapy 5–6 / `blocked_external`.

