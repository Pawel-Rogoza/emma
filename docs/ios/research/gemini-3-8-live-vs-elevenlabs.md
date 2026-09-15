# Gemini 3.8 Live jako zamiennik Qwen + ElevenLabs — analiza wykonalności

Data analizy: 2026-09-15. Każdy fakt zewnętrzny ma link do źródła. Rozdzielam
**potwierdzone w dokumentacji** od **do sprawdzenia na koncie/urządzeniu**.

Pytanie właściciela: czy Gemini 3.8 Live (wydany 2026-09) można użyć do
speech-to-speech i jako „mózg” kancelarii zamiast Qwen 3.8 + ElevenLabs.

## 0. Werdykt w jednym akapicie

**Tak, to jest technicznie realny i sensowny kierunek — ale nie jako podmiana
1:1 i nie dziś wieczorem.** Gemini 3.8 Live jest stabilny, robi audio→audio,
wywołuje funkcje i jest ok. 3–5× tańszy za minutę rozmowy niż hosted agent.
Zastępuje **dwa** elementy naraz (transport + pętla agenta + LLM), więc znika
cała warstwa custom LLM i protokół ElevenLabs. Ale: (a) 3.8 Live istnieje
**tylko w Gemini Developer API** — nie ma go w Vertex/EU, więc pytanie o
przetwarzanie danych w UE zostaje otwarte; (b) **nie ma oficjalnego SDK Swift
dla 3.8 Live** — trzeba napisać własny transport WebSocket; (c) Live API **nie
ma structured outputs i nie wykonuje narzędzi samo** — pętla narzędzi i bramka
zgody zostają po naszej stronie. Rekomendacja: spike za adapterem, nie
przepisanie ścieżki produkcyjnej.

## 1. Co faktycznie wyszło

| Fakt | Wartość | Źródło |
| --- | --- | --- |
| Model | `gemini-3.8-live`, **Stable**, update September 2026 | [model card](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-live) |
| Warianty | `gemini-3.8-live` (niska latencja) i `gemini-3.8-live-extended-thinking` (background reasoning) | [models](https://ai.google.dev/gemini-api/docs/models) |
| Wejście / wyjście | tekst, obraz, audio, wideo → **tekst i audio** | [model card](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-live) |
| Limity | 131 072 wejścia / 65 536 wyjścia | tamże |
| Funkcje | Live API ✔, function calling ✔, thinking (interleaved) ✔, Search grounding ✔ | tamże |
| **Bez wsparcia** | structured outputs ✘, code execution ✘, file search ✘, caching ✘, batch ✘, Maps ✘ | tamże |
| Migracja z 3.1 | `thinking_level` **nieobsługiwany** — pominąć; async function calling (`NON_BLOCKING`) **domyślne**; `proactive_audio` na stałe włączone; affective dialogue usunięte | tamże |

## 2. Co Live API daje, a czego nie daje

**Daje (potwierdzone):**

- **Sesja:** połączenie ok. 10 min, sesja audio bez kompresji 15 min;
  `sessionResumption` (token ważny 2 h) pozwala ciągnąć jedną sesję przez wiele
  połączeń, `contextWindowCompression` (sliding window) — bez limitu czasu.
  Serwer wysyła `GoAway` przed zerwaniem. [session management](https://ai.google.dev/gemini-api/docs/live-api/session-management)
- **Narzędzia:** function calling z `send_tool_response`; **Live API nie robi
  automatycznej obsługi odpowiedzi narzędzi — klient musi je odesłać ręcznie**.
  [tool use](https://ai.google.dev/gemini-api/docs/live-api/tools)
- **Sekrety:** **ephemeral tokens** (Preview) — backend wydaje krótki token,
  `uses: 1`, `expireTime` (domyślnie 30 min), `newSessionExpireTime` (1 min);
  token można **zablokować na konfiguracji**, w tym trzymać `systemInstruction`
  po stronie serwera. Działa wyłącznie z `v1beta` i tylko dla Live API.
  [ephemeral tokens](https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens)
- **Kontekst w trakcie sesji:** `send_client_content` z jawnymi rolami działa
  przez całe życie sesji; `turn_complete=true` przerywa generowanie.
  [model card](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-live)
- **VAD, przerwanie wypowiedzi, transkrypcje:** konfigurowalny VAD
  (`start_of_speech_sensitivity`, `silence_duration_ms`…) albo ręczne
  `activity_start`/`activity_end`; transkrypcja wejścia i wyjścia do włączenia
  osobno. [capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities)

**Nie daje:** warstwy agenta hostowanej u dostawcy (nie ma odpowiednika
ElevenLabs Agents: brak wbudowanego prowadzenia rozmowy z narzędziami,
brak webhooków dostawcy, brak gotowej obsługi narzędzi), brak structured
outputs, brak wyboru regionu w Developer API.

## 3. Koszt (Gemini Developer API, tier płatny)

| Pozycja | Cena | Przeliczenie |
| --- | --- | --- |
| audio wejście | $3,00 / 1M tokenów | **$0,005 / min** |
| audio wyjście (z thinking) | $12,00 / 1M | **$0,018 / min** |
| tekst wejście | $0,75 / 1M | — |
| tekst wyjście | $4,50 / 1M | — |
| obraz/wideo wejście | $1,00 / 1M | $0,002 / min |

Źródło: [pricing](https://ai.google.dev/gemini-api/docs/pricing).

Czyli **oba kierunki audio ≈ $0,023/min ≈ $1,38/h** rozmowy, plus żetony
tekstowe (instrukcja systemowa, kontekst sprawy) — przy 131 k okna to nie jest
pozycja dominująca, ale zależy od tego, ile kontekstu wstrzykujemy na start.

**Twarda uwaga:** w tierze **Free** treść jest używana do ulepszania
produktów; w **Paid** — nie. Dla kancelarii Free jest wykluczony z definicji.
Do porównania brakuje mi w tej sesji aktualnego cennika ElevenLabs z waszego
planu — nie zgaduję go; trzeba podstawić realną stawkę za minutę i doliczyć
koszt LLM.

Uwaga na przyszłość: **3.8 Flash drożeje 2027-01-01** ($0,75→$1,50 wejście,
$3,75→$7,50 wyjście). Jeśli „mózg” tekstowy ma iść na Gemini, wycenę trzeba
zrobić na cenach po 1 stycznia.

## 4. Co to znaczy dla naszej architektury (konkret vs repo)

| Element dziś | Po 3.8 Live | Uwaga |
| --- | --- | --- |
| `ElevenLabsVoiceTransport` (SDK 3.3.1 + LiveKit/WebRTC) | nowy `GeminiLiveTransport` na `URLSessionWebSocketTask` | zależność LiveKit znika; PCM 16 kHz we / 24 kHz wy, AVAudioSession zostaje w `AudioSessionController` |
| Custom LLM + gateway (jeden krok Qwen) | **znika** — 3.8 Live sam prowadzi turę | mniej tłumaczenia protokołu; ale to my implementujemy pętlę narzędzi |
| 8 narzędzi `/api/emma/tools/*` z sekretem usługi | deklaracje funkcji w sesji; wykonanie po naszej stronie | trzeba wybrać: relay backendem albo bezpośrednio z aplikacji |
| `POST /voice/conversation-token` → `{token, conversation_id}` | ephemeral token → `{token.name, expireTime, session_id}` | nasze `expires_at` było opcjonalne i puste — teraz ma realną wartość |
| `PATCH /voice/sessions/{id}/context` + `context_version` | zostaje, ale wysyłka przez `send_client_content` | wersja dalej rośnie tylko w górę, backend dalej waliduje |
| `userTranscriptPartial/Final`, `agentTextFinal` | mapuje się na zdarzenia transkrypcji Live | model zdarzeń z planu §5 pasuje bez zmian |
| `provider_conversation_id` w tabeli technicznej | `provider_session_id` + **resumption handle** | handle jest sekretem sesji transportu; nie do treści rozmowy |

**Dwie realne architektury do wyboru:**

- **Relay przez backend** — iOS ⇄ WS ⇄ backend ⇄ Live API. Klucz zostaje na
  serwerze, narzędzia idą przez wspólny action engine z sekretem usługi, audyt
  pełny, „tylko potrzebne dane do modelu” egzekwowalne. Koszt: trzeba postawić
  trwałe WebSocket po stronie Node (Astro route tego nie utrzyma) i dodać skok
  opóźnienia.
- **Bezpośrednio z telefonu (ephemeral token)** — mniejsze opóźnienie, zero
  sekretów na urządzeniu, token zablokowany na modelu i `systemInstruction`.
  Koszt: narzędzia woła aplikacja (bearer użytkownika przez `/api/mobile`),
  treść rozmowy idzie prosto do Google i nie ma centralnego logu rozmowy.

Moja rekomendacja na spike: **bezpośrednio**, bo dokładnie po to są ephemeral
tokens, a narzędzia zapisu i tak muszą przejść przez bramkę zgody po stronie
backendu (zasada „argument modelu nie jest zgodą” nie zmienia się).

## 5. Ryzyka, których nie wolno przemilczeć

1. **UE / rezydencja danych.** `gemini-3.8-live` jest tylko w Gemini Developer
   API. Vertex (Gemini Enterprise Agent Platform) Live API ma **tylko**
   `gemini-live-2.5-flash-native-audio` (GA) i `gemini-3.5-transcribe-live-preview`;
   modele Live 3.x — brak. [Vertex Live API](https://cloud.google.com/vertex-ai/generative-ai/docs/live-api).
   Jeśli wymogiem jest przetwarzanie w UE z rezydencją, **3.8 Live tego dziś nie
   daje** — trzeba albo zostać na 2.5 native audio na Vertex, albo świadomie
   przyjąć procesor poza UE z umową powierzenia.
2. **Brak SDK Swift dla 3.8 Live.** Oficjalne biblioteki: Python, JS, Go, Java,
   C#; dla Swift dokumentacja kieruje do Firebase AI Logic, a Firebase Live API
   wymienia dla 3.x **tylko `gemini-3.1-flash-live-preview` (Preview)** —
   `gemini-3.8-live` tam nie występuje. [libraries](https://ai.google.dev/gemini-api/docs/libraries),
   [Firebase Live API](https://firebase.google.com/docs/ai-logic/live-api),
   [Firebase models](https://firebase.google.com/docs/ai-logic/models).
   Dodatkowo Firebase AI Logic od **2026-11-02** wymaga App Check.
   Ścieżka bez Firebase = własny WebSocket (co i tak planujemy).
3. **Kwestie Preview.** Ephemeral tokens są w Preview; sama Live API ma
   elementy preview. Ephemeral token = jedna sesja (`uses: 1`), więc wznowienie
   po 10 min musi użyć tego samego tokenu i `sessionResumption`.
4. **Brak structured outputs w Live.** Propozycje akcji (`propose_*`) muszą być
   walidowane po stronie backendu, a złożone rozumowanie „mózgu” lepiej
   kierować do 3.8 Flash przez `generateContent`, nie przez model głosowy.
5. **Jakość polskiego** na nazwiskach i sygnaturach — to już jest w M5 jako
   „niepotwierdzone, wymaga oceny człowieka”. Gemini tego nie zmienia
   automatycznie na plus; trzeba zmierzyć.
6. **Trwałość decyzji:** 2.5 Live „stable” modele nie są objęte październikowym
   wyłączeniem, ale 3.1 Flash Live Preview jest oznaczony jako legacy
   („recommend updating to Gemini 3.8 Live”). Kierunek 3.8 jest zgodny z
   rekomendacją dostawcy.

## 6. Proponowany spike (1–2 dni, poza ścieżką produkcyjną)

1. Backend: endpoint wydający ephemeral token z `liveConnectConstraints`
   (`model: gemini-3.8-live`, `responseModalities: [AUDIO]`,
   `sessionResumption: {}`, `systemInstruction` zablokowana) — bez zmian w
   istniejących trasach M5.
2. iOS: `GeminiLiveTransport` za istniejącym protokołem, jeden ekran, VAD i
   przerwanie wypowiedzi, transkrypcja wejścia i wyjścia.
3. Jedno narzędzie read-only (`get_today_overview`) przez backend z bearerem
   użytkownika — dowód, że pętla `tool_call → FunctionResponse` działa.
4. Pomiar: polski na nazwiskach/sygnaturach, latencja pierwszej odpowiedzi,
   przerwanie, reconnect po `GoAway`, zużycie tokenów na 10 min rozmowy.

**Kryteria go/no-go:** przerwanie wypowiedzi działa naturalnie; polski
akceptowalny na nazwiskach i sygnaturach; koszt zmierzony < obecny koszt
ElevenLabs + Qwen; brak sekretu stałego na urządzeniu; narzędzie nie może
wykonać zapisu bez bramki zgody.

Jeśli spike przejdzie: 3.8 Live = głos, 3.8 Flash = czat i rozumowanie,
Qwen wypada z planu. Jeśli nie: zostaje ElevenLabs, a jako „mózg” wystarczy
podmienić LLM w custom LLM (mniejsza zmiana, ten sam problem z UE).
