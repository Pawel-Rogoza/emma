# Redesign na iOS 26 — 10.10.2026 (0.22.0)

Źródło: review designu z 10.10.2026 (artefakt „Emma iOS — kierunek designu”).
Decyzje właściciela: iOS 26 jako minimum, koniec zamrożonego kontraktu
z prototypem HTML, **bez trybu ciemnego**, Emma zostaje **środkową zakładką**,
ale ma się wyraźniej wyróżniać.

## Co się zmieniło

| Obszar | Przed | Po |
|---|---|---|
| Cel wdrożenia | iOS 17 | **iOS 26** (`project.yml`) |
| Kontrakt designu | kolory i wymiary z kaskady CSS prototypu; bramka `design-token-diff.py` odrzucała każdy kolor spoza referencji | koniec kontraktu; bramka `check-color-tokens.py`: literały kolorów tylko w `EmmaTheme.swift` (i w renderze postaci Emmy), tokeny semantyczne muszą istnieć |
| Typografia | DM Sans (bez cyrylicy) + SF Pro dla cyrylicy — dwie czcionki w jednym wierszu | **SF Pro** dla całego tekstu, Manrope tylko w dużych tytułach; DM Sans usunięta z pakietu; podpis 13 pt zamiast 12 pt |
| Kolor | ponad 130 tokenów nazwanych po selektorach CSS; „niebezpieczeństwo” ceglaste, amber ≈ urgent | tokeny semantyczne `accent`, `emma`, `critical`, `warning`, `positive` (+ `…Soft`); stare nazwy są aliasami; czerwony tylko dla terminów |
| Pasek zakładek | płaski, nieprzezroczysty, Emma w ciemnym „chipie” | pływająca kapsuła **Liquid Glass** nad treścią; **Emma w środku jako uniesiony, okrągły przycisk z portretem** w obwódce koloru Emmy; pasek znika w otwartej rozmowie i przy klawiaturze |
| Nawigacja | własny `DetailHeader`, ukryty systemowy powrót, hak UIKit przywracający gest | systemowy pasek nawigacji (szkło), tytuł + `navigationSubtitle`, przyciski w `.toolbar`; `DetailHeader` i `EmmaSwipeBack` usunięte |
| „Dzisiaj” | do 11 sekcji o tej samej wadze (puls, po terminie, leady, najbliższy termin, napisali, dalej dziś, zadania, 7 dni…) | **Następne** (bohater, godzina 32 pt) → **Wymaga Ciebie** (jedna kolejka: po terminie, leady, napisali, zadania; ikona w kolorze stanu) → **Później dziś** → Zadania |
| Wątek | stały nagłówek z powrotem, belka kontekstu, dok z obramowaniem | rozmówca w pasku nawigacji, kontekst sprawy jako pigułka w szkle, pole/mikrofon/gotowe odpowiedzi w szkle, „Odpowiedz z Emmą” w kolorze Emmy |
| Mini-panel głosu | belka nad paskiem | pigułka w szkle nad pływającym paskiem |
| Arkusze | — | szczegół zadania od połowy ekranu; narożniki systemowe |
| Poza aplikacją | szybkie akcje z ikony, Spotlight | + **App Intents**: „Rozmawiaj z Emmą”, „Nowy termin”, „Nowe zadanie” (Siri, Spotlight, Skróty, przycisk czynności, Centrum sterowania przez Skróty) |

## Czego nie zrobiono i dlaczego

- **Tryb ciemny** — decyzja właściciela (nikt z kancelarii go nie używa).
  Tokeny semantyczne ułatwią go później: wystarczą warianty ciemne.
- **Widżety i Live Activity „Rozprawa za 45 min”** — wymagają rozszerzenia
  WidgetKit z osobnym bundle ID, App Group i **drugim profilem
  dystrybucyjnym** w sekretach CI (`IOS_DISTRIBUTION_PROFILE_BASE64` obejmuje
  dziś tylko aplikację). Do zrobienia po decyzji właściciela:
  zarejestrować `pl.kancelaria.emma.widgets` i App Group w Apple Developer,
  dodać profil do sekretów.
- **Akcje w powiadomieniach** — sensowne dopiero z pushem (roadmapa, etap 1);
  lokalne przypomnienia otwierają już właściwy ekran po Face ID.
- **Emma jako akcesorium nad paskiem** (`tabViewBottomAccessory`) — odrzucone:
  Emma zostaje zakładką, wyeksponowaną w pasku.
- **Podgląd plików z WhatsApp i „Dołącz do akt”** — zależy od decyzji o relayu
  mediów Dualhooka (roadmapa, etap 1, punkt 4).

## Do sprawdzenia na telefonie

- Czytelność treści pod pływającym paskiem (końce list nie mogą chować się pod szkłem).
- Środkowy przycisk Emmy przy dużym tekście i na iPhonie SE/mini.
- Rozmowa: pole odpowiedzi w szkle na tle tapety czatu, powrót gestem krawędzi.
- Siri: „Rozmawiaj z Emmą” po instalacji z TestFlight (skróty pojawiają się
  po pierwszym uruchomieniu aplikacji).
