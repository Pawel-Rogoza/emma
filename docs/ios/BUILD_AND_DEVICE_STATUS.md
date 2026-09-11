# Bramki build i urządzenie — raport uczciwy

Ten dokument mówi wyłącznie o tym, **co zostało faktycznie sprawdzone**, a czego nie.
Powstał w środowisku bez macOS i bez Xcode, więc nie może zawierać deklaracji kompilacji.

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
| Testy logiki domenowej i głosu | **wykonane** | `Executed 132 tests, with 0 failures (0 unexpected)` |
| Kontrola składni wszystkich plików Swift (w tym SwiftUI) | **wykonana** | `Sprawdzono plików: 60, błędów składni: 0`
| Kontrola odwołań do zależności i tokenów | **wykonana** | `brak odwołań bez deklaracji` | |
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

## Zalecana kolejność pierwszego uruchomienia na Macu

1. `cd ios && ./scripts/generate-project.sh`
2. Otwórz `ios/Emma.xcodeproj`, poczekaj na pobranie pakietów (ElevenLabs, LiveKit).
3. Zbuduj schemat `Emma-Demo` — **tu po raz pierwszy sprawdzane są typy**.
4. Napraw to, co zgłosi kompilator; po każdej poprawce dopisz wynik do
   `docs/ios/IMPLEMENTATION_STATUS.md`.
5. `Cmd+U` (schemat `Emma-Demo`) i dopiero potem uruchomienie na urządzeniu.
6. Zrzuty ekranu pięciu zakładek → porównanie z referencją → wpis w
   `docs/ios/DESIGN_DEVIATIONS.md`.
