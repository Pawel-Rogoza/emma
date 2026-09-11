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
| `verify-linux-logic.sh` | 5/5 kroków bez zastrzeżeń |

**Czego to nie dowodzi:** że kod się kompiluje w Xcode. Zmiany w `App/`, `Features/`,
`DesignSystem/` i `VoiceAdapters/` są nadal tylko prze-parsowane — kontrola typów
i zależności od SwiftUI/UIKit nastąpi dopiero na Macu. Nowe elementy w tych warstwach
to: wywołania fabryk, wpięcie zdarzeń audio, skalowanie typografii i usunięcia typów.
Logika (limity, korelacja, wyszukiwanie, trasa) jest w warstwie testowanej wykonaniem.

## 7. Pierwsze kroki na Macu — kolejność z tego audytu

1. `./scripts/generate-project.sh`, build, naprawa błędów typów (lista w `BUILD_AND_DEVICE_STATUS.md`).
2. Sprawdzić **D-13**: duży Dynamic Type w kategorii XXXL — czy nic się nie obcina.
3. Sprawdzić wpięcie zdarzeń audio: przełączenie na głośnik w trakcie odsłuchu
   ma **zatrzymać** odsłuch z komunikatem, a nie przenieść go na głośnik.
4. Sprawdzić stróża limitów na urządzeniu: sesja bezczynna kończy się po 5 minutach
   i pokazuje powód.
5. Wrzucić zrzuty z CI i porównać z prototypem; każde odstępstwo dopisać do
   `DESIGN_DEVIATIONS.md` — **nie** zmieniając wzorca.
