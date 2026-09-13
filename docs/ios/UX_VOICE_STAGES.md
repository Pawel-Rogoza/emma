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
