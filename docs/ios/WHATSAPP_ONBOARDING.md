# WhatsApp Business — instrukcja podłączenia numeru kancelarii

Ten dokument opisuje drogę do legalnego, **oficjalnego** połączenia numeru kancelarii
z aplikacją. Status całości: **blocked_external** — nie wykonano żadnego kroku
wymagającego konta Meta ani uprawnień Tech Providera.

## Zasada nadrzędna — numer właściciela jest nietykalny

Właściciel **używa** numeru w aplikacji WhatsApp Business App i prowadzi na nim
rozmowy z klientami. Dlatego w trakcie implementacji **nie wolno**:

- zmieniać numeru ani go przenosić,
- wyrejestrowywać numeru z WhatsApp,
- usuwać ani „czyścić” historii rozmów,
- uruchamiać procesu, który wymaga usunięcia konta WhatsApp Business,
- migrować numeru na nowy numer telefonu.

Jeśli jakikolwiek krok wymagałby którejkolwiek z tych czynności — **krok zostaje
zatrzymany** i wraca jako pytanie do właściciela. Utracona historia rozmów z klientami
jest szkodą nieodwracalną, a nie „kosztem wdrożenia”.

## Dlaczego nie da się tego zrobić „przy okazji”

Koegzystencja (jednoczesne działanie aplikacji WhatsApp Business i API na tym samym
numerze) **nie jest samoobsługowa**. Wymaga:

| Wymóg | Znaczenie |
| --- | --- |
| Status Tech Providera lub Solution Partnera | zwykły dostęp deweloperski nie wystarcza |
| Embedded Signup | proces, w którym właściciel sam przechodzi logowanie biznesowe |
| Aplikacja w trybie na żywo z zatwierdzonymi uprawnieniami | tryb testowy nie wystarcza dla koegzystencji |
| Zgoda właściciela na warunki Meta | zgoda biznesowa, nie techniczna |

Dopóki te warunki nie są spełnione, żadna część tego dokumentu nie może być wykonana —
i aplikacja tego nie udaje: stopka listy rozmów mówi wprost „WhatsApp niepołączony”,
a statusy wiadomości są oznaczone jako przykładowe.

## Krok po kroku (do wykonania, gdy warunki będą spełnione)

### K-1 · Ustalenie statusu dostępu

1. Ustal, czy konto ma status Tech Providera lub jest prowadzone przez Solution Partnera.
2. Jeśli nie — pozyskaj partnera; **nie próbuj obchodzić tego wymogu**.
3. Zapisz wynik w `docs/ios/IMPLEMENTATION_STATUS.md` jako `zweryfikowane na koncie`
   albo `blocked_external`.

### K-2 · Aplikacja Meta i uprawnienia

1. Utwórz (lub wskaż) aplikację biznesową w panelu Meta dla kancelarii.
2. Wnioskuj o uprawnienia do zarządzania kontem WhatsApp Business i wysyłania wiadomości.
3. Poczekaj na zatwierdzenie — bez niego proces nie przejdzie dalej.

### K-3 · Embedded Signup z właścicielem przy ekranie

Embedded Signup prowadzi **właściciel numeru**, nie programista:

1. Właściciel otwiera proces logowania po stronie Meta.
2. Wybiera numer, którego już używa w aplikacji WhatsApp Business.
3. Potwierdza warunki i **wyraźnie wybiera tryb koegzystencji**, jeśli jest oferowany.
4. Po zakończeniu zapisujemy identyfikator konta WhatsApp Business (WABA) i identyfikator
   numeru telefonu — **nie** numer w postaci tekstowej w kodzie.

**Warunek zatrzymania:** jeśli ekran Meta proponuje „migrację” numeru, usunięcie
aplikacji WhatsApp Business albo ponowną weryfikację numeru z utratą historii —
**przerywamy i pytamy właściciela.**

### K-4 · Webhook po stronie backendu

1. Backend wystawia jeden publiczny adres HTTPS na zdarzenia wiadomości.
2. Każde żądanie jest weryfikowane podpisem `X-Hub-Signature-256`.
3. Wiadomości są deduplikowane po identyfikatorze dostawcy — powtórzone zdarzenie
   nie tworzy drugiej wiadomości w aplikacji.
4. Backend używa wersji Graph API `v26.0` (jedna wersja, jawnie wskazana w żądaniach).

### K-5 · Limity i kolejkа

1. Wysyłka przechodzi przez kolejkę z kluczem idempotencji.
2. Limit tempa jest respektowany: konto startuje z niskim limitem (20 wiadomości
   na sekundę) i rośnie w miarę reputacji — nie zakładamy z góry wysokiego limitu.
3. Przekroczenie limitu jest błędem odzyskiwalnym: żądanie czeka, nie ginie.

### K-6 · Sprawdzenie na sucho

1. Wyślij wiadomość z aplikacji na **własny** numer testowy.
2. Sprawdź, że status przechodzi przez kolejne etapy i że żaden etap nie jest pokazany
   wcześniej, niż potwierdził go dostawca.
3. Wyślij wiadomość z WhatsApp Business App właściciela i sprawdź, że pojawia się
   w aplikacji w jednym wątku z wiadomościami API.
4. Sprawdź, że **historia rozmów właściciela w aplikacji WhatsApp Business jest nienaruszona**.

### K-7 · Sprawdzenie na produkcji

1. Rozmowa z jednym zaufanym klientem za jego zgodą.
2. Sprawdzenie, że wiadomości z API i z aplikacji właściciela trafiają do właściwego wątku.
3. Sprawdzenie, że nieprzeczytane liczą się niezależnie dla każdego użytkownika kancelarii.

## Czego aplikacja już pilnuje po swojej stronie

To nie jest lista życzeń — te zachowania są zaimplementowane i pokryte testami logiki:

- jeden wątek na klienta, bez duplikatów przy powtórzonym zdarzeniu,
- kursor odczytu nigdy się nie cofa i jest niezależny dla każdego użytkownika,
- status wiadomości może się tylko poprawiać (monotoniczny postęp transportu),
- wysyłka jest idempotentna po kluczu,
- brak symulowanych potwierdzeń dostarczenia,
- interfejs mówi wprost, że WhatsApp nie jest połączony.

## Zapisy wymagane po wykonaniu

- `docs/ios/IMPLEMENTATION_STATUS.md` — status każdego kroku z dowodem,
- `docs/ios/PROVIDER_CONTRACT_TESTS.md` — wyniki testów kontraktowych,
- `docs/ios/API_GAP_ANALYSIS.md` — zaktualizowana tabela luk (Blocked → Gotowe/Wymagane).

Każdy krok bez dowodu pozostaje `niezweryfikowany`. Wpis „podłączone” bez testu
na żywym numerze nie jest dopuszczalny.
