# M1 (iOS) — logowanie do prawdziwego backendu

Data: 2026-09-14 · Gałąź: `codex/emma-ux-voice` · Backend: `docs/emma/MOBILE_API_M1_LOGIN.md` (repo backendu)
Status: **zrobione i sprawdzone end-to-end na lokalnym backendzie**; dane po zalogowaniu nadal demo (M2).

## 1. Co powstało

| Element | Plik | Rola |
|---|---|---|
| Modele i błędy | `ios/Emma/Core/Auth/MobileAuthModels.swift` | `AuthSession`/`User` wg kontraktu, `MobileAuthError` z kodami `{code, message}` i komunikatem po polsku |
| Klient HTTP | `ios/Emma/Core/Auth/MobileAuthClient.swift` | `POST /api/mobile/v1/auth/login\|refresh\|revoke`, tolerancyjne dekodowanie daty, błędy z ciała i ze statusu |
| Prowadzenie sesji | `ios/Emma/Core/Auth/MobileSessionKeeper.swift` | zapis/odczyt sesji, odświeżanie z wyprzedzeniem, sklejanie równoległych odnowień, wylogowanie, zmiana konta |
| Trwałość | `ios/Emma/Features/Auth/KeychainMobileSessionStore.swift` | para tokenów w kluczyku (`AfterFirstUnlockThisDeviceOnly`), tożsamość instalacji |
| Warstwa aplikacji | `ios/Emma/Features/Auth/AuthStore.swift` | stan `signedOut/locked/unlocked`, dwie ścieżki (Demo vs backend), token dla reszty aplikacji |
| Ekran | `ios/Emma/Features/Auth/LoginScreen.swift` | pole kodu jednorazowego **tylko** w trybie backendu, opis mówiący prawdę o tym, dokąd trafiają dane |
| Złącze | `ios/Emma/App/EmmaApp.swift`, `AppDependencies.swift` | token dostępu z `AuthStore`; koniec sesji kończy rozmowę głosową |
| Kontrakt | `docs/ios/api/emma-mobile-api.yaml` | dodane opcjonalne pole `totp` w `/auth/login` |

Kod logiki (`Core/Auth`, bez SwiftUI/`Security`) wchodzi do pakietu `EmmaCore`
(`Package.swift`), dzięki czemu `swift test` sprawdza go bez Xcode. Kluczyk
i `AuthStore` zostają w warstwie aplikacji, jak `BiometricAuthenticator`.

## 2. Decyzje

1. **Dwie ścieżki, jedno wejście.** `AuthStore.signIn(email:password:totp:)`
   wybiera backend albo walidację Demo. Widok nie zna różnicy, ale ścieżka Demo
   jest **zamknięta**, gdy skonfigurowano backend: wpuszczenie tam znaczyłoby
   „zalogowany bez sesji”, czyli aplikację, która wygląda na działającą,
   a nie może wykonać żadnego żądania.
2. **Token w kluczyku, nie w `UserDefaults`.** Kopia zapasowa i inne procesy
   w piaskownicy nie mogą zobaczyć tokenu. Aplikacja nigdy nie interpretuje
   tokenu — jest nieprzezroczysty (świadoma różnica wobec JWT).
3. **Odświeżanie z wyprzedzeniem (120 s) i sklejone.** Backend rotuje tokeny,
   więc dwa równoległe odnowienia unieważniłyby się nawzajem i wylogowały
   użytkownika; pilnuje tego test „jedno odnowienie dla równoległych żądań”.
4. **Awaria sieci nie wylogowuje, odrzucona sesja — tak.** Brak internetu
   zostawia sesję (token nadal ważny), `401` przy odnowieniu czyści ją
   i pokazuje ekran logowania. Bez tego aplikacja wyglądałaby na zalogowaną,
   nie mogąc wykonać żadnego żądania.
5. **Rozmowa głosowa nie przeżywa wylogowania.** `AuthStore.onSessionEnded`
   woła `handleUserLoggedOut`/`handleAccountSwitched` koordynatora. Przy okazji
   zniknęło martwe publiczne API (`handleAccountSwitched` nie miał wywołania) —
   kontrola `check-dead-code.py` przechodzi.
6. **Brak biometrii nie jest obejściem w trybie backendu.** W Demo brak Face ID
   wpuszcza (inaczej demo zamyka użytkownika na stałe); przy prawdziwych danych
   nie wpuszcza i mówi, co zrobić.

## 3. Dowody

**Testy jednostkowe i integracyjne (bez sieci):**
`swift test` (pakiet logiki) → **265/265 PASS**, w tym 13 testów klienta HTTP
(kształt żądania, brak hasła w adresie, mapowanie `401/429/404/500`, awaria
transportu, dekodowanie daty z milisekundami i bez) i 12 testów prowadzenia
sesji (rotacja, sklejanie, czyszczenie po `401`, wylogowanie bez sieci).
`xcodebuild test -only-testing:EmmaTests` → **336/336 PASS** (+18 testów
warstwy aplikacji: stany początkowe, komunikaty backendu, ścieżka Demo,
złącze z głosem). Pełny zestaw UI w Demo → **37 testów PASS, 2 pominięte**
(pomijane są właśnie testy integracyjne bez wskazanego backendu).

**Test end-to-end przeciw prawdziwemu backendowi** (aplikacja w symulatorze,
iPhone 17 Pro, backend `node dist/server/entry.mjs` na `127.0.0.1:4399`,
`NODE_ENV=production`, konto admina z TOTP):

| Sprawdzenie | Wynik |
|---|---|
| `BackendLoginUITests/testRealLoginReachesApp` — wpisanie e-maila, hasła i kodu TOTP w interfejsie | **PASS**, po odpowiedzi serwera pojawia się powłoka aplikacji |
| `BackendLoginUITests/testWrongPasswordShowsServerMessageAndStaysOnLogin` | **PASS**, widoczny komunikat `Nieprawidłowe dane logowania.`, brak wpuszczenia |
| Wpis w bazie backendu | `mobile_sessions`: `installation_id = 8F7B66CC-…`, `device_name = iPhone 17 Pro` |
| Audyt backendu | `mobile.login` z `meta_json = {"device":"iPhone 17 Pro","totp":true}` |

Testy integracyjne są **pomijane** (`XCTSkip`) bez zmiennej `EMMA_UI_BACKEND_URL`,
więc zwykły przebieg Demo i CI bez serwera nie kłamią zielonym wynikiem.

**Zrzuty ekranu** (`docs/ios/screenshots/m1-2026-09-14/`):
`M1-01-ekran-logowania.png`, `M1-02-po-zalogowaniu.png`, `M1-03-bledne-haslo.png`.

**Ograniczenie co do zrzutów — mówię wprost:** model, który prowadził tę sesję,
nie przyjmuje obrazów, więc **nie obejrzałem zrzutów wzrokowo**. Zamiast tego
odczytałem z nich tekst przez framework Vision (OCR) i to jego wynik jest
podstawą poniższych zdań:
`M1-02` zawiera „Dzień dobry”, „Porozmawiaj z Emmą”, „Najbliższy termin” oraz
zakładki „Klienci / Emma / Rozmowy / Kalendarz” — czyli realne wejście do
aplikacji; `M1-03` zawiera „Zaloguj się”, „Kod jednorazowy (jeśli konto go
używa)”, „6 cyfr”, „Nieprawidłowe dane logowania.” oraz stopkę „Hasło i kod
jednorazowy trafiają do serwera kancelarii…”. Na `M1-01` dolna część formularza
jest zasłonięta klawiaturą (ekran sam ustawia fokus na polu e-mail) — pełny
formularz widać na `M1-03`.

## 4. Czego ten etap **nie** robi

1. **Dane po zalogowaniu to nadal demo.** `EmmaRepository` to wciąż
   `MockRepository`; token jest pobierany i gotowy do użycia, ale żaden ekran nie
   czyta jeszcze klientów, spraw i zadań z backendu. To M2 i to jest jedyne
   miejsce, w którym ten etap mógłby wyglądać na więcej, niż zrobił.
2. **Brak zmiany konta w interfejsie.** `prepareForAccountSwitch()` istnieje
   i jest przetestowane, ale w UI nie ma jeszcze ekranu wyboru/zmiany konta.
3. **Konto musi mieć hasło.** Zaproszeni użytkownicy (passkey) nie mają
   `password_hash`, więc nie zalogują się z aplikacji — luka L11 po stronie
   backendu.
4. **Brak biometrii nie ma jeszcze alternatywy poza ponownym logowaniem** —
   docelowo hasło urządzenia, ale to osobna decyzja UI.
5. **Nie testowano na fizycznym urządzeniu** ani przez HTTPS: przebieg był na
   symulatorze i po `http://127.0.0.1`. Zasady ATS dla ruchu lokalnego nie były
   zmieniane w `Info.plist` (żadnego wyjątku nie dodano) — po podłączeniu
   prawdziwego, publicznego adresu HTTPS trzeba to potwierdzić na urządzeniu.
