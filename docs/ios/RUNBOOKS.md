# Runbooki — sytuacje, które wymagają decyzji człowieka

Krótkie procedury na moment, gdy coś idzie nie tak. Każda mówi wprost, **czego nie
wolno zrobić**, bo w tym projekcie najdroższe błędy to te nieodwracalne: wysłanie
wiadomości do klienta, utrata historii rozmów i pokazanie sukcesu, którego nie było.

---

## R-1 · Niepewny wynik wykonania akcji

**Objaw:** karta akcji pokazuje „Sprawdzamy status wysyłki”, a nie „Wykonano”.

**Co robić:**
1. Nie ponawiać. Powtórzenie bez rozstrzygnięcia może wysłać drugą wiadomość.
2. Odczytać stan wykonania po identyfikatorze akcji (`GET /actions/{id}/execution`).
3. Sprawdzić u dostawcy, czy wiadomość wyszła (identyfikator dostawcy).
4. Dopiero po ustaleniu faktu: oznaczyć jako wykonane albo jako nieudane do ponowienia.

**Czego nie wolno:** pokazać „wysłano”, bo minęło dużo czasu. Brak potwierdzenia to brak
potwierdzenia, także po godzinie.

---

## R-2 · Wygląd przestał zgadzać się z referencją

**Objaw:** zrzut ekranu różni się od prototypu.

**Co robić:**
1. Ustalić, czy różnica jest w implementacji, czy w referencji.
2. Jeśli w implementacji — naprawić implementację.
3. Jeśli to świadoma decyzja — dopisać wpis (`D-nn`) do `docs/ios/DESIGN_DEVIATIONS.md`
   z powodem i sposobem cofnięcia.

**Czego nie wolno:** aktualizować wzorca ani progu porównania po to, żeby różnica
przestała być widoczna. To zamienia regresję w fałszywy spokój.

---

## R-3 · WhatsApp: proces prosi o zmianę lub migrację numeru

**Objaw:** ekran Meta proponuje przeniesienie numeru, ponowną weryfikację z utratą
historii albo usunięcie aplikacji WhatsApp Business.

**Co robić:** **zatrzymać proces.** Zapisać dokładny komunikat, zrzut ekranu i wrócić
z pytaniem do właściciela.

**Czego nie wolno:** kontynuować „na próbę”. Numer obsługuje realnych klientów,
a utraconej historii rozmów nie da się odtworzyć. Szerszy kontekst:
`docs/ios/WHATSAPP_ONBOARDING.md`.

---

## R-4 · Dostawca głosu niedostępny

**Objaw:** rozmowa nie startuje, backend zwraca `503` albo sesja się nie łączy.

**Co robić:**
1. Pokazać użytkownikowi prawdziwy stan („połączenie nie powiodło się”), nie spinner w nieskończoność.
2. Sprawdzić, czy problem jest po stronie dostawcy, czy tokenu (wygaśnięcie, odwołanie sesji).
3. Umożliwić pracę dalej bez głosu: dyktowanie tekstu, przyciski w interfejsie.

**Czego nie wolno:** udawać połączenia ani podstawiać odpowiedzi modelu w miejsce rozmowy.

---

## R-5 · Mikrofon przestał działać w trakcie pracy

**Objaw:** użytkownik odebrał uprawnienie mikrofonu, gdy karta akcji była otwarta.

**Co robić:** zostawić propozycję na ekranie i zablokować wyłącznie zgodę głosową.
Zatwierdzenie przyciskiem w interfejsie nadal działa. Wyjaśnić w komunikacie, co się stało.

**Czego nie wolno:** usuwać propozycji — użytkownik straciłby przygotowaną treść
z powodu, który nie ma z nią nic wspólnego.

---

## R-6 · Wylogowanie albo zmiana konta na tym samym urządzeniu

**Objaw:** inny prawnik loguje się na tym samym iPhonie.

**Co robić (kolejność ma znaczenie):**
1. Zakończyć sesję głosową i zwolnić mikrofon.
2. Odwołać sesję urządzenia (`POST /auth/revoke`).
3. Wyczyścić stan lokalny: historię rozmowy z Emmą, szkice, kursory odczytu, tokeny.
4. Pobrać dane nowego użytkownika od zera.

**Czego nie wolno:** pozostawić liczników nieprzeczytanych ani historii rozmowy
poprzedniej osoby. To nie jest tylko błąd wyświetlania — to ujawnienie cudzych spraw.

---

## R-7 · Fałszywe „dostarczono” w demo

**Objaw:** w wersji demo ktoś zgłasza, że wiadomość „poszła do klienta”.

**Co robić:** przypomnieć, że demo nie ma połączenia z WhatsApp, a statusy są przykładowe.
Wskazać stopkę listy rozmów, która mówi o tym wprost, oraz braki w
`docs/ios/IMPLEMENTATION_STATUS.md`.

**Czego nie wolno:** włączać automatycznych odpowiedzi do prawdziwych klientów dlatego,
że polecenie adwokata działa poprawnie. Autonomiczny autoresponder to inna polityka
i inna decyzja właściciela.

---

## R-8 · „Wszystko działa” przed pierwszym uruchomieniem w Xcode

**Objaw:** w rozmowie pada stwierdzenie, że aplikacja działa, choć nie było kompilacji.

**Co robić:** pokazać `docs/ios/BUILD_AND_DEVICE_STATUS.md`. Widoki SwiftUI w tym
środowisku zostały wyłącznie prze-parsowane — kod nie został sprawdzony przez typy.

**Czego nie wolno:** deklarować kompilacji, uruchomienia na symulatorze ani testu na
iPhonie bez wykonania tych kroków.

---

## R-9 · Podgląd na Linuksie pokazuje coś innego niż prototyp

**Objaw:** w `http://127.0.0.1:8098/` element wygląda inaczej niż w prototypie
(`reference/prototype/index.html`).

**Co robić:**
1. Sprawdzić, czy to podgląd, czy kod. Podgląd jest rekonstrukcją w HTML — błąd
   w podglądzie **nie** jest jeszcze błędem aplikacji.
2. Od 0.22.0 referencja HTML nie jest wzorcem (koniec kontraktu, patrz
   `REDESIGN_IOS26_2026-10-10.md`). `python3 scripts/check-color-tokens.py`
   sprawdza tylko, czy kolory pochodzą z motywu.
3. Jeśli różnica jest w kodzie — naprawić kod i token, nie podgląd.
4. Jeśli różnica jest w podglądzie — naprawić podgląd (to tylko narzędzie).

**Czego nie wolno:** uznawać przejścia pomiaru renderu za dowód zgodności z referencją.
Pomiar sprawdza, czy strona się nie rozjeżdża, a nie czy wygląda jak prototyp.

---

## R-10 · Podgląd nie chce się zbudować albo pokazuje stare dane

**Objaw:** `start-preview.sh` kończy się błędem, strona jest pusta albo pokazuje dane
z poprzedniej wersji.

**Co robić:**
1. Sprawdzić, czy Swift jest widoczny: `swift --version`. Skrypt sam dodaje
   `~/.local/swift/usr/bin` i `~/.local/libshim`, jeśli nie ma go w `PATH`.
2. Uruchomić sam eksporter: `swift run EmmaPreviewExport` (w `ios/`). Błąd kompilacji
   oznacza, że zmienił się model domenowy — poprawić `EmmaPreview/Export.swift`.
3. Przebudować podgląd: `python3 scripts/build-preview.py`. Strona nie odświeża się sama.
4. Sprawdzić, czy port nie jest zajęty: `PORT=8099 ./scripts/start-preview.sh`.
5. Gdy brak przeglądarki: `python3 scripts/verify-preview-render.py` powie wprost,
   że nie zmierzył renderu — wtedy podgląd jest wyłącznie wygenerowany, a nie sprawdzony.
