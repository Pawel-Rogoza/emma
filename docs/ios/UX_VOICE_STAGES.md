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
| `check-readability.py` (nowy krok 9/9) | 64 pliki ekranów, 20 tokenów: jedna skala (brak tekstu <12 pt) i wszystkie tokeny ≥4,5:1 |
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
