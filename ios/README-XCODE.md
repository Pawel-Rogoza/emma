# Emma na iPhonie — jak otworzyć i uruchomić projekt

Ten plik opisuje **jedyną** drogę do zbudowania aplikacji: projekt Xcode generowany
z `project.yml`. Nie ma osobnego, ręcznie utrzymywanego `.xcodeproj` w repozytorium —
dzięki temu konfiguracja nie rozjeżdża się między maszynami.

## 1. Czego potrzebujesz

| Element | Wymaganie |
| --- | --- |
| System | macOS z zainstalowanym Xcode (Xcode 16 lub nowszy — projekt deklaruje Swift 6.0) |
| Narzędzie | [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen` |
| Urządzenie | iPhone z iOS 17 lub nowszym (albo symulator iOS 17+) |
| Sieć | tylko przy pierwszym otwarciu projektu — Xcode pobiera dwa pakiety Swift |

Aplikacja **nie wymaga żadnych kont dostawców ani kluczy API**. Tryb Demo działa
w pełni offline: dane pochodzą z repozytorium demo, a głos z deterministycznych mocków.

## 2. Wygenerowanie projektu

```bash
cd ios
./scripts/generate-project.sh
```

Skrypt sprawdza obecność `xcodegen`, pilnuje, żeby nie brakowało `Config/Local.xcconfig`
(jeśli istnieje — nie jest wymagany), i wypisuje wynik. Efektem jest `ios/Emma.xcodeproj`.
Skrypt **odmawia pracy na Linuksie** i mówi wprost, że wymaga macOS — nie udaje, że
wygenerował projekt.

## 3. Konfiguracja bez sekretów

Trzy środowiska odpowiadają trzem schematom:

| Schemat | Konfiguracja | Backend | Głos |
| --- | --- | --- | --- |
| `Emma-Demo` | `Config/Demo.xcconfig` | brak (pusty adres) | mocki deterministyczne |
| `Emma-Staging` | `Config/Staging.xcconfig` | `EMMA_API_BASE_URL` właściciela | dostawca, jeśli skonfigurowany |
| `Emma-Production` | `Config/Production.xcconfig` | adres produkcyjny | dostawca |

W repozytorium nie ma żadnych sekretów. Jeśli chcesz ustawić własne wartości lokalnie:

```bash
cd ios/Config
cp Local.xcconfig.example Local.xcconfig
# uzupełnij EMMA_BUNDLE_ID, EMMA_DEVELOPMENT_TEAM i ewentualnie EMMA_API_BASE_URL
```

`Local.xcconfig` jest w `.gitignore` i nigdy nie trafia do repozytorium.
**Klucze dostawców (ElevenLabs, WhatsApp) nie należą do aplikacji** — aplikacja
otrzymuje wyłącznie krótkotrwały token rozmowy wydany przez backend.

## 4. Uruchomienie

1. Otwórz `ios/Emma.xcodeproj` w Xcode.
2. Wybierz schemat **`Emma-Demo`** (schemat współdzielony, gotowy w repozytorium).
3. Wybierz symulator iPhone lub podłączone urządzenie.
4. `Cmd+R`.

Schemat `Emma-Demo` przekazuje przy starcie argumenty `--demo` i `--fixture today-default`,
więc aplikacja od razu pokazuje dzień referencyjny: **piątek 11 września 2026**.

## 5. Co zobaczysz

Pięć zakładek z zaakceptowanego prototypu: **Dzisiaj · Klienci · Emma · Rozmowy · Kalendarz**.
Dane pochodzą z tego samego zestawu, co w referencji (Olena Kovalenko, Andrii Melnyk,
Maria Sokołowa, Dmytro Bondarenko; sprawy `case-041` i `case-038`).

Głos w trybie Demo:
- rozmowa z Emmą działa na scenariuszach mocka (propozycja → zatwierdzenie → wykonanie),
- dyktowanie wpisuje tekst do pola i **nigdy** nie wysyła wiadomości samo,
- odsłuch briefingu nie otwiera mikrofonu.

Przy pierwszym użyciu mikrofonu system zapyta o zgodę. Odmowa nie psuje aplikacji:
tekst i przyciski w interfejsie działają dalej.

## 6. Uruchomienie testów

W Xcode: `Cmd+U` na schemacie `Emma-Demo` (targety `EmmaTests` i `EmmaUITests`).

Testy logiki (bez Xcode, także na Linuksie) uruchamia skrypt:

```bash
cd ios
./scripts/verify-linux-logic.sh
```

Ten skrypt kompiluje i wykonuje logikę domenową oraz sprawdza składnię wszystkich
plików Swift, w tym widoków SwiftUI. **Nie kompiluje SwiftUI i nie uruchamia
symulatora** — to wymaga macOS i Xcode.

## 7. Pakiety zależności

`project.yml` przypina dwie wersje dokładnie:

- `elevenlabs-swift-sdk` `exactVersion: 3.3.1` — oficjalne SDK rozmowy głosowej,
- `client-sdk-swift` (LiveKit) `exactVersion: 2.16.0` — świadome przypięcie zależności
  przechodniej, bo kolejne wydania LiveKit wymagają coraz nowszego toolchainu.

Kod adaptera dostawcy jest objęty `#if canImport(ElevenLabs)`, więc projekt zbuduje się
także bez pobranych pakietów — tylko bez ścieżki dostawcy głosu.

## 8. Czego ten projekt jeszcze nie robi

Uczciwie, bez upiększania:

- **Nie ma zweryfikowanej integracji z dostawcą głosu** — brak konta u dostawcy
  (`blocked_external`). Adapter jest napisany, ale nieuruchomiony na urządzeniu.
- **WhatsApp nie jest połączony.** Ekran rozmów pokazuje to wprost w stopce listy
  („Wiadomości przykładowe · WhatsApp niepołączony”), a statusy wiadomości są przykładowe.
- **Nie ma backendu** — repozytorium demo udaje warstwę danych i działa w pamięci.
- Kompilacja SwiftUI, testy na symulatorze i test na iPhonie **nie zostały wykonane**
  w środowisku, w którym powstawał kod (brak macOS i Xcode). Szczegóły i tabela bramek:
  `docs/ios/BUILD_AND_DEVICE_STATUS.md`.

---

## 9. Podgląd bez MacBooka (na Linuksie)

Jeśli nie masz przy sobie Maca, a chcesz zobaczyć, co aplikacja pokaże, jest podgląd
generowany z kodu — bez udawania, że jest to build:

```bash
cd ios
./scripts/start-preview.sh          # → http://127.0.0.1:8098/
```

Podgląd pokazuje **prawdziwe** dane demo (czytane przez `MockRepository`), prawdziwe
napisy (`DateTextFormatter`, `EmmaPlural`, `EmmaBriefing`), prawdziwe czcionki z repo,
wszystkie stany z en-ów rdzenia i tokeny projektowe odczytane z `EmmaTheme`,
`EmmaTypography`, `EmmaMetrics` i `EmmaOrb`. **Układ ekranów jest rekonstrukcją
referencji w HTML**, więc nie jest to render SwiftUI ani zrzut ekranu iPhone'a —
nagłówek strony mówi to wprost, żeby nikt nie pomylił podglądu z dowodem działania.

Render podglądu jest mierzony w prawdziwej przeglądarce:

```bash
python3 scripts/verify-preview-render.py
```

Szczegóły i granice tego narzędzia: `docs/ios/BUILD_AND_DEVICE_STATUS.md`
(sekcja „Podgląd aplikacji bez MacBooka”) oraz `docs/ios/RUNBOOKS.md` (R-9, R-10).
