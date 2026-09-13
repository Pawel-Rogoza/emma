# Emma iOS: pakiet dla modelu wdrażającego

Zacznij od `Emma-iOS-Implementation-Plan.md`. Sekcja 16 zawiera gotowe polecenie startowe.

## Zawartość

- `Emma-iOS-Implementation-Plan.md`: szczegółowy plan natywnej aplikacji, etapy 00–16, design, hooki voice, API, WhatsApp i Xcode.
- `reference/prototype/`: dokładne źródło zatwierdzonego prototypu po poprawkach rozmów i kalendarza, commit `b97685b5e2c2cd3d6f78b172b9c0b5cee114270b`. To wzorzec wyglądu i procesów demo, nie kod backendu ani docelowej aplikacji iOS.
- `reference/previous-plan/Emma-Legacy-Voice-Plan.md`: wcześniejszy plan przesłany przez właściciela, bez zmian. W kwestiach nowego klienta pierwszeństwo ma nowy plan.
- `reference/manifest.json`: pochodzenie i sumy kontrolne referencji.

Nie implementuj nowego designu na podstawie samego opisu. Przeczytaj źródło prototypu i odtwórz jego aktualne stany. Nie kopiuj starego desktopowego układu pozostawionego w nieaktywnych regułach CSS.

## Stan implementacji

Aplikacja natywna jest w `ios/`: Swift 6, SwiftUI, iOS 17, projekt generowany z `ios/project.yml`
(XcodeGen — w repozytorium nie ma ręcznie utrzymywanego `.xcodeproj`, żeby konfiguracja nie
rozjeżdżała się między maszynami). Instrukcja uruchomienia: `ios/README-XCODE.md`.

**Co jest już zrobione i czym to udowodniono**

| Sprawdzone na Linuksie (bez Xcode) | Dowód |
| --- | --- |
| Logika domeny i głosu | 178 testów, 0 błędów (`swift test`) |
| Składnia wszystkich plików Swift, także SwiftUI | 65 plików, 0 błędów (`swiftc -parse`) |
| Odwołania do tokenów i typów systemowych | 1079 odwołań, brak bez deklaracji |
| Kolory wobec reguł referencji | 100 tokenów, 0 wymyślonych |
| Martwe publiczne API rdzenia | 0 z 520 składowych |
| Wierność wyglądu | pomiar renderu podglądu w przeglądarce (czcionki, szerokości, ucinanie, nakładanie) |

Wszystko powyżej odtwarza jedno polecenie: `bash ios/scripts/verify-linux-logic.sh` (9 kroków).

**Czego jeszcze nie ma**

Skompilowanej aplikacji, zrzutów z symulatora i testu na iPhonie — to wymaga macOS i Xcode.
Kontrola typów SwiftUI **nie została wykonana**; pierwsze uruchomienie na Macu może ujawnić
błędy typów, których parser składni nie widzi. Ta lista jest prowadzona jawnie w
`docs/ios/BUILD_AND_DEVICE_STATUS.md`, razem z tym, co pozostaje `blocked_external`
(backend, dostawca głosu, WhatsApp).

**Podgląd bez MacBooka**

`ios/scripts/start-preview.sh` buduje i wystawia podgląd ekranów na Linuksie: prawdziwe dane
demo, napisy, stany i tokeny z kodu, odtworzone w stylach referencji. To **rekonstrukcja**, nie
render SwiftUI — nie dowodzi układu, zawijania tekstu, animacji, gestów ani VoiceOver.
Audyt z opisem metod i znalezisk: `docs/ios/AUDIT.md`.

## Obejrzenie referencji

Opublikowany prototyp: https://emma-kancelaria-ios.pawrogozas.chatgpt.site

Kopia `reference/prototype/index.html` służy również jako lokalna referencja. W zwykłym środowisku deweloperskim można udostępnić ten folder prostym serwerem statycznym; w środowisku zarządzanym należy korzystać z jego zatwierdzonej ścieżki podglądu. Fonty CSS odwołują się do Google Fonts, więc do wiernego wyświetlenia referencji wymagane jest ich załadowanie. Docelowa aplikacja SwiftUI ma używać fontów lokalnych z licencjami.

Dane w prototypie są fikcyjne; AI i WhatsApp są symulowane. Nie przenoś timerów i fałszywych statusów do trybu live.
