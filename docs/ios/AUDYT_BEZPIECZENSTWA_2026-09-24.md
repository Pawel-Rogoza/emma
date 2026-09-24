# Audyt bezpieczeństwa aplikacji Emma — 24.09.2026 (wersja 0.3.0 → 0.3.1)

Zakres: całe repozytorium `emma` — aplikacja iOS (`ios/Emma`, 29 tys. linii Swift),
testy, skrypty, workflowy GitHub Actions, konfiguracja `.xcconfig`/`Info.plist`,
dokumentacja i historia gita (skan sekretów), prototypy webowe.

Poza zakresem: kod backendu (`adwokat-app-project`). W tej sesji nie było do niego
dostępu, więc punkty, które zależą od serwera, są wypisane osobno w sekcji
„Do sprawdzenia w backendzie”. Nie przeczytano też pliku
`ios/Emma/Features/Auth/LoginScreen.swift` (odczyt zablokowały uprawnienia sesji).
Wnioski o `LockScreen` wynikają z miejsc jego użycia.

Model zagrożeń: telefon prawnika z danymi klientów kancelarii (tajemnica
adwokacka, RODO). Napastnicy: osoba z fizycznym dostępem do odblokowanego
telefonu, autor treści zgłoszenia ze strony (pole formularza, treść rozmowy
czytana przez model), model językowy sterujący aplikacją (prompt injection),
łańcuch dostaw CI.

## Podsumowanie

| # | Waga | Znalezisko | Stan |
| --- | --- | --- | --- |
| S1 | **Wysoka** | Ekran blokady leżał pod otwartymi arkuszami: formularz lub szczegół był widoczny i edytowalny bez Face ID | Naprawione |
| S2 | **Wysoka** | Dotknięcie powiadomienia o terminie przy zablokowanej aplikacji otwierało szczegóły nad blokadą | Naprawione (ta sama poprawka) |
| S3 | Średnia | Wylogowanie po ponad 30 min bezczynności nie unieważniało sesji na serwerze (token odświeżania zostawał ważny) | Naprawione |
| S4 | Średnia | „Tak” z transkrypcji mowy zatwierdzało akcję jako `direct_ui_button`, z pominięciem reguł zgody głosowej | Naprawione |
| S5 | Średnia | Przypomnienia z nazwami klientów przeżywały wylogowanie | Naprawione |
| S6 | Średnia | Workflow TestFlight: akcja zewnętrzna przypięta tagiem, brak środowiska chronionego dla sekretów podpisu | Zalecenie |
| S7 | Niska | Wstrzyknięcie parametrów do `mailto:` z adresu e-mail z formularza strony | Naprawione |
| S8 | Niska | Identyfikatory od modelu (`app_open_case`, `app_open_client`) trafiały do ścieżki URL bez walidacji (`../`) | Naprawione |
| S9 | Niska | Odpowiedzi API mogły trafiać do `URLCache` na dysku | Naprawione |
| S10 | Niska | Nadpisanie adresu backendu argumentem startowym działało w buildzie wydawniczym | Naprawione |
| S11 | Niska | Sesja w pęku kluczy przeżywała reinstalację aplikacji | Naprawione |
| S12 | Niska | Treść przypomnień (klient, termin) widoczna na ekranie blokady telefonu | Zalecenie |
| S13 | Niska | Brak podglądu prywatności w stanie `.inactive` (przełącznik aplikacji) | Częściowo (S1) + zalecenie |
| S14 | Informacyjna | Tokeny w pęku kluczy nie są związane z biometrią | Zalecenie |
| S15 | Informacyjna | `BackendRepositoryError.decoding` pokazuje w UI surowy opis błędu dekodera | Zalecenie |
| S16 | Informacyjna | Odświeżenie zakończone 403 nie kończy sesji lokalnie | Zalecenie |

Co jest zrobione dobrze (sprawdzone, bez zmian): tokeny w pęku kluczy z
`AfterFirstUnlockThisDeviceOnly`, bez synchronizacji iCloud; brak wyjątków ATS
(tylko HTTPS); brak kluczy dostawców w aplikacji i w historii gita; token Gemini
efemeryczny z backendu, model i narzędzia przypięte po stronie serwera; nazwa
narzędzia od modelu filtrowana wyrażeniem `^[a-z_]{1,48}$`; narzędzia `app_*`
działają tylko na propozycjach z bieżącej rozmowy (edycja/anulowanie szukają
akcji lokalnie); zgody „od modelu” nie ma w kodzie; brak logowania danych
wrażliwych; brak `URL scheme`/universal links (brak powierzchni deep linków);
tekst z backendu nie jest renderowany jako Markdown; rozmowa głosowa kończy się
przy przejściu w tło i przy wylogowaniu; sekrety podpisu w CI sprzątane `trap`.

## Szczegóły i poprawki

### S1, S2 — Blokada pod arkuszami (wysoka)

**Mechanizm.** `EmmaApp` pokazywał `LockScreen` jako warstwę `ZStack` nad
`RootShell`. Wszystkie formularze (`NoteSheet`, `EventDetailSheet`,
`TaskDetailSheet`, `ProfileSheet`…) są prezentowane przez `.sheet(item:)`.
UIKit prezentuje arkusz w osobnym kontrolerze **nad** całą hierarchią widoków
okna, więc warstwa blokady była pod nim. `.allowsHitTesting(false)` na powłoce
nie działa na zaprezentowany arkusz.

**Skutek.** Otwarty formularz → wyjście do innej aplikacji → powrót: arkusz
widoczny i edytowalny bez Face ID (np. notatka o kliencie, szczegóły terminu,
profil z wylogowaniem). Test `LockPreservesWorkUITests` to maskował:
`if unlock.isHittable { unlock.tap() }` — przycisk był niedotykalny właśnie
dlatego, że zasłaniał go arkusz.

Druga ścieżka: `EventNotificationRouter` po dotknięciu przypomnienia woła
`dependencies.present(.eventDetail(...))`. Przy zablokowanej aplikacji arkusz
otwierał się nad blokadą — szczegóły terminu bez Face ID.

**Poprawka.** `ios/Emma/App/LockOverlayWindow.swift`: gdy powłoka już żyje,
blokada jest w osobnym `UIWindow` o poziomie `.alert + 1`, z nieprzezroczystym
tłem i `accessibilityViewIsModal`. Zasłania arkusze i alerty aplikacji, nie
niszczy stanu pod spodem (zachowuje cel poprawki A8 z audytu 23.09). Okno
pokazujemy synchronicznie przy `.background`, więc zrzut do przełącznika
aplikacji też go zawiera. Test UI wymaga teraz, żeby przycisk odblokowania był
dotykalny.

### S3 — Wylogowanie bez unieważnienia na serwerze (średnia)

`MobileSessionKeeper.signOut` wysyłał `revoke` z bieżącym tokenem dostępu.
Token żyje 30 minut; po dłuższej bezczynności serwer odpowiadał 401, a
`MobileAuthClient.revokeSession` traktuje 401 jako „już wylogowany”. Lokalnie
sesja znikała, na serwerze token odświeżania zostawał ważny do wygaśnięcia —
czyli „Wyloguj” i „zmiana konta” nie zamykały sesji urządzenia.

**Poprawka.** Wygasły lub wygasający token jest najpierw odnawiany (albo
wykorzystywany jest wynik trwającego odnowienia — bez drugiego odświeżenia tym
samym, rotowanym tokenem), a wynik służy wyłącznie do `revoke` i nie trafia do
pamięci ani kluczyka. Testy: `testSignOutWithExpiredAccessTokenRefreshesBeforeRevoking`,
`testSignOutWithValidAccessTokenDoesNotRefresh`, rozszerzony
`testLateRefreshAfterSignOutDoesNotRestoreSession`.

### S4 — Zgoda z transkrypcji mowy (średnia)

`AssistantStore.handleCommand` rozpoznawał „tak”/„zatwierdź” zarówno z pola
tekstowego, jak i z transkrypcji mowy (`origin: .voice` — gdy nie mówi dostawca,
np. w oknie tuż po zakończeniu sesji), i w obu przypadkach wysyłał zgodę jako
`X-Emma-Consent: direct_ui_button`. Transkrypcja nie jest dotknięciem — „tak”
mógł powiedzieć telewizor albo klient na głośniku. Omijało to reguły, które
kod już ma dla głosu: uzbrojona prezentacja (`armedPresentationID`) i
`voiceWritesRevoked`.

**Poprawka.** Zgoda z transkrypcji idzie jako `authenticatedVoiceTurn` i
podlega regułom głosu; wpisane „tak” zostaje `direct_ui_button`.

### S5 — Przypomnienia po wylogowaniu (średnia)

Zaplanowane powiadomienia (`emma.event.*`) z tytułem terminu i nazwą klienta
zostawały po wylogowaniu i dalej pojawiały się na ekranie blokady.
**Poprawka:** `EventReminderScheduler.removeAll()` zdejmuje zaplanowane i
dostarczone powiadomienia Emmy przy końcu sesji (`onSessionEnded`).

### S6 — CI i sekrety podpisu (średnia, zalecenie)

`ios-testflight.yml` ma w jednym zadaniu `maxim-lobanov/setup-xcode@v1`
(przypięte tagiem) i krok z certyfikatem dystrybucyjnym, kluczem App Store
Connect i profilem. Przejęty tag akcji uruchamia się przed krokiem z sekretami
i może podmienić `distribute-testflight.sh` albo `xcodebuild` w `PATH`.
Dodatkowo `workflow_dispatch` pozwala uruchomić wysyłkę z dowolnej gałęzi.

Zalecenia (wymagają ustawień repozytorium, więc nie zostały zmienione w kodzie):

1. Przypiąć akcje do pełnego SHA commita (`actions/checkout`,
   `setup-xcode`, `upload-artifact`) i włączyć Dependabot dla `github-actions`.
2. Przenieść sekrety podpisu do GitHub Environment (np. `testflight`) z regułą
   „tylko gałąź `master`” i, opcjonalnie, wymaganym zatwierdzeniem.
3. Przypiąć wersję XcodeGen (`brew install xcodegen` bierze najnowszą).

### S7 — `mailto:` z formularza strony (niska)

`ContactLinks.mailURL` sklejał `mailto:` z adresem z publicznego formularza.
`anna@x.pl?bcc=obcy@evil.test&body=…` dopisywał ukrytego odbiorcę i treść
do wiadomości tworzonej przez prawnika, przecinek — kolejnych adresatów.
**Poprawka:** dokładnie jeden `@`, znaki lokalnej części i domeny z białej
listy, domena z kropką. Testy w `LeadWorkflowTests`.

### S8 — Identyfikatory w ścieżce URL (niska)

`BackendAPIClient` składał ścieżki przez `appendingPathComponent`, który nie
usuwa `..` ani `/`. `app_open_case`/`app_open_client` przekazują identyfikator
od modelu bez normalizacji, więc wstrzyknięta treść (np. z wiadomości klienta
czytanej przez model) mogła skierować żądanie GET z tokenem użytkownika na inną
trasę API. Zapisy (`edit`/`cancel`) były już bezpieczne, bo szukają akcji w
lokalnej rozmowie. **Poprawka:** `BackendAPIClient.isSafePath` — każdy segment
niepusty, różny od `.`/`..`, znaki `[A-Za-z0-9._:-]`; inaczej `notFound` bez
wysyłania żądania. Test `testUnsafeIdentifierIsRejectedWithoutRequest`.

### S9 — Pamięć podręczna HTTP (niska)

Klienci backendu używali `URLSession.shared`, a więc `URLCache.shared`, który
może zapisać odpowiedź GET (nazwiska, sprawy) w `Library/Caches/…/Cache.db`,
jeśli serwer nie wyśle `Cache-Control: no-store`. Plik przeżywał wylogowanie.
**Poprawka:** `URLSession.emmaAPI` bez `urlCache` i z
`reloadIgnoringLocalCacheData`, domyślna dla wszystkich klientów backendu.
WebSocket Gemini zostaje na `.shared` (nie ma czego cache’ować).

### S10 — Argumenty startowe w buildzie wydawniczym (niska)

`-EMMAApiBaseURL`, `-EMMAEnvironment`, `-EMMAVoiceProvider` działały także w
TestFlight. Wymaga to fizycznego dostępu do sparowanego urządzenia, ale skutkiem
byłoby wysłanie hasła i TOTP na obcy serwer. **Poprawka:** nadpisania tylko
przy `DEBUG || EMMA_DEMO` (testy UI i schemat Demo działają jak dotąd).

### S11 — Pęk kluczy po reinstalacji (niska)

Pęk kluczy przeżywa usunięcie aplikacji, `UserDefaults` nie. Po reinstalacji
tokeny poprzedniej instalacji leżały w kluczyku (aplikacja i tak startowała
na ekranie logowania). **Poprawka:** brak `emma.installation.id` = świeża
instalacja → czyścimy sesję w kluczyku przed utworzeniem `MobileSessionKeeper`.

## Zalecenia bez zmian w kodzie

- **S12 — treść powiadomień.** Tytuł terminu i nazwisko klienta są widoczne na
  zablokowanym telefonie. Do decyzji: treść neutralna („Termin za 30 min”) albo
  kategoria z `hiddenPreviewsBodyPlaceholder` i zalecenie ustawienia
  „Pokaż podgląd: gdy odblokowany” w iOS.
- **S13 — `.inactive`.** Blokada działa przy `.background` (świadomie, by nie
  urywać rozmowy przy Centrum sterowania). Podgląd przy przytrzymanym
  przełączniku aplikacji nadal pokazuje ekran. Można dodać samą zasłonę
  (bez blokady) w `.inactive`, z wyjątkiem trwającej rozmowy głosowej.
- **S14 — biometria w kluczyku.** Face ID jest bramką interfejsu, nie
  kryptograficzną: tokeny są czytelne po pierwszym odblokowaniu telefonu.
  Wzmocnienie: token odświeżania z `SecAccessControl(.userPresence)` i odczyt
  przy odblokowaniu; token dostępu tylko w pamięci. Wymaga przemyślenia
  odnawiania w tle.
- **S15 — komunikaty dekodowania.** `BackendRepositoryError.decoding("\(error)")`
  trafia do UI z opisem `DecodingError`, który może zawierać surowe wartości
  z odpowiedzi. Lepiej: ogólny komunikat w UI, szczegół tylko w diagnostyce.
- **S16 — 403 przy odświeżeniu.** Jeśli backend zwraca 403 dla odwołanej
  instalacji, aplikacja zostaje „zalogowana” bez możliwości wykonania żądania.
  Do ustalenia z kontraktem: 401 dla odwołanego urządzenia albo obsługa 403.
- **Rozpoznawanie mowy.** `requiresOnDeviceRecognition` jest włączane tylko
  wtedy, gdy urządzenie je wspiera — inaczej dyktowanie idzie do serwerów
  Apple. Dla tajemnicy adwokackiej warto wymagać trybu lokalnego i przy jego
  braku proponować klawiaturę.
- **Ochrona plików.** Dodać uprawnienie `com.apple.developer.default-data-protection`
  = `NSFileProtectionComplete` (dane aplikacji niedostępne przy zablokowanym
  telefonie). Po S9 na dysku zostaje niewiele, ale to tania warstwa.
- **Przypinanie certyfikatu** — opcjonalne; przy jednym własnym hoście
  (`advokat-varshava.pl`) można przypiąć klucz publiczny (SPKI) z kluczem
  zapasowym. Koszt: procedura rotacji certyfikatu.

## Do sprawdzenia w backendzie (poza zasięgiem tej sesji)

1. **Zgoda na akcje.** `X-Emma-Consent` to nagłówek wysyłany przez klienta —
   dowodem jest tylko to, że żądanie przyszło z tokenem użytkownika. Backend
   musi wiązać `confirm` z aktualnym `presentation_id` i wersją, odrzucać
   zgodę dla akcji innego użytkownika i nigdy nie wykonywać akcji z samego
   wywołania narzędzia modelu.
2. **Narzędzia głosu.** `POST /voice/tools/{name}` dostaje nazwę i argumenty
   od modelu. Wymagana biała lista po stronie serwera, autoryzacja per
   użytkownik, brak narzędzi zapisujących bez ścieżki zgody.
3. **Idempotencja tokenu rozmowy.** Aplikacja wysyła deterministyczny
   `Idempotency-Key: emma-voice-token-{session}-v{version}`. Jeśli backend
   zapisuje odpowiedzi idempotentne, zapisuje też token Gemini (sprzeczne z
   „backend nie zapisuje go”), a wznowienie po `goAway` może dostać zużyty token.
4. **`Cache-Control: no-store`** na wszystkich trasach `/api/mobile/v1/*`.
5. **Unieważnienie** — czy `revoke` unieważnia także token odświeżania i czy
   wykrywane jest ponowne użycie zrotowanego tokenu odświeżania.
6. **Gemini — warunki danych.** Z audytu 15.09: darmowy tier Gemini może
   używać treści do ulepszania produktów Google. Z danymi klientów kancelarii
   wymagany płatny tier / umowa powierzenia (RODO art. 28).
7. **Rotacja klucza Gemini i hasła testowego** z audytu 15.09 (klucz pojawił
   się w transkrypcie sesji) — potwierdzić, że wykonane.
8. **`npm audit`** w zależnościach produkcyjnych backendu (7 podatności wg
   audytu 15.09).

## Pozostałe obszary

- **Historia gita:** brak kluczy API, certyfikatów, `.p8/.p12`, `Local.xcconfig`.
  W testach są tylko hasła testowe, w runbooku — lokalne konto `example.test`.
- **Prototypy webowe** (`reference/prototype`, `emma-3d-prototype`): statyczne
  makiety z fikcyjnymi danymi, `innerHTML` z danymi przepuszczonymi przez `esc()`;
  nie są częścią aplikacji i nie przetwarzają danych kancelarii.

## Weryfikacja

- Kontrole z `ios/scripts/verify-linux-logic.sh`, które nie wymagają Swifta:
  odwołania (1530, bez braków), kontrakt API, struktura CI, martwe API (717
  składowych, brak), czytelność — bez zastrzeżeń.
- **Kompilacja i testy nie zostały wykonane.** W kontenerze audytu nie ma
  toolchaina Swift (pobranie zablokowane), a workflow `Emma · iOS` (run
  36066592854) nie dostał runnera macOS — job kończy się po ~8 s bez kroków
  i logów. Tak samo kończą się wszystkie runy macOS od 23.09, także na
  `master` i TestFlight, więc to stan konta GitHub Actions (limit/rozliczenie
  minut macOS), nie tej zmiany.
- Przed scaleniem: na Macu `bash ios/scripts/verify-linux-logic.sh`, potem
  `xcodebuild test -scheme Emma-Demo` (EmmaTests) oraz
  `-only-testing:EmmaUITests/LockPreservesWorkUITests` — ten test sprawdza S1.
  Miejsca najbardziej narażone na błąd kompilacji w Swift 6:
  `LockOverlayWindow.swift`, `@MainActor static let lockOverlay` w `EmmaApp`,
  `EventReminderScheduler.removeAll()` (`deliveredNotifications()`).
