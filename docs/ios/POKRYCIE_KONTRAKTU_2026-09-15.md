# Pokrycie kontraktu mobilnego — stan na 2026-09-15

Dokument jest **dowodem**, nie planem: pokazuje, które trasy z
`docs/ios/api/emma-mobile-api.yaml` mają odpowiednik w kodzie backendu, a które
nie. Wygenerowane porównaniem specyfikacji z plikami w
`src/pages/api/mobile/v1/` (trasy dynamiczne normalizowane: `[client_id]` =
`{client_id}`).

## Wynik

**23 z 28 tras pokrytych. Brakuje 5.**

| Trasa | Stan |
| --- | --- |
| `/auth/login`, `/auth/refresh`, `/auth/revoke` | pokryte |
| `/briefing` | pokryte |
| `/clients`, `/clients/{client_id}` | pokryte |
| `/cases`, `/cases/{case_id}` | pokryte |
| `/tasks`, `/tasks/{task_id}` | pokryte |
| `/events`, `/events/{event_id}` | pokryte |
| `/notes` | pokryte |
| `/actions`, `/actions/{action_id}`, `/confirm`, `/execution`, `/cancel` | pokryte (commit `1a9a735`, **niewdrożone**) |
| `/voice/sessions`, `/conversation-token`, `/{id}`, `/{id}/context`, `/{id}/status` | pokryte |
| `/threads`, `/threads/{id}/messages`, `/threads/{id}/read-state` | **brak** |
| `/sync/changes`, `/push/devices` | **brak** |

## Dlaczego brakuje tych pięciu

- **`/threads` (3 trasy)** — brak kanału WhatsApp Business: nie ma konta,
  numeru telefonu ani tabeli z treścią wiadomości. Wątki bez treści byłyby
  pustym ekranem udającym funkcję, dlatego ich nie ma. Zablokowane zewnętrznie,
  nie technicznie.
- **`/sync/changes`, `/push/devices`** — poza zakresem celu, który wyliczał
  logowanie, leady/klientów/sprawy/zadania/zdarzenia, pliki, akcje i
  `/voice/conversation-token`. Do zrobienia, gdy pojawi się synchronizacja
  przyrostowa i powiadomienia (APNs wymaga klucza `p8`, Key ID i Team ID).

## „Leady" — pokryte inaczej, niż sugeruje nazwa

Kontrakt **nie ma** trasy `/leads` i to jest celowe: warstwa mobilna scala
leady i kartotekę w jedną listę etapów (`mergeClients` w
`src/lib/crm/mobile/read.ts`), a etap bierze z najdalej posuniętego aktywnego
leada. Klient bez leadów jest klientem. Dzięki temu aplikacja nie pokazuje
dwóch wpisów dla tej samej osoby — jedna osoba, jedna pozycja.

## „Pliki" — jedyna pozycja celu bez odpowiednika

Cel wymienia pliki, ale **kontrakt ich nie definiuje** (pliki występują w nim
tylko jako rodzaj załącznika w wiadomości: `kind: attachment`). W kodzie
aplikacji typ encji `'file'` jest zadeklarowany (`dto.ts:28`), lecz **nikt go
nie produkuje**, a klient HTTP aplikacji nie ma ani jednego wywołania plików.
Backend ma natomiast gotowy podsystem dla panelu: tabele `files` + `file_meta`
(foldery, grupy wersji, `version_number`, `is_current`), logikę `fileMeta.ts`
i trasy `/api/crm/files/[id]`.

Wniosek: to nie zepsuta funkcja, a **niedomknięty zakres** — brakuje decyzji
o kształcie odpowiedzi, bo nie ma go skąd wziąć. Gdy zdecydujesz, wystawienie
listy plików dla sprawy to kilka tras korzystających z istniejącej logiki,
a nie nowy magazyn.

## Weryfikacja, na której opiera się ten dokument

- Pełny zestaw backendu: **116 plików / 924 testy, 0 porażek**.
- `npx astro check`: **0 błędów**.
- `npm run build`: przechodzi.
- Migracja `045` na istniejącej bazie: 44 → 45, tabele akcji powstały;
  powtórne uruchomienie zatrzymuje się na 45.
- Aplikacja iOS na urządzeniu: rozmowa dwukierunkowa działa, narzędzia agenta
  wołane w trakcie rozmowy (audyt: `get_today_overview`, `search_clients` — 200).
