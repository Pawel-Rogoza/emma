# M7 — akcje mobilne i kontrola zgód (plan wykonawczy)

Stan: **zaplanowane, niezaimplementowane.** Ten dokument nie opisuje zrobionej
pracy — opisuje różnicę między kontraktem a kodem, który dziś istnieje, oraz
kolejność, w jakiej tę różnicę domkniemy.

Źródło wymagań: `docs/ios/api/emma-mobile-api.yaml`, trasy `/actions`
(linie 638–775). Źródło prawdy o kodzie: `src/lib/crm/assistantActions.ts`
i migracje backendu.

## 1. Czego żąda kontrakt

| Trasa | Semantyka, której nie wolno uprościć |
| --- | --- |
| `POST /actions` | tworzy **propozycję**, nie wykonuje zapisu; zwraca identyfikator prezentacji, termin ważności i wersję kontekstu |
| `PATCH /actions/{id}` | korekta **unieważnia wcześniejszą zgodę** — zmienia identyfikator prezentacji i sumę treści |
| `POST /actions/{id}/confirm` | **jedyny** moment powstania zgody; nagłówek `X-Emma-Consent` (`direct_ui_button` / `authenticated_voice_turn`), backend **odrzuca** `language_model_argument`; powtórzone potwierdzenie zwraca **to samo** wykonanie |
| `GET /actions/{id}/execution` | służy do rozstrzygania stanu `unknown`; aplikacja **nie ponawia** automatycznie, tylko czeka na ten odczyt |
| `POST /actions/{id}/cancel` | anulowanie przed wykonaniem; `409`, gdy wykonanie już się rozpoczęło |

Kluczowa treść tego kontraktu to nie trasy, a **niezmienniki**: zgoda jest
osobnym, jawnym zdarzeniem; dotyczy dokładnie tej treści, którą użytkownik
widział; nie da się jej rozciągnąć na treść zmienioną po fakcie; powtórzenie
żądania nie mnoży skutków.

## 2. Co realnie istnieje w backendzie (potwierdzone w kodzie)

- `src/lib/crm/assistantActions.ts:38` — `proposeAction(db, conversationId, userId, input)`
  **zapisuje od razu** rekord do `case_actions`. To lista „następnych czynności"
  sprawy w panelu, nie propozycja czekająca na zgodę. Nie ma identyfikatora
  prezentacji, sumy treści ani terminu ważności.
- `src/lib/crm/migrations/025_next_actions.sql` (`case_next_actions`) i
  `037_case_actions.sql` (`case_actions`) to tabele panelu; nie przechowują
  stanu zgody ani wykonania.
- W `src/` **nie występuje** `X-Emma-Consent` (grep bez trafień) — kontrola
  zgód dla akcji mobilnych nie istnieje w żadnej formie.
- Brak magazynu propozycji, brak rekordu wykonania, brak klucza idempotencji
  dla akcji, brak wygasania, brak audytu akcji mobilnych.
- Trasy `/actions/*` nie istnieją w `src/pages/api/mobile/v1/`.

Wniosek: nie „brakuje kilku linijek". Brakuje **całego podsystemu**, a jego
sedno stanowi bezpieczeństwo, nie wygoda. Dlatego najpierw plan, potem kod.

## 3. Projekt

### 3.1 Migracja `045_mobile_action_proposals.sql`

```
mobile_action_proposals
  action_id           TEXT PRIMARY KEY   -- identyfikator propozycji (nie prezentacji)
  user_id             INTEGER NOT NULL   -- właściciel: użytkownik
  installation_id     TEXT    NOT NULL   -- właściciel: instalacja aplikacji
  action_type         TEXT    NOT NULL
  payload_json        TEXT    NOT NULL
  content_hash        TEXT    NOT NULL   -- suma treści, którą użytkownik widział
  presentation_id     TEXT    NOT NULL   -- identyfikator tej konkretnej prezentacji
  context_version     TEXT    NOT NULL
  state               TEXT    NOT NULL   -- proposed | confirmed | executed | cancelled | expired | failed
  consent_source      TEXT               -- direct_ui_button | authenticated_voice_turn
  consent_evidence    TEXT               -- dowód dla voice (identyfikator sesji/tury)
  idempotency_key     TEXT
  created_at          TEXT    NOT NULL
  expires_at          TEXT    NOT NULL
  execution_id        TEXT
  UNIQUE(user_id, idempotency_key)

mobile_action_executions
  execution_id        TEXT PRIMARY KEY
  action_id           TEXT NOT NULL
  user_id             INTEGER NOT NULL
  state               TEXT NOT NULL      -- running | succeeded | failed | unknown
  result_json         TEXT
  started_at          TEXT NOT NULL
  finished_at         TEXT
```

Suma treści jest liczona z kanonicznej postaci `payload_json`, a nie z tekstu
przycisku — inaczej korekta odstępu unieważniałaby zgodę bez powodu, a korekta
istotna mogłaby ją zachować.

### 3.2 Niezmienniki i gdzie je pilnujemy

| Niezmiennik | Realizacja |
| --- | --- |
| Zgoda tylko w `confirm` | żadna inna trasa nie zmienia `state` na `confirmed` |
| `language_model_argument` odrzucone | walidacja nagłówka względem zamkniętej listy; każda inna wartość → `400`, nigdy „przyjmij i działaj" |
| Zgoda dotyczy tego, co widziano | `confirm` wymaga `presentation_id` **i** zgodności `content_hash`; niezgodność → `409` |
| Korekta unieważnia zgodę | `PATCH` przelicza `content_hash` i **rotuje** `presentation_id` |
| Powtórzenie nie mnoży skutków | `UNIQUE(user_id, idempotency_key)`; `confirm` na stanie `executed` zwraca **ten sam** `execution_id` |
| Wygasanie | `expires_at`; `confirm` po terminie → `410` |
| Brak automatycznych ponowień | aplikacja po `unknown` tylko czyta `GET /execution`; ponowienie wymaga nowej zgody |
| Izolacja właściciela | każda trasa filtruje po `user_id` + `installation_id`; cudza propozycja = `404` (nie `403`, żeby nie potwierdzać istnienia) |
| Ślad | audyt `assistant.emma.action` (proposed/confirmed/executed/cancelled/failed) **bez** treści danych klienta |

### 3.3 Dowód dla zgody głosowej

`authenticated_voice_turn` nie może być deklaracją w nagłówku. Wymagamy:
identyfikatora sesji głosu należącej do tego użytkownika w stanie `active`
(tabela z migracji `044`) oraz tego, że propozycja powstała w tej sesji.
Bez tego zgodę głosową traktujemy jak brak zgody.

### 3.4 Wykonanie

Zapis do CRM wykonuje **ta sama funkcja, której używa panel** — żadnego drugiego
implementowania reguł. Kolejność: `state=confirmed` → rekord wykonania
`running` → zapis w CRM → `succeeded`/`failed`. Rekord `running` jest
zapisany **przed** efektem, żeby po awarii dało się odróżnić „nie wiem" od
„nie zrobiłem".

## 4. Typy akcji: co wolno wykonywać

Do Twojej decyzji, ale proponuję start zachowawczy:

- **Wykonywalne od razu po zgodzie:** dodanie zadania/czynności do sprawy,
  dopisanie notatki do sprawy. Skutek widoczny w panelu, odwracalny.
- **Tylko propozycja (bez wykonania) do czasu osobnej decyzji:** wysłanie
  wiadomości do klienta, zmiana terminu, cokolwiek nieodwracalnego.

## 5. Testy, które muszą przejść (zanim cokolwiek wdrożymy)

1. `language_model_argument` w nagłówku → odrzucone, brak zmiany stanu.
2. Korekta po zgodzie → stara zgoda **nie** potwierdza nowej treści (`409`).
3. Powtórzony `confirm` z tym samym kluczem → jedno wykonanie, ten sam
   `execution_id`.
4. `confirm` po `expires_at` → `410`.
5. `cancel` po rozpoczęciu wykonania → `409`.
6. Cudza propozycja (inny `user_id` albo inna instalacja) → `404` i brak
   jakiegokolwiek skutku.
7. `GET /execution` po symulowanej awarii → `unknown`, bez ponowienia.
8. Audyt zawiera zdarzenia i **nie** zawiera treści danych klienta.

## 6. Otwarte decyzje (potrzebne przed kodowaniem)

1. **Długość ważności propozycji** — proponuję 15 minut; dłużej oznacza zgodę
   na treść, której użytkownik może już nie pamiętać.
2. **Czy zgoda głosowa wystarcza**, czy przy typach nieodwracalnych wymagamy
   dodatkowo potwierdzenia na ekranie (albo biometrii).
3. **Zakres wykonywalnych typów** — jak w §4.
4. **Czy wykonanie ma zapisywać do CRM od razu**, czy najpierw trafiać do
   kolejki do zatwierdzenia w panelu. To zmienia sens całej funkcji, więc
   decyzja jest Twoja.
