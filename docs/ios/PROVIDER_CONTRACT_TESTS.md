# Testy kontraktowe dostawcy głosu — do wykonania po uzyskaniu konta

Status całości: **nieuruchomione** (`blocked_external` — brak konta u dostawcy
i brak macOS). Ten dokument jest gotowym planem wykonania, nie raportem z wykonania.

Zasada nadrzędna: **testy nie wymagają klucza w aplikacji iOS.** Klucz dostawcy żyje
wyłącznie na backendzie. Aplikacja dostaje krótkotrwały token rozmowy i nic więcej.

## Warunki wstępne

| Warunek | Kto dostarcza |
| --- | --- |
| Konto dostawcy głosu z agentem | właściciel |
| Klucz API po stronie backendu (nie w iOS) | backend |
| Endpoint wydający token rozmowy (`GET`/`POST v1/voice/conversation-token`) | backend |
| Adres backendu w `EMMA_API_BASE_URL` (Staging) | właściciel |
| Agent skonfigurowany po stronie dostawcy (głos, język, prompt) | właściciel |

## T-1 · Token rozmowy

**Cel:** potwierdzić, że aplikacja nigdy nie widzi klucza API.

1. Ustaw `EMMA_API_BASE_URL` na środowisko Staging i uruchom schemat `Emma-Staging`.
2. Włącz nagrywanie ruchu HTTP (np. przez proxy na Macu).
3. Sprawdź, że żądanie idzie na **backend**, a nie na domenę dostawcy.
4. Sprawdź, że odpowiedź zawiera pole `token` i czas wygaśnięcia.
5. Sprawdź, że w całym ruchu z aplikacji **nie występuje** klucz API dostawcy.

**Warunek zaliczenia:** brak klucza w aplikacji i w jej ruchu; token pochodzi z backendu.
**Sposób oznaczenia wyniku:** „zweryfikowane na koncie” + zrzut nagranego ruchu
(z zamaskowanym tokenem).

## T-2 · Nawiązanie rozmowy

**Cel:** potwierdzić, że adapter łączy się oficjalnym SDK i raportuje stany.

1. Otwórz zakładkę Emma i rozpocznij rozmowę.
2. Sprawdź kolejność stanów: `requestingPermission` → `connecting` → `connected`.
3. Sprawdź, że po `connected` orb jest aktywny i widoczny przycisk zakończenia.
4. Sprawdź, że mikrofon nie jest otwierany przed zgodą użytkownika.

**Warunek zaliczenia:** stany zgodne z `ConnectionState`, brak otwarcia mikrofonu bez zgody.

## T-3 · Tura i transkrypcja

**Cel:** potwierdzić, że mowa użytkownika i odpowiedź Emmy trafiają do modelu stanu.

1. Powiedz zdanie po polsku; sprawdź transkrypcję końcową.
2. Powiedz zdanie po ukraińsku; sprawdź, że język rozpoznania się nie „przełącza” na polski.
3. Sprawdź, że odpowiedź agenta jest odtwarzana i że stan tury wraca do słuchania.

## T-4 · Przerwanie głosem (barge-in)

**Cel:** potwierdzić realne przerwanie, a nie tylko lokalne zatrzymanie dźwięku.

1. Podczas odpowiedzi Emmy zacznij mówić.
2. Sprawdź, że odtwarzanie ustaje i pojawia się zdarzenie przerwania.
3. Sprawdź, że model oznacza turę jako przerwaną, a nie zakończoną.

**Uwaga:** rozróżnienie „przerwanie u dostawcy” od „lokalne zatrzymanie odtwarzania”
musi być widoczne w kodzie — lokalne zatrzymanie nie może być raportowane jako
przerwanie po stronie dostawcy.

## T-5 · Kontekst sprawy

**Cel:** potwierdzić, że kontekst jest przyjmowany i wersjonowany.

1. Otwórz Emmę z karty klienta (kontekst: klient) i z rozmowy (kontekst: klient + wątek).
2. Sprawdź, że potwierdzenie kontekstu wraca od backendu z numerem wersji.
3. Sprawdź, że zmiana kontekstu w trakcie sesji nie wykonuje żadnej akcji zapisu.

## T-6 · Propozycja i zgoda

**Cel:** potwierdzić, że zapis wymaga zgody człowieka.

1. Poproś Emmę o przygotowanie odpowiedzi do klienta.
2. Sprawdź, że powstaje **propozycja**, a nie wiadomość wysłana.
3. Zatwierdź przyciskiem w interfejsie — sprawdź, że powstaje jedno wykonanie.
4. Powtórz na nowej propozycji wypowiadając potwierdzenie głosem — sprawdź, że zgoda
   jest liczona jako tura uwierzytelniona.
5. Spróbuj wymusić zatwierdzenie argumentem tekstowym podanym modelowi — sprawdź,
   że **nie** jest traktowane jako zgoda.

**Warunek zaliczenia:** brak wykonania bez zgody; brak drugiego wykonania przy powtórzeniu.

## T-7 · Niepewny wynik wykonania

**Cel:** potwierdzić brak automatycznego ponowienia.

1. Wymuś przerwanie sieci w momencie wykonywania akcji.
2. Sprawdź, że interfejs pokazuje stan **niepewny**, a nie „wykonano”.
3. Sprawdź, że system nie ponawia automatycznie i wymaga rozstrzygnięcia.

**Warunek zaliczenia:** wykonanie w stanie `unknown` nigdy nie jest raportowane jako sukces.

## T-8 · Wznowienie po utracie sieci

1. Podczas rozmowy wyłącz sieć na 20 s i włącz z powrotem.
2. Sprawdź, że stan przechodzi w `reconnecting`, a zdarzenia ze starego połączenia
   są odrzucane (rosnąca generacja połączenia).
3. Sprawdź, że rozmowa wznawia się bez utraty kontekstu albo kończy się czytelnym błędem.

## T-9 · Przejęcie sesji przez inne urządzenie

1. Rozpocznij rozmowę na iPhonie, następnie otwórz sesję z tego samego konta gdzie indziej.
2. Sprawdź, że iPhone kończy sesję i pokazuje to jasno, bez udawania, że nadal rozmawia.

## T-10 · Odmowa uprawnień i odebranie uprawnienia

1. Odmów zgody na mikrofon — sprawdź komunikat i brak zawieszenia interfejsu.
2. Odbierz uprawnienie mikrofonu w Ustawieniach **w trakcie** aktywnej propozycji.
3. Sprawdź, że propozycja **nie znika**, a jedynie zgoda głosowa jest zablokowana;
   zatwierdzenie przyciskiem w interfejsie nadal działa.

## T-11 · Trasa audio i przerwanie systemowe

1. Podłącz słuchawki Bluetooth w trakcie rozmowy — sprawdź zmianę trasy.
2. Zadzwoń na telefon w trakcie rozmowy — sprawdź zdarzenie przerwania systemowego
   i brak automatycznego wznowienia bez działania użytkownika.

## T-12 · Limit kosztów i czasu sesji

1. Sprawdź, że sesja ma ograniczony czas życia i kończy się przewidywalnie.
2. Sprawdź, że długie milczenie nie utrzymuje sesji w nieskończoność.

## Format wyniku

Każdy test kończy się jednym z trzech wpisów w `IMPLEMENTATION_STATUS.md`:

- `zweryfikowane na koncie` — z dowodem (zrzut, log, nagranie ruchu),
- `niezweryfikowane` — kod istnieje, testu nie wykonano,
- `blocked_external` — brak konta, dostępu lub decyzji.

Wpis „działa” bez dowodu nie jest dopuszczalny.
