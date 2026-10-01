# Audyt „oczami karnisty” — 01.10.2026

**Perspektywa:** adwokat prawa karnego i cudzoziemców. Praca nad sprawą ma być
łatwa i przyjemna: jedno dotknięcie zamiast formularza, aplikacja pamięta za
adwokata o datach, których przegapienie kończy się źle.

## 0. Stan wydań przed audytem

Od 0.9.3 kompilacja w CI padała (podwójny atrybut `@ViewBuilder`
w `CaseScreen.swift`), więc TestFlight stał na **0.9.1**, a wersje 0.9.2–0.9.6
nie dotarły na telefon. Testy UI wyglądały na zielone, bo krok ma
`continue-on-error`.

Naprawione, a CI dostało dwie zmiany:

- błędy kompilatora trafiają do adnotacji przebiegu (widać je w podsumowaniu
  i w API `check-runs` bez logowania),
- workflow „Emma · iOS” biegnie też na gałęziach `feat/**` — zmiany można
  sprawdzić przed wysłaniem do TestFlight.

## 1. Najważniejsze wnioski

1. **Aplikacja nie znała sprawy karnej.** Sprawa miała trzy statusy i nic
   więcej: ani rodzaju, ani etapu, ani roli klienta. Od nich zależy, jakie
   terminy w ogóle biegną.
2. **Areszt i koniec legalnego pobytu nie miały gdzie mieszkać.** Dwie daty,
   których przegapienie jest najdroższe, musiały udawać zwykły termin
   w kalendarzu.
3. **Plik od klienta był pustym dymkiem.** Typ wiadomości (zdjęcie, dokument,
   nagranie) przychodził z backendu, ale żaden ekran go nie używał — zdjęcie
   wezwania wyglądało jak pusta wiadomość.
4. **Kalkulator nie liczył miesięcy** (subsydiarny akt oskarżenia) i nie znał
   zażalenia na areszt.
5. **Po rozprawie nic się nie działo.** Notatka, kolejny termin i zamknięcie
   terminu wymagały trzech wejść w trzy miejsca.

## 2. Wdrożone (0.10.0)

| Obszar | Co | Gdzie |
|---|---|---|
| Profil sprawy | rodzaj (karna, wykonawcza, pobytowa, deportacyjna, inna), etap (zależny od rodzaju: „Wojewoda”, „Straż Graniczna”, „Sąd penitencjarny”…), rola klienta (tylko w karnej) — chipy na jedno dotknięcie, każde pytanie dopiero gdy ma sens; zmiana etapu sama przestawia rolę (podejrzany → oskarżony), chyba że wybrano ją ręcznie; etykieta sygnatury i organu idzie za etapem („Sygnatura prokuratury”, „Znak sprawy”) | `CaseProfile.swift`, `CaseSettingsSheet` |
| Areszt / legalny pobyt | przełącznik i data w ustawieniach sprawy; karta z licznikiem dni w sprawie i na „Dzisiaj” (≤ 30 dni, czerwona w ostatnim tygodniu, pulsuje); zdanie o dniu w ostatnim tygodniu; powiadomienia 14/7/3/1/0 dni o 8:30, dotknięcie otwiera sprawę; „Dodaj do kalendarza” w menu karty | `CaseWatch`, `CaseWatchCard`, `EventReminderScheduler` |
| Kalkulator terminów | terminy miesięczne (art. 123 § 2 k.p.k. — ten sam dzień miesiąca, a bez niego ostatni dzień), zażalenie na areszt, zażalenie na umorzenie, subsydiarny akt oskarżenia, skarga kasacyjna do NSA; czynności w kolejności etapu sprawy; sąd sprawy podpowiada miejsce | `ProceduralDeadlines` |
| Pliki z WhatsApp | karta pliku w dymku (ikona, nazwa, rodzaj); menu: „Otwórz w WhatsApp”, „Dołącz do akt sprawy” (notatka „Od: … — dokument · wyrok.pdf”), „Policz termin od doręczenia” (formularz z kalkulatorem i datą wiadomości); listy pokazują „Dokument · wyrok.pdf” zamiast pustego tekstu | `Messaging.swift`, `MessageBubble`, `ThreadScreen` |
| Po rozprawie | na „Dzisiaj” karta „Jak poszło?” po zakończonym, niezamkniętym terminie w sprawie: Notatka · Kolejny termin · Załatwione | `DayAgenda.debrief`, `TodayScreen` |
| Spotlight | sprawy (tytuł, sygnatura, sąd, klient) i klienci w wyszukiwarce iPhone'a; otwarcie po Face ID; indeks z ochroną `.complete` (nieczytelny przy zablokowanym telefonie), kasowany przy wylogowaniu, wyłączony w Demo | `SpotlightIndex` |

Pliki od klienta zostają w WhatsApp Business — zgodnie z rekomendacją
`research/whatsapp-partnerzy-i-koszty.md` §9 (wariant 1): Emma zna rodzaj
i nazwę pliku, nie pobiera go przez relay dostawcy.

## 3. Backend — co musi dojść (kontrakt w `api/emma-mobile-api.yaml`)

Aplikacja działa ze starszym serwerem: pola są opcjonalne, zapis bez profilu
nie wysyła nieznanych kluczy, a gdy serwer nie odeśle zapisanego profilu,
aplikacja mówi to wprost („Serwer nie obsługuje jeszcze rodzaju, etapu i dat
sprawy”) zamiast udawać sukces.

1. `LegalCase` i `PATCH /cases/{id}`: `kind`, `stage`, `client_role`,
   `custody_until`, `legal_stay_until`. Pusty tekst czyści pole, brak klucza —
   bez zmiany.
2. `Message`: `attachment_name` (nazwa pliku z webhooka WhatsApp).

## 4. Zablokowane poza kodem

| Rzecz | Dlaczego stoi | Co trzeba zrobić |
|---|---|---|
| Push o nowej wiadomości WhatsApp | wymaga capability Push w App ID, nowego profilu dystrybucyjnego (sekret `IOS_DISTRIBUTION_PROFILE_BASE64`) i klucza APNs po stronie backendu | właściciel: włączyć Push Notifications w Apple Developer, wygenerować profil i klucz `.p8`; potem trasa `POST /devices` w backendzie i rejestracja w aplikacji |
| Widżet i Live Activity „Następny termin” | rozszerzenie widżetu to osobny target z własnym profilem dystrybucyjnym i App Group — CI podpisuje dziś jeden profil | właściciel: App ID rozszerzenia, App Group, profil; potem target w `project.yml` |
| Tryb ciemny | bramka `design-token-diff.py` przepuszcza tylko kolory z referencji prototypu, a referencja nie ma palety ciemnej; zrzuty z CI są dostępne tylko po zalogowaniu, więc paleta nie dałaby się obejrzeć przed wydaniem | decyzja właściciela: ciemna paleta w referencji (albo zgoda na wyjątek w bramce) i przegląd zrzutów |

## 5. Do sprawdzenia na telefonie

- Ustawienia sprawy: chipy zawijają się na SE; przełącznik aresztu i data.
- Karta pliku w wątku: menu po dotknięciu; „Policz termin od doręczenia”
  otwiera „Termin w sprawie” z datą wiadomości.
- Spotlight: wpisać sygnaturę — wynik otwiera sprawę po Face ID; po
  wylogowaniu wyników nie ma.

## 6. Asystent głosowy (0.11.0)

Przegląd 01.10.2026. Emma w rozmowie widziała klientów, sprawy, zadania,
kalendarz i zgłoszenia, ale nie miała dostępu do reszty aplikacji.

| Brak | Skutek | Teraz |
|---|---|---|
| Model nie znał dzisiejszej daty | „zadanie na jutro”, „termin od piątku” dostawały datę zgadniętą | instrukcja w tokenie zaczyna się od „Dziś jest …” (Europe/Warsaw) |
| Brak dostępu do WhatsApp | „kto pisał?”, „co napisał Zenon?” — bez odpowiedzi | `list_conversations`, `get_conversation` (pliki po rodzaju i nazwie) |
| Profil sprawy niewidoczny | rodzaj, etap, rola, areszt i pobyt z 0.10.0 nie docierały do rozmowy | pola w `search_cases` / `get_case`; `list_case_watches`; `case_watches` w przeglądzie dnia |
| Wiadomość do klienta — „nie da się głosem” | adwokat musiał sam wejść w rozmowę i pisać | `app_draft_reply`: szkic w polu odpowiedzi rozmowy, wysyła adwokat |
| Termin w kalendarzu — tylko tekstowo | | `app_prepare_event`: wypełniony formularz, zapis w formularzu |
| Liczenie terminów „w pamięci” modelu | ryzyko złej daty (soboty, święta) | `app_compute_deadline` — ta sama arytmetyka co kalkulator w formularzu |
| Skrót „Odpowiedz” przy prawdziwym backendzie | karta „Wiadomość” odrzucana (422) — skrót kończył się błędem | szkic trafia w pole odpowiedzi rozmowy WhatsApp |

Szybkość: narzędzia CRM odpowiadają na serwerze w 2–15 ms (audyt produkcji),
więc czas zależy od liczby rund modelu. Instrukcja każe wywoływać niezależne
narzędzia równolegle i używać jednego `get_today_overview` przy pytaniach
o dzień. Przegląd dnia zawiera też areszty i pobyty, więc to jedno wywołanie
mniej.

Granica się nie zmienia. Żadne narzędzie nie zapisuje, nie wysyła i nie daje
zgody: zapis wymaga przycisku na karcie, wysyłka przycisku w rozmowie, termin
przycisku w formularzu.

## 7. Emma śledzi ekran, zmiany sprawy głosem, akta w telefonie (0.12.0)

- **Kontekst rozmowy idzie za ekranem.** Karta klienta, sprawy albo rozmowy
  otwarta w trakcie rozmowy staje się kontekstem Emmy („dodaj notatkę do tej
  sprawy”). Wcześniej kontekst ustawiał się raz, przy starcie.
- **`app_update_case`**: „areszt przedłużony do 12 grudnia”, „sprawa poszła do
  apelacji” otwiera ustawienia sprawy z wpisanymi zmianami. Zapis przyciskiem
  „Zapisz”. Data aresztu bez rodzaju sprawy ustawia rodzaj „karna”, bo inaczej
  formularz by ją zgubił.
- **`app_open_screen`**: kalendarz na wskazanym dniu, ekran zgłoszeń.
- **Akta sprawy** (zakładka „Akta”): skan aparatem (VisionKit) do jednego PDF
  albo plik z Plików, nazwa i folder, potem „Zapisz w aktach”. Lista z panelu
  ze statusami pism, podgląd QuickLook (kopia z ochroną `.complete`, usuwana
  po zamknięciu). Backend: `GET/POST /cases/{id}/files`, `GET /files/{id}`.
  Te same limity, sprawdzenie typu po sygnaturze i ten sam skan AV co w panelu
  (wspólna funkcja `saveUploadedFiles`).

**Do decyzji właściciela:** na produkcji `UPLOAD_SCAN_MODE=disabled`, a demon
ClamAV nie działa. Pliki z panelu i z telefonu nie są skanowane antywirusem.
Włączenie wymaga uruchomienia `clamd` (około 1 GB RAM) i zmiany trybu na
`required`.
