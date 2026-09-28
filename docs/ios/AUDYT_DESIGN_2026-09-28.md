# Audyt designu i użyteczności — 28.09.2026

**Perspektywa:** adwokat prawa karnego. Chce, żeby rzeczy były „zrobione”: jedno
dotknięcie, zero szukania, żadnych opcji dla samych opcji. Premium znaczy tu
*pewność i szybkość*, a nie ozdobniki. Ruch jest po to, żeby pokazać, co się
zmieniło, i żeby czynność „kliknęła”.

**Zakres:** wszystkie ekrany (`ios/Emma/Features`, `DesignSystem`, `App`).
**Ograniczenie:** kod nieskompilowany lokalnie (brak Swifta na Linuksie, CI
wyłączone do 1.10). Zmiany wymagają przejścia w Xcode przed TestFlight.

---

## 1. Najważniejsze wnioski

1. **Przegapiony termin procesowy był niewidoczny.** Niezakończony „termin
   w sprawie” sprzed kilku dni nie pojawiał się nigdzie jako alarm, a sprawa
   wyglądała na spokojną („W toku”). Dla karnisty to najgorsza możliwa wpadka.
   → **Naprawione** (0.4.1 + 0.5.0): czerwona karta „Po terminie” na
   „Dzisiaj”, plakietka „minął 2 dni temu” na liście i w sprawie, przycisk
   „Załatwione” w szczegółach terminu.
2. **Rozprawa bez wpisanego klienta „znikała”.** Termin dodany do sprawy
   z kalendarza sądu (bez klienta) nie liczył się dla klienta w kartotece
   i **nie pokazywał się na ekranie sprawy** (zapytanie szło po kliencie).
   → **Naprawione.**
3. **Karta klienta pokazywała jedną sprawę.** Klient z dwoma postępowaniami
   (np. karne + wykonawcze) miał na karcie tylko jedno. → **Naprawione:**
   lista wszystkich spraw, aktywne najpierw, zamknięte wyszarzone.
4. **Aplikacja się nie ruszała.** Filtry, zakładki i odhaczanie działały
   skokiem, a kółko zadania zmieniało się dopiero po odpowiedzi serwera
   (~0,5 s) — odhaczenie „nie trafiało”. → **Naprawione** (niżej).
5. **Kontakt z klientem wymagał dwóch–trzech kroków.** → **Naprawione:**
   przesunięcie w kartotece (Zadzwoń / WhatsApp / Termin), przyciski telefonu
   i WhatsApp przy kliencie na ekranie sprawy, wyszukiwanie po numerze.

---

## 2. Wdrożone w 0.5.0

### Ruch i reakcja („premium”, „fun to use”)

| Gdzie | Co | Dlaczego |
|---|---|---|
| `EmmaMotion` | trzy krzywe na całą aplikację: `snappy`, `bouncy`, `smooth` (≤ 0,35 s) | spójny ruch, nigdy nie spowalnia pracy |
| `SegmentedFilter` | biała pigułka przesuwa się do wybranego segmentu, wibracja wyboru | widać, skąd i dokąd zmienił się widok |
| `ListFilterChips` | zaznaczenie przesuwa się między chipami, liczniki „przewijają” cyfry | liczby żyją, gdy lista się zmienia |
| Pasek zakładek | nowo wybrana ikona „odbija”, treść zakładek przenika się | potwierdzenie przejścia bez spowalniania |
| `TaskRow` | kółko wypełnia się **od razu** (optymistycznie) sprężyście, tytuł przygasa; bezpiecznik 4 s przy nieudanym zapisie | odhaczenie ma być natychmiastowe i satysfakcjonujące |
| `LoadingState` | szkielet trzech kart z połyskiem zamiast kręciołka | ekran od razu ma swój kształt; szanuje „Ogranicz ruch” |
| Komunikaty (toast) | ikona ✓ / ! z odbiciem, sprężyste wejście | „Zapisano” i „Nie udało się” były nie do odróżnienia |
| „Po terminie” | ikona ostrzeżenia delikatnie pulsuje | jedyne miejsce, które ma krzyczeć |

### Funkcje „bez pierdolenia się”

- **„Dzisiaj” → karta „Po terminie · N”** nad wszystkim: niezakończone terminy
  w sprawach z 30 dni. Dotknięcie — termin, przytrzymanie — sprawa / klient.
- **Szczegóły terminu → „Załatwione”** (dla terminów dziś i minionych): jedno
  dotknięcie zamyka termin i zdejmuje przypomnienie.
- **Ekran sprawy:** plakietka „Termin jutro / Termin minął 2 dni temu” obok
  statusu; przy kliencie przyciski telefonu i WhatsApp; plakietka języka.
- **Karta klienta:** wszystkie sprawy klienta.
- **Klienci** (0.4.1): pilność z przegapionymi terminami, przesunięcia,
  chip „Bez ruchu”, szukanie po telefonie, zgłoszenia w wynikach kartoteki.

---

## 3. Backlog — rekomendacje w kolejności opłacalności

**P1 — duża wartość, mały koszt**

1. ~~„Załatwione” na wierszach terminów~~ — **zrobione w 0.5.2** (menu wiersza
   na „Dzisiaj” i przytrzymanie na karcie „Po terminie”); Kalendarz jeszcze nie.
2. **Zamknięcie sprawy z listy** (przesunięcie na karcie sprawy „Zamknij”
   z potwierdzeniem) — dziś tylko przez ⋯ na ekranie sprawy.
3. **Szybkie akcje ikony aplikacji** (Home Screen Quick Actions): „Nowy
   termin”, „Nowa notatka”, „Porozmawiaj z Emmą”. Trzy wejścia, zero menu.
4. **Numer sygnatury sądowej** jako osobne pole sprawy (dziś jest tylko numer
   kancelarii `KAN/…`). Karnista szuka po sygnaturze („II K 123/26”).
   Wymaga backendu.
5. **Rodzaj sprawy (karna / wykonawcza / legalizacja / deportacja)** z kolorem
   i ikoną na karcie — brak w backendzie (D-34 „Czego nie ma”).

**P2 — premium i przyjemność**

6. **Tryb ciemny.** Wszystkie kolory są w `EmmaTheme`, więc to zmiana jednego
   pliku (pary jasne/ciemne przez `Color(light:dark:)`) + przegląd kontrastów.
   Adwokat czyta akta wieczorem — dziś aplikacja świeci na biało.
7. **Wejście kart listy** (lekki fade + przesunięcie 6 pt przy pierwszym
   wczytaniu, kaskadowo po 20 ms) — tylko przy pierwszym pokazaniu, nie przy
   każdym odświeżeniu.
8. **Hero-przejście awatara** z listy klientów do karty klienta
   (`matchedTransitionSource` / `navigationTransition(.zoom)` od iOS 18).
9. **Licznik „do rozprawy”** na karcie sprawy z terminem ≤ 7 dni — duża cyfra
   dni zamiast samej plakietki.
10. **Widżet i Live Activity „Następny termin”** — godzina, sala, klient na
    ekranie blokady w dniu rozprawy.

**P3 — porządki**

11. `LeadCard` i `ClientDirectoryCard` mają osobne menu kontekstowe z tymi
    samymi czynnościami — wspólny komponent „czynności osoby”.
12. `TodayStore` i `ClientsStore` liczą podobne rzeczy osobno; „Dzisiaj” mogłoby
    brać pilność z `ClientsModel.make`.
13. Szkielet ładowania w małych arkuszach (wysokość 320 pt) — rozważyć jeden
    wiersz zamiast trzech.

---

## 4. Czego świadomie nie robimy

- **Więcej filtrów i ustawień.** Chip „Bez ruchu” pojawia się tylko wtedy,
  gdy ktoś taki jest; nie dodajemy sortowania „według…” ani widoków do
  konfiguracji.
- **Ozdobnych animacji** (konfetti, długie przejścia). Ruch ma trwać krócej niż
  mrugnięcie i zawsze odpowiadać na czynność użytkownika.
- **Potwierdzeń tam, gdzie da się cofnąć.** Pytamy tylko przy usuwaniu.

## 5. Wydania po audycie (TestFlight, 28.09.2026)

| Wersja | Co | CI |
|---|---|---|
| 0.5.0 | ruch, „Po terminie”, „Załatwione”, ekran sprawy, karta klienta | zielone (pierwsza kompilacja SwiftUI w CI) |
| 0.5.1 | formularz zadania w stylu terminu, demo z przegapionym terminem, 4 nowe zrzuty | zielone |
| 0.5.2 | animacja samej pigułki (listy się nie przenikają), „Załatwione” w menu | zielone |
| 0.5.3 | „Po terminie”: czas pod tytułem; stopka sprawy | zielone, 18/18 zrzutów |

## 6. Do sprawdzenia na telefonie

- Kompilacja (zmiany pisane bez kompilatora) i `swift test` dla
  `ClientsOverviewTests`.
- Przesunięcia w kartotece z VoiceOver (akcje w rotorze).
- „Ogranicz ruch”: połysk szkieletu wyłączony, odbicia ikon systemowo stłumione.
- Karta „Po terminie” na małym ekranie (SE) — nie powinna wypychać leadów
  poniżej pierwszego widoku przy 1–2 pozycjach.
