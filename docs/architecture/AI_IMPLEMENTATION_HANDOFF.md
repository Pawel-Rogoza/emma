# Plan wykonawczy dla kolejnego modelu AI: Emma Live i wiedza prawna

Data: 2026-09-22. Status: zadania do wykonania po wydaniu poprawek głosu.
Ten plan nie upoważnia do oznaczania niewykonanych etapów jako gotowych.
Historia konkretnego wydania: `RELEASE_2026-09-22.md` w tym katalogu.

## Gotowe polecenie startowe

> Pracujesz nad Emmą, polskojęzyczną asystentką kancelarii. Przeczytaj ten plan,
> dokument GEMINI_LIVE_AND_RAG_2026-09-22.md i raport wydania. Pracuj kolejno
> według etapów, zapisując wyniki i dowody. Zacznij od sprawdzenia aktualnych
> gałęzi, zmian użytkownika i kontraktów obu repozytoriów. Nie odtwarzaj już
> wdrożonych poprawek. Dostawcą głosu iOS jest wyłącznie Gemini Live. Nie
> przywracaj ElevenLabs ani nie migruj istniejącej bazy CRM bez potrzeby.
> Wykonuj testy odpowiednie do zmiany. Odróżniaj test na atrapie od testu Google,
> upload do Apple od dostępności dla testerów oraz projekt RAG od działającego
> retrieval. Jeśli zależność wymaga konta, źródła lub decyzji właściciela,
> nazwij ją precyzyjnie i kontynuuj niezależne prace. Nie udawaj dostępu do
> internetu ani źródeł. Autoryzację produkcyjnego wdrożenia ustal z bieżącej
> sesji użytkownika; ten dokument sam jej nie udziela.

## 0. Kontekst i stan wejściowy

Repo iOS: `Pawel-Rogoza/emma`, gałąź `master`, lokalnie
`/Users/pawelrogoza/Documents/ChatGPT/emma`.
Repo backendu: `Pawel-Rogoza/adwokat-app-project`, gałąź `main`, lokalnie
`/Users/pawelrogoza/projects/adwokat-app-project`. Na innej maszynie najpierw
odszukaj checkouty; nie zakładaj istnienia tych ścieżek.

Przeczytaj lokalne AGENTS.md, aktualny status Git i README, a następnie:

- iOS: `Core/Voice/GeminiLiveProtocol.swift`, `GeminiLiveTurnTracker.swift`,
  `PlaybackSuppression.swift`, `VoiceEvents.swift`, `VoiceStateReducer.swift`;
  `VoiceAdapters/GeminiLiveTransport.swift`, `BackendVoiceToolExecutor.swift`;
  `Features/Assistant/AssistantStore.swift`, `AssistantScreen.swift`.
- Backend: `src/lib/crm/voice/{gemini,config}.ts`, `src/lib/crm/emma/tools.ts`,
  rejestr `src/lib/crm/assistant/tools/registry.ts`, mobilne trasy głosu.
- Architektura: `knowledge/schema.sql`, `retrieval.schema.json`,
  `validate_contract.py` obok tego pliku. To szkice, nie wdrożone migracje.

Już zrobione: pojedynczy ogon mikrofonu po kolejce, monotoniczny czas,
składanie transkrypcji, anulowanie tool calls i odrzucanie ich późnych wyników,
tryb NON_BLOCKING 3.8, instrukcja odpowiedzi, flaga Search domyślnie false.
Nie ma jeszcze: UI cytowań Google, retrieval, importu, bazy PostgreSQL ani
pełnego dupleksu na głośniku. Potwierdź te fakty w kodzie przed rozpoczęciem.

## 1. Źródła i cytowania w iOS — pierwszy etap implementacji

Cel: każda odpowiedź oparta na Search ma widoczne, trwałe źródła.

1. Zweryfikuj aktualny surowy protokół Google, zwłaszcza `groundingMetadata`,
   `groundingChunks`, `groundingSupports`, `searchEntryPoint` i ich dostępność
   w audio. Zachowaj zanonimizowane fixtures prawdziwych odpowiedzi.
2. W `Core/Voice` dodaj typy źródła, wsparcia fragmentu odpowiedzi i metadanych
   wyszukiwania. Nie utożsamiaj indeksu źródła z trwałym ID. Zachowaj pola
   potrzebne do wymaganej prezentacji Search suggestions Google.
3. Rozszerz kodek, event, tracker, reducer i zapis historii w AssistantStore.
   Obsłuż metadane przed/po transkrypcji, wiele pakietów, puste wyniki,
   przerwaną turę, reconnect i ponowne wejście na ekran. Wiąż źródła z turą,
   nie z ostatnią dowolną odpowiedzią.
4. W AssistantScreen i mini-panelu udostępnij sekcję źródeł oraz przejście do
   pełnej odpowiedzi. Linki otwieraj tylko po działaniu użytkownika. Zadbaj
   o VoiceOver, Dynamic Type i długie tytuły. HTML dostawcy nie może otrzymać
   dostępu do tokenów, plików aplikacji ani dowolnego mostka JavaScript.
5. Testy: fixture z kilkoma źródłami, duplikaty, zła referencja indeksu,
   brak metadanych, przejście tur, historia, niedozwolony schemat URL.

Odbiór: cytowanie otwiera właściwy URL i odpowiada właściwej wypowiedzi;
sugestie Search są wyświetlane zgodnie z bieżącą dokumentacją Google.
Dopiero wtedy wykonaj etap 2. Nie włączaj flagi globalnie wcześniej.

## 2. Search i bezpieczny dostęp do publicznych stron

Cel: potwierdzony internet w rozmowie, z kontrolą zakresu danych.

1. Sprawdź `GEMINI_LIVE_GOOGLE_SEARCH=true` na sesji testowej: token z maską
   pól, setup, Search + CRM, odpowiedź audio, cytowania. Klucz stały zostaje
   na backendzie. Testy płatnego API uruchamiaj jawnie, nigdy w zwykłym CI.
2. Dla pracy z aktami wybierz izolowane narzędzie `search_public_sources`:
   oddzielne zapytanie dostawcy, bez historii CRM. Zaprojektuj politykę
   minimalizacji danych; prompt „nie wysyłaj danych” nie jest izolacją.
3. Dodaj `fetch_public_source` z allowlistą źródeł, limitami czasu, bajtów,
   treści i przekierowań. Zweryfikuj DNS i adres po każdym redirect; blokuj
   localhost, prywatne IP, metadata endpoints, userinfo w URL i inne protokoły.
   Nie przekazuj cookies ani bearerów użytkownika. Parsowanie HTML/PDF
   odbywa się poza krytyczną ścieżką audio.
4. Executor zwraca treść, kanoniczny URL, czas pobrania i status; nie mówi
   „zweryfikowano”, jeśli uzyskał wyłącznie snippet wyszukiwarki.
5. Testy: deadline, 429, 5xx, brak wyników, prompt injection, DNS rebinding,
   redirect do prywatnego IP, duży PDF, cancellation i brak danych CRM
   w żądaniu izolowanego research.

Odbiór: realna odpowiedź z poprawnym źródłem; błąd kończy się jawnym statusem,
bez zmyślonego wyniku. Rollback: flaga false i nowa sesja. Udokumentuj koszty
oraz ograniczenia konta, zamiast zakładać bezpłatność lub pełną dostępność.

## 3. Pomiary i domknięcie transportu audio

Można wykonywać niezależnie od importu, po zachowaniu poprawek obecnego wydania.

1. Dodaj telemetrykę monotoniczną: koniec mowy, początek/koniec toola,
   pierwszy pakiet i pierwsza próbka playbacku, zwolnienie mikrofonu.
   Bez surowego audio i treści akt w logach. Oddziel „sprawdzam” od odpowiedzi.
2. Wysyłaj mikrofon dopiero po setupComplete. Zaprojektuj ograniczoną kolejkę
   audio i jasne zachowanie przy przeciążeniu sieci; nie odtwarzaj starych
   sekund nagrania po wznowieniu połączenia.
3. Koniec lokalnego odtwarzania rozlicz callbackiem AVAudioPlayerNode;
   `turnComplete` nie jest dowodem, że głośnik już zamilkł.
4. Obsłuż unieważnienie resumption handle, GoAway i zamknięcie podczas
   oczekiwania na token. Sprawdź brak wznowienia po wylogowaniu.
5. Zestaw 30 wypowiedzi na wariant VAD 700/500/350 ms. Nazwiska, sygnatury,
   liczby, autokorekta, pauzy i hałas; głośnik i słuchawki osobno.
6. AEC/pełny dupleks wyłącznie jako kontrolowany eksperyment z możliwością
   powrotu do półdupleksu. Wcześniejsza próba psuła audio na iPhonie.

Odbiór: p50/p95 przed/po i brak regresji poprawności krytycznych danych.
Cel do sprawdzenia: p95 <2 s bez toola, <4 s z lokalnym retrieval. Nie wpisuj
celu jako wyniku. Testy symulatora nie zastępują odsłuchu na telefonie.

## 4. Magazyn publicznej wiedzy i infrastruktura

1. Utwórz moduł `src/lib/crm/knowledge/` w backendzie i osobnego workera importu.
   Nie wystawiaj nowego nieautoryzowanego API ani nie zmieniaj bazy CRM.
2. Przygotuj środowisko deweloperskie PostgreSQL + pgvector z przypiętymi
   wersjami, migracjami, healthcheckiem i instrukcją uruchomienia.
3. Zamień szkic DDL na rzeczywiste migracje; uruchom na pustej bazie,
   przetestuj constraints, upgrade i odtworzenie backupu. Rola odczytu API
   ma SELECT, worker ma ograniczone uprawnienia importu.
4. Magazyn oryginałów trzyma niezmienne obiekty i checksum; dostęp przez
   backend. Rewizja + parser + profil embeddingów muszą być odtwarzalne.
5. Szkic nie obsługuje akt prywatnych. Nie wkładaj tam plików klientów.
   Nie usuwaj historycznej wersji tylko dlatego, że przepis uchylono.

Odbiór: prawdziwy lokalny import fixture i odczyt; utrata procesu workera
nie zostawia częściowo opublikowanej rewizji. DDL sprawdzony tylko parserem
nie spełnia tego etapu.

## 5. Import ELI i wersjonowanie prawa

1. Zweryfikuj dokumentację API Sejmu, endpointy i sposób wykrywania zmian.
   Start od uzgodnionego zestawu kodeksów: KC/KPC/KK/KPK i aktów dziedzinowych.
2. Adapter: discovery, paginacja, checkpoint, ETag/Last-Modified, retry z
   Retry-After, checksum i deduplikacja. Powtórny import jest idempotentny.
3. Zachowaj oryginalny tekst, metadane, publikację, relacje zmian i parser.
   Fragmentuj według struktury prawnej, nie losowej liczby znaków.
4. Ustalaj daty obowiązywania per przepis; rozróżniaj datę publikacji,
   wejścia w życie i stosowania. Nieznane daty oznaczaj unknown.
   Tekst jednolity wymaga sprawdzenia późniejszych zmian i przepisów przejściowych.
5. Kwarantanna: błędny PDF, brak tekstu, niewiarygodny OCR numeracji,
   konflikt dat, utrata fragmentu. Publikacja dopiero po walidacji.
6. Testy na fixtures: dwie wersje artykułu, częściowa nowelizacja,
   przyszła data, uchylenie, powtórka importu, 429, wznowienie po awarii.

Odbiór: pytanie o dwie daty prowadzi do właściwych, różnych wersji; każdy
fragment prowadzi do konkretnego oryginału. Bez deklaracji kompletności
korpusu na podstawie jednego poprawnie pobranego kodeksu.

## 6. Retrieval i połączenie z głosem

1. Wybierz multilingual embeddings na oznaczonym zestawie pytań. Zapisz model,
   wymiar i preprocessing. Nie mieszaj wektorów różnych profili.
2. Najpierw exact match identyfikatorów i filtry dat/jurysdykcji/rodzaju,
   potem lexical + vector search, połączenie RRF, reranking, deduplikacja.
   Baseline exact search służy do oceny utraty recall przez ANN.
3. Implementuj `search_legal_knowledge` i `get_legal_passage` w rejestrze
   backendu oraz allowliście głosu. Zachowaj istniejący envelope `{tool,result}`.
   Zwaliduj JSON Schema w runtime, w tym daty, limit 8 i statusy wyniku.
4. Wynik: konkretne passages + citation, corpusVersion, retrievalProfile,
   warnings i status. 24 KiB UTF-8; nie stosuj limitu tekstu CRM 400 znaków
   do podstawy prawnej. Dołącz potrzebne definicje i przepisy przejściowe.
5. Cache uwzględnia datę, filtry i wersję korpusu. Wycofanie błędnej rewizji
   unieważnia cache; similarity score nie jest pewnością prawną.
6. iOS wyświetla dowody z tego samego kontraktu, Live mówi krótko. Przy
   `no_results`, `needs_clarification`, `unavailable` nie wymyśla podstawy.

Odbiór: co najmniej 100 pytań z oczekiwanymi źródłami, recall@8 ≥90% jako cel;
100% poprawnych identyfikatorów cytowań w zestawie. Osobna ocena adwokata
co do zastosowania przepisów. Raportuj wyniki, również niespełnione progi.

## 7. EUR-Lex i orzecznictwo

Adaptery wdrażaj osobno. EUR-Lex: uzyskaj wymagany dostęp webservice, rozdziel
wyszukiwanie metadanych i pobieranie tekstu. SN/CBOSA: nie zakładaj istnienia
publicznego REST API bez potwierdzenia. SAOS może pomóc odkrywać dokumenty,
ale zachowaj pierwotne źródło. Zweryfikuj warunki pobierania i limity.

Każdy adapter zapisuje sąd, datę, sygnaturę, źródło, oryginał i rewizję.
Deduplikuj orzeczenia z kilku kanałów; rozdziel sentencję od uzasadnienia.
Nie przedstawiaj daty orzeczenia jako „obowiązuje od” ani pojedynczego
orzeczenia jako jednolitej linii orzeczniczej. Testuj sprzeczne rozstrzygnięcia,
nieistniejącą sygnaturę, braki pokrycia i opóźnienia publikacji.

Odbiór: raport pokrycia i świeżości per źródło; link do oryginału każdego wyniku.

## 8. Wydanie i przekazanie wyniku

Każdy etap kończy się małym commitem, testami i aktualizacją statusu tego planu.
Przed wdrożeniem sprawdź różnicę między aktywnym wydaniem a docelowym SHA.
Backend: istniejący workflow Deploy buduje poza VPS-em, aktywacja robi
healthcheck i rollback. Nie uruchamiaj rutynowo ciężkiego buildu na serwerze.
iOS: push master uruchamia TestFlight; monitoruj dokładnie docelowy SHA.

Po autoryzowanym wdrożeniu sprawdź: aktywny release SHA, usługę, stronę,
booking availability, ochronę mobilnych endpointów i jawną konfigurację
nowej sesji. Nie wypisuj .env, tokenów, transkrypcji ani logów z danymi klientów.
Search włączaj dopiero po etapach 1–2 i sprawdzeniu faktycznej wersji klienta.

Raport końcowy dla właściciela: co działa; linki do commitów i przebiegów;
dowody testów; dostępność buildu u Apple; ograniczenia; następny etap.
Jeśli upload Apple się udał, ale build jest nadal przetwarzany, zapisz właśnie
to. Wskaż rollback konfiguracji i commit poprzedniego zdrowego wydania.
