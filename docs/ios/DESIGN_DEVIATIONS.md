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

### D-09 · ~~Wyszukiwanie przez `lowercased()`~~ — **zamknięte w audycie kodu**

**Treść (stan poprzedni):** filtrowanie ignorowało wielkość liter przez `lowercased()`,
bez uwzględnienia polskich znaków diakrytycznych.

**Stan obecny:** jedna reguła `SearchText` (`Core/Domain/ClockAndFormatting.swift`)
składa znaki diakrytyczne i mapuje `ł` → `l` jawnie (`ł` nie jest literą diakrytyczną
w sensie Unicode, więc samo składanie jej nie usuwa). Ekrany klientów i rozmów
korzystają z tej reguły zamiast własnych kopii.

**Wpływ:** „zelazna” znajduje „Żelazna”, „lukasz” znajduje „Łukasz”, cyrylica działa.
Testy: `SearchTextTests` (8 przypadków).

**Uwaga:** `PersonResolver` (rozpoznawanie osoby w poleceniu głosowym) nadal używa
`lowercased()`. To osobna reguła domenowa z własnymi testami; ujednolicenie jest
kandydatem na przyszłość, ale zmienia zachowanie rozpoznawania i wymaga osobnej decyzji.

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

### D-13 · Dynamic Type: tekst rośnie, odstępy nie

**Treść:** wszystkie style typografii skalują się względem stylu treści (`.body`),
ale odstępy, promienie i szerokości kart pozostają stałe.

**Powód:** plan wymaga zachowania treści i obsługi przy dużym Dynamic Type, ale nie
wymaga zgodności pikselowej z domyślnym rozmiarem tekstu. Jedna krzywa skalowania
w `EmmaTypography` jest przewidywalna i łatwa do sprawdzenia; skalowanie odstępów
rozjechałoby siatkę kart z referencji bez potrzeby.

**Wpływ:** przy domyślnej wielkości tekstu wygląd jest identyczny z referencją
(mnożnik 1). Przy dużym tekście litery rosną wewnątrz stałych odstępów — kontenery
mają **minimalne** wysokości, więc treść nie jest obcinana.

**Wymaga potwierdzenia na urządzeniu:** przewijanie długich nazwisk i przycisków
przy kategorii dostępności XXXL. To pozycja pierwszego testu na symulatorze.

---

### D-14 · Tłumaczenia usunięte z rozmów — **decyzja właściciela**

**Treść:** dymki wiadomości nie pokazują sekcji „Tłumaczenie” (odpowiednik
`<details class="bubble-translation">` z referencji). Pole `Message.translation`
zostaje w modelu i danych — mogłoby wrócić jako opcja — ale nie jest wyświetlane.
Tokeny `bubbleTranslation*` usunięte z `EmmaTheme`.

**Powód:** polecenie właściciela podczas audytu designu: zespół rozumie języki
ukraiński i rosyjski, więc tłumaczenia zaburzają czytelność rozmowy.

**Wpływ:** krótsze, czystsze dymki; interfejs rozmowy mniej obleczony tekstem
pomocniczym. Preview (`build-preview.py`) i pomiar renderu zaktualizowane.

**Cofnięcie:** jedno `if let translation` w `MessageBubble` + przywrócenie tokenów.

### D-15 · Ekran główny to Emma, nie kokpit — **decyzja właściciela**

**Treść:** zakładka „Dzisiaj” nie odtwarza `home()` z referencji (karta Emmy
z briefingiem, statystyki, najbliższa konsultacja, sekcje o sprawach). Zamiast
tego: nagłówek z datą i powitaniem, **zwięzły wiersz „Zapytaj Emmę o dzień”**
(orb `.card` + mikrofon, start rozmowy głosowej), sekcja **„Dziś w kalendarzu”**
z dzisiejszymi terminami oraz **„Zadania na dziś”** z odhaczaniem i łączem do
pełnej listy zadań.

**Powód:** polecenie właściciela: ekran główny nie ma być podsumowaniem
z statystykami, a Emma ma być na nim obecna. W drugiej iteracji właściciel
dodał, że „Dzisiaj” ma pokazywać **dzisiejsze zadania z terminarza**, a nie
tylko przekierowywać do Emmy — stąd agenda dnia zamiast samego orba.

**Wpływ:** statystyki i sekcje o sprawach zniknęły z ekranu głównego
(„Klienci” i „Kalendarz” mają je u siebie). Briefing dnia jest dalej dostępny
na ekranie Emmy („Opowiedz mi o dzisiejszym dniu”). `TasksScreen` nie ma własnej
zakładki, więc łącze „Wszystkie zadania” jest jego wejściem (rozszerzenie stosu
nawigacji zakładki „Dzisiaj”). Ekran ładuje terminy i zadania, ale bez migotania:
stan ładowania pokazuje się tylko przy pierwszym wczytaniu.

**Cofnięcie:** przywrócenie poprzedniej wersji `TodayScreen` z historii gita.

### D-16 · Logowanie demo i blokada Face ID — **decyzja właściciela**

**Treść:** przed powłoką aplikacji stoją dwa ekrany: `LoginScreen` (e-mail + hasło,
raz na urządzenie) i `LockScreen` (odblokowanie Face ID / hasłem urządzenia przy
każdym powrocie). Nie ma ich w referencji — prototyp startował od razu na pulpicie.

**Powód:** polecenie właściciela: logowanie ma być, Face ID też.

**Wpływ:** dane logowania są demonstracyjne (nie ma backendu), więc ekran mówi to
wprost, a brak skonfigurowanej biometrii nie zamyka dostępu na stałe — pokazuje
jawny przycisk odblokowania. Stan „zalogowany” jest zapamiętywany, więc logowanie
przeżywa restart, ale sam dostęp nadal wymaga odblokowania.

**Cofnięcie:** usunięcie `Features/Auth/` i bramki w `EmmaApp.swift`.

**Odstępstwo w testach:** scenariusze UI używają argumentu startowego `--skip-auth`,
żeby nie zależeć od biometrii symulatora. Sam ekran logowania ma osobny test
(`testLoginScreenAcceptsDemoCredentials`) na argumencie `--reset-auth`.

### D-17 · Koniec podziału na użytkowników i pojęcia opiekuna — **decyzja właściciela**

**Treść:** z domeny, repozytorium, interfejsu i testów usunięte zostały:
`ownerID` (klient, sprawa, zadanie, termin, notatka, drafty akcji), typ `OwnerName`,
`assignOwner`, `switchUser`, `users()`, arkusz `AssignOwnerSheet`, filtry per opiekun
oraz nazwiska „Tomasz”/„Paweł” w zadaniach, terminach, sprawach i briefingu.
Repozytorium demo nie przypisuje już nikogo do niczego.

Dodatkowo **dane demo mają jedno wspólne konto kancelarii** zamiast dwóch
prawników: `UserID.kancelaria` (`user-kancelaria`), nazwa „Kancelaria Rogoża”,
inicjały „KR”. Zniknęły: stałe `DemoFixtures.tomasz`/`.pawel`, wybór zalogowanego
w `Dataset.currentUserID`, zestaw `second-lawyer` (zastąpiony przez
`mixed-languages`) oraz odmiana imienia w powitaniu (`EmmaBriefing.vocative`,
`User.greetingName`). Powitanie to teraz po prostu „Dzień dobry”.

**Powód:** polecenie właściciela: zespół ma te same zadania i te same sprawy, więc
dzielenie pracy per osoba jest fikcją — wszystko należy do kancelarii.

**Wpływ:** aplikacja ma jedno wspólne konto (patrz D-16). Zadania i terminy pokazują
klienta i status, bez prowadzącego. Profil nie ma przełącznika użytkownika.
Stan odczytu wiadomości nadal jest przypisany do konta (`ThreadUserState.userID`) —
to warunek działania liczników nieprzeczytanych, ale licznik jest jeden. `UserID`
i `User` zostają wyłącznie jako opis sesji, nie własności danych.

**Cofnięcie:** przywrócenie pól i arkusza z historii gita; dane demo trzeba by
wtedy z powrotem przypisać do osób.

### D-18 · Plakietka z inicjałami „KR” — **usunięta**

**Treść:** nagłówki ekranów nie mają już awatara z inicjałami zalogowanego konta.
Zniknął wariant `PersonAvatar.Style.user` wraz z tokenami `avatarBackground`
i `avatarText`.

**Powód:** polecenie właściciela: ikonka „KR” w prawym górnym rogu jest
niepotrzebna w żadnym miejscu. Konto jest jedno i wspólne dla kancelarii, więc
plakietka nic nie wnosiła.

**Wpływ:** wejście do profilu zostało w jednym miejscu — cicha ikona konturu osoby
w nagłówku ekranu „Dzisiaj”. To nadal potrzebne, bo stamtąd wylogowuje się
i blokuje aplikację (D-16); usunięcie całego wejścia odebrałoby dostęp do tych
funkcji. Ikona nie pokazuje żadnych danych osobowych.

**Cofnięcie:** przywrócenie wariantu w `PersonAvatar` i przekazanie inicjałów
w `ScreenHeader`.

### D-19 · Ekran „Dzisiaj”: scena Emmy, oś dnia i pierścienie zadań — **decyzja właściciela**

**Treść:** trzy zmiany w jednej sekcji:

1. **Emma ma więcej miejsca.** Zamiast zwięzłego wiersza z orbem `.card` jest
   scena: orb w nowym rozmiarze `.stage` (132 pt) na miękkiej poświacie, pod nim
   „Jestem Emma”, jedno zdanie wyjaśnienia i główne wejście w rozmowę głosową
   oraz drugie, cichsze — na piśmie. Wysokość sceny jest stała, żeby późniejsza
   podmiana orba na animację 3D głowy (psa) nie przesunęła terminarza.
2. **Terminy to oś dnia.** Dzisiejsze terminy są w jednym pojemniku, z paskiem
   stanu, godziną i czasem trwania. Termin, który minął, zostaje na liście, ale
   jest wygaszony i opisany „Minęło”; trwający dostaje pill „Teraz”. Pod
   wielokropkiem jest menu z „Usuń termin” (z potwierdzeniem) — wcześniej była
   tam strzałka, która obiecywała przejście dalej.
3. **Zadania odhacza się pierścieniem.** Biały kwadrat 24×24 z referencji
   (`.task-check`) zastąpił pierścień, który wypełnia się kolorem akcentu
   z haczykiem — puste pole czytało się jak formularz do wypełnienia.

**Powód:** polecenie właściciela: sekcja „Dzisiaj” jest zbyt podstawowa, ma być
bardziej dopracowana przy zachowaniu minimalizmu i czytelności; Emma ma dostać
więcej przestrzeni, terminy trzeba odróżnić, a w zadaniach zmienić sposób
odhaczania.

**Wpływ:** wiersze terminu na kartach klienta i sprawy też wygaszają minione
terminy (wspólna reguła w rdzeniu, `ScheduledEvent.hasPassed(at:)`). Doszła
operacja `deleteEvent` w repozytorium agendy — wcześniej nie było sposobu
usunięcia terminu z aplikacji. Poprawiony został też gradient orba: rósł ze
stałym promieniem 26 pt, choć referencja rozciąga go na cały element, więc duże
orby były płaskie.

**Cofnięcie:** poprzednia wersja `TodayScreen`, `EventRow` i `TaskRow` z historii
gita; usunięcie `deleteEvent` z protokołu agendy.

---

### D-20 · Ciemniejsze tokeny tekstu dla kontrastu 4,5:1 — **etap 2 audytu UX (F09)**

**Treść:** 20 tokenów tekstowych w `EmmaTheme` ma ciemniejsze wartości niż w referencji,
np. `mutedSoft` `#7A8492` → `#5F6D7D`, `taskDateText` `#8B96A5` → `#66768B`,
`contextStripText` `#6B84A0` → `#526F91`, `dockStatusText` `#8A9AAC` → `#5F6D7D`.

**Powód:** pomiar sRGB w audycie wykazał kontrast poniżej 4,5:1 dla etykiet, które
decydują o dniu i sterowaniu głosem (np. `dockStatusText` 2,68:1). To nie jest kwestia
gustu — przy takim kontraście danych nie da się odczytać w słońcu ani przy słabym wzroku.
Cel: co najmniej 4,5:1 dla zwykłego tekstu (WCAG AA), zgodnie z §3 audytu.

**Wpływ:** metadane są ciemniejsze, więc hierarchia jest mniej „mglista”, ale nadal
czytelna jako drugi plan. Każda nowa wartość **występuje już w regułach referencji**,
więc kontrola `design-token-diff.py` nadal nie zgłasza kolorów spoza wzorca.

**Kontrola:** `ios/scripts/check-readability.py` (krok 9/9 `verify-linux-logic.sh`) liczy
kontrast zadeklarowanych tokenów wobec ich rzeczywistych teł i przerywa przy regresji.

**Cofnięcie:** przywrócenie poprzednich wartości z historii gita (kosztem kontrastu).

### D-21 · Jeden powrót na ekranie szczegółu i przywrócony gest — **etap 2 audytu UX (F12)**

**Treść:** `ClientCardScreen` i `TasksScreen` chowają systemowy przycisk powrotu
(`.navigationBarBackButtonHidden(true)`), tak jak wcześniej `CaseScreen` i `ThreadScreen`.
Jedyne wejście powrotu to własny przycisk w `DetailHeader` („Wróć”). Ekran Zadania dostał
`DetailHeader` zamiast `ScreenHeader` + osobnego wiersza z „+”, więc u góry nie ma już
dwóch nagłówków. Nowy `EmmaSwipeBack` przywraca gest przesunięcia od krawędzi, który
ukrycie systemowego przycisku domyślnie wyłącza.

**Powód:** na karcie klienta były dwa powroty obok siebie, a na Zadaniach systemowy
powrót i własny nagłówek tworzyły podwójną, pustą strefę. Audyt wymaga jednego sposobu
budowania nagłówka i zachowania gestu powrotu.

**Wpływ:** spójny nagłówek na wszystkich wypychanych ekranach; tytuł pozostaje dostępny
dla VoiceOver („Wróć” + tytuł). Gest krawędzi działa, ale tylko gdy na stosie jest więcej
niż jeden ekran — na ekranie głównym nie ma czego przewracać.

**Ograniczenie:** przywrócenie gestu opiera się na delegacie
`interactivePopGestureRecognizer` (UIKit). Jeśli hierarchia nie zna jeszcze
`UINavigationController`, modyfikator nic nie robi — brak gestu, nie błąd. Zachowanie
pilnuje test UI wykonujący przeciągnięcie od krawędzi.

### D-22 · Licznik nieprzeczytanych w osobnej kolumnie — **etap 2 audytu UX (F13)**

**Treść:** w wierszu listy rozmów czas, licznik nieprzeczytanych, pinezka i menu tworzą
osobną kolumnę w układzie (`VStack` po prawej), a nie warstwy nałożone na tekst.

**Powód:** licznik był wyśrodkowaną nakładką i nachodził na dwuliniowy podgląd wiadomości,
najgorzej w pierwszym wierszu i przy długiej cyrylicy.

**Wpływ:** podgląd nie może wejść w prostokąt kolumny, bo kolumna zajmuje własną szerokość.
Przy dużym Dynamic Type kolumna rośnie w pionie razem z resztą wiersza.

**Cofnięcie:** przywrócenie nakładek z historii gita (kosztem kolizji).

### D-23 · Jedna skala tekstu: najniższy stopień 12 pt — **etap 2 audytu UX (F09)**

**Treść:** wszystkie metadane i podpisy przechodzą przez `EmmaTypography.caption(...)`
(12 pt). Dawne `EmmaTypography.ui(10…)`/`ui(11…)` w widokach zostały zamienione na ten
styl (73 miejsca w 22 plikach). Style nazwane, które miały 10–11 pt
(`kicker`, `meetingMeta`, `taskMeta`, `taskDate`, `caseNumber`, `bubbleMeta`, `pill`,
`tabLabel`), mają teraz 12 pt. `button` urósł z 13 na 16 pt (audyt: przyciski 16–17 pt).

**Powód:** etykiety 10–11 pt przy słabym kontraście podejmowały decyzje o dniu i wysyłce.
Audyt wymaga jednej skali i braku stałych rozmiarów w ekranach.

**Wpływ:** metadane są nieco większe (o 1–2 pt), przyciski bardziej czytelne. Przy
domyślnym tekście wygląd pozostaje bliski referencji; skala nadal rośnie z Dynamic Type.

**Kontrola:** `check-readability.py` przerywa, gdy w ekranie pojawi się tekst 10 lub 11 pt.

**Cofnięcie:** przywrócenie poprzednich stylów z historii gita.

---

### D-24 · „Dzisiaj”: najpierw sprawa, potem scena Emmy — **etap 3 audytu UX (F08)**

**Treść:** układ ekranu „Dzisiaj” zmienia kolejność i ciężar elementów. Pełna scena Emmy
(orb `.stage`, „Jestem Emma”, zdanie wyjaśnienia i dwa przyciski) ustępuje **kompaktowej
karcie** o wysokości ~94 pt: portret 52 pt (`EmmaOrb.Size.compact`), napis „Porozmawiaj
z Emmą”, podpis „Zapytaj o dzień, terminy lub wiadomości.”, okrągły przycisk mikrofonu
44 pt i cichy „Napisz” pod nim. Kolejność sekcji to teraz: nagłówek dnia → karta Emmy →
„Najbliższy termin” (godzina, status, miejsce, linki do klienta i sprawy, „Przygotuj
mnie”, „Szczegóły”) → „Zadania” z liczbą otwartych i zaległych oraz wejściem „Wszystkie
zadania” → „Dalej dziś” z pozostałymi terminami → zwijana sekcja „Minione terminy”.
Nagłówki sekcji na tym ekranie używają wariantu `SectionHeader(compact:)`.

**Powód:** audyt F08 — przy pełnej scenie Emmy najbliższy termin i wejście do zadań
wypadały poza pierwszy widok, a pilne zadanie lądowało pod długą listą spotkań. To
świadome **uchylenie punktu 1 decyzji właściciela D-19** („Emma ma więcej miejsca”):
scena wraca tam, gdzie jest na nią miejsce, czyli do zakładki „Emma”. Pozostałe punkty
D-19 (oś dnia, wygaszanie minionych, pierścienie zadań) zostają bez zmian, a miniony
termin nadal widać — tylko w zwiniętej sekcji.

**Wpływ:** pierwszy widok dnia pokazuje najbliższy termin i zadania bez przewijania
(potwierdzone testem `Stage3LayoutUITests.testNextEventAndTaskEntryAreAboveTheFold`).
Portret Emmy jest mniejszy niż w D-19; pełna scena nadal istnieje w zakładce „Emma”,
więc wizerunek Emmy nie znika z aplikacji. Doszły reguły rdzenia `DayAgenda` (najbliższy
termin / dalsze / minione) i `TaskGrouping` (zaległe / na dziś / później), wspólne dla
„Dzisiaj” i „Zadania”; `EmmaOrb` dostał rozmiar `.compact` (52 pt).

**Cofnięcie:** przywrócenie poprzedniej wersji `TodayScreen` z historii gita; usunięcie
`DayAgenda`, `TaskGrouping` i przypadku `.compact` w `EmmaOrb`.

---

### D-25 · Wiersz zadania i karta Emmy układają się w kolumnę przy dużym tekście — **etap 3 audytu UX (F09)**

**Treść:** przy rozmiarach dostępności (`dynamicTypeSize.isAccessibilitySize`) dwa
poziome układy przechodzą w pionowy:

1. `TaskRow` — data i plakietka „Pilne” schodzą pod tytuł, na pełną szerokość
   (wcześniej trzy kolumny zostawiały tytułowi ~150 pt).
2. kompaktowa karta Emmy na „Dzisiaj” — portret i tytuł w jednym wierszu, pod nimi
   podpis oraz mikrofon i „Napisz”.

**Powód:** OCR zrzutów przy `Accessibility XXXL` wykazał łamanie wyrazów w środku:
„Porozm / awiaj z / Emmą” oraz „zatrzyma / nia”. To nie jest estetyka — tekst pocięty
w połowie wyrazu czyta się jak uszkodzony.

**Wpływ:** bez zmian przy standardowym tekście (układ poziomy zostaje). Przy dużym
tekście lista zadań i karta Emmy są dłuższe, ale czytelne; porównanie w
`docs/ios/screenshots/stage3-2026-09-13/` (`24-duzy-tekst-dzisiaj.png`,
`25-duzy-tekst-zadania.png`).

**Kontrola:** OCR zrzutów po zmianie czyta „Porozmawiaj” i „z Emmą” w całości oraz
„Oddzwonić w / sprawie / zatrzymania”.

**Uzupełnienie (etap 4):** poprawka z etapu 3 była niepełna. Na małym ekranie
(375 pt) przy `Accessibility XXXL` portret w tym samym wierszu co tytuł nadal urywał
wyraz — OCR zrzutu `30-duzy-tekst-mini-panel.png` czytał „Porozmawi / aj z Emmą”.
Etap 4 kładzie portret **nad** tytułem, a tytuł i podpis zajmują pełną szerokość karty
(`frame(maxWidth: .infinity, alignment: .leading)`). Po poprawce OCR obu ekranów czyta
„Porozmawiaj” i „z Emmą” w całości. Zrzuty etapu 3 zostały **wykonane ponownie**
(`24-duzy-tekst-dzisiaj.png` na obu ekranach), bo poprzednia wersja utrwalała błąd —
etap 3 oceniłem wtedy tylko na dużym ekranie i przeoczyłem to na małym.

**Cofnięcie:** usunięcie gałęzi `if dynamicTypeSize.isAccessibilitySize` w `TaskRow`
i `TodayScreen.emmaCompactCard()`.

---

### D-26 · Sterowanie rozmową istnieje poza ekranem Emmy (globalny mini-panel) — **etap 4 audytu UX (F06)**

**Treść:** dopóki sesja głosu istnieje, nad paskiem zakładek — a gdy otwarty jest arkusz
modalny, nad treścią tego arkusza — widnieje pasek o wysokości 56 pt: mały portret Emmy,
jeden stan („Łączę z Emmą”, „Słucham”, „Mikrofon wyciszony”, „Emma mówi”, „Rozmowa
niedostępna”), przycisk wyciszenia (44 pt) i „Zakończ rozmowę” (44 pt). Dotknięcie treści
wraca do pełnej rozmowy. Panelu **nie ma** na zakładce „Emma” (tam jest pełny dock) ani
w drzewie dostępności za otwartym arkuszem, gdy ten rysuje własny panel.

**Powód:** audyt F06 — sterowanie było dostępne wyłącznie na ekranie Emmy, więc rozmowa
uruchomiona „przy okazji” zadania lub notatki stawała się nieosiągalna bez porzucenia
tego, co się robiło. To także wymaganie akceptacyjne etapu: „Jedna sesja; sterowanie
dostępne we wszystkich zakładach i modalach”.

**Wpływ:** panel czyta stan z **jednego** koordynatora (`VoiceUIState`) i woła jego metody
przez `AppDependencies.toggleVoiceMicrophone()` / `endVoiceSession()`; nie powstaje drugi
silnik, druga subskrypcja ani druga sesja. Wyciszenie nie kończy rozmowy, a zakończenie
jest tą samą ścieżką co w docku Emmy. Przy największym tekście panel skraca się o podpis
„Wróć do rozmowy”, żeby stan nie był urywany (zrzut `30-duzy-tekst-mini-panel.png`).
`RootShell` rezerwuje na panel miejsce w układzie, więc nie zasłania treści.

**Cofnięcie:** usunięcie `VoiceMiniPanel.swift` i trzech wstawień w `RootShell`
(oraz `AppDependencies.toggleVoiceMicrophone()` / `endVoiceSession()`); powrót
`AssistantStore.endSession()` do bezpośredniego wołania koordynatora.

---

### D-27 · Dock Emmy nie mówi już o „Połączeniu: Nieaktywna”, a kompozytor ma jedno „Rozmawiaj” — **etap 4 audytu UX (F07)**

**Treść:** trzy zmiany widoczne na ekranie Emmy:

1. Linia techniczna „Połączenie: … · Mikrofon: … · Tryb: …” jest pokazywana **tylko**, gdy
   sesja istnieje. Bez sesji dock mówi jednym zdaniem („Gotowa do rozmowy”).
2. Dock ma wyciszenie mikrofonu obok przerwania i zakończenia; przycisk zakończenia
   w docku skrócony do „Zakończ” (pełne „Zakończ rozmowę” zostało w mini-panelu), żeby
   trzy akcje zmieściły się w jednym wierszu na 375 pt.
3. Kompozytor: jedno główne „Rozmawiaj” (56 pt, `EmmaMetrics.emmaVoiceButtonSize`)
   zamiast trzech ikon w jednym rzędzie, pod nim tryb pisania z jawnym „Dyktuj tekst”
   i wysłaniem **nieaktywnym**, gdy pole jest puste. Stan dyktowania nazywa się
   „Zakończ”, więc nie ma dwóch znaczeń jednego przycisku.

**Powód:** audyt F07 — dock jednocześnie twierdził „Rozmowa głosowa”, „Połączenie:
Nieaktywna” i „Mikrofon niedostępny”, a trzy ikony o równej wadze nie mówiły, co jest
wejściem w rozmowę. Warunek etapu: mikrofon 56–64 pt i nieaktywne wysłanie pustego pola.

**Wpływ:** znika sprzeczny komunikat bez sesji; wizualnie dock jest krótszy, bo linia
techniczna pojawia się dopiero w rozmowie. Etykiety zmieniły się w testach dostępności
(„Rozpocznij wypowiedź” → „Rozmawiaj”, „Zatrzymaj nasłuch” → „Wycisz mikrofon”).
Pełna prawda o połączeniu i mikrofonie nadal jest podana wprost, nigdy tylko kolorem.

**Cofnięcie:** przywrócenie poprzedniego `composer` i `stateLabel` w `AssistantScreen`
i `VoiceDock` oraz bezwarunkowej linii technicznej.

### D-28 · Godzina terminu zadania jest pokazana, ale nie jest osobnym polem listy — **etap 5 audytu UX (F14/§6-C)**

**Treść:** „Dodaj zadanie: wyślij dokumenty Olenie jutro do 14” tworzy propozycję
z terminem `2026-09-12`, a w odpowiedzi Emmy i na karcie widać **godzinę 14:00**.
Sama propozycja zapisuje jednak wyłącznie datę (`ActionProposal.taskDueDate`) — model
zadania w tym prototypie zna dzień, nie godzinę.

**Powód:** audyt wymaga, żeby „Do 14” **nie zniknęło** i żeby ograniczenie było
wypowiedziane *przed* zapisem. Dodanie godziny do zadania zmieniłoby wspólną listę
zadań, ekran „Dzisiaj” i dane demo — czyli zakres poza etapem 5. Zamiast zgadywać,
Emma mówi wprost: „Godzina 14:00 jest w treści polecenia; lista zadań pokazuje samą
datę”.

**Wpływ:** termin słyszalny i widoczny jest datą bezwzględną (`2026-09-12`), godzina
zostaje w treści wypowiedzi i w potwierdzeniu. Formularz **spotkania** przenosi godzinę
do pola „Godzina” (`EventDraftSeed`), bo wydarzenie ma pełny termin — tam nic nie ginie.

**Cofnięcie:** rozszerzenie `ActionProposal`/`TaskItem` o `dueTime` i pokazanie godziny
w listach zadań.

---

### D-29 · Rozmowa Emmy jest kotwiczona na dole — **etap 5 audytu UX (F04/§6)**

**Treść:** `AssistantScreen` dostał `.defaultScrollAnchor(.bottom)`. Przy pojawieniu się
klawiatury najnowsza karta propozycji zostaje nad nią, a nie pod nią.

**Powód:** bez kotwicy karta (ok. 350 pt) wypadała poza okno rozmowy nad klawiaturą —
`scrollTo(last.id, anchor: .bottom)` wykonywał się **przed** zmianą wstawki klawiatury,
więc użytkownik widział sam przycisk zgody bez treści, którą zatwierdza (zmierzone:
pole treści na `y = -306 pt`, czyli poza ekranem 874 pt).

**Wpływ:** kolejność tur i animacje bez zmian; zmieniła się tylko pozycja przewinięcia.
Zrzuty etapu 5 pokazują całą treść karty (pole treści `y = 224 pt` w oknie 874 pt).

**Cofnięcie:** usunięcie `.defaultScrollAnchor(.bottom)`.

### D-30 · Odsłuch w demo pozostaje scenariuszowy, poza demo mówi syntezator systemu — **etap 6 audytu (F05)**

**Treść:** „Odsłuchaj” w Demo nadal korzysta z `MockSpeechPlaybackService` (zdarzenia
bez dźwięku). Poza Demo — gdy jest skonfigurowany backend — wybierany jest
`SystemSpeechPlaybackService`, który naprawdę mówi systemowym `AVSpeechSynthesizer`.
Stopka demo mówi jedno i drugie wprost.

**Powód:** dwa sprzeczne wymagania. Testy i zrzuty muszą być deterministyczne (mock
kończy odsłuch natychmiast), a użytkownik nie może usłyszeć **głosu systemowego** jako
głosu Emmy i pomyśleć, że to integracja z dostawcą. Rozdzielenie według konfiguracji
zachowuje jedno i drugie, a nota w interfejsie nie pozwala pomylić jednego z drugim.

**Wpływ:** odsłuch przestał być pustą atrapą w kodzie produkcyjnym; w Demo nadal nie ma
dźwięku i jest to wypowiedziane na ekranie. Głos Emmy od dostawcy pozostaje otwarty —
do czasu konta i backendu wydającego token.

**Cofnięcie:** zwrócenie `MockSpeechPlaybackService()` w obu wariantach (stan sprzed
etapu 6) i skrócenie noty w stopce.

---

### D-31 · „Dzisiaj”: leady do obsługi, portret Emmy w nagłówku — **review właściciela 23.09.2026**

**Treść:** na ekranie głównym, zaraz pod nagłówkiem, jest sekcja „Leady do obsługi”
(najwyżej trzy wiersze: najpierw czekające ≥ 24 h, potem nowe) z okrągłym
przyciskiem „obsłużone” w każdym wierszu. Kompaktowa karta Emmy z D-24 zamieniła się
w portret Emmy w nagłówku, obok profilu: dotknięcie zaczyna rozmowę głosową,
przytrzymanie daje „Napisz do Emmy” i „Podsumuj mój dzień”. Powitanie zależy od pory
(„Dzień dobry” / „Dobry wieczór”).

**Powód:** właściciel chce widzieć oczekujące zgłoszenia na stronie głównej. Karta
Emmy zajmowała ~110 pt; z sekcją leadów nad nią najbliższy termin i wejście do zadań
spadałyby pod zgięcie ekranu, czego zabrania F08. Portret w nagłówku zachowuje
jedno-dotknięciowe wejście w rozmowę i obecność Emmy, a oddaje wysokość treści.

**Wpływ:** kolejność: nagłówek → leady → najbliższy termin → zadania → dalej dziś.
Z rachunku wysokości (nie z pomiaru na urządzeniu): na iPhonie 16 przy dwóch leadach
„Wszystkie zadania” mieści się w pierwszym widoku; przy trzech leży na granicy —
do potwierdzenia testem `Stage3LayoutUITests` na symulatorze.

**Cofnięcie:** przywrócenie `emmaCompactCard()` z historii Gita i usunięcie
`leadsSection` z `TodayScreen.loaded`.

---

### D-32 · Leady jako kolejka pracy: 24 h „Nowy”, potem „Oczekuje” — **review właściciela 23.09.2026**

**Treść:** etap `new` z backendu nie mówi, jak długo zgłoszenie czeka, więc na liście
wszystko było „Nowe”. Reguła `LeadWorkflow` (rdzeń, testy w `LeadWorkflowTests`):
„Nowy” przez 24 h od przyjęcia, potem „Oczekuje”; `in_contact` to „W kontakcie”
(= obsłużone). Domyślny filtr listy to „Do obsługi” (czekające najpierw, najstarsze
na górze; potem nowe), dalej „Nowe”, „Oczekujące”, „W kontakcie”, „Wszystkie”.
Karta leada ma kolorowy pasek stanu z lewej, plakietkę z wiekiem („Nowy · 3 godz.
temu”, „Oczekuje · 2 dni”), temat bez prefiksu „Termin: …” i osobną linię z terminem
z rezerwacji. Obsłużenie: okrągły przycisk na karcie, przesunięcie w prawo albo menu;
zawsze z „Cofnij” w komunikacie. W lewo: konwersja (z pytaniem) i usunięcie (z pytaniem).
Plakietka z liczbą zgłoszeń do obsługi stoi na zakładce „Klienci”.

**Powód:** leady to rezerwacje konsultacji; zgłoszenie, które czeka dobę, najczęściej
jest stracone. Lista ma pokazywać, co jest do zrobienia i od kiedy, a odhaczenie ma być
tak szybkie jak odhaczenie zadania.

**Wpływ:** lista leadów stoi na `List` (systemowe przesunięcia z obsługą VoiceOver);
karty zachowują własny wygląd (tło i separatory wiersza wyłączone). Dokładny wiek
w godzinach wymaga pola `received_at` z backendu (rozszerzenie kontraktu, opcjonalne);
bez niego wiek liczony jest z daty z przyjęciem południa i pokazywany w dniach.

**Cofnięcie:** przywrócenie `ClientsScreen`/`LeadCard` z historii Gita; `LeadWorkflow`
może zostać (nie zmienia danych).

---

### D-33 · Cień kart i reakcja na dotyk — **review właściciela 23.09.2026**

**Treść:** karty (`SurfaceCard`, karta leada, sprawy, spotkania) mają miękki,
dwuwarstwowy cień z atramentu `ink` o niskiej przezroczystości; karty-przyciski lekko
się zapadają pod palcem (`EmmaCardButtonStyle`). Ważne czynności (odhaczenie zadania,
obsłużenie leada, zmiana filtra, zakładki, tygodnia) dają krótką odpowiedź dotykową.
Komunikat może mieć akcję („Cofnij”) i wtedy przyjmuje dotyk.

**Powód:** „premium” w odbiorze właściciela: płaskie karty z samą ramką i brak
reakcji na dotyk sprawiały wrażenie makiety. Żaden nowy kolor nie powstał — cień to
istniejący token z przezroczystością.

**Cofnięcie:** usunięcie `emmaCardShadow()` z `SurfaceCard` i kart oraz powrót do
`.buttonStyle(.plain)`.

---

### D-34 · Ekran „Klienci”: stały kolor osoby, trzy tryby, pilność spraw — **review właściciela 27.09.2026**

**Treść:**
- Awatar osoby ma **stały ton** liczony z identyfikatora (`IdentityTone`, FNV-1a,
  sześć stonowanych par w `EmmaTheme.identityAvatar`). Ta sama osoba wygląda tak
  samo na liście leadów, w kartotece, na karcie sprawy, w rozmowach i na swojej
  karcie. Zastępuje §4.3 („ton zależy od pozycji na liście rozmów”) — typ
  `Client.AvatarTone` i ton pozycyjny zostały usunięte.
- Obok nazwiska plakietka języka klienta („UA”, „RU”, „PL”).
- „Klienci” ma trzy tryby: **Leady · Klienci · Sprawy**. Nowy tryb to kartoteka
  (etap `client`) w sekcjach A–Ż z paskiem „Ostatnio otwierani” (zapamiętany
  w `UserDefaults`) i filtrami Wszyscy / Z aktywną sprawą / Wymaga uwagi.
- Nad listą trzy kafelki podsumowania (`PulseTile`, wspólny z „Dzisiaj”).
  Zniknął podpis „BAZA KANCELARII” — zostaje sam tytuł.
- Karta sprawy zaczyna się od klienta (awatar, nazwisko, język), plakietka mówi
  „dziś / jutro / za N dni” (czerwona do 3 dni, bursztynowa do 7) zamiast stałego
  „W toku”; numer sprawy zszedł do stopki. Aktywne sprawy w grupach
  **Wymaga uwagi → W toku → Czekamy na klienta** (`CaseBoard`).
- Kolejka leadów „Do obsługi” ma nagłówki „Czekają ponad dobę” i „Nowe”.
- Nowy token `pillDanger*` (czerwony akcent pilnego terminu).

**Powód:** „wszystko się zlewa, w sekcji sprawy/klienci nie odróżnisz jednego od
drugiego”. Identyczne szare awatary i jednakowe karty zmuszały do czytania każdego
nazwiska; pilna sprawa wyglądała jak ta, w której nic się nie dzieje, a klient bez
otwartego leada był osiągalny tylko przez wyszukiwanie.

**Czego nie ma (brak danych w backendzie):** rodzaju sprawy (kolor/ikona
legalizacja–karna–deportacja) i daty zmiany statusu („czekamy od 9 dni”).

**Cofnięcie:** `PersonAvatar(style: .person)` zamiast `.identity`, usunięcie trybu
`.clients` z `ClientListMode` i powrót `CaseCard` do wersji z 0.3.0.

---

### D-35 · „Klienci”: terminy po czasie, przesunięcia, „bez ruchu” — **28.09.2026**

**Treść:**
- Niezakończony **termin w sprawie** z ostatnich 30 dni to najwyższy poziom pilności
  (`CaseUrgency.Level.missed`): czerwona plakietka „minął wczoraj / minął 3 dni temu”,
  pierwszy w „Wymaga uwagi”. Wcześniej sprawa po terminie lądowała w „W toku”.
- Termin sprawy bez wpisanego klienta (np. rozprawa z kalendarza sądu) liczy się dla
  właściciela sprawy — kartoteka pokazuje go i oznacza klienta jako „Wymaga uwagi”.
- Kartoteka: przesunięcie w prawo — „Zadzwoń” / „WhatsApp”, w lewo — „Termin”.
  Na kartach spraw w lewo — „Termin” w tej sprawie.
- Chip „Bez ruchu” (aktywna sprawa starsza niż 30 dni, zero terminów od miesiąca
  i przed nami) — widoczny tylko, gdy ktoś taki jest.
- Wyszukiwanie po numerze telefonu (same cyfry, z +48 lub bez); w trybie Klienci
  wyniki obejmują też zgłoszenia.
- Kafelek „czeka ponad dobę” przewija do tej grupy zamiast dublować „do obsługi”.
- Zamknięte sprawy od najnowszych.
- Liczenie (pilność, filtry, liczniki) raz przy wczytaniu: `ClientsModel.make`.

**Cofnięcie:** `missedEvents: [:]` w `CaseBoard.make`, usunięcie `.stale`
z `ClientDirectoryFilter` i `swipeActions` z wierszy kartoteki.

---

### D-36 · Ruch, szkielet ładowania, „Po terminie” — **audyt 28.09.2026**

**Treść:** przesuwana pigułka w segmentach i chipach, odbicie ikony wybranej
zakładki i przenikanie zakładek, optymistyczne odhaczenie zadania, szkielet kart
zamiast `ProgressView`, ikona ✓ / ! w komunikatach, karta „Po terminie” na
„Dzisiaj”, „Załatwione” w szczegółach terminu, pilność i kontakt na ekranie
sprawy, wszystkie sprawy na karcie klienta. Szczegóły:
`docs/ios/AUDYT_DESIGN_2026-09-28.md`.

**Powód:** aplikacja reagowała skokiem i nie pokazywała przegapionych terminów.

**Cofnięcie:** `EmmaMotion` → `nil`-owe animacje; `LoadingState` do wersji
z `ProgressView`; usunięcie `missedDeadlinesCard` i `markFinished`.

### D-37 · Zieleń WhatsAppa na liście rozmów — **decyzja właściciela 02.10.2026**

**Treść:** `EmmaTheme.chatGreen` (`#1DAA61`) — godzina i licznik nowych
wiadomości, kropka „bez odpowiedzi” i „Szkic:” w podglądzie wiersza rozmowy
(`MessagingComponents.swift`, wersja 0.15.1). Referencja nie ma tego koloru.

**Powód:** lista rozmów ma wyglądać jak w WhatsAppie, z którego kancelaria
przychodzi; zielony sygnał „twój ruch” jest tam znany bez nauki.

**Wpływ:** kontrast `#1DAA61` na białym tle to ok. 3,0:1 — poniżej 4,5:1
dla tekstu. Akceptowalne tylko dla krótkich, pogrubionych etykiet (godzina,
licznik, „Szkic:”); nie używać do treści.

**Kontrola:** `scripts/design-token-diff.py` zna ten kolor z listy
`REGISTERED_COLOURS` i wypisuje go jako zarejestrowany zamiast błędu.

**Cofnięcie:** `chatGreen` → `EmmaTheme.primary` albo inny token z referencji
i usunięcie wpisu z `REGISTERED_COLOURS`.

---

## Czego ten rejestr nie zawiera

Nie zawiera porównania zrzutów ekranu z referencją **piksel po pikselu**. Zrzuty są
wykonane (`docs/ios/screenshots/`, etapy 1–4), ale nie ma narzędzia zestawiającego je
z `reference/prototype`; ocena opiera się na pomiarach (OCR + geometria ramek) i na
kaskadzie CSS referencji. Ocena wizualna „na oko” wymaga człowieka albo modelu z
obsługą obrazu — model prowadzący etapy 1–4 nie ma wejścia obrazowego.

