# Audyt kodu Emmy — co znaleziono i co z tym zrobiono

Audyt wykonany przed pierwszym uruchomieniem na Macu, na polecenie właściciela:
„wykonaj audyt kodu pod względem jakości, designu i tak dalej; jeśli gdzieś klepnąłeś
pięć funkcji, gdzie można klepnąć jedną, to wiesz co robić”.

Ten dokument jest raportem, a nie listą życzeń: każda pozycja ma status
**zrobione**, **świadomie zostawione** albo **do zrobienia na Macu**.

Stan po audycie: **161 testów logiki, 0 błędów** (było 142), **64 pliki bez błędu
składni**, `swift build` **bez ostrzeżeń**, filtr odwołań czysty.

---

## 1. Błędy realne, nie kosmetyczne

Cztery znaleziska nie były kwestią stylu — kod nie robił tego, co deklarował.

### A-01 · Limity sesji głosowej istniały tylko na papierze — **zrobione**

`VoiceSessionCoordinator` przyjmował `idleTimeout: 5 min` i `sessionLifetime: 30 min`,
zapisywał `startedAt`, a w `viewDidDisappear()` stało `_ = idleTimeout`, `_ = sessionLifetime`,
`_ = startedAt` — czyli trzy przypisania istniejące wyłącznie po to, żeby kompilator
nie zgłaszał nieużywanych pól. Limity **nie były nigdzie egzekwowane**: rozmowa mogła
trwać dowolnie długo i nie kończyła się po pięciu minutach ciszy.

Zrobione: znacznik `lastActivityAt`, metoda `enforceSessionLimits()` oraz **stróż**
(„watchdog”), który sam sprawdza limity co 15 s, dopóki sesja żyje. Stróż należy do
koordynatora, bo opuszczenie ekranu Emmy **nie** kończy rozmowy (§5.6) — zegar w widoku
zawiódłby dokładnie w tym przypadku. Powód zakończenia jest widoczny dla użytkownika
(„Brak aktywności”, „Sesja wygasła”), bo „Zakończona” bez wyjaśnienia wygląda jak awaria.

Testy: 5 nowych przypadków + próba mutacyjna (po wyłączeniu stróża testy padają).

### A-02 · Spóźnione zdarzenie odsłuchu zmieniało stan sesji — **zrobione**

`PlaybackEvent` niesie `sourceID` z komentarzem „do korelacji ze stanem”, a koordynator
miał `_ = sourceID`. Skutek: zakończenie **poprzedniego** odsłuchu zatrzymywało bieżący,
a błąd starego żądania ustawiał stan całej sesji. To dokładnie ta klasa błędu, przed którą
ostrzega plan (§5.4, zdarzenia spóźnione).

Zrobione: koordynator pamięta `activePlaybackSourceID`, nowe żądanie unieważnia poprzednie,
zdarzenia innego żądania są odrzucane.

Testy: 2 nowe przypadki (z usługą sterowaną ręcznie, bo mock kończy odtwarzanie od razu)
+ próba mutacyjna.

### A-03 · Fabryka usług głosowych była kodem, którego nikt nie wołał — **zrobione**

`VoiceServicesFactory` istniała, miała dokumentację i decydowała „mock czy dostawca
SDK”. A **sześć** miejsc tworzyło mocki bezpośrednio, z pominięciem fabryki:

| Plik | Co tworzył wprost |
| --- | --- |
| `AssistantStore.swift` | `MockVoiceTransport`, `MockDictationService`, `MockSpeechPlaybackService` |
| `ThreadScreen.swift` | `MockDictationService` |
| `WorkSheets.swift` | `MockDictationService` |
| `TodayScreen.swift` | `MockSpeechPlaybackService` |

Skutek: build bez Demo nadal mówiłby mockiem, a ścieżka dostawcy była **nieosiągalna**.
To nie „porządek”, to pozorna integracja, której plan wprost zakazuje.

Zrobione: jedno miejsce decyzyjne — `AppDependencies.makeVoiceTransport`,
`makeDictationService`, `makePlaybackService`, wszystkie przez fabrykę. Dodatkowo
`makePlaybackService(configuration:)` przyjmował parametr i go ignorował (`_ = configuration`),
sugerując wybór, którego nie ma — parametr usunięty, a powód zapisany w komentarzu.

### A-04 · Polityka trasy audio była martwą logiką — **zrobione**

`AudioRoutePolicy` miała testy i regułę „po odłączeniu słuchawek nie przenoś poufnego
odsłuchu na głośnik”, ale **nikt jej nie wywoływał**: `AudioSessionController` raportował
zmiany trasy i przerwania do nikogo.

Zrobione: `handleAudioRouteChange(to:)` w koordynatorze nadaje polityce skutek
(zatrzymuje odsłuch, mówi dlaczego, nie przenosi na głośnik), a `AppDependencies` wpięło
zdarzenia `onRouteChange` i `onInterruption`. Test + próba mutacyjna.

---

## 2. Pięć funkcji tam, gdzie wystarczy jedna

### A-05 · Trzynaście kopii tłumaczenia błędu — **zrobione**

Ten sam trójkąt `catch let error as DomainError { phase = .failed(error.safeMessage) }`
powtarzał się **13 razy** w 11 plikach. Każda kopia to osobna okazja, żeby jeden ekran
zaczął pokazywać surowy błąd techniczny.

Zrobione: jedno `ScreenLoad.message(for:fallback:)` i jedno miejsce decyzji.

### A-06 · Trzy kopie formatera godziny — **zrobione**

`ConversationRow`, `MessageBubble` i `MessagingSheets` tworzyły własny `DateFormatter`
z „HH:mm” i strefą referencyjną. Poprawka strefy wymagałaby trzech zmian.

Zrobione: `DateTextFormatter.clockTime(_:)` — jedna implementacja, jedno miejsce.
W całym projekcie został **jeden** `DateFormatter`.

### A-07 · Trzy kopie reguły wyszukiwania — **zrobione (i zamyka D-09)**

Filtrowanie robiło `lowercased().contains(…)` w trzech miejscach. Skutek: „zelazna”
nie znajdowało „Żelazna”, „lukasz” nie znajdowało „Łukasz” — znana różnica D-09.

Zrobione: `SearchText` w domenie (testowalne na Linuksie), 8 testów. Uwaga warta
zapamiętania: `ł` **nie** jest literą diakrytyczną w sensie Unicode, więc samo składanie
znaków jej nie usuwa — trzeba jawnego mapowania. Sprawdziłem to pomiarem, nie założeniem.

Wpływ: ekrany klientów i rozmów znajdują teraz nazwiska wpisane bez polskich znaków.

### A-08 · `_ = pole` jako sposób na ostrzeżenia — **zrobione**

Cztery obejścia tego typu (`_ = idleTimeout`, `_ = sourceID`, `_ = configuration`,
`_ = turn`). Nie usunąłem ich po cichu: każde wskazywało albo na nieużywany stan
(A-01, A-04), albo na nieużywane wiązanie (`Actions.swift`: `if let existing = …` bez
użycia `existing`). Wszystkie cztery mają teraz jasny powód w kodzie.

### A-09 · Ostrzeżenia kompilatora — **zrobione (0)**

| Ostrzeżenie | Co się okazało |
| --- | --- |
| `value 'existing' was defined but never used` | wiązanie bez zastosowania → `!= nil` |
| `initialization of immutable value 'revised' was never used` | lokalna kopia niepotrzebna → `_ =` z uzasadnieniem |
| `result of call to 'confirm' is unused` | j.w. |
| `found 53 file(s) which are unhandled` (pakiet) | brak jawnego `exclude` warstw iOS → dodane `App`, `DesignSystem`, `Features`, `VoiceAdapters`, `Resources` |

`swift build` przechodzi teraz **bez ani jednego ostrzeżenia**, a lista tego, co da się
sprawdzić na Linuksie, jest zamknięta i widoczna w `Package.swift`.

---

## 3. Martwy kod i wymaganie, które nie było spełnione

### A-10 · Dynamic Type nie działał — **zrobione**

Plan wymaga (linia 120): „Przy dużym Dynamic Type zachowaj treść i obsługę…”. Typografia
używała `.custom(nazwa, size:)` i `.system(size:)`, czyli **tekst nie skalował się wcale**.
Obok leżał nieużywany `ScaledSpacing`, który skalowałby odstępy — czyli dokładnie odwrotnie,
niż było trzeba.

Zrobione w jednym miejscu (`EmmaTypography`): wszystkie style przechodzą przez trzy
konstruktory, one skalują się teraz względem `.body`. Przy domyślnej wielkości tekstu
mnożnik wynosi 1, więc zgodność z referencją jest zachowana. Szczegóły i dług: D-13.

Sprawdziłem też stałe wysokości (`frame(height:)`): wszystkie 7 to cienkie linie
separatorów i kwadratowe ikony — żadna nie obcina tekstu.

### A-11 · Trzy typy bez ani jednego użycia — **usunięte**

| Typ | Sytuacja | Decyzja |
| --- | --- | --- |
| `AssistantTurn` | nieużywany w aplikacji i testach, brak odpowiednika w kontrakcie API | usunięty (a `AssistantTurnRole` zostaje — tego używa ekran) |
| `EmmaOrbWithStatus` | komponent poziomy, niezgodny z układem referencji (orb hero + tekst wyśrodkowany) | usunięty |
| `ScaledSpacing` | bez użycia; po A-10 skalowanie odstępów jest niepotrzebne | usunięty |

Martwy typ to przyszłe dwa źródła prawdy. Zostały dwa poprawne typy mniej.

---

## 4. Sprawdzone i świadomie zostawione

Audyt bez tej sekcji byłby listą zmian dla samych zmian.

| Rzecz | Dlaczego zostaje |
| --- | --- |
| **Rozmiary ikon** (9 wartości inline: 11–19) | Referencja sama używa **11 różnych** rozmiarów `svg` w CSS (13, 14, 15, 16, 17, 18, 19, 21, 22, 25…). Wymyślenie skali „small/medium/large” **zatarłoby** związek z konkretnymi regułami CSS. To nie duplikacja, to wierność wzorcowi. |
| **`SearchText` a `PersonResolver`** | `PersonResolver` nadal używa `lowercased()`. To reguła rozpoznawania polecenia głosowego z własnymi testami; ujednolicenie **zmieni** zachowanie rozpoznawania, więc wymaga osobnej decyzji. Zapisane w D-09. |
| **`.task(id: dependencies.dataVersion)` × 12** | Wspólny modyfikator zasłoniłby moment przeładowania. Jedna jawna linia na ekran mówi wprost, co uruchamia wczytanie. |
| **Stałe odstępy przy skalowanym tekście** | Siatka kart z referencji; kontenery mają minimalne wysokości, więc treść się nie obcina. Zapisane w D-13. |
| **`EmmaMetrics`/`EmmaTheme` jako duże typy** | To tokeny designu z referencji, nie logika. Rozbijanie ich pogorszyłoby czytelność. |

---

## 5. Design — co sprawdzono

- **Zakazane elementy:** brak kolumny godzin w kalendarzu, brak etykiet pilności
  w rozmowach, brak liczników fałszywego dostarczenia, brak ramki telefonu i sztucznego
  paska systemowego (D-00a–d nadal aktualne).
- **Tokeny:** kolory i typografia przechodzą przez `EmmaTheme`/`EmmaTypography`; tokeny
  asystenta i docku są w tych samych typach, bez prywatnych stałych w widokach.
- **Pięć zakładek i orb:** bez zmian względem referencji.
- **Arkusz `ScreenLoad`/`SearchText`:** nowe reguły są w domenie, więc mają testy —
  a nie tylko „wyglądają dobrze”.
- **Czego nie sprawdzono:** wyglądu. Brak macOS i symulatora, więc porównania zrzutów
  nadal **nie było**. Audyt nie zmienia tego faktu i niczego nie deklaruje w tym zakresie.

---

## 6. Jak to zostało sprawdzone

| Metoda | Wynik |
| --- | --- |
| `swift test` | 161 testów, 0 błędów (przed audytem: 142) |
| Testy mutacyjne | 4 mutacje (limity, stróż, korelacja odsłuchu, trasa audio) — każda wywołała padnięcie właściwych testów; po cofnięciu wszystko zielone |
| `swift build` | 0 ostrzeżeń (przed: 5 kategorii ostrzeżeń) |
| `swiftc -parse` | 64 pliki, 0 błędów składni |
| Filtr odwołań | 0 odwołań do nieistniejących składowych |
| `verify-linux-logic.sh` | 5/5 kroków bez zastrzeżeń (runda 1; runda 2 rozszerzyła bramkę do 7) |

**Czego to nie dowodzi:** że kod się kompiluje w Xcode. Zmiany w `App/`, `Features/`,
`DesignSystem/` i `VoiceAdapters/` są nadal tylko prze-parsowane — kontrola typów
i zależności od SwiftUI/UIKit nastąpi dopiero na Macu. Nowe elementy w tych warstwach
to: wywołania fabryk, wpięcie zdarzeń audio, skalowanie typografii i usunięcia typów.
Logika (limity, korelacja, wyszukiwanie, trasa) jest w warstwie testowanej wykonaniem.


## 7. Audyt runda 2 — czego nie widział filtr nazw (i widzi teraz)

Runda 2 powstała z pytania „czy da się jeszcze coś poprawić”. Zamiast czytać kod
trzeci raz, dołożyłem **cztery kontrole automatyczne**, które mają szukać tam, gdzie
człowiek przestaje zauważać: martwe tokeny, kolory bez odpowiednika w referencji,
odwołania do niezadeklarowanych składowych typów systemowych oraz pomiar renderu.

### A-12 · Dziewiętnaście odwołań do `Color.<token>`, których nigdzie nie było — **zrobione**

Najpoważniejsze znalezisko tej rundy i **błąd, który zatrzymałby pierwszy build**.

W pięciu plikach widoków kod wołał `Color.emmaDockStatusText`,
`Color.emmaActionHeadingText`, `Color.emmaListenText`, `Color.emmaSuggestionIcon`
i trzynaście podobnych. Takiej składowej nie ma ani w `EmmaTheme`, ani w żadnym
rozszerzeniu `Color` — tokeny nazywają się `EmmaTheme.dockStatusText`,
`EmmaTheme.actionHeadingText` itd. Na Linuksie nikt tego nie zauważył, bo:

* filtr odwołań (krok 3) sprawdzał wyłącznie uchwyty `EmmaTheme.`, `EmmaTypography.`,
  `EmmaRadii.`, `EmmaSpacing.`, `EmmaMetrics.`, `dependencies.`, `repository.`, `voice.`,
  `clock.`, `dataset.`, `dateText.` — **nie sprawdzał `Color.`**,
* `swiftc -parse` sprawdza składnię, a `Color.emmaDockStatusText` jest składniowo poprawne.

Naprawa: 24 odwołania zamienione na właściwe tokeny (`Color.emmaX` → `EmmaTheme.x`,
a dla doku i akcji na nazwy bez przedrostka `emma`). Filtr odwołań rozszerzony tak,
by każdy uchwyt typu systemowego (`Color`, `Font`, `Image`, `ShapeStyle`) musiał być
albo składową systemową z jawnej listy, albo **zadeklarowany w rozszerzeniu tego typu**.
Test mutacyjny: wstrzyknięcie `Color.emmaBogusToken` do `VoiceDock.swift` wywala filtr
z komunikatem, po cofnięciu — zielono.

### A-13 · Tokeny bez zastosowania i token wymyślony — **zrobione**

Skan „zadeklarowane, nigdzie nieużyte” wskazał dziesięć tokenów. Po naprawie A-12
zostało pięć, z czego trzy usunięte:

| Token | Co było | Decyzja |
| --- | --- | --- |
| `emmaCardMuted` | koloru `#9FB0C4` **nie ma w referencji** w ogóle | usunięty jako wymyślony |
| `focusRing` | `#91AFD0` to `:focus-visible` z CSS — pojęcie przeglądarki | usunięty; na iOS fokus rysuje system |
| `sheetHandle` | `#C9D0D9` to `.handle` z arkusza HTML | usunięty; arkusz używa systemowego uchwytu (`presentationDragIndicator`) |
| `emmaGradientStart` / `emmaGradientEnd` | gradient `.case-emma` `110deg` | **zostawione i użyte** — patrz A-14 |

### A-14 · Karta „Przygotuj mnie do tej sprawy” nie wyglądała jak w referencji — **zrobione**

Porównanie z regułą `.case-emma` pokazało pięć różnic naraz: brak gradientu
(`linear-gradient(110deg,#eaf0f6,#f6f8fa)`) zastąpiony białym tłem, promień 17 pt
zamiast 14, orb 37 pt zamiast 32, tytuł 14 pt zamiast 13, podtytuł 11 pt w `muted`
zamiast 10 pt w `#8494A7`, ikona 15 pt w `mutedSoft` zamiast 18 pt w `#557799`
i padding 15/16 zamiast 14. Dodane tokeny `caseEmmaBorder`, `caseEmmaSubtitle`,
`caseEmmaIcon`, `EmmaRadii.caseEmmaCard`, `EmmaSpacing.caseEmmaGap` mają komentarze
z selektorem referencji, więc następna osoba nie zgadnie, skąd te liczby.

### A-15 · Tłumaczenie w dymku było zawsze rozwinięte i miało wymyślony kolor — **zrobione**

Referencja trzyma tłumaczenie w `<details>` — czyli **zwinięte**, z nagłówkiem
„Tłumaczenie”, linią `#E1E7EE` nad treścią i osobnymi kolorami etykiety (`#627790`)
i treści (`#4E6178`). Aplikacja pokazywała całość od razu, etykietę 10 pt semibold
z rozstrzeleniem i kolor `#5E6E80`, którego w referencji nie ma. Teraz: zwijane,
z `@State` w dymku, linią, odstępami 9/8 pt i trzema właściwymi kolorami
(`bubbleTranslationRule`, `bubbleTranslationLabel`, `bubbleTranslationText`).

### A-16 · Dwa kolory bez odpowiednika w referencji — **zrobione**

`translationText` (patrz A-15) oraz `weekControlText` = `#4C6480`, gdy
`.week-controls .icon-button` ma `#69819b`. Oba poprawione; kontrole kolorów
(nowy krok 6 bramki) nie znajdują już żadnego wymyślonego koloru w 100 tokenach.

### A-17 · Briefing „Dzisiaj” był uwięziony w pliku SwiftUI — **zrobione**

`TodayStore.briefing` i `TodayStore.vocative` leżały w `TodayScreen.swift`. Skutek
praktyczny: tego samego napisu nie mogły użyć ani testy logiki, ani podgląd na
Linuksie — a więc prędzej czy później powstałaby druga kopia. Przeniesione do
`Emma/Core/Domain/EmmaBriefing.swift` (warstwa kompilowana i testowana na Linuksie),
ekran woła `EmmaBriefing.briefing(...)`. To ta sama zasada, co przy A-05/A-07:
jedna funkcja, jedno miejsce.

### A-18 · Filtr odwołań zaniżał własny zasięg — **zrobione**

Komunikat końcowy mówił „sprawdzono, brak odwołań bez deklaracji (**0 kandydatów**)",
bo licznik zwiększał się tylko przy znalezieniu problemu. Wyglądało to jak brak
kontroli. Teraz licznik liczy wszystkie sprawdzone odwołania: **1078**, w tym
rozszerzenia typów systemowych.

### Narzędzia dodane w tej rundzie

| Narzędzie | Co sprawdza | Kiedy się myli |
| --- | --- | --- |
| `scripts/check-cross-references.py` (rozszerzony) | uchwyty zależności **oraz** składowe typów systemowych | nie zna typów spoza listy uchwytów |
| `scripts/design-token-diff.py` | wartości użyte w komponencie wobec reguł CSS referencji; rozdziela „kolor wymyślony” (błąd) od „token współdzielony” (do oka) | selektory potomne poza listą komponentu |
| `scripts/verify-preview-render.py` | **prawdziwy render** podglądu: czcionki, wystawanie poza okno, ucinanie tekstu, nachodzenie elementów, tła, zwinięcie tłumaczenia | wymaga przeglądarki; bez niej mówi „nie zmierzono” |

### Runda 2 w liczbach

| Metoda | Wynik |
| --- | --- |
| `verify-linux-logic.sh` | **7/7** kroków bez zastrzeżeń (było 5; runda 3 rozszerzyła do 8) |
| `swift test` | 161 testów, 0 błędów |
| `swiftc -parse` | 65 plików, 0 błędów składni |
| Filtr odwołań | 1078 odwołań sprawdzonych, 0 bez deklaracji |
| Kontrola kolorów | 100 tokenów koloru, **0** spoza referencji |
| Pomiar renderu podglądu | 5/5 czcionek, 0 przekroczeń szerokości, 0 ucięć, 0 nachodzenia |

## 8. Audyt runda 3 — obietnice bez pokrycia

Runda 3 wyszła z jednego pytania: „które publiczne elementy rdzenia nikt nie woła?”.
Takie elementy są groźniejsze niż brak kodu: wyglądają na gotowe, a przy okazji
zapraszają do drugiej implementacji tej samej reguły. Skan nazw wykazał 10 takich
składowych — i **trzy z nich okazały się niedokończonymi wymaganiami z planu**.

### A-19 · Przejęcie sesji przez inne urządzenie nie robiło nic — **zrobione**

Plan (linia 342): „Odebranie uprawnienia, wylogowanie, zmiana konta i **przejęcie sesji
przez inne urządzenie** kończą możliwość wykonania narzędzi.” Koordynator miał metodę
`handleSessionTakenOverByAnotherDevice()`, ale **nikt jej nie wołał** — więc w praktyce
przejęcie sesji nie kończyło u nas prawa zapisu głosem.

Co zrobione: koordynator przyjmuje teraz wstrzykiwane źródło stanu sesji
(`sessionStatus`), a jego stróż — ten sam, który pilnuje limitów czasu — pyta backend
raz na cykl. Gdy backend raportuje sesję jako **nieaktywną**, choć my wciąż trzymamy
połączenie, sesja kończy się z powodem „przejęta przez inne urządzenie” i traci prawo
zapisu, zachowując szkic. Aplikacja wpięła źródło w `AppDependencies` (zapytanie idzie
tym samym repozytorium co reszta).

Testy: 4 nowe (`testBackendReportingInactiveSessionEndsItAndRevokesVoiceWrites`,
`testBackendReportingActiveSessionKeepsItRunning`,
`testReconciliationWithoutStatusSourceDoesNothing`, `testWatchdogReconcilesSessionWithBackend`).
Testy mutacyjne: usunięcie wywołania w stróżu oraz zamiana kończenia na zwykłe `end`
(bez odebrania prawa zapisu) — każda mutacja wywala właściwy test.

### A-20 · „Spróbuj ponownie” tam, gdzie ponowienie nie ma sensu — i jego brak tam, gdzie ma — **zrobione**

`DomainError.isRetryable` mówi wprost: ponowienie ma sens tylko przy `offline`
i `transportFailure`; konflikt wersji i brak uprawnień nie naprawią się od kliknięcia
(§4.4, §7). A ekrany robiły odwrotnie:

| Ekrany | Co pokazywały | Problem |
| --- | --- | --- |
| Dzisiaj, Klienci, Karta klienta | „Spróbuj ponownie” przy **każdym** błędzie | obietnica bez pokrycia przy konflikcie wersji i braku uprawnień |
| Zadania, Kalendarz, Rozmowy, Sprawa, Wątek, trzy arkusze | tylko komunikat | przy zerwanej sieci nie było czym ponowić |

Co zrobione: `LoadPhase.failed` niesie teraz `LoadFailure` (komunikat **i** regułę
ponowienia), `ScreenLoad.failure(for:fallback:)` wyznacza oba z jednego miejsca, a jeden
wspólny widok `LoadFailureView` pokazuje przycisk dokładnie wtedy, gdy reguła na to
pozwala. Dwanastoletnia różnica między ekranami zniknęła razem z 12 kopiami bloczka.

Przy okazji `LoadPhase.swift` przeniesiony z `App/` do `Core/Domain/`: nie ma w nim ani
jednego odwołania do SwiftUI, ale ponieważ leżał w warstwie wykluczonej z pakietu
linuksowego, reguły ponowienia **nie dało się przetestować**. Teraz ma 5 testów.

### A-21 · Znacznik wysyłki liczony w dwóch miejscach — **zrobione**

`MessageTransport.receiptGlyph` w rdzeniu opisywał, który znacznik odpowiada któremu
stanowi (`clock` / `single` / `double`), a widok `ReceiptMark` liczył to samo drugi raz
(`== .pending`, `== .delivered || == .read`) i **nigdy nie używał reguły z rdzenia**.
Teraz widok przełącza się po `transport.receiptGlyph`, więc zmiana reguły zmienia
zarówno rdzeń, jak i ekran.

### A-22 · Etykieta kontekstu jako literał w trzech miejscach — **zrobione**

„Cała kancelaria” było wpisane w `AssistantStore`, w arkuszu wyboru kontekstu i jako
`AssistantContext.displayLabel` w rdzeniu (którego nikt nie wołał). Teraz obie warstwy
używają `AssistantContext.firm.displayLabel`.

### A-23 · Sześć składowych rdzenia bez użycia — **usunięte**

| Składowa | Dlaczego usunięta |
| --- | --- |
| `VoiceSessionCoordinator.stateStream()` | drugi sposób obserwacji stanu obok `addObserver`, którego używa aplikacja; dwa sposoby na to samo rozjeżdżają się |
| `VoiceSessionCoordinator.disarmVoiceConfirmation()` | akcje anuluje `cancelAction`, a rozbrojenie robi silnik przy nowej propozycji i reconnectcie |
| `DateTextFormatter.isoField(_:)` | jednowierszowa nakładka na `date.isoString` |
| `LocalDate.startOfMonth` | pasek tygodnia go nie potrzebuje |
| `ScheduledEvent.startInstant` | aplikacja używa `day` + `time` |
| `MockVoiceTransport.reportsExactPlayback` | flaga mocka, której nie ustawiał ani nie czytał żaden test |

### A-24 · Kontrola martwego API jako stała bramka — **dodane**

Skoro ta klasa problemu była niewidoczna, jest teraz krokiem bramki:
`scripts/check-dead-code.py` liczy wystąpienia każdej publicznej składowej `Emma/Core/**`
we wszystkich źródłach Swift (aplikacja, testy, testy UI, eksporter podglądu) i kończy
się błędem, jeśli któraś nie ma ani jednego użycia. Lista wyjątków (składowe wymagane
przez protokoły: `description`, `id`, `body`…) jest **jawna** — ukryta lista wyjątków
to sposób na to, żeby kontrola nic nie znaczyła. Test mutacyjny: dopisanie metody
`speculativeHelper()` kończy kontrolę błędem, po cofnięciu mija.

Stan po rundzie 3: **0** martwych publicznych składowych rdzenia na 514 sprawdzanych.

### Runda 3 w liczbach

| Metoda | Wynik |
| --- | --- |
| `verify-linux-logic.sh` | **8/8** kroków bez zastrzeżeń (było 7) |
| `swift test` | **170** testów, 0 błędów (było 165 po rundzie 2, 161 po rundzie 1) |
| Testy mutacyjne rundy 3 | 3 mutacje (brak uzgadniania w stróżu, brak odebrania prawa zapisu, martwa metoda) — każda wywołała padnięcie właściwego testu |
| Martwe publiczne API rdzenia | 0 z 514 |
| Pomiar renderu podglądu | bez zastrzeżeń |

## 9. Pierwsze kroki na Macu — kolejność z tego audytu

1. `./scripts/generate-project.sh`, build, naprawa błędów typów (lista w `BUILD_AND_DEVICE_STATUS.md`).
2. Sprawdzić **D-13**: duży Dynamic Type w kategorii XXXL — czy nic się nie obcina.
3. Sprawdzić wpięcie zdarzeń audio: przełączenie na głośnik w trakcie odsłuchu
   ma **zatrzymać** odsłuch z komunikatem, a nie przenieść go na głośnik.
4. Sprawdzić stróża limitów na urządzeniu: sesja bezczynna kończy się po 5 minutach
   i pokazuje powód.
5. Wrzucić zrzuty z CI i porównać z prototypem; każde odstępstwo dopisać do
   `DESIGN_DEVIATIONS.md` — **nie** zmieniając wzorca.
