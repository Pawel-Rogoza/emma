# Plan: Emma w App Store jako aplikacja niepubliczna (unlisted)

Decyzja z 2026-09-14: dystrybucja **unlisted** (dostęp tylko z linku), konto
Apple Developer Program aktywne. Unlisted **przechodzi pełny App Review** — nie
jest skrótem od recenzji, tylko od wyszukiwania. Poniżej co musi być gotowe
i w jakiej kolejności.

## Stan wyjściowy (sprawdzony w kodzie 2026-09-14)

| Element | Stan |
| --- | --- |
| `EMMA_API_BASE_URL` | **puste** w `Config/{Demo,Staging,Production}.xcconfig` → `AppConfiguration.usesMockServices` = `apiBaseURL == nil` → build pokazuje dane demo, nie dane kancelarii |
| Zapisy (zadanie, notatka, klient, termin) | `BackendRepository` rzuca `notAvailableInBackend` — backend ma trasy od M4a, aplikacja ich nie woła |
| Oznaczenia demo | 44 pliki w `Features/`; głos symulowany, wiadomości demo |
| Uprawnienia w `Info.plist` | **są**: mikrofon, rozpoznawanie mowy, Face ID |
| Bundle ID | `pl.kancelaria.emma` (+ `.demo`, `.staging`) |
| Backend publiczny | `https://advokat-varshava.pl/api/mobile/v1/...` odpowiada kontraktem, certyfikat ważny, panel 200 |
| Konto testowe dla recenzenta | brak |
| Polityka prywatności, karta App Privacy | brak |

## Zmiana decyzji (2026-09-14, później tego dnia)

Zamiast pokazywać w recenzji build bez prawdziwego głosu i wiadomości:
**wstrzymujemy wysłanie do App Review do czasu prawdziwych integracji**
(ElevenLabs, APNs, WhatsApp Business). Recenzja nie jest celem samym w sobie —
ma pokazać działającą Emmę, a nie jej zakres.

**Co to zmienia praktycznie:** nic nie stoi na przeszkodzie, żebyś miał Emmę na
swoim iPhonie wcześniej — do tego służy **TestFlight (testy wewnętrzne)** albo
**Ad Hoc**, które nie przechodzą App Review. Kolejność się nie zmienia:
najpierw podłączyć zapisy i ustawić adres backendu, potem wgrać build na
TestFlight i testować na własnym telefonie, a do App Store wysłać później,
gdy głos i WhatsApp będą prawdziwe.

### Czego potrzebuję od Ciebie do prawdziwych integracji

| Integracja | Czego brakuje |
| --- | --- |
| Głos (M5) | konto ElevenLabs + **ID agenta** + klucz API (sekret zostaje na serwerze, nigdy w aplikacji); backend wystawia wtedy `/voice/conversation-token` |
| Asystent tekstowy | klucz do modelu (Qwen/DashScope), jeśli asystent ma działać poza mockiem |
| Powiadomienia (APNs) | klucz `.p8` + **Key ID** + **Team ID** dla bundle `pl.kancelaria.emma` |
| WhatsApp (M6) | konto WhatsApp Business (Meta): numer, phone number ID, trwały token, token weryfikacji webhooka |
| App Store Connect | rekord aplikacji dla `pl.kancelaria.emma` + URL polityki prywatności |

Bez tych danych M5 i M6 mogę doprowadzić tylko do granicy „trasy i kontrakt
przetestowane”, ale **nie** zadeklaruję, że głos albo wysyłka WhatsApp działają.

## Kolejność prac

1. **Podłączyć zapisy do backendu** (trasy działają od M4a): `createTask`,
   `updateTask`, `setDone`, `createEvent`, `updateEvent`, `deleteEvent`,
   `addNote`, `createClient`, `updateClient`. Bez tego recenzent dotknie
   „dodaj” i dostanie błąd (wytyczna 2.1 — kompletność). Wymaga klucza
   idempotencji i obsługi 409 (`current_version`).
2. **Dokończyć model pod kontrakt**: termin zadania opcjonalny („bez terminu”
   w widoku), termin całodniowy bez godziny. Dziś zadanie bez terminu znika.
3. **Rozdzielić demo od produkcji**: build produkcyjny pokazuje wyłącznie to,
   co naprawdę działa (klienci, sprawy, zadania, terminy, notatki, briefing,
   wyszukiwanie). Głos i wiadomości — do decyzji: ukryte w produkcji albo
   jawnie opisane jako niedostępne. **Oznaczeń demo nie usuwamy** — zostają
   w konfiguracji Demo.
4. **`EMMA_API_BASE_URL = https://advokat-varshava.pl`** w `Production.xcconfig`
   (dopiero po kroku 1, żeby nie wypuścić builda z działającym odczytem
   i niedziałającym zapisem).
5. **Konto dla recenzenta**: e-mail + hasło, **bez TOTP** (recenzent nie ma
   jak odczytać kodu). Utworzone po stronie kancelarii, dane opisane
   w App Review Notes. Hasło ustawia `scripts/mobile-set-password.mjs`.
6. **Polityka prywatności** (URL) + **karta App Privacy**: dane klientów
   kancelarii, mikrofon, mowa, identyfikator urządzenia. Trzeba powiedzieć
   wprost, że to dane osobowe klientów przetwarzane w imieniu kancelarii.
7. **Metryka App Store**: nazwa, opis, zrzuty (wymagane mimo unlisted),
   kategoria, wsparcie, wiek, eksport (tylko HTTPS → standardowe zwolnienie).
8. **Wniosek o unlisted** składa właściciel konta w App Store Connect.

## Czego NIE robimy przed recenzją

- Nie zdejmujemy oznaczeń demo (zasada z etapów iOS).
- Nie wysyłamy builda, w którym zapisy rzucają wyjątek.
- Nie deklarujemy głosu ani WhatsApp jako działających — do czasu prawdziwych
  integracji (ElevenLabs/APNs/WhatsApp Business).
