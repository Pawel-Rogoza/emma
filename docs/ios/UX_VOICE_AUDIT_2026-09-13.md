# Emma iOS — audyt wizualny i funkcjonalny oraz plan pracy głosem

Data: 13 września 2026. Kod bazowy: `8495ca0`. Status: **audyt i specyfikacja do wdrożenia przez kolejny model; bez zmian kodu aplikacji**.

## 1. Wniosek produktowy

Emma ma spójną, spokojną oprawę i dobry fundament kontroli działań. Największy potencjał leży w skróceniu drogi od intencji do wyniku: adwokat mówi, Emma ustala brakujące szczegóły, przedstawia konkretną czynność, wykonuje ją po odpowiedniej decyzji i pokazuje rezultat.

Obecnie aplikacja jest przede wszystkim demonstracją ekranów i scenariuszy. Nie zapewnia jeszcze kompletnego przepływu „rozmawiam i załatwiam sprawy”. Samo podłączenie dostawcy głosu nie uzupełni obsługi poleceń, korekt, kontekstu, historii ani potwierdzeń.

Rekomendowany kierunek:

- **Dzisiaj:** zwięzły plan pracy i stale dostępne wejście do rozmowy.
- **Emma:** pełny widok rozmowy, bieżąca transkrypcja i karty konkretnych działań.
- **Pozostałe ekrany:** można je przeglądać podczas rozmowy; miniaturowy panel Emmy zachowuje sterowanie mikrofonem.
- **Dotyk i głos:** operują na tej samej propozycji działania, odbiorcy, terminie i wersji treści.

Zachować granat, jasne powierzchnie, zaokrąglone karty, polski język i obecny wizerunek Emmy. Zmniejszyć dekoracyjną scenę na ekranie pracy. Aktualny build pokazuje portret psa; starszy zrzut w repozytorium pokazuje kulę. Nie traktować starego zrzutu jako aktualnego wyglądu i nie wymieniać samodzielnie tożsamości wizualnej.

## 2. Zakres i wiarygodność

Wykonano przegląd SwiftUI, nawigacji, typografii, kolorów, formularzy, warstwy rozmowy i adapterów. Uruchomiono istniejący `ScreenshotCaptureUITests/testCaptureAllScreens` na iPhone 17 Pro, iOS 26.5, schemat `Emma-Demo`. Wynik: **1 test przeszedł, 0 błędów; `TEST SUCCEEDED`**. Obejrzano wszystkie 11 zapisanych obrazów. Zrzuty 01–10 pokazują ekrany do oceny; obraz 11, mimo nazwy „profil”, pokazuje ekran Dzisiaj podczas przejścia, więc **wygląd profilu nie został wiarygodnie zweryfikowany**.

Materiały: `docs/ios/screenshots/audit-2026-09-13/`. Log: `/tmp/emma-design-audit-20260913-build.log`; wynik Xcode: `/tmp/emma-design-audit-20260913.xcresult`.

Oznaczenia dowodów poniżej: **W** — obejrzany aktualny render; **K** — ustalenie z kodu; **R** — rekomendacja projektowa. Test zrzutów potwierdza przejście podstawowej trasy, nie poprawność wszystkich interakcji. Błędy logiki opisane jako K nie były osobno odtwarzane na urządzeniu.

Nie wykonano rozmowy z rzeczywistym dostawcą, wysyłki WhatsApp, testów na fizycznym iPhonie, VoiceOver, największego Dynamic Type, polskiego rozpoznawania w hałasie ani sesji ze słuchawkami. Nie deklaruję pomiaru opóźnień czy skuteczności rozpoznawania. Ocena jest eksperckim audytem, nie badaniem z adwokatami.

## 3. Problemy do rozwiązania w pierwszej kolejności

P0: blokuje wiarygodne wykonanie zadania lub grozi błędnym wynikiem. P1: częsta przeszkoda w codziennej obsłudze. P2: dalsza poprawa komfortu.

| ID | Priorytet / dowód | Ustalenie i skutek | Zalecenie / kryterium odbioru |
| --- | --- | --- | --- |
| F01 | P0 / K | `CalendarStore.load` ustawia `.loading` przed `configure`; `configure` sprawdza `phase.hasLoaded`, które wtedy zawsze jest fałszywe. Wybór dnia i przesunięcie tygodnia zostają zastąpione dzisiejszą datą. | Oddzielić jednorazową inicjalizację od odświeżania. Wybrać sobotę, przesunąć tydzień i odświeżyć: wybór ma pozostać bez zmiany. Tylko „Dzisiaj” resetuje datę. |
| F02 | P0 / K | `briefing()` zamienia błędy odczytu przez `try?` na puste kolekcje, po czym mówi o zerowej liczbie wydarzeń i braku zadań. | Odróżnić „pusto” od „nie udało się sprawdzić”. Awaria kalendarza nie może dać odpowiedzi „nie masz terminów”. Przy danych częściowych nazwać zakres dostępności. |
| F03 | P0 / K | Edycja karty ma opóźnienie 700 ms; aktywny przycisk potwierdzenia wywołuje `onConfirm()` bez przekazania bieżącego `draft`. Szybkie zatwierdzenie może dotyczyć poprzedniej treści. | Przed zatwierdzeniem zapisać i odebrać aktualną rewizję albo blokować potwierdzenie do synchronizacji. Test: edycja i natychmiastowe wysłanie muszą wykonać dokładnie widoczną treść. Tak samo traktować odsłuch. |
| F04 | P0 dla celu głosowego / K | `userTranscriptFinal` zapisuje `lastUserUtterance`; `AssistantStore.apply` nie dopisuje finalnych tur ani nowych propozycji dostawcy do historii. `armVoiceConfirmation` nie ma wywołania w aplikacji. Komentarz Store wprost nazywa zgodę głosową przyszłą funkcją. | Domknąć przepływ zdarzeń głos → historia → propozycja → korekta → zgoda → wynik. Jedno zdarzenie nie może utworzyć dwóch tur ani dwóch operacji. |
| F05 | P0 przed użyciem produkcyjnym / K | `AppDependencies.repository` ma konkretny typ `MockRepository`; `makePlaybackService()` zawsze zwraca mock. Adapter głosu istnieje, lecz nie oznacza to integracji danych ani rzeczywistego odsłuchu. | Wydzielić kontrakty danych i odtwarzania, wdrożyć adaptery produkcyjne i test z rzeczywistym odbiorcą testowym. Demo pozostaje jawne. |
| F06 | P1 / W+K | Sterowanie rozmową jest tylko na ekranie Emmy. `viewDidDisappear()` nie kończy sesji; poza nim brak panelu wyciszenia i zakończenia. | Wspólny mini-panel ponad zakładkami, widoczny również nad formularzem, jeśli mikrofon pozostaje aktywny. Zmiana zakładki nie gubi sesji ani kontroli. |
| F07 | P1 / W+K | Mikrofon rozmowy i fala dyktowania stoją obok pola bez widocznego opisu. Dock równocześnie mówi „Rozmowa głosowa”, „Połączenie: Nieaktywna” i „Mikrofon niedostępny”. | Jedno główne „Rozmawiaj”, osobny tryb pisania z opcją „Dyktuj tekst”. Stan bez sesji: „Gotowa do rozmowy”. Brak uprawnienia pokazywać dopiero, gdy rzeczywiście jest problemem. |
| F08 | P1 / W+K | Na Dzisiaj duża scena Emmy, slogan i dwa wejścia zajmują większość górnej części. Zadania nie mieszczą się w pierwszym widoku nawet na dużym telefonie. | Kompaktowa karta Emmy, najbliższy termin i widoczny skrót z liczbą zadań przed przewinięciem. Pełna scena w zakładce Emma. |
| F09 | P1 / W+K | Wiele ważnych etykiet ma 10–12 pt i słaby kontrast; dotyczy to dat, kontekstu i sterowania głosem. | Style semantyczne, większe rozmiary i kontrast z tabeli poniżej. Decyzja nie może zależeć od ledwo widocznej metadanej. |
| F10 | P1 / K | `DateField` i `TimeField` ignorują niepoprawny tekst i zachowują poprzednią wartość. „Dodaj termin na ten dzień” nie przekazuje wybranego dnia do formularza. | Natywny wybór daty/godziny, jawna walidacja i `initialDay` w trasie formularza. Widoczny termin musi być tym, który zostanie zapisany. |
| F11 | P1 / K | Wyszukiwanie rozmów filtruje ponownie już przefiltrowane `model.rows`. Usunięcie zapytania nie odtworzy utraconych pozycji. „Szukaj … wiadomości” sprawdza tylko ostatni podgląd. | Przechowywać pełny zbiór osobno. Test: wpisać nazwisko, wyczyścić i zobaczyć całą listę. Dopóki brak wyszukiwania historii, nazwać zakres uczciwie. |
| F12 | P1 / W | Na karcie klienta są dwa przyciski Wstecz: systemowy i własny. Na Zadaniach systemowy powrót i własny nagłówek tworzą nadmierną pustą strefę. | Jeden sposób budowania nagłówka i jeden powrót na ekran. Zachować gest powrotu i tytuł dostępny dla VoiceOver. |
| F13 | P1 / W | Licznik nieprzeczytanych w pierwszym wierszu Rozmów nachodzi na obszar tekstu podglądu. | Osobna kolumna dla czasu, licznika i menu; podgląd nie wchodzi w jej prostokąt. Sprawdzić długą cyrylicę i duży tekst. |
| F14 | P1 / K | `handleCommand` rozpoznaje słowa przez `contains`, wymaga dwukropka dla pełnej treści, obsługuje „jutro” w wąskiej ścieżce. Niejednoznacznego klienta każe wybrać dotykiem. Akcje obejmują reply/note/task, bez tworzenia wydarzenia. | Ustrukturyzowane intencje z uzupełnianiem pól w dialogu. Nazwiska, daty i odbiorców walidować w danych. „Dodaj spotkanie” nie może uruchamiać tylko briefingu. |
| F15 | P1 / K | Oczekująca propozycja blokuje kolejne zwykłe polecenia, a `forwardTypedTurn` jest wywoływane przed lokalną blokadą. | Zezwolić na pytania odczytowe i korekty przy zachowaniu szkicu. Wyznaczyć jednego właściciela wykonania intencji; nie przetwarzać tej samej tury niezależnie lokalnie i u dostawcy. |
| F16 | P1 / K | Arkusze szczegółów i wyboru używają `try?`; błąd może wyglądać jak nieskończone ładowanie lub pusta lista. | Wprowadzić stany ładowania, pusty, błąd i ponowienie. Formularz zachowuje niezapisany tekst po błędzie. |

### Czytelność: aktualny pomiar

Obliczenia kontrastu sRGB dla bieżących nieprzezroczystych tokenów i ich rzeczywistych teł, nie szacunek ze zrzutu:

| Token / zastosowanie | Tekst / tło | Kontrast |
| --- | --- | --- |
| `dockStatusText` | `#8A9AAC` / `#F5F7F9` | 2,68:1 |
| `dockActionText` | `#8196AD` / `#F5F7F9` | 2,83:1 |
| `emmaStatusText` | `#8395A9` / `#F5F6F8` | 2,84:1 |
| `taskDateText` | `#8B96A5` / biały | 3,00:1 |
| `contextStripText` | `#6B84A0` / `#EAF0F6` | 3,37:1 |

Przyjąć projektowy cel co najmniej 4,5:1 dla zwykłego tekstu; kontrolować też kontrast ikon i obramowań istotnych kontrolek. Zachować Dynamic Type, który już istnieje. Proponowane rozmiary bazowe: treść rozmowy i wartości 17 pt, wiersze/listy i przyciski 16–17 pt, metadane 13–14 pt, nagłówki sekcji 18–20 pt, tytuły ekranów 28–30 pt. Nie powiększać wszystkiego mechanicznie: wraz ze skalą tekstu zmieniać układ poziomy na pionowy.

Apple zaleca czytelność przy większym tekście i dostępne kontrolki; dla głównych akcji Emmy przyjąć pole trafienia minimum 44 × 44 pt, a mikrofon 56–64 pt. Aktualny przycisk kompozytora ma 43 × 43 pt. Źródła: [Apple — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [UI Design Dos and Don’ts](https://developer.apple.com/design/tips/).

## 4. Docelowy układ ekranów

### Dzisiaj

Zostawić pięć istniejących zakładek w pierwszym wdrożeniu. Dzisiaj i Emma otrzymują wyraźnie różne role. Nie dodawać szóstej zakładki; Zadania udostępnić wysoko na Dzisiaj jednym dotknięciem. Jeżeli późniejsze badanie pokaże potrzebę własnej zakładki Zadań, osobno rozważyć zastąpienie zakładki Emma globalną prezentacją rozmowy.

Kolejność treści od góry:

1. Data i krótki nagłówek; profil po prawej.
2. Kompaktowa karta Emmy: mały portret 48–64 pt, „Porozmawiaj z Emmą”, dodatkowo „Napisz”. Około 80–100 pt wysokości przy standardowym tekście, bez sztywnego limitu w dostępności.
3. „Najbliższy termin”: godzina, klient, sprawa, lokalizacja; akcja „Przygotuj mnie”. Jeżeli nie ma przyszłych wydarzeń, jasny pusty stan.
4. „Zadania” z liczbą otwartych i zaległych oraz „Wszystkie zadania”, widoczne bez przewijania przy typowym zestawie danych.
5. Dalsze terminy i pełna lista zadań. Wydarzenia minione w zwijanej sekcji. Nie chować pilnego zadania pod długą listą spotkań.

Zamiast „Zapytam o dzień” użyć „Zapytaj o dzień, terminy lub wiadomości”. Zdanie opisuje możliwość użytkownika i usuwa błąd perspektywy.

### Rozmowa z Emmą

Stały nagłówek zawiera nazwę i krótki kontekst: „Cała kancelaria” albo „Olena · KR/2026/041”. Kontekst musi odróżniać osobę od konkretnej sprawy. Widoczne polecenie „Zmień” oraz odpowiednik głosowy. Obecne mapowanie jednego aktywnego case na klienta trzeba rozszerzyć przed obsługą wielu spraw tej samej osoby.

Środek ekranu: bieżąca wypowiedź i wynik. Portret większy wyłącznie w stanie początkowym; podczas pracy mały. Długi briefing zamienić na krótką odpowiedź i listę kart: terminy, zadania, osoby oczekujące odpowiedzi. Karta otwiera właściwy rekord bez ponownego wyszukiwania.

Na dole jedna strefa sterowania. W trybie głosowym: stan, ostatnia transkrypcja, duży mikrofon, „Zakończ” oraz „Napisz”. W trybie tekstowym: pole wielowierszowe, wysłanie i jednoznaczne „Dyktuj tekst”. Przełączenie na pisanie nie wysyła szkicu i jawnie pokazuje, czy mikrofon został wyciszony. Wysłanie pustego pola jest nieaktywne.

Automatyczne przewijanie działa, gdy użytkownik jest przy końcu rozmowy. Przy czytaniu wcześniejszych tur pozostawić pozycję i pokazać „Nowa odpowiedź”. Bieżąca transkrypcja i możliwość zatrzymania mikrofonu nie mogą zależeć od przewinięcia historii na dół.

### Mini-panel podczas przeglądania aplikacji

Wspólny komponent oparty o istniejący `VoiceSessionCoordinator`, bez drugiego silnika ani drugiej subskrypcji transportu. Na ekranie Emmy nie dublować go z pełnym panelem. Na innych ekranach umieścić nad paskiem zakładek, z rezerwacją miejsca w układzie.

Zawartość: mały wizerunek, „Słucham”/„Mikrofon wyciszony”/„Emma mówi”, wyciszenie, zakończenie. Dotknięcie treści otwiera pełną rozmowę. Formularz prezentowany modalnie musi mieć dostępne sterowanie, jeśli rozmowa trwa pod spodem. Pojawienie się klawiatury nie może zasłonić zakończenia sesji.

Samo przeglądanie innej sprawy nie powinno po cichu zmieniać adresata przygotowanej wiadomości. Polecenie „Pracujmy nad tą sprawą” zmienia kontekst jawnie; propozycja przechowuje własny, niezmienny zestaw identyfikatorów do czasu korekty.

### Kalendarz i zadania

Kalendarz: zachować widok dnia i pasek tygodnia, przenieść plus do nagłówka. Dodać przejście do dowolnej daty z tytułu miesiąca; widok godzinowy dopiero w kolejnym etapie. Godzina i nazwa wydarzenia powinny być bardziej wyraziste niż awatar i status. Konflikt godzin, czas trwania, miejsce i powiązana sprawa widoczne w edycji. Typ wydarzenia „rozprawa”, „spotkanie” czy „termin czynności” ma opisywać dane; nie wdrażać automatycznego wyliczania terminów procesowych w ramach redesignu.

Zadania: sekcje Zaległe / Dzisiaj / Później, nie tylko Otwarte / Wykonane. Szybkie „Wykonaj”, „Zmień termin”, „Otwórz sprawę”. Po odhaczeniu możliwe „Cofnij” rzeczywiście odwracające zmianę. Nie dodawać fikcyjnego przydzielania osobom, jeśli domena działa nadal na wspólnym koncie — model właścicieli jest osobnym rozszerzeniem.

### Klienci, sprawa i wiadomości

Na liście klientów zastąpić „Leady” zrozumiałym „Zgłoszenia”. Wyjaśnić, że drugi segment zawiera sprawy; docelowo umożliwić wyszukanie klienta niezależnie od etapu współpracy. Skrócić nagłówki i przestrzeń nad listą. Przycisk plus zawsze przy tytule, nie w pustym osobnym wierszu.

Karta klienta: jeden powrót, mniejszy awatar, nazwisko i pilny powód kontaktu wysoko. Dodać łatwo dostępne „Dodaj zadanie” do istniejących szybkich akcji; przy dużym tekście siatka 2 kolumn zamiast ścisku w 4. „Formularz WWW” przenieść do źródła zgłoszenia — nie powinien dominować w nagłówku roboczym.

Sprawa: nad opisem eksponować następny termin i najbliższe działanie. Zachować skrót „Przygotuj mnie”. Przy `upcomingEvents.prefix(2)` dodać drogę „Wszystkie terminy tej sprawy”, zachowując filtr sprawy po przejściu.

Rozmowy: oddzielna kolumna czasu/licznika, przewidywalne wyszukiwanie, szybkie akcje odczytania i przypięcia. Status połączenia WhatsApp umieścić wysoko i zrozumiale: „Demo — wiadomości przykładowe” lub rzeczywisty stan integracji. W wątku utrzymać jasne rozróżnienie „Napisz do klienta” oraz „Poproś Emmę o pomoc”. Mikrofon w polu wiadomości oznacza dyktowanie; nie powinien niespodziewanie rozpoczynać rozmowy z asystentką.

Wiadomości ukraińskie i rosyjskie są już czytelnie renderowane. Nie przywracać automatycznych tłumaczeń usuniętych wcześniej na życzenie właściciela. Język wysyłanej treści musi być natomiast widoczny w propozycji i możliwy do zmiany głosem.

## 5. Reguły rozmowy speech-to-speech

| Stan użytkowy | Komunikat | Dostępne zachowanie |
| --- | --- | --- |
| Gotowość | „Porozmawiaj z Emmą” | Jedno dotknięcie rozpoczyna połączenie. Mikrofon nie jest opisywany jako uszkodzony tylko dlatego, że brak sesji. |
| Łączenie | „Łączę…” | Anulowanie. Widoczny brak nasłuchu, jeśli audio nie jest jeszcze gotowe. |
| Nasłuch | „Słucham” + bieżące słowa | Wycisz, zakończ, pisz. Krótka haptyka/sygnał gotowości jako uzupełnienie tekstu. |
| Przetwarzanie | „Sprawdzam dzisiejsze terminy…” | Możliwość doprecyzowania lub przerwania; przy dłuższym oczekiwaniu informacja o postępie, bez udawania wyniku. |
| Odpowiedź | „Emma mówi” + zsynchronizowany tekst | Użytkownik może wejść w słowo. Przerwanie TTS nie kończy całej sesji. |
| Doprecyzowanie | „Olena Kovalenko czy Olena Nowak?” | Odpowiedź nazwiskiem, numerem opcji lub dotykiem; utrzymanie dotychczasowej treści polecenia. |
| Propozycja | „Wiadomość do Oleny przez WhatsApp. Wysłać?” | Wyślij / popraw / anuluj. Zgoda związana z konkretną aktualną treścią. |
| Wykonanie | „Wysyłam…” / „Zapisuję…” | Nie powtarzać operacji przy ponownym „tak”. |
| Wynik | „Wysłano” / „Zapisano” / „Nie mam potwierdzenia wyniku” | Otwórz rekord, sprawdź stan. Nie utożsamiać przyjęcia przez API z doręczeniem. |
| Wyciszenie lub problem | „Mikrofon wyciszony”, „Utracono połączenie” | Jawne wznowienie albo tekst. Szkic pozostaje. |

Jedna tura pytająca powinna zwykle zawierać jedno pytanie. Nie czytać całych kart i technicznych statusów. Krótkie podsumowanie dnia, potem opcja „Rozwiń”. Użytkownik może powiedzieć „powtórz”, „krócej”, „wolniej”, „przerwij”, „wróć do wiadomości”, „pokaż tę sprawę”. Nawigacja głosowa jest oddzielną klasą intencji, nie zmianą danych.

Odczyt informacji nie wymaga zatwierdzenia. W pierwszej wersji zapis notatki/zadania ma jedno krótkie potwierdzenie kompletnej propozycji. Wysłanie wiadomości wymaga jasnej decyzji odnoszącej się do odbiorcy i treści. Późniejszy tryb szybkiego zapisu własnych odwracalnych zadań można rozważyć dopiero z historią i prawdziwym cofnięciem; nie osłabiać istniejącego mechanizmu zgód przy przebudowie UI.

Tekst „Potwierdzenie głosem jest uzbrojone dla tej prezentacji” zastąpić „Powiedz «wyślij», aby wysłać tę wiadomość” — ale dopiero po podłączeniu i sprawdzeniu tego zachowania. Gdy głos nie jest dostępny: „Wyślij przyciskiem poniżej”. Informacje o wersji, prezentacji i uzbrojeniu należą do diagnostyki.

Istniejąca aplikacja wstrzymuje obsługę po utracie aktywności i blokuje dostęp w tle. Pierwsze wydanie powinno zachować tę politykę i wyjaśniać ją użytkownikowi. Rozmowa przy zablokowanym telefonie, Siri/App Intents oraz inne wejścia systemowe to osobny etap wymagający testów i decyzji o uprawnieniach, nie obietnica obecnego planu UI.

## 6. Trzy wzorcowe przebiegi

### A. „Wyślij Olenie WhatsApp, że spóźnię się 15 minut”

1. Emma rozpoznaje zamiar, odbiorcę i treść; wyszukuje prawdziwy kontakt i kanał, nie buduje threadID według reguły demo.
2. Jeśli są dwie Oleny: „Olena Kovalenko czy Olena Nowak?”. Użytkownik odpowiada głosem, bez obowiązkowego otwierania selektora.
3. Emma przygotowuje wiadomość. Karta: odbiorca, rozróżniający kontakt/numer, WhatsApp, język, powiązana sprawa i pełna treść. Domyślny język kontaktu jest widoczny; zmiana na polski nie wymaga rozpoczynania od nowa.
4. Odczyt treści lub jej jednoznaczna prezentacja zgodnie z przyjętą polityką zgody. Pytanie: „Wysłać?”.
5. „Zmień na 20 minut” aktualizuje tę samą propozycję, unieważnia wcześniejszą zgodę i odczytuje poprawkę.
6. „Wyślij” wykonuje jedną operację. UI pokazuje kolejno stan wysyłki i potwierdzenie; „Dostarczono” tylko po takim statusie od integracji.
7. „Dodaj też zadanie, żebym dosłał dokumenty jutro” rozpoczyna kolejną czynność w jawnym kontekście Oleny.

WhatsApp wymaga osobnego przygotowania integracji biznesowej. Oficjalna dokumentacja Meta opisuje Cloud API, konto WhatsApp Business i numer firmowy; nie jest to automatyczny dostęp do dowolnego prywatnego konta w telefonie. [Dokumentacja Meta w Postman](https://www.postman.com/meta/whatsapp-business-platform/documentation/wlk6lh4/whatsapp-cloud-api).

Przed produkcją backend musi zwracać możliwości wysyłki dla konkretnego kontaktu: wolny tekst, wymagany szablon, brak uprawnienia lub brak połączenia. Interfejs pokazuje ten wynik przed decyzją o wysłaniu. Reguły okna kontaktu i szablonów sprawdzić w aktualnej dokumentacji Meta przy integracji; bezpośredni odczyt nowej strony Meta w tym audycie zwrócił HTTP 429. Nie zaszywać tutaj niezweryfikowanej polityki ani cennika. Przekazanie szkicu do zewnętrznej aplikacji, jeśli zostanie wybrane jako wariant, opisywać jako otwarcie szkicu, a nie wysłanie przez Emmę.

### B. „Jakie mam terminy na dzisiaj?”

Emma ustala datę i strefę czasową z kontekstu aplikacji; demo zachowuje swój zegar referencyjny. Przy wspólnym kalendarzu mówi „W kalendarzu kancelarii…”, a nie udaje osobistego zakresu. Po dodaniu właścicieli zakres „moje / kancelarii” musi być jawny.

Odpowiedź najpierw podaje najbliższy przyszły termin i liczbę dalszych; pełna lista jest widoczna. „A jutro?” zmienia zakres daty. „Przygotuj mnie do pierwszego” odnosi się do pierwszego elementu właśnie przedstawionej listy i otwiera kontekst właściwej sprawy. Gdy pobranie nie działa: „Nie udało mi się sprawdzić kalendarza”, z możliwością ponowienia.

### C. „Dodaj zadanie: wyślij dokumenty Olenie jutro do 14”

Propozycja zawiera tytuł, osobę/sprawę, pełną datę i godzinę. „Do 14” nie może zniknąć, jeśli obecny model przechowuje tylko datę: trzeba rozszerzyć domenę albo jawnie powiedzieć o ograniczeniu przed zapisem. „Nie, na poniedziałek” aktualizuje termin; Emma powtarza datę bezwzględną. Po „zapisz” karta zawiera link do zadania, a Dzisiaj/Zadania pokazują spójny wynik. Przypomnienie jest osobnym polem — data wykonania nie oznacza automatycznie powiadomienia.

## 7. Plan wdrożenia dla kolejnego modelu

Pracować etapami, w osobnych małych zmianach. Ten dokument jest specyfikacją przyszłych zmian, nie dowodem ich wykonania. Przed każdym etapem przeczytać aktualny kod i instrukcje repozytorium. Zachować istniejący koordynator głosu, reguły wersjonowania, idempotencję, rozdzielenie propozycji od wyniku i tryb demo. Nie kopiować starych komentarzy o „zamrożonej referencji” jako uzasadnienia utrzymania usterek opisanych tutaj.

| Etap | Zakres / pliki w `ios/Emma/` | Zależności | Warunek zakończenia |
| --- | --- | --- | --- |
| 1 — wiarygodność | F01–F03, F10–F11, F16. `Features/Calendar/CalendarScreen.swift`, `Features/Assistant/AssistantStore.swift`, `Features/Shared/EmmaActionCard.swift`, `Features/Forms/WorkSheets.swift`, `Features/Messages/MessagesScreen.swift`, `App/AppRoute.swift` | Bez backendu | Testy wyboru daty, błędu briefingu, natychmiastowej edycji/zgody, czyszczenia wyszukiwania i błędu arkusza. |
| 2 — czytelność | F09, F12–F13. `DesignSystem/EmmaTypography.swift`, `EmmaTheme.swift`, `EmmaMetrics.swift`, `EmmaComponents.swift`, `EmmaTabBar.swift`, `Features/Shared/MessagingComponents.swift`, nagłówki ekranów | Etap 1 nie jest technicznie konieczny, lecz ma pierwszeństwo produktowe | Obejrzane zrzuty na małym i dużym ekranie, duży tekst, brak podwójnego powrotu i kolizji badge. |
| 3 — dzień i listy | F08, grupowanie zadań, kompaktowe nagłówki, linki do powiązanych rekordów. `Features/Today/TodayScreen.swift`, `Features/Tasks/TasksScreen.swift`, ekrany klienta i sprawy | Etap 2 | Najbliższy termin i wejście do zadań na pierwszym widoku, 1 dotknięcie do listy zadań, listy zachowują pozycję przy odświeżeniu. |
| 4 — globalny panel | F06–F07. `App/RootShell.swift`, `Features/Shared/VoiceDock.swift`, `Features/Assistant/AssistantScreen.swift`, prezentacja arkuszy | Etap 2 | Jedna sesja; sterowanie dostępne we wszystkich zakładkach i modalach; test wyciszenia, przerwania i zakończenia; poprawne zachowanie klawiatury. |
| 5 — wspólny dialog i intencje | F04, F14–F15. `AssistantStore.swift`, `Core/Domain/Assistant.swift`, `Actions.swift`, `Core/Voice/VoiceSessionCoordinator.swift`, `VoiceEvents.swift`, `VoiceStateReducer.swift`, `AppRoute.swift` | Etap 4; uzgodniony kontrakt narzędzi | Trzy przebiegi z §6 na deterministycznych zdarzeniach. Korekta odbiorcy/terminu/tekstu, doprecyzowanie głosem, deduplikacja zdarzeń, zachowanie szkicu przy pytaniu odczytowym. |
| 6 — prawdziwe usługi | F05. `App/AppDependencies.swift`, `VoiceAdapters/VoiceServicesFactory.swift`, `ElevenLabsVoiceTransport.swift`, `BackendConversationTokenProvider.swift`, kontrakty backendu i WhatsApp | Etap 5, konta i usługi zewnętrzne | Test na iPhonie z realnym głosem oraz faktycznie odebraną wiadomością testową; prawdziwe stany wysłania i dostarczenia. Mock nie jest zaliczeniem tego etapu. |

W etapie 5 dodać wspólny model intencji: rodzaj operacji, kontekst, odbiorca, sprawa, treść, data/godzina, brakujące pola i identyfikator tury. Odczyt, nawigacja, propozycja zapisu, korekta i potwierdzenie muszą być odróżniane. Parser demo może pozostać deterministyczny za wspólnym interfejsem. Model językowy proponuje ustrukturyzowaną intencję; warstwa domenowa rozwiązuje identyfikatory, sprawdza kompletność, uprawnienia i aktualność. Wykonanie po stronie jednej wyznaczonej ścieżki backendu, a nie równocześnie telefonu i agenta głosowego.

Nie tworzyć nowej architektury głosu od podstaw. Istnieją wartościowe zabezpieczenia: oddzielenie odsłuchu od mikrofonu, odrzucanie spóźnionych zdarzeń, anulowanie zgody przy rewizji i obsługa niepewnego wyniku. Trzeba je połączyć z doświadczeniem użytkownika.

Po etapach 1–4 aplikacja może być wyraźnie wygodniejsza wizualnie, ale nadal nie wolno przedstawiać jej jako kompletnej aplikacji do wykonywania działań samą rozmową. Tę bramkę zamykają etapy 5–6.

## 8. Odbiór i testy użytkowe

Testy regresji dobierać do zmiany. Istniejący test zrzutów musi czekać na charakterystyczny element ekranu przed zdjęciem; „11-profil” dowodzi, że sam brak błędu testu nie wystarcza. Nie przepisywać wszystkich testów tylko z powodu kosmetyki.

| Scenariusz | Oczekiwany rezultat |
| --- | --- |
| Wybór dnia, następnego tygodnia, odświeżenie | Data pozostaje wybrana; formularz dziedziczy tę datę. |
| Wpisanie i usunięcie zapytania w Rozmowach | Wraca pełny zbiór i właściwy filtr. |
| Utrata sieci przy pytaniu o dzień | Brak fałszywego „wolny dzień”; jawnie niepełne/nieaktualne dane. |
| Edycja wiadomości i natychmiastowe „Wyślij” | Wysłana wyłącznie najnowsza potwierdzona wersja. |
| Dwie osoby o tym samym imieniu | Wybór głosem bez utraty treści wiadomości. |
| Przerwanie odczytu propozycji, potem „tak” | Brak wykonania nieaktualnej lub nieprzedstawionej propozycji. |
| „A jakie mam jutro terminy?” w trakcie szkicu | Odpowiedź odczytowa, szkic zachowany, możliwy powrót. |
| Zmiana zakładki, wejście do arkusza, klawiatura | Mikrofon i zakończenie rozmowy nadal pod kontrolą. |
| Telefon, odłączenie słuchawek, tło, Face ID | Stan prawdziwy i zrozumiały; szkic zachowany; brak niezamierzonego przejścia na głośnik lub zapisu. |
| Powtórzone zdarzenie końcowe / „wyślij” dwa razy | Jedna operacja i jedna karta wyniku. |
| Timeout po wysłaniu | Najpierw sprawdzenie stanu; bez automatycznego ponowienia tworzącego duplikat. |
| Duży tekst, długie nazwisko i cyrylica | Brak nakładania elementów; wszystkie decyzje i kontrolki dostępne. |

Matryca wizualna: mały ekran około 375 pt szerokości i większy iPhone; zwykły tekst i największe rozmiary dostępności; klawiatura otwarta; długie dane, puste dane, błędy; Reduce Motion i VoiceOver. Obecne wymuszenie jasnego motywu odnotować; dark mode jest P2 po poprawieniu czytelności jasnego wariantu.

Na realnym urządzeniu zmierzyć czas do gotowości mikrofonu, czas od końca wypowiedzi do pierwszego dźwięku oraz reakcję na wejście w słowo. Proponowane cele startowe do weryfikacji: sygnał po dotknięciu w 200 ms; pierwsza odpowiedź dla prostego odczytu w około 2 s w medianie; zatrzymanie mowy po przerwaniu w około 300 ms. To cele projektowe, nie uzyskane wyniki ani gwarancje dostawcy. Raportować medianę i p95, sieć oraz model urządzenia.

Pilotaż: 3–5 adwokatów wykonuje po kilka razy trzy scenariusze z §6. Mierzyć ukończenie bez pomocy, liczbę dotknięć po starcie rozmowy, liczbę doprecyzowań i pomyłki odbiorcy/terminu. Celem przepływu głosowego jest ukończenie po jednym dotknięciu startu, z doprecyzowaniem i zgodą udzielanymi mową. W kontrolowanym zestawie nie akceptować pomyłek adresata ani treści wysyłki; sama poprawna transkrypcja nie oznacza wykonania zadania.

## 9. Dalsze możliwości — P2

- Powiadomienia i przypomnienia powiązane z realną datą, godziną i strefą, z wejściem do właściwego zadania.
- Wyszukiwanie pełnej historii wiadomości oraz wyszukiwanie klientów, spraw i zadań jednym poleceniem.
- Historia działań Emmy z wynikiem i powiązanym rekordem; po ponownym otwarciu aplikacji zachowany kontekst pracy.
- Tryb dyskretny: tekstowe odpowiedzi w miejscach publicznych i jawny wybór wyjścia dźwięku; bez automatycznego odczytywania treści klienta po zmianie słuchawek na głośnik.
- Obsługa przypisania do członka zespołu dopiero po rzeczywistym modelu użytkowników i uprawnień.
- Przywracanie szkiców po przerwaniu, synchronizacja i stan ostatniego odświeżenia zasilany prawdziwymi danymi.
- Personalizacja wyglądu i animacji Emmy po zapewnieniu czytelności i płynnego przepływu głosowego.

## 10. Prompt startowy dla modelu wdrażającego

> Przeczytaj `docs/ios/UX_VOICE_AUDIT_2026-09-13.md` oraz instrukcje repozytorium. Wdrażaj plan etapami z §7, zaczynając od etapu 1. Przed zmianą potwierdź ustalenia w aktualnym kodzie. Zachowaj wizerunek Emmy, polskie nazewnictwo, pojedynczy VoiceSessionCoordinator, kontrolę zgód, wersjonowanie i idempotencję. Nie usuwaj oznaczeń demo bez prawdziwej integracji. Po każdym etapie wykonaj adekwatne testy i obejrzyj zrzuty zmienionych ekranów; zapisz wynik i ograniczenia. Nie uznawaj mocka za dowód realnego speech-to-speech ani wysłania WhatsApp. Etapy zależne od backendu prowadź zgodnie z rzeczywistym kontraktem i dostępnymi usługami, bez fikcyjnych sukcesów.
