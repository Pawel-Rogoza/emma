# Audyt designu i czytelności Emmy — 11 września 2026

Audyt na polecenie właściciela: „sprawdź niedociągnięcia w designie i możliwości jego
poprawy, ulepszenia funkcjonalności i czytelności aplikacji”.

Dwie zmiany zgłoszone wprost zostały **wdrożone** w tym samym kroku
(patrz §1). Reszta raportu to ustalenia z rekomendacjami i priorytetami.

Zakres: `ios/Emma/DesignSystem/*` (tokeny, typografia, komponenty, orb, pasek zakładek),
wszystkie ekrany i arkusze z `Features/`, skrypty podglądu. Kontrasty policzone wg WCAG 2.x
(względne luminancje sRGB). Build `Emma-Demo` kompiluje się po zmianach.

---

## 1. Wdrożone zmiany (z polecenia właściciela)

### Z-1 · Ekran główny: Emma zamiast kokpitu — **zrobione**

Zakładka „Dzisiaj” nie pokazuje już wielkiego podsumowania (karta z briefingiem,
statystyki, najbliższa konsultacja, listy zadań i spraw). Nowy ekran:

- nagłówek z datą i powitaniem (bez zmian),
- duży orb Emmy z **nową animacją obecności** (`breathing`: delikatne oddychanie
  i rozchodząca się poświata; przy „Ograniczeniu ruchu” wyłączona; orb nadal
  pulsuje mocniej, gdy Emma mówi),
- krótka podpowiedź („Pytaj o sprawy, wiadomości i terminy…”),
- dwa przyciski: „Porozmawiaj głosem” i „Napisz do Emmy” + dotknięcie orbu
  rozpoczyna rozmowę głosową,
- dyskretne łącze „Zadania na dziś” — **konieczne**, bo `TasksScreen` nie ma
  własnej zakładki i bez tego łącza byłby nieosiągalny.

Bonus: ekran nie ładuje już repozytorium — brak „Wczytuję…” na starcie.
Briefing dnia pozostaje przez zakładkę Emma → „Opowiedz mi o dzisiejszym dniu”.
Rejestr: `DESIGN_DEVIATIONS.md` D-15.

### Z-2 · Tłumaczenia wiadomości usunięte — **zrobione**

Dymki pokazują wyłącznie oryginał. Sekcja „Tłumaczenie” (rozwijany blok pod tekstem)
usunięta z `MessageBubble`, tokeny `bubbleTranslation*` z `EmmaTheme`, rekonstrukcja
i pomiar podglądu (`build-preview.py`, `verify-preview-render.py`) zaktualizowane.
`Message.translation` zostaje w modelu/danych — gdyby ktoś w zespole kiedyś chciał
opcję, powrót to jedno `if let` + tokeny. Rejestr: `DESIGN_DEVIATIONS.md` D-14.

### Z-3 · Drobiazg: błędna nota o głosie w profilu — **zrobione**

„Głos korzysta z funkcji przeglądarki” → „Głos działa w trybie demonstracyjnym”.
Aplikacja jest natywna; wzmianka o przeglądarce była pozostałością po prototypie HTML
i osłabiała wiarygodność noty o demo.

---

## 2. Czytelność i typografia [wykładnia: wysoki priorytet]

**A. Mikrotekst jest dominującą warstwą informacji.**
Style 10–12 pt (`caseNumber`, `taskDate`, `tabLabel` = 10 pt; `kicker`, `meetingMeta`,
`taskMeta`, `bubbleMeta`, `pill` = 11 pt; ~38 ad-hoc `ui(10–12)` w komponentach i ekranach,
w tym **cała treść `InfoList` w 12 pt**, stopka `WorkspaceStats` w 10 pt). Dla prawników
czytających w biegu to za mało — a teksty te niosą metadane spraw, terminów i rozmów.

*Rekomendacja:* podłoga 12 pt dla meta (tf. usunąć kroje 10 pt), dodać nazwany styl
`.caption` i zastąpić nim ad-hoc `ui(10–12)`. Dynamic Type już skaluje style, więc
zmiana rozmiaru bazowego jest bezpieczna.

**B. Kontrasty poniżej WCAG AA (policzone).**
Poniżej 3:1 (tekst!): `taskDateText` 3,0:1, `emmaStatusText` 2,84, `dockActionText` 2,83
(klikalne akcje docku głosowego!), `dockStatusText` 2,68, `emmaDemoFootText` 2,64,
`emmaSuggestionSubtitle` 2,86, `receiptDefault` na dymku wychodzącym 2,64.
Najgorzej wypada meta-informacja tam, gdzie pada decyzja: godzina wysyłki, stan dyktowania.

*Rekomendacja:* przyciemnić wszystkie tokeny „meta/sub” o ~15–20 % (cel ≥4,5:1 przy
tekście ≤12 pt); zestawy pigułek (urgent/amber) z ciemniejszym tekstem.

**C. Ikony i awatary nie rosną z Dynamic Type.**
SF Symbols wszędzie stałopunktowe (`.system(size:)`) — przy większym tekście ikony
zostają małe i nieczytelne. `PersonAvatar` omija kroje DM Sans/Manrope.

*Rekomendacja:* ikony przez `.system(size:weight:)` z `Image.Scale` lub rozmiar
powiązany z kategorią DT; inicjały awatara tokenem typografii.

---

## 3. Płynność i interakcja

**A. Mignięcie „Wczytuję…” przy każdej zmianie filtra.** [wysoki]
`TasksScreen` i `CalendarScreen` przy każdym przeładowaniu ustawiają `phase = .loading`,
czyli lista znika przy zmianie segmentu; `MessagesScreen` zmiana filtra strzela
pełnym wczytaniem repozytorium, podczas gdy szukajka filtruje lokalnie.
*Rekomendacja:* wzorzec z `ClientsStore` (`if !phase.hasLoaded { phase = .loading }`)
+ lokalne filtrowanie z trzymaną pełną listą.

**B. Brak pull-to-refresh na wszystkich listach** (0 wystąpień `.refreshable`).
*Rekomendacja:* dodać `.refreshable` na listach (Kalendarz, Klienci, Zadania, Rozmowy,
Sprawa, Karta klienta) — czysta zmiana widokowa, woła istniejący `store.load`.

**C. Pola daty i godziny to wolny tekst.** [wysoki]
`DateField`/`TimeField` parsują po cichu: literówka zostawia starą datę, a komunikat
„Uzupełnij nazwę i prawidłową datę” nie wskazuje pola. Gorsze: formularze startują
z zaszytą datą demo 11.09.2026/09:00.
*Rekomendacja:* `DatePicker` / picker godziny albo walidacja na żywo z błędem inline.

**D. Ślepe stany w arkuszach szczegółów.** [wysoki]
`TaskDetailSheet`, `EventDetailSheet`, `MessageOptionsSheet`, `NewConversationSheet`:
`try?` + „Wczytuję…” bez końca przy błędzie; `NewConversationSheet` kręci się też
na pustej bazie i nie ma szukajki przy długiej liście.
*Rekomendacja:* przejść na `LoadPhase` z `LoadFailureView` (wzorzec już istnieje
w `AssignOwnerSheet`), dodać `SearchField` (istnieje) w wyborach kontrahenta/kontekstu.

---

## 4. Funkcjonalność — okazje zgodne z istniejącą architekturą

1. **Przypięcie „Dodaj termin na ten dzień” do daty** — dziś otwiera formularz
   z „dziś”, etykieta mija się z treścią. Parametr `day` w `AppSheet.eventForm` albo
   zmiana etykiety. [średni]
2. **Swipe / menu kontekstowe na rozmowie** — „Przypnij” i „Odczytane” to 2 najczęstsze
   akcje ukryte w arkuszu opcji; repozytorium już to obsługuje. [średni]
3. **Grupowanie zadań: przeterminowane / dziś / później** — lista jest już posortowana
   po terminie, nagłówki sekcji to czysta warstwa widoku z dużą wartością praktyczną. [średni]
4. **Szybka akcja „Zadanie” na karcie klienta** — `TaskFormSheet` już przyjmuje `clientID`;
   w QuickActions brakuje tej pozycji. [niski]
5. **„Wszystkie terminy” w sprawie** — podgląd pokazuje tylko 2 najbliższe — ślepa uliczka. [średni]
6. **Wyznaczniki stanów pustych** — wyznaczyć wszędzie `EmptyState` z akcją
   (np. puste zadania gołym tekstem 12 pt, podczas gdy inne ekrany mają komponent + CTA). [średni]
7. **Wskazanie, kto jest zalogowany w profilu** — lista użytkowników nie zaznacza
   aktywnego; przełącznik „w ciemno”. [średni]
8. **Podwójna ramka przycisku „+” w Zadaniach** — IconButton rysuje obrys, ekran
   dokłada drugi — niespójne z pozostałymi „+”. [niski]

## 5. Spójność design systemu

- Promienie 13/15 i wymiar 19 zahardkodowane w komponentach (`InfoList`, `TraceToast`,
  `QuickActions`, case-card) zamiast tokenów `EmmaRadii`; paddingi 14/15/18 luźno. [średni]
- Martwe tokeny: `EmmaRadii.avatar`, `EmmaRadii.badge`; duplikat znaczenia
  `EmmaRadii.avatar=41` vs `EmmaMetrics.avatar=41`; prawie-identyczne pary kolorów
  (`taskMetaText` vs `taskDateText`, `muted` vs `mutedSoft`). [niski]
- `Manrope-Bold` / parametr `bold:` w `heading()` nigdy nieużywane. [niski]
- Cele dotyku < 44 pt: menu wiadomości „⋯” 28×28 w dymku. [średni — audyt też wymagał
  min. 44 przy usuniętym zwijalniku tłumaczenia]

## 6. Decyzje produktowe do podjęcia

1. **Tryb ciemny.** Cały `EmmaTheme` to stałe kolory sRGB — brak dynamicznych wariantów.
   Albo pełny dark mode (każdy token z wariantem), albo świadome zablokowanie
   `UIUserInterfaceStyle = Light` w Info.plist + wpis w kontrakcie.
2. **Pasek zakładek, etykiety 10 pt, kontrast `tabInactive` 3,02:1** — przy 5 zakładkach
   tekst da się podnieść do 11–12 pt bez zmiany układu.
3. **Dane demo i skalowanie:** `MessagesStore` pobiera podglądy N+1 w pętli po wątkach —
   przy prawdziwym WhatsApp lista rozmów będzie wolna; dopisać do analizy API jako ryzyko.

---

## 7. Stan po zmianach

- `xcodebuild -scheme Emma-Demo` **kompiluje się** (pozostały wcześniejsze ostrzeżenia
  „any”, niepowiązane).
- `swift test` (logika domeny i głosu): **178 testów, 0 błędów**.
- `xcodebuild test` (symulator iPhone 17, iOS 26.5): **wszystkie testy przechodzą**,
  w tym 10 testów XCUITest. Przy okazji naprawiono cztery scenariusze UI, które nigdy
  wcześniej nie były uruchamiane i zawierały błędne założenia o interfejsie
  (nieistniejące etykiety przycisków, klientka ze statusem „Klient” szukana na liście
  leadów, brak znajdowania numeru sprawy).
- **Nowa zachowanie:** ponowne dotknięcie aktywnej zakładki wraca do jej ekranu
  głównego (popToRoot) — standardowy nawyk z iOS, wcześniej ekrany szczegółów
  „zawieszały” zakładkę.
- Rekonstrukcja podglądu i pomiar renderu zaktualizowane o nowy ekran główny
  i brak tłumaczeń.
- Rejestr odstępstw: nowe pozycje D-14 (tłumaczenia) i D-15 (ekran główny).


## 8. Uwagi z komentarzy do podglądu (do doprecyzowania)

Podczas audytu wpłynęły dwa komentarze wizualne do podglądu:

1. „te ikonki w białym prostokącie są troszku przesunięte i ucięte w pionie,
   czy powinny takie być?” — dotyczyło elementu z klasami `chipRow`/`w-col`
   w widoku klientów.
2. „te ikonki są nieczytelne, zaczernione” — dotyczyło dolnego paska nawigacji.

**Problem:** komentarze wskazują na strony podglądu spoza tego repozytorium
(klasy `w-col`, `#swapper-row`, `#home` to układ Webflow, którego nie ma ani
w aplikacji SwiftUI, ani w `reference/prototype/`), a pliki tego podglądu nie są
już dostępne na dysku — nie da się ich otworzyć ani zweryfikować. Nie mogę też
obejrzeć obrazu (bieżący model nie przyjmuje obrazów).

**Co sprawdziłem liczbowo w aplikacji:** pasek zakładek nie ucina ikon —
chip Emmy ma 43×34 pt przy ikonie 17 pt, pozostałe zakładki mają 19 pt
w ramce 34 pt. Kolor nieaktywnej zakładki `tabInactive` (#8A93A0) na białym tle
ma jednak tylko ~3,0:1 kontrastu, co faktycznie wygląda na „przygaszone”
i jest już ujęte w §2B jako problem do naprawy.

**Proszę o wskazanie:** czy chodzi o (a) aplikację iOS, (b) opublikowany prototyp
pod adresem `emma-kancelaria-ios.pawrogozas.chatgpt.site`, czy (c) inny podgląd?
Jeśli (a) — podeślij proszę zrzut ekranu lub nazwę ekranu, wtedy poprawię
konkretny komponent.

---

## 9. Druga iteracja — poprawki z przeglądu aplikacji na urządzeniu

Po uruchomieniu aplikacji na symulatorze właściciel zgłosił cztery rzeczy.
Wszystkie cztery są wdrożone i zweryfikowane na symulatorze.

### Z-4 · Znak zatrzymania nasłuchu — **zrobione**

Przycisk kończący słuchanie w trybie głosowym Emmy pokazywał „checkmark”, który
sugeruje zatwierdzenie, a naprawdę wycisza mikrofon. Teraz to wyraźny `stop.fill`
z etykietą „Zatrzymaj nasłuch” i wartością stanu dla VoiceOver.

### Z-5 · Pole wiadomości w rozmowie — **zrobione**

`TextEditor` z minimalną wysokością 40 pt wyglądał jak pusty, wysoki prostokąt.
Zastąpiony polem jednoliniowym, które rośnie razem z treścią (1–6 linii).

### Z-6 · „Dzisiaj” z dzisiejszym terminarzem — **zrobione**

Ekran był tylko wejściem do Emmy i faktycznie nic nie wnosił. Teraz pokazuje
powitanie, zwięzły wiersz „Zapytaj Emmę o dzień” (orb + start rozmowy głosowej),
sekcję **„Dziś w kalendarzu”** z dzisiejszymi terminami i **„Zadania na dziś”**
z odhaczaniem oraz łączem do pełnej listy. Bez statystyk i sekcji o sprawach.

### Z-7 · Koniec podziału na użytkowników + logowanie i Face ID — **zrobione**

Zespół ma te same zadania i sprawy, więc podział na Tomasza i Pawła był fikcją —
podobnie jak przypisywanie opiekuna. Usunięte zostały `ownerID`, `OwnerName`,
`assignOwner`, `switchUser` i arkusz opiekuna, a dane demo mają **jedno wspólne
konto kancelarii** (`user-kancelaria`, inicjały „KR”) zamiast dwóch prawników.
Wszystko należy do kancelarii, a powitanie to po prostu „Dzień dobry”.

Zamiast podziału dochodzą dwa ekrany dostępu: logowanie demo (raz na urządzenie)
i odblokowanie Face ID / hasłem urządzenia przy każdym wejściu. Szczegóły decyzji
i cofnięcia: `DESIGN_DEVIATIONS.md` D-16 i D-17.

**Weryfikacja:** `swift test` 173/0; `xcodebuild test` 196/0 (w tym 11 XCUITest
i 12 nowych testów logiki dostępu); build `Emma-Demo` SUCCEEDED; aplikacja
zainstalowana i uruchomiona na iPhone 17 Pro (iOS 26.5).

---
