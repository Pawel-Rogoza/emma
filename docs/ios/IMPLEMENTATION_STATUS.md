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

## Etapy 07–16 · Stan każdego wymagania

Zasada z bramki M3: **każde brakujące wymaganie ma jawny status i przyczynę.**
Poniżej pełna lista, bez pomijania pozycji niewygodnych.

### Etap 07 · API mobilne, autoryzacja i cache

| Wymaganie | Stan | Uwaga |
| --- | --- | --- |
| Kontrakt OpenAPI | **dostarczone** (propozycja) | `docs/ios/api/emma-mobile-api.yaml` — 24 ścieżki, 29 operacji, 33 schematy; struktura sprawdzana skryptem |
| Przykładowe payloady | **dostarczone** | przykłady w polach `example` i w schematach żądań |
| Lista testów logowania/refresh/revoke, paginacji, 401/403, konfliktów, offline | **dostarczone** | `docs/ios/api/CONTRACT_TEST_CHECKLIST.md` (A–G, 40 sprawdzeń) |
| Wdrożenie kontraktów w backendzie | **blocked_external** | repozytorium backendu niedostępne z tego środowiska |
| Testy logowania/refresh/revoke wykonane | **niezweryfikowane** | brak serwera |
| Repozytoria live i cache lokalny | **blocked_external** | aplikacja ma jedno miejsce podmiany (`MockRepository` → repozytorium zdalne) |
| Zapisy nie blokują wątku UI | **zaprojektowane** | repozytorium to `actor`; potwierdzenie wymaga urządzenia |

### Etap 08 · realtime i push

| Wymaganie | Stan | Uwaga |
| --- | --- | --- |
| Kontrakt zmian (`/sync/changes`) i rejestracji push | **dostarczone** (propozycja) | w tym samym pliku kontraktu |
| Znacznik kursora i brak luki | **zaprojektowane** | aplikacja odrzuca zdarzenia starsze niż kursor |
| APNs, routing po tap | **niezaimplementowane** | brak podpisania i provisioningu; nie deklarowano inaczej |
| Testy DEV/PROD APNs | **blocked_external** | wymaga konta deweloperskiego Apple |

### Etap 09 · prawdziwy voice na danych syntetycznych

| Wymaganie | Stan | Uwaga |
| --- | --- | --- |
| Adapter oficjalnego SDK | **zaimplementowany**, nieuruchomiony | `#if canImport(ElevenLabs)`, wersje przypięte w `project.yml` |
| Token rozmowy z backendu | **zaimplementowany** (klient) | brak serwera → `blocked_external` |
| Cykl życia audio natywnego | **zaimplementowany**, nieuruchomiony | jeden kontroler sesji dla rozmowy, dyktowania i odsłuchu |
| Tabela capabilities | **zapisana z dokumentacji** | `docs/ios/research/elevenlabs-swift-sdk.md`; pomiar na koncie: `blocked_external` |
| Test na fizycznym iPhonie, Bluetooth | **niezweryfikowane** | brak macOS i urządzenia |
| Spike na koncie dostawcy | **blocked_external** | brak konta |

### Etap 10 · wspólne narzędzia, akcje i voice z CRM

| Wymaganie | Stan | Uwaga |
| --- | --- | --- |
| Jeden silnik akcji dla UI i głosu | **zaimplementowany** | `ActionEngine` + `VoiceSessionCoordinator` |
| Zgoda tylko z przycisku albo uwierzytelnionej tury | **zaimplementowane i przetestowane** | `languageModelArgument` odrzucany; testy w `VoiceAndActionTests` |
| Idempotencja potwierdzenia | **zaimplementowana i przetestowana** | powtórzenie zwraca to samo wykonanie |
| Korekta unieważnia zgodę | **zaimplementowana i przetestowana** | zmiana hashu i identyfikatora prezentacji |
| Niepewny wynik bez ponowienia | **zaimplementowane i przetestowane** | `ExecutionState.unknown` |
| Trwały outbox i claim przez dwa procesy | **blocked_external** | należy do backendu; po stronie klienta jest tylko model stanu |
| Wykonanie narzędzi u dostawcy po stronie backendu | **blocked_external** | brak backendu i konta |

### Etap 11 · WhatsApp Business, inbound i koegzystencja

| Wymaganie | Stan | Uwaga |
| --- | --- | --- |
| Analiza koegzystencji i wymogów | **dostarczona** | `docs/ios/research/whatsapp-coexistence.md` |
| Instrukcja podłączenia numeru | **dostarczona** | `docs/ios/WHATSAPP_ONBOARDING.md`, z warunkami zatrzymania |
| Webhook, dedup, statusy w backendzie | **blocked_external** | wymaga Tech Providera i backendu |
| Aplikacja nie udaje połączenia | **zaimplementowane** | stopka listy rozmów mówi wprost o braku połączenia |
| Prawdziwa wiadomość widoczna w iOS | **blocked_external** | brak konta |
| Niezmienność numeru właściciela | **zapisane jako warunek** | kroki wymagające zmiany numeru są zabronione i zatrzymują proces |

### Etap 12 · WhatsApp outbound z composera i voice

| Wymaganie | Stan | Uwaga |
| --- | --- | --- |
| ścieżka prepare → revise → present → confirm → outbox | **zaimplementowana w logice** | UI i mock głosu; wykonanie kończy się na outboxie |
| Rzeczywiste receipts | **blocked_external** | brak dostawcy |
| Stan unknown i recovery | **zaimplementowane** | brak automatycznego ponowienia |
| Testy timeoutu, restartu workera, okna 24 h | **blocked_external** | należą do backendu |

### Etap 13 · niezawodność i odbiór M2b

| Wymaganie | Stan | Uwaga |
| --- | --- | --- |
| Macierz audio/sieci na urządzeniu | **niezweryfikowane** | brak urządzenia |
| Pomiar latencji i kosztów | **niezweryfikowane** | brak konta i urządzenia |
| Brak nagrywania po końcu sesji | **zaprojektowane** | zwolnienie zasobu audio po zakończeniu; potwierdzenie wymaga urządzenia |
| Voice po zablokowaniu ekranu | **jawnie nieobsługiwane** | nie deklarowano wsparcia tła; flaga Background Modes nie jest dowodem |

### Etap 14 · dokumenty, media i długie joby

| Wymaganie | Stan | Uwaga |
| --- | --- | --- |
| Całość zakresu | **niezaimplementowane** | świadomie poza M1; wymaga backendu, workera i storage |

### Etap 15 · analiza prawna i projekty pism

| Wymaganie | Stan | Uwaga |
| --- | --- | --- |
| Całość zakresu | **niezaimplementowane** | zależne od etapu 14 i konta modelu; brak potwierdzonego kontraktu Qwen |

### Etap 16 · przekazanie i pilot

| Wymaganie | Stan | Uwaga |
| --- | --- | --- |
| Audyt designu bez regresji | **częściowo** | brak porównania zrzutów (brak symulatora) |
| Instrukcja Xcode i konfiguracja bez sekretów | **dostarczone** | `ios/README-XCODE.md` |
| Runbooki | **dostarczone** | `docs/ios/RUNBOOKS.md` (osiem sytuacji wymagających decyzji człowieka), `WHATSAPP_ONBOARDING.md`, `PROVIDER_CONTRACT_TESTS.md`, `api/CONTRACT_TEST_CHECKLIST.md`; runbook rollbacku backendu należy do backendu — `blocked_external` |
| Wyniki kompilacji i testów | **dostarczone dla tego, co wykonalne** | 142 testy logiki, 63 pliki sprawdzone składniowo; kompilacja Xcode: nieuruchomiona |
| Test migracji, backup/restore, rollback bez ponownych wysyłek | **blocked_external** | należy do backendu |
| Tag/SHA wydania | **dostarczone** | commity w repozytorium; tag wydania po pierwszej kompilacji na Macu |

### Podsumowanie luk

- **Dostarczone i sprawdzone w tym środowisku:** logika domeny, głos (mocki), silnik akcji,
  design system, wszystkie ekrany M1, kontrakt API jako propozycja, instrukcje i raporty.
- **Zaimplementowane, nieuruchomione:** adaptery dostawcy i mowy systemu.
- **blocked_external:** backend, konta dostawców, WhatsApp, Qwen, urządzenie i symulator.
- **Jawnie niezaimplementowane:** etapy 14 i 15 oraz push (etap 08) — bez deklarowania inaczej.

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
| Podgląd wzorca designu na Linuksie | **dostępny** — `reference/prototype/index.html`, także przez `ios/scripts/start-prototype-preview.sh` |
| Workflow CI dla macOS (build, testy, zrzuty ekranu) | **przygotowany, nieuruchomiony** — brak zdalnego repozytorium i macOS; instrukcja w `docs/ios/CI_MACOS.md` |

---

## Następny krok

1. Uruchomić `ios/scripts/generate-project.sh` na Macu i zbudować schemat `Emma-Demo`.
2. Wykonać `Cmd+U` i naprawić to, co ujawni kompilator — to pierwszy moment,
   w którym kod SwiftUI zostanie sprawdzony przez typy.
3. Zrobić zrzuty pięciu zakładek i porównać z referencją; odstępstwa dopisać do
   `docs/ios/DESIGN_DEVIATIONS.md` (bez aktualizowania wzorca tylko po to, by ukryć regresję).
4. Po uzyskaniu kont dostawcy wykonać `docs/ios/PROVIDER_CONTRACT_TESTS.md`.
