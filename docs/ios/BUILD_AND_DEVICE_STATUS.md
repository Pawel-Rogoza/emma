# Bramki build i urządzenie — raport uczciwy

Ten dokument mówi wyłącznie o tym, **co zostało faktycznie sprawdzone**, a czego nie.
Powstał w środowisku bez macOS i bez Xcode, więc nie może zawierać deklaracji kompilacji.

## 2026-09-15 — drugi dostawca głosu (Gemini Live): co dokładnie zmierzono

Nowy przebieg na macOS (Xcode 26.6, Swift 6.3.3), gałąź `feat/gemini-live-voice`:

| Bramka | Wynik | Dowód |
| --- | --- | --- |
| Kompilacja projektu Xcode ze ścieżką Gemini Live | **wykonana** | `** BUILD SUCCEEDED **` (`-scheme Emma-Demo`, iPhone 17 Pro) |
| Testy logiki (`swift test`) | **330/330** | `Executed 330 tests, with 0 failures` |
| Testy w Xcode (`-only-testing:EmmaTests`) | **428/428** | `Executed 428 tests, with 0 failures` (w tym 3 integracyjne transportu Gemini Live na prawdziwym gnieździe WebSocket: uścisk dłoni, obieg narzędzia, barge-in i wznowienie po `goAway`) |
| Skrypt `verify-linux-logic.sh` | **9/9 kroków** | 125 plików, 0 błędów składni; 1167 odwołań bez braków; 0 martwego API (650 składowych) |
| Kontrakt Live API **u Google** na żywym kluczu | **wykonany** | `GEMINI_LIVE_SPIKE=1` → `Test Files 1 passed`, `Tests 3 passed`: poświadczenie (`auth_tokens/…`, ~0,5 s), polska tura („Jestem Emma, asystentka w kancelarii adwokackiej. W czym mogę Ci dzisiaj pomóc?” + 250 562 B audio 24 kHz), obieg narzędzia (`get_today_overview` → po `FunctionResponse` głos + 253 442 B audio) |
| Realna rozmowa Gemini Live na urządzeniu | **niewykonana** | wymaga iPhone'a i oceny polskiego przez człowieka (lista w `RUNBOOK_GEMINI_LIVE.md`, sekcja 5) |

Szczegóły przełącznika i rollbacku: `docs/ios/RUNBOOK_GEMINI_LIVE.md`.
Analiza wyboru dostawcy (ceny, ograniczenia, brak SDK Swift): `docs/ios/research/gemini-3-8-live-vs-elevenlabs.md`.

Żywy API odrzucił przy pierwszym uruchomieniu trzy rzeczy, które przechodziły testy
jednostkowe i atrapę: nazwę pola blokady (`liveConnectConstraints` nie istnieje
w bieżącym `v1beta`), `additionalProperties` w schematach narzędzi oraz
`properties` potraktowane jak schemat (to ostatnie zamykało sesję kodem `1007`
przed `setupComplete`). Wszystkie trzy naprawione i pokryte testami; opis wraz
ze źródłami w `docs/emma/GEMINI_LIVE_KONTRAKT.md` w repo backendu.

**Naprawa zastanej usterki (niezwiązana z Gemini).** `swift test` **nie przechodził**
przed tą zmianą: `EmmaTests/Logic/EmmaOrbTests.swift` testował `EmmaOrb`, który jest
widokiem SwiftUI z warstwy wykluczonej z pakietu logiki. Plik przeniesiono do
`EmmaTests/App/` (ten sam cel co inne testy widoków). Bez tego żadna bramka logiczna
nie dawała się uruchomić, więc nie dało się zmierzyć niczego powyżej.

## Stan bieżący — macOS, Xcode 26.6 (12 września 2026)

Bramki, które wcześniej były „niewykonane z braku macOS”, są **wykonane**:

| Bramka | Stan | Dowód |
| --- | --- | --- |
| Kompilacja projektu Xcode (scheme `Emma-Demo`) | **wykonana** | `** BUILD SUCCEEDED **` |
| Testy logiki domenowej i głosu (`swift test`) | **wykonane** | `Executed 182 tests, with 0 failures` (w tym 9 dla osi dnia i usuwania terminu) |
| Testy jednostkowe w Xcode | **wykonane** | `Executed 194 tests, with 0 failures` (w tym 12 dla logowania i Face ID) |
| Testy interfejsu (XCUITest) | **wykonane** | `Executed 11 tests, with 0 failures` — 10 scenariuszy przepływu + bramka logowania |
| Cały zestaw Xcode (`xcodebuild test`) | **wykonany** | `Executed 205 tests, with 0 failures` |
| Uruchomienie na symulatorze | **wykonane** | iPhone 17 Pro (iOS 26.5), `simctl install` + `launch` potwierdzone PID-em |
| Zrzuty ekranu porównane z referencją | **niewykonane** | zrzuty są zbierane (`ScreenshotCaptureUITests`), ale **nie zostały obejrzane** przez autora zmian |
| Test na fizycznym iPhonie | **niewykonana** | wymaga urządzenia |
| Realna rozmowa z dostawcą głosu | **niewykonana** | `blocked_external` — brak konta |
| Realny odbiór/wysyłka WhatsApp | **niewykonana** | `blocked_external` — brak Tech Providera |

Uwaga o zrzutach ekranu: scena `11-profil` pokazuje profil po usunięciu przełącznika
użytkowników, a `testLoginScreenAcceptsDemoCredentials` przechodzi samą bramkę dostępu.
Wygląd ekranów logowania i blokady **nie został oceniony wzrokowo**.

To samo dotyczy przeprojektowanej sekcji „Dzisiaj” (scena Emmy, oś dnia, pierścienie
zadań). Zrzut jest zapisany w `screenshots/01-dzisiaj-po-zmianach.png`, ale **nie został
obejrzany** przez autora zmian — agent nie analizuje obrazów.

## Środowisko, w którym powstał kod

```
System operacyjny : Linux (bez macOS)
Xcode             : niedostępny
Symulator iOS     : niedostępny
iPhone            : niedostępny
Swift             : 6.1 (toolchain w ~/.local/swift)
Docker            : demon niedostępny
Backend           : repozytorium prywatne, brak dostępu
```

## Tabela bramek

| Bramka | Stan | Dowód |
| --- | --- | --- |
| Testy logiki domenowej i głosu | **wykonane** | `Executed 178 tests, with 0 failures (0 unexpected)` |
| Kontrola składni wszystkich plików Swift (w tym SwiftUI) | **wykonana** | `Sprawdzono plików: 65, błędów składni: 0` |
| Kontrola odwołań do zależności i typów systemowych | **wykonana** | `sprawdzono 1079 odwołań, brak odwołań bez deklaracji` |
| Kontrola tokenów koloru wobec referencji | **wykonana** | `100 tokenów, 0 spoza referencji` |
| Kontrola martwego publicznego API rdzenia | **wykonana** | `0 martwych składowych na 514 sprawdzanych` |
| Pomiar renderu podglądu dla Linuksa | **wykonany** | `5/5 czcionek, 0 przekroczeń szerokości, 0 ucięć, 0 nachodzenia` |
| Eksport danych demo tym samym kodem co aplikacja | **wykonany** | `swift run EmmaPreviewExport` → 4 klientów, 2 sprawy, 4 rozmowy, 8 wiadomości |
| Kontrola typów SwiftUI | **niewykonana** | wymaga kompilatora Apple |
| Kompilacja projektu Xcode | **niewykonana** | wymaga macOS |
| Testy jednostkowe w Xcode (`Cmd+U`) | **niewykonana** | wymaga macOS |
| Testy interfejsu (XCUITest) | **niewykonana** | wymaga macOS i symulatora |
| Uruchomienie na symulatorze | **niewykonana** | wymaga macOS |
| Test na fizycznym iPhonie | **niewykonana** | wymaga macOS i urządzenia |
| Zrzuty ekranu porównane z referencją | **niewykonane** | wymaga symulatora |
| Realna rozmowa z dostawcą głosu | **niewykonana** | `blocked_external` — brak konta |
| Realny odbiór/wysyłka WhatsApp | **niewykonana** | `blocked_external` — brak Tech Providera |
| Testy kontraktowe backendu | **niewykonane** | `blocked_external` — brak dostępu do repozytorium |

## Co dokładnie robi skrypt kontrolny

```bash
cd ios && ./scripts/verify-linux-logic.sh
```

Dwa kroki, żadnego udawania:

1. `swift test` na pakiecie `ios/Package.swift` — kompiluje i **wykonuje** logikę domenową
   oraz logikę głosu (cele `Emma` i `EmmaLogicTests`). Ten cel nie importuje SwiftUI,
   więc jego wynik jest prawdziwym wynikiem wykonania kodu.
2. `swiftc -parse` po **wszystkich** plikach Swift w projekcie, łącznie z widokami SwiftUI.
   To sprawdza wyłącznie składnię. Parser nie zna typów z SwiftUI, więc **nie wykryje**
   błędów typów, złych sygnatur ani brakujących symboli.
3. `scripts/check-cross-references.py` — czyta zadeklarowane składowe zależności,
   repozytorium i tokenów design systemu i porównuje je z użyciami w widokach.
   Ten filtr znalazł realny błąd (`dataset.user`, którego nie było w `DemoFixtures.Dataset`),
   ale nie sprawdza typów argumentów ani przeciążeń.

Dlatego pliki SwiftUI mają w rejestrze status „sprawdzone składniowo”, a nie
„zweryfikowane”. Pierwszym realnym sprawdzeniem typów będzie kompilacja na Macu.

## Ryzyka, które ujawni dopiero kompilator

Wypisane wprost, żeby nie zniknęły w raporcie końcowym:

1. **Sygnatury komponentów.** Widoki pisane równolegle w kilku przyrostach korzystają
   ze wspólnych komponentów (`PersonRow`, `CaseCard`, `MeetingCard`, `InfoList`,
   `ChoiceList`, `SurfaceCard`, `TaskRow`). Sygnatury porównano z miejscami wywołań
   oraz z `SheetHost` i `RouteDestination`, ale nie sprawdzono ich typami —
   liczba i typy argumentów pozostają do potwierdzenia przez kompilator.
2. **Liczba dzieci `ViewBuildera`.** Limit dziesięciu gałęzi jest pilnowany ręcznie —
   parser go nie sprawdza.
3. **Adnotacje współbieżności.** Projekt włącza `SWIFT_STRICT_CONCURRENCY: complete`
   i tryb języka Swift 6. Kontroler sesji audio i usługa mowy korzystają z domknięć
   wywoływanych poza wątkiem głównym; poprawność `@MainActor` potwierdzi dopiero kompilator.
4. **Dostępność API SDK.** Adapter dostawcy używa wywołań zwrotnych i publikowanych
   stanów opisanych w dokumentacji SDK. Nazwy i kształty tych API pochodzą z dokumentacji
   i researchu, nie z kompilacji — mogą wymagać korekty po pobraniu pakietu.
5. **Customowe czcionki.** Rejestracja sprawdza dostępność w czasie działania i zgłasza
   brak; jeśli pliki TTF nie trafią do pakietu zasobów, aplikacja użyje czcionki systemowej
   i powie o tym w konsoli.
6. **`Info.plist` i uprawnienia.** Opisy uprawnień są kompletne w `Info.plist`, ale
   `Package.swift` (ścieżka linuksowa) ich nie używa — realny efekt widać tylko na urządzeniu.

## Audyt kodu przed pierwszym uruchomieniem

Przed pierwszym uruchomieniem na Macu wykonano audyt jakości (polecenie właściciela).
Pełny raport: `docs/ios/AUDIT.md`. Najważniejsze skutki:

| Znalezisko | Skutek |
| --- | --- |
| Limity sesji głosowej były skonfigurowane, ale **nigdy nie egzekwowane** | dodany stróż limitów + 6 testów |
| Spóźnione zdarzenie odsłuchu zmieniało stan sesji | korelacja po identyfikatorze żądania + 2 testy |
| Fabryka usług głosowych była martwym kodem (6 miejsc omijało decyzję mock/dostawca) | jedno miejsce decyzyjne |
| `AudioRoutePolicy` była martwą logiką bez wywołań | wpięta w zdarzenia systemu audio |
| 13 kopii tłumaczenia błędu, 3 kopie formatera godziny, 3 kopie reguły wyszukiwania | po jednej implementacji każde |
| Dynamic Type nie skalował tekstu (wymóg planu) | skalowanie w jednym miejscu (`EmmaTypography`) |
| 3 typy bez użycia | usunięte |

Testy logiki: **142 → 161**, wszystkie przechodzą. `swift build`: **0 ostrzeżeń**
(wcześniej 5 kategorii). Cztery mutacje celowo zepsutego kodu wywołały padnięcie
właściwych testów, co potwierdza, że nowe testy faktycznie coś sprawdzają.

**Nadal niezweryfikowane:** kompilacja SwiftUI. Zmiany w warstwie iOS są tylko
prze-parsowane — kontrola typów nastąpi na Macu.

## Podgląd aplikacji bez MacBooka — co dokładnie pokazuje

Na Linuksie nie ma SwiftUI, więc **nie da się** zbudować aplikacji ani zrobić zrzutu
ekranu. Da się natomiast uruchomić prawdziwy kod danych i pokazać go w układzie referencji:

```bash
cd ios && ./scripts/start-preview.sh      # → http://127.0.0.1:8098/
```

Co w tym podglądzie jest prawdziwe (i skąd):

| Element | Źródło | Bramka |
| --- | --- | --- |
| Dane demo (klienci, sprawy, zadania, wydarzenia, notatki, historia, rozmowy, wiadomości) | `MockRepository` + `DemoFixtures`, czytane przez publiczne API repozytorium | `swift run EmmaPreviewExport` |
| Napisy („PIĄTEK, 11 WRZEŚNIA”, godziny, odmiana „3 zadania / 5 zadań”, briefing) | `DateTextFormatter`, `EmmaPlural`, `EmmaBriefing` — ten sam kod co ekrany | testy logiki |
| Stany (107 stanów w 20 en-umach) | `displayName` z rdzenia: połączenie, tura, trasa audio, powód zakończenia, wykonanie akcji, błędy | odczyt z kodu |
| Kolory, typografia, promienie, odstępy, orb | `EmmaTheme`, `EmmaTypography`, `EmmaMetrics`, `EmmaOrb` | krok 6 bramki |
| Czcionki | prawdziwe pliki `DMSans-*.ttf` i `Manrope-*.ttf` z `Emma/Resources/Fonts` | pomiar renderu |
| Układ ekranów | **rekonstrukcja referencji w HTML** — nie SwiftUI | pomiar renderu |

Czego ten podgląd **nie** pokazuje: dokładnego układu SwiftUI, zawijania tekstu w komórkach,
animacji, gestów, VoiceOver, Dynamic Type w kategorii XXXL (D-13) i wyglądu na urządzeniu.
Nie ma w nim ramki telefonu ani sztucznego paska systemowego — zgodnie z planem.
Podgląd jest generowany (`ios/.preview/index.html`) i nie trafia do repozytorium.

Render podglądu jest **mierzony**, a nie oceniany „na oko”:

```bash
cd ios && python3 scripts/verify-preview-render.py
```

Skrypt uruchamia headless Firefoksa, wstrzykuje pomiar układu i sprawdza: wczytanie
pięciu plików czcionek, brak wystawania poza szerokość okna, brak ucinania tekstu
w kontenerach o stałej szerokości, brak nachodzenia rodzeństwa w kolumnach ekranów,
brak pustych kart, obecność teł, zwinięcie tłumaczenia jak `<details>` w referencji.
Bez przeglądarki mówi wprost „nie zmierzono” — nie udaje, że sprawdził.

## Droga do pierwszej kompilacji bez MacBooka

Właściciel pracuje na Linuksie, więc przygotowano dwie rzeczy, które **nie wymagają Maca**:

| Element | Co daje |
| --- | --- |
| `.github/workflows/ios-macos.yml` | kompilacja i testy na runnerze `macos-15` oraz zrzuty ekranu jedenastu ekranów jako artefakt do pobrania |
| `ios/EmmaUITests/ScreenshotCaptureUITests.swift` | przejście po ekranach i zapis zrzutów wraz z raportem, który wprost oznacza ekrany nieudane |
| `ios/scripts/start-prototype-preview.sh` | podgląd zatwierdzonego wzorca designu w przeglądarce (`http://127.0.0.1:8099/`) |
| `ios/scripts/validate-ci-workflow.py` | kontrola struktury workflow — bo uruchomić go lokalnie nie można |

Instrukcja: `docs/ios/CI_MACOS.md`.

**Ten workflow nie został uruchomiony ani razu** — powstał bez macOS i bez dostępu do
GitHuba. Pierwszy przebieg jest zarazem pierwszą kontrolą typów SwiftUI i pierwszym
sprawdzeniem, czy przypięte wersje pakietów się rozwiązują.

## Zalecana kolejność pierwszego uruchomienia na Macu

1. `cd ios && ./scripts/generate-project.sh`
2. Otwórz `ios/Emma.xcodeproj`, poczekaj na pobranie pakietów (ElevenLabs, LiveKit).
3. Zbuduj schemat `Emma-Demo` — **tu po raz pierwszy sprawdzane są typy**.
4. Napraw to, co zgłosi kompilator; po każdej poprawce dopisz wynik do
   `docs/ios/IMPLEMENTATION_STATUS.md`.
5. `Cmd+U` (schemat `Emma-Demo`) i dopiero potem uruchomienie na urządzeniu.
6. Zrzuty ekranu pięciu zakładek → porównanie z referencją → wpis w
   `docs/ios/DESIGN_DEVIATIONS.md`.
