# Stan implementacji Emmy — rejestr przyrostów

Ten plik jest prowadzony na bieżąco po każdym przyroście: co zostało zrobione,
jak zostało sprawdzone i co jest następnym krokiem. Nie zawiera deklaracji,
których nie da się potwierdzić w tym środowisku.

Legenda statusów:

- **zweryfikowane** — kod wykonany i sprawdzony działaniem (testy na Linuksie),
- **sprawdzone składniowo** — plik przechodzi `swiftc -parse` (SwiftUI nie kompiluje się na Linuksie),
- **niezweryfikowane** — napisane, ale nieuruchomione (wymaga macOS + Xcode),
- **blocked_external** — wymaga konta, dostępu lub decyzji poza tym środowiskiem.

---

## Środowisko wykonawcze

| Element | Stan |
| --- | --- |
| System | Linux, bez macOS i bez Xcode |
| Swift | 6.1 (toolchain Ubuntu 24.04 w `~/.local/swift`) |
| Symulator iOS | niedostępny |
| Urządzenie iPhone | niedostępne |
| Docker | demon niedostępny (użyto lokalnego toolchainu) |
| Backend | repozytorium prywatne, bez dostępu — `blocked_external` |

Szczegóły audytu: `docs/ios/BASELINE.md`.

---

## Etap 00 · Audyt rzeczywistego stanu

**Status: zweryfikowane (dokumentacja) + blocked_external (backend)**

- [x] Sprawdzone sumy kontrolne referencji wobec `reference/manifest.json` — zgodne.
- [x] Przeanalizowana kaskada CSS referencji: wskazane żywe i martwe warstwy selektorów.
- [x] Zmierzona kontrola pokrycia glifów czcionek (odczyt tablic `cmap` i `name` plików TTF).
- [x] Audyt backendu: `git ls-remote` prosi o poświadczenia, GitHub API zwraca 404 dla
      obu kandydackich repozytoriów. Historycznego opisu backendu **nie da się potwierdzić**
      na żadnym SHA — oznaczony jako `blocked_external`, nie przepisany bezkrytycznie.
- [x] Zapisany kontrakt designu i lista świadomych odstępstw.

Dokumenty: `docs/ios/BASELINE.md`, `docs/ios/DESIGN_CONTRACT.md`,
`docs/ios/research/elevenlabs-swift-sdk.md`, `docs/ios/research/whatsapp-coexistence.md`.

---

## Etap 01 · Szkielet projektu

**Status: zweryfikowane (składnia) — kompilacja Xcode: niezweryfikowane**

- [x] `ios/project.yml` jako jedyne źródło projektu Xcode (trzy konfiguracje, trzy schematy współdzielone).
- [x] Pakiety dostawcy przypięte dokładnie (ElevenLabs 3.3.1, LiveKit 2.16.0), adapter za `canImport`.
- [x] Zestawy danych demo (`--fixture`): dzień referencyjny, zalogowany prawnik i scenariusz mocka
      wybierane nazwą; nieznana nazwa kończy się czytelnym zgłoszeniem, nie cichym fallbackiem.
- [x] `Config/{Demo,Staging,Production}.xcconfig` bez sekretów, `Local.xcconfig` w `.gitignore`.
- [x] `Info.plist`: środowisko, adres backendu, locale, opisy uprawnień mikrofonu i mowy,
      `UIAppFonts` z pięcioma czcionkami, tryb jasny, tylko pion.
- [x] Assety: `AccentColor`, tło ekranu startowego, ikona 1024×1024 wygenerowana programowo.
- [x] Czcionki: DM Sans (Regular/Medium/SemiBold) i Manrope (Bold/ExtraBold) + licencje OFL.
- [x] Kontrola rejestracji czcionek przy starcie (`EmmaFontRegistration`) — brak czcionki
      jest głośno raportowany, a nie po cichu zastępowany.

---

## Etap 02 · Design System

**Status: zweryfikowane (składnia)**

- [x] `EmmaTheme` — tokeny kolorów wyliczone z kaskady CSS referencji.
- [x] `EmmaTypography` — nazwy PostScript odczytane z plików, jawne rozstrzygnięcie cyrylicy.
- [x] `EmmaMetrics` — promienie, odstępy, wymiary, adaptacja do szerokości ≤ 365 pt,
      `ScaledSpacing` dla Dynamic Type.
- [x] `EmmaOrb` — pięć rozmiarów, gradient promienisty z tymi samymi punktami koloru,
      pulsowanie wyłączone przy „Ograniczeniu ruchu”.
- [x] `EmmaComponents` — ok. 20 komponentów (karty, nagłówki, awatary, pigułki, filtry,
      pola, listy wyboru, stany puste, błędy, komunikaty, kafelki, statystyki).
- [x] `EmmaTabBar` — pięć zakładek, środkowy chip Emmy, plakietka nieprzeczytanych.

Świadome wykluczenia z podglądu HTML: ramka telefonu, sztuczny pasek systemowy, wyspa,
wskaźnik strony głównej i podpis podglądu — nie są częścią aplikacji.

---

## Etapy 03–05 · Logika domeny demo

**Status: zweryfikowane (wykonane testy)**

- [x] Typy identyfikatorów jako odrębne typy (bez „magicznych” napisów).
- [x] `LocalDate` oparty na numerze dnia (bez zależności od `Calendar.current`),
      strefa kancelarii `Europe/Warsaw`.
- [x] Wiadomości: kierunek, źródło, transport z monotonicznym postępem, cytaty, szkice,
      reguła odczytu niezależna dla każdego użytkownika.
- [x] Zadania, terminy, notatki, historia sprawy, klienci i sprawy z wersjonowaniem.
- [x] `MockRepository` jako jedno repozytorium demo: blokady optymistyczne, klucze
      idempotencji, zakaz duplikowania sprawy, walidacja kolizji prowadzącego,
      zakaz cofania kursora odczytu.
- [x] Licznik nieprzeczytanych liczony **tą samą** regułą co otwarty wątek.

---

## Etap 06 · Voice: logika i mocki

**Status: zweryfikowane (wykonane testy) + adaptery niezweryfikowane**

- [x] `VoiceEvent` z pełną kopertą (identyfikator, sesja, generacja, tura, czas, źródło).
- [x] Reduktor stanu: odrzucanie zdarzeń spóźnionych, obcych sesji i po zakończeniu.
- [x] Jeden `VoiceSessionCoordinator` — jedyny właściciel transportu i jedyny subskrybent.
- [x] Trzy tryby (rozmowa, dyktowanie, odsłuch) na jednym zasobie audio.
- [x] Sześć deterministycznych scenariuszy mocka, w tym przerwanie głosem, odmowa
      uprawnienia, wznowienie i zdarzenie spóźnione.
- [x] Dyktowanie do zamrożonego celu — tekst „wyślij to jutro” **nie** wykonuje akcji.
- [x] Silnik akcji: korekta unieważnia zgodę, argument modelu językowego nie jest zgodą,
      powtórne potwierdzenie nie tworzy drugiego wykonania, niepewny wynik bez ponowienia.
- [x] Spójność danych przykładowych (15 testów): brak wiszących odwołań między klientami,
      sprawami, terminami, zadaniami, notatkami, wątkami i wiadomościami; kursor odczytu
      nie wyprzedza historii; `currentUserID` istnieje wśród użytkowników.
- [x] Adaptery dostawcy (ElevenLabs, mowa systemu, sesja audio) — **niezweryfikowane**,
      brak konta i brak macOS.

---

## Etapy 07–16 · Praca niezależna od kont dostawców

**Status: częściowo zweryfikowane, część blocked_external**

- [x] Dokumentacja kontraktu backendu i adaptera dostawcy
      (`docs/ios/research/elevenlabs-swift-sdk.md`).
- [x] Analiza koegzystencji WhatsApp Business (`docs/ios/research/whatsapp-coexistence.md`)
      wraz z ograniczeniem: wymagany Solution Partner / Tech Provider, Embedded Signup,
      logowanie sesji. Właściciel zachowuje aplikację WhatsApp Business na swoim numerze.
- [x] Lista testów kontraktowych dostawcy do wykonania po uzyskaniu konta
      (`docs/ios/PROVIDER_CONTRACT_TESTS.md`).
- [ ] Testy kontraktowe wykonane na prawdziwym koncie — `blocked_external`.
- [ ] Weryfikacja logowania Embedded Signup — `blocked_external` (wymaga Tech Providera).
- [ ] Kontrakt Qwen potwierdzony na działającym backendzie — `blocked_external`.

---

## Bramki jakości — stan faktyczny

| Bramka | Stan |
| --- | --- |
| Testy logiki (SwiftPM, Linux) | **wykonane** — 142 testy, 0 błędów |
| Kontrola składni wszystkich plików Swift | **wykonana** — 63 pliki, 0 błędów |
| Kontrola odwołań do zależności i tokenów | **wykonana** — 0 odwołań bez deklaracji |
| Kompilacja projektu Xcode | **niewykonana** — brak macOS |
| Testy jednostkowe w Xcode | **niewykonana** — brak macOS |
| Testy interfejsu (XCUITest) | **niewykonana** — brak macOS |
| Uruchomienie na symulatorze | **niewykonana** — brak macOS |
| Test na fizycznym iPhonie | **niewykonana** — brak urządzenia |
| Porównanie zrzutów z referencją | **niewykonane** — brak symulatora; porównanie oparte na kaskadzie CSS i pomiarach, nie na obrazie |

---

## Następny krok

1. Uruchomić `ios/scripts/generate-project.sh` na Macu i zbudować schemat `Emma-Demo`.
2. Wykonać `Cmd+U` i naprawić to, co ujawni kompilator — to pierwszy moment,
   w którym kod SwiftUI zostanie sprawdzony przez typy.
3. Zrobić zrzuty pięciu zakładek i porównać z referencją; odstępstwa dopisać do
   `docs/ios/DESIGN_DEVIATIONS.md` (bez aktualizowania wzorca tylko po to, by ukryć regresję).
4. Po uzyskaniu kont dostawcy wykonać `docs/ios/PROVIDER_CONTRACT_TESTS.md`.
