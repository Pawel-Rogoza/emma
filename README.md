# Emma iOS: pakiet dla modelu wdrażającego

Zacznij od `Emma-iOS-Implementation-Plan.md`. Sekcja 16 zawiera gotowe polecenie startowe.

## Zawartość

- `Emma-iOS-Implementation-Plan.md`: szczegółowy plan natywnej aplikacji, etapy 00–16, design, hooki voice, API, WhatsApp i Xcode.
- `reference/prototype/`: dokładne źródło zatwierdzonego prototypu po poprawkach rozmów i kalendarza, commit `b97685b5e2c2cd3d6f78b172b9c0b5cee114270b`. To wzorzec wyglądu i procesów demo, nie kod backendu ani docelowej aplikacji iOS.
- `reference/previous-plan/Emma-Legacy-Voice-Plan.md`: wcześniejszy plan przesłany przez właściciela, bez zmian. W kwestiach nowego klienta pierwszeństwo ma nowy plan.
- `reference/manifest.json`: pochodzenie i sumy kontrolne referencji.

Nie implementuj nowego designu na podstawie samego opisu. Przeczytaj źródło prototypu i odtwórz jego aktualne stany. Nie kopiuj starego desktopowego układu pozostawionego w nieaktywnych regułach CSS.

Pakiet nie zawiera jeszcze projektu Swift, skompilowanej aplikacji ani screenshotów z symulatora. Ich wykonanie jest zadaniem modelu w opisanych etapach.

## Obejrzenie referencji

Opublikowany prototyp: https://emma-kancelaria-ios.pawrogozas.chatgpt.site

Kopia `reference/prototype/index.html` służy również jako lokalna referencja. W zwykłym środowisku deweloperskim można udostępnić ten folder prostym serwerem statycznym; w środowisku zarządzanym należy korzystać z jego zatwierdzonej ścieżki podglądu. Fonty CSS odwołują się do Google Fonts, więc do wiernego wyświetlenia referencji wymagane jest ich załadowanie. Docelowa aplikacja SwiftUI ma używać fontów lokalnych z licencjami.

Dane w prototypie są fikcyjne; AI i WhatsApp są symulowane. Nie przenoś timerów i fałszywych statusów do trybu live.
