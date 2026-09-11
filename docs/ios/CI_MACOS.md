# Kompilacja i podgląd aplikacji bez MacBooka (GitHub Actions, macOS)

Ten dokument odpowiada na jedno pytanie: **jak zobaczyć i sprawdzić aplikację Emma
iOS, mając pod ręką tylko Linuksa.**

Krótka odpowiedź: SwiftUI nie działa na Linuksie, więc jedyną drogą do prawdziwej
kompilacji i prawdziwego podglądu jest wynajęty (albo darmowy w ramach CI) Mac
w chmurze. Ten dokument opisuje gotową do użycia drogę.

---

## Co już działa bez Maca

| Sposób | Co pokazuje |
| --- | --- |
| Prototyp w przeglądarce: `reference/prototype/index.html` | **zatwierdzony wzorzec designu**, interaktywny: pięć zakładek, arkusze, rozmowa z Emmą |
| `bash ios/scripts/verify-linux-logic.sh` | logika domeny i głosu (178 testów), składnia, odwołania, kontrakt API, martwe API |
| `bash ios/scripts/start-prototype-preview.sh` | lokalny serwer podglądu prototypu pod `http://127.0.0.1:8099/` |

Czego **nie** daje żadne z tych narzędzi: podglądu prawdziwego interfejsu SwiftUI.
Prototyp to wzorzec, a nie aplikacja — wygląda podobnie, ale to inny kod.

## Co daje workflow `ios-macos.yml`

Plik `.github/workflows/ios-macos.yml` uruchamia na runnerze `macos-15`:

1. wybór Xcode i instalację XcodeGen,
2. wygenerowanie `Emma.xcodeproj` z `project.yml`,
3. pobranie przypiętych pakietów (ElevenLabs, LiveKit) — pierwsze realne sprawdzenie,
   że wersje się rozwiązują,
4. **`xcodebuild build`** — pierwsza w historii projektu kontrola typów SwiftUI,
5. testy jednostkowe w Xcode,
6. **zrzuty ekranu jedenastu ekranów** z symulatora (`ScreenshotCaptureUITests`),
7. publikację artefaktu `emma-ios-artifacts` ze zrzutami i pakietami wyników,
8. podsumowanie przebiegu w `Step Summary` (widoczne w interfejsie GitHuba).

Zrzuty obejmują: Dzisiaj, Klienci, karta klienta, sprawa, zadania, kalendarz, rozmowy,
wątek, Emma, rozmowa z Emmą na mocku, profil.

## Jak uruchomić

Repozytorium nie ma jeszcze zdalnego adresu. Kroki:

```bash
# 1. Utwórz puste repozytorium na GitHubie (może być prywatne) i podłącz je:
cd /home/pawel/Projekty/Emma
git remote add origin git@github.com:<konto>/<repo>.git
git push -u origin main

# 2. W GitHubie: zakładka „Actions” → „Emma · iOS” → „Run workflow”.
#    Workflow uruchamia się też sam przy zmianach w katalogu ios/.
```

Po przebiegu: **Actions → wybrany przebieg → Artifacts → `emma-ios-artifacts`**.
W środku są pliki PNG oraz `raport.txt` z listą ekranów.

### Koszt i limity

| Plan | macOS | Uwaga |
| --- | --- | --- |
| Repozytorium publiczne | darmowe | bez limitu minut |
| Repozytorium prywatne, plan Free | 2000 minut/mies. **liczone ×10 dla macOS** | efektywnie ~200 minut macOS na miesiąc |
| Repozytorium prywatne, plany płatne | więcej minut, mnożnik ×10 nadal obowiązuje | — |

Jeden przebieg to zwykle 10–20 minut (pobranie pakietów dominuje przy pierwszym razie).
Limit `timeout-minutes: 60` chroni przed zawieszonym symulatorem.

## Jak czytać wynik

| Krok | Znaczenie |
| --- | --- |
| „Kompilacja” | **bramka**. Czerwony krok = kod się nie kompiluje; to pierwsze miejsce, gdzie wychodzą błędy typów w widokach |
| „Testy logiki z pakietu SwiftPM” | **bramka**. Te same testy, co lokalnie na Linuksie |
| „Testy jednostkowe w Xcode” | **bramka**. Testy uruchomione na symulatorze |
| „Zrzuty ekranu…” | **nieblokujący** (`continue-on-error`). Zrzuty powstają nawet wtedy, gdy ekran się nie wczytał — wtedy w `raport.txt` jest wpis „NIE UDAŁO SIĘ” z powodem |
| „Zrzut z symulatora (droga zapasowa)” | zawsze wykonuje się; pokazuje ekran, na którym zatrzymały się testy |

Praktyczna kolejność pracy po pierwszym przebiegu:

1. Napraw to, co zgłosi kompilacja. Dopisz wynik do `docs/ios/IMPLEMENTATION_STATUS.md`.
2. Pobierz artefakt i obejrzyj zrzuty.
3. Porównaj z prototypem i każde odstępstwo zapisz w `docs/ios/DESIGN_DEVIATIONS.md`
   — **bez** zmieniania wzorca tylko po to, żeby różnica zniknęła.

## Uczciwe zastrzeżenia

- **Ten workflow nie został uruchomiony ani razu.** Powstał w środowisku bez macOS
  i bez dostępu do GitHuba. Pierwszy przebieg może wymagać poprawek — najczęściej
  w nazwie symulatora albo w składni `xcresulttool` (zmieniała się między wersjami
  Xcode, dlatego w kroku eksportu są dwie próby i droga zapasowa).
- **Zrzuty nie są testem funkcjonalnym.** Pokazują, że ekran się wczytał i jak wygląda.
  Nie dowodzą, że zachowanie jest poprawne — to robią testy logiki i testy XCUITest.
- **CI nie zastępuje urządzenia.** Mikrofon, Bluetooth, trasa audio, przerwanie
  telefonem i zachowanie po zablokowaniu ekranu wymagają fizycznego iPhone'a
  (`docs/ios/PROVIDER_CONTRACT_TESTS.md`, etap 13 planu).
- **Bez kont dostawców** CI sprawdzi wszystko poza prawdziwym głosem i WhatsApp —
  aplikacja w trybie Demo nie potrzebuje żadnych kluczy i taki jest zamysł.
- Kod adaptera dostawcy jest objęty `#if canImport(ElevenLabs)`. Jeśli pobranie
  pakietów nie powiedzie się, kompilacja przejdzie bez ścieżki dostawcy — wtedy
  w logu kroku „Pobranie pakietów” będzie widać, co się nie udało.

## Drogi alternatywne

| Opcja | Kiedy ma sens |
| --- | --- |
| [Codemagic](https://codemagic.io) | darmowy tier na M1, wygodniejszy interfejs niż Actions, gdy GitHub jest niewygodny |
| Xcode Cloud | wymaga konta Apple Developer; dobre przy dalszej dystrybucji (TestFlight) |
| Wynajem Maca na godziny (MacinCloud, MacStadium, Scaleway Mac mini) | gdy chcesz sam klikać w Xcode i symulatorze, a nie tylko patrzeć na artefakty |
| Pożyczony Mac na jedno popołudnie | najszybsza droga do pierwszego `Cmd+R`; wystarczy `./scripts/generate-project.sh` |

Jeśli któraś z tych dróg zostanie użyta, wynik (co się udało, co nie) należy dopisać
do `docs/ios/BUILD_AND_DEVICE_STATUS.md` — ten raport ma pokazywać fakty, nie zamiary.
