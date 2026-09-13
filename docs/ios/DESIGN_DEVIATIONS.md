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

## Czego ten rejestr nie zawiera

Nie zawiera porównania zrzutów ekranu, bo **nie zostały wykonane** — brak macOS
i symulatora (patrz `BUILD_AND_DEVICE_STATUS.md`). Ocena zgodności wizualnej opiera się
na kaskadzie CSS referencji, pomiarach plików czcionek i przeglądzie komponentów.
Pierwsze realne porównanie obrazu jest pierwszym punktem listy po uruchomieniu na Macu.

