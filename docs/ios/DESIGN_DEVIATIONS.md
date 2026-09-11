# Odstępstwa od referencji — rejestr

Wzorzec wizualny to prototyp z commita `b97685b5e2c2cd3d6f78b172b9c0b5cee114270b`
(`reference/prototype/`). Każde odejście od niego musi być tu zapisane wraz
z powodem. **Wzorzec nie jest aktualizowany po to, żeby ukryć regresję** — jeśli
implementacja odbiega, odbiega implementacja i wpis to pokazuje.

Konwencja: `D-nn`, treść, powód, wpływ na wygląd, czy da się cofnąć.

---

## Wykluczenia wymagane przez plan (nie są regresją)

| Id | Co | Powód |
| --- | --- | --- |
| D-00a | Ramka telefonu, sztuczny pasek systemowy, wyspa, wskaźnik strony głównej, podpis podglądu | To atrybuty podglądu HTML w przeglądarce, nie interfejs aplikacji. W aplikacji te elementy rysuje system. |
| D-00b | Kolumna godzin po lewej stronie kalendarza | Jawnie wykluczona w planie; realny ekran iPhone'a nie ma na nią miejsca. |
| D-00c | Etykiety pilności w rozmowach | Jawnie wykluczone w planie; pilność należy do zadań, nie do wiadomości. |
| D-00d | Liczniki czasu przy statusie dostarczenia | Plan zakazuje symulowania dostarczenia. Status pochodzi z modelu transportu, a demo mówi wprost, że WhatsApp nie jest połączony. |

## Odstępstwa techniczne i decyzje projektowe

### D-01 · Czcionka dla cyrylicy — **wpływ widoczny**

**Treść:** DM Sans (Regular/Medium/SemiBold) nie zawiera glifów cyrylickich. Teksty
w języku ukraińskim i rosyjskim są rysowane czcionką systemową, a nie DM Sans.

**Powód:** pomiar tablic `cmap` i `name` plików TTF w repozytorium wykazał brak zakresu
cyrylickiego. Rysowanie brakujących glifów dawałoby „kratki” w imionach klientów
(Olena Kovalenko, Andrii Melnyk), czyli dokładnie tam, gdzie czytelność jest krytyczna.

**Wpływ:** inne, ale spójne kształty liter w tekstach cyrylickich; wersaliki i interfejs
pozostają na DM Sans.

**Cofnięcie:** możliwe po dodaniu kroju z pełną cyrylicą. Kod decyduje o czcionce
na podstawie wykrytego skryptu tekstu, więc zmiana jest w jednym miejscu.

### D-02 · Waga nagłówków na Manrope ExtraBold

**Treść:** nagłówki używają Manrope ExtraBold; DM Sans nie jest dostępny w wadze 800
w plikach, które mamy.

**Powód:** referencja deklaruje `font-weight: 800` dla nagłówków. Użycie DM Sans Bold
(700) spłaszczyłoby hierarchię, więc zamiast tego użyto Manrope ExtraBold z tej samej
rodziny, którą referencja już wykorzystuje.

**Wpływ:** subtelna różnica w rysunku liter nagłówków.

### D-03 · Stała strefa czasowa kancelarii

**Treść:** daty i godziny są formatowane w strefie `Europe/Warsaw`, niezależnie od
strefy ustawionej w iPhonie.

**Powód:** godzina konsultacji jest faktem w kalendarzu kancelarii. Gdyby wyświetlała się
według strefy urządzenia, ten sam termin pokazywałby się inaczej na służbowym i prywatnym
telefonie — to realne ryzyko pomyłki w spotkaniu.

**Wpływ:** przy podróży poza Polskę godziny pozostają godzinami kancelarii.
`MeetingInstant` przechowuje strefę razem z czasem, więc decyzję można zmienić punktowo.

### D-04 · Pigułka „Pilny kontakt” na podstawie `needsReply`

**Treść:** ekran klientów pokazuje pigułkę „Pilny kontakt” wtedy, gdy klient ma
nieodpowiedzianą wiadomość (`needsReply`). Domena nie ma osobnego pola „pilny”.

**Powód:** referencja rozróżnia etap klienta i pilność, ale model domeny w planie
nie definiuje flagi pilności klienta; dodanie jej bez potrzeby biznesowej byłoby
zgadywaniem wymagań.

**Wpływ:** pigułka pojawia się dokładnie tam, gdzie klient czeka na odpowiedź —
w praktyce pokrywa się to z intencją referencji.

**Cofnięcie:** dodanie pola `isUrgent` do `Client` i jednej linii w widoku.

### D-05 · Klikalny wiersz „Opiekun” w `InfoList`

**Treść:** wiersz opiekuna jest klikalny dzięki przezroczystemu celowi dotyku
nałożonemu na wiersz, ponieważ `InfoList` nie przyjmuje akcji na wiersz.

**Powód:** komponent nie miał takiej możliwości, a wchodzenie w zmianę opiekuna jest
w referencji naturalną akcją z karty klienta.

**Wpływ:** brak wpływu na wygląd; dotyk działa na całym wierszu.

**Dług:** należy dodać akcję na wiersz w `InfoList` i usunąć obejście.

### D-06 · Zaznaczenie w `ChoiceList` znakiem „✓”

**Treść:** aktualnie wybrany element listy wyboru ma w tytule znak „✓”, a nie ikonę
po prawej stronie.

**Powód:** `ChoiceList` rysuje chevron i nie przyjmuje znacznika wyboru.

**Wpływ:** wybór jest widoczny, ale w innym miejscu niż w referencji.

### D-07 · Data w `EventRow` z zależności

**Treść:** wiersz terminu pobiera sformatowaną datę z obiektu zależności
(`dateText`), a nie z własnego `Calendar`.

**Powód:** sygnatura komponentu zamrożona bez daty, a formatowanie dat musi być
spójne z resztą aplikacji i z dniem referencyjnym demo.

**Wpływ:** brak wizualnego; gwarantuje jednolite nazwy dni.

### D-08 · Okno ±3 lata dla terminów klienta

**Treść:** terminy klienta pobierane są oknem ±3 lata wokół dnia referencyjnego.

**Powód:** repozytorium demo nie ma zapytania „terminy klienta” z zakresem; okno
obejmuje całość danych przykładowych.

**Wpływ:** brak dla użytkownika; przy prawdziwym backendzie zastąpi to zapytanie zakresowe.

### D-09 · Wyszukiwanie przez `lowercased()`

**Treść:** filtrowanie tekstu ignoruje wielkość liter przez `lowercased()`, a nie
przez porównanie uwzględniające polskie znaki diakrytyczne.

**Powód:** brak odpowiednika `toLocaleLowerCase('pl')`; pełne porównanie wymaga
uwzględnienia znaków diakrytycznych i jest osobnym zadaniem.

**Wpływ:** „Zolc” nie znajdzie „Żółć”. Wpisywanie bez ogonków działa.

**Dług:** dodać porównanie diakrytyczno-niewrażliwe.

### D-10 · `SegmentedFilter` zamiast listy rozwijanej

**Treść:** wybór języka i prowadzącego to segmentowany przełącznik, a nie lista
rozwijana jak w referencji.

**Powód:** design system nie ma komponentu listy rozwijanej, a dodawanie go dla dwóch
pól wprowadziłoby nowy wzorzec interakcji.

**Wpływ:** wszystkie opcje są widoczne od razu; przy większej liczbie prowadzących
segmenty przestaną się mieścić.

### D-11 · Najbliższe tokeny i promień 8 zamiast 9

**Treść:** kilka odcieni z referencji (`#35577d`, `#7b8898`, `#8692a2`, `#67768a`)
jest odwzorowanych najbliższymi istniejącymi tokenami, a chipy mają promień 8 zamiast 9.

**Powód:** nie tworzono nowych tokenów poza `EmmaTheme`, żeby uniknąć prywatnych
stałych kolorów rozsianych po widokach.

**Wpływ:** różnice jednocyfrowe w jasności odcieni, praktycznie niewidoczne.

**Dług:** dopisać dokładne tokeny do `EmmaTheme` i `EmmaRadii`, jeśli porównanie
zrzutów wykaże różnicę.

### D-12 · Mock dyktowania w trybie Demo

**Treść:** w trybie Demo dyktowanie pochodzi z usługi scenariuszowej, nie z rozpoznawania
mowy systemu.

**Powód:** deterministyczne testy i praca bez mikrofonu; plan wymaga mocków działających
bez kont i bez uprawnień.

**Wpływ:** w Demo dyktowanie nie reaguje na prawdziwy głos — i mówi o tym w interfejsie.

---

## Czego ten rejestr nie zawiera

Nie zawiera porównania zrzutów ekranu, bo **nie zostały wykonane** — brak macOS
i symulatora (patrz `BUILD_AND_DEVICE_STATUS.md`). Ocena zgodności wizualnej opiera się
na kaskadzie CSS referencji, pomiarach plików czcionek i przeglądzie komponentów.
Pierwsze realne porównanie obrazu jest pierwszym punktem listy po uruchomieniu na Macu.
