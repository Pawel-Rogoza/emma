# Runbook: aplikacja ↔ lokalny backend

Cel: uruchomić **prawdziwy** backend na tym Macu i zalogować się do niego
aplikacją w symulatorze. Ten przebieg został wykonany 2026-09-14 (etap M1)
i jest podstawą dowodów w `docs/ios/M1_LOGOWANIE_MOBILNE.md`.

Wszystko dzieje się lokalnie: żadne dane nie idą do produkcji, adres
`178.104.190.220` nie jest tu potrzebny.

## 1. Zbuduj backend (raz, po każdej zmianie)

```bash
cd ~/projects/adwokat-app-project
npm ci                 # jeśli brak node_modules
npm run build
```

## 2. Uruchom go na tymczasowej bazie

```bash
DIR=/tmp/emma-live && rm -rf "$DIR" && mkdir -p "$DIR"
NODE_ENV=production \
CRM_HOST=127.0.0.1 \
CRM_DATA_DIR="$DIR" \
CRM_SETUP_CODE=emma-live-kod \
CRM_SESSION_SECRET="$(head -c 32 /dev/urandom | base64)" \
CRM_DATA_ENCRYPTION_KEY="v1:$(head -c 32 /dev/urandom | xxd -p | tr -d '\n')" \
HOST=127.0.0.1 PORT=4399 \
node ./dist/server/entry.mjs
```

Dlaczego tak:
- `CRM_HOST=127.0.0.1` — host-guard panelu przepuszcza `/api/mobile/…` tylko na
  hoście panelu; adres bez portu musi zgadzać się z nagłówkiem `Host`;
- `CRM_DATA_DIR` w `/tmp` — baza jest jednorazowa, nie dotykamy niczyich danych;
- `CRM_SESSION_SECRET` i `CRM_DATA_ENCRYPTION_KEY` — w trybie produkcyjnym są
  wymagane (bez nich trasa zwraca 500, a sekret TOTP nie byłby szyfrowany).

## 3. Załóż konto i weź sekret TOTP

```bash
curl -sS -X POST -H 'Content-Type: application/json' \
  -d '{"code":"emma-live-kod","email":"pawel@majkuny.pl","name":"Paweł Rogoża","password":"Emma-live-2026!"}' \
  http://127.0.0.1:4399/api/crm/auth/setup > /tmp/emma-live/setup.json

python3 -c "
import json,urllib.parse as u
d=json.load(open('/tmp/emma-live/setup.json'))
print(u.parse_qs(u.urlparse(d['totpEnrollUrl']).query)['secret'][0])" > /tmp/emma-live/secret.txt
```

## 3a. Wsyp dane, które istnieją **tylko** w bazie

Test integracyjny z M2b sprawdza, czy aplikacja pokazuje dane z backendu. Żeby
to było dowodem, a nie zbiegiem okoliczności, dane muszą być takie, jakich nie
ma żadna fikstura w kodzie — inaczej wynik przeszedłby także na atrapie:

```bash
sqlite3 /tmp/emma-live/crm.sqlite3 \
  "INSERT INTO clients (name,language,notes,created_at)
     VALUES ('Zenon Backendowicz-Testowy','ukraiński','Notatka','2026-09-10T08:30:00.000Z');
   INSERT INTO cases (client_id,title,signature,stage,opened_at,assignee)
     VALUES (last_insert_rowid(),'Zatrzymanie prawa jazdy','II K 999/26','active','2026-09-11',1);"
```

## 4. Uruchom test integracyjny aplikacji

```bash
cd ~/projects/emma/ios   # albo ~/Desktop/emma/ios
SECRET=$(cat /tmp/emma-live/secret.txt)
TEST_RUNNER_EMMA_UI_BACKEND_URL=http://127.0.0.1:4399 \
TEST_RUNNER_EMMA_UI_LOGIN_EMAIL=pawel@majkuny.pl \
TEST_RUNNER_EMMA_UI_LOGIN_PASSWORD='Emma-live-2026!' \
TEST_RUNNER_EMMA_UI_TOTP_SECRET="$SECRET" \
TEST_RUNNER_EMMA_UI_EXPECT_CLIENT='Zenon Backendowicz-Testowy' \
TEST_RUNNER_EMMA_UI_EXPECT_CASE='II K 999/26' \
xcodebuild -project Emma.xcodeproj -scheme Emma-Demo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build/DerivedData test \
  -only-testing:EmmaUITests/BackendLoginUITests
```

Przedrostek `TEST_RUNNER_` jest konieczny: `xcodebuild` przekazuje do procesu
testów tylko zmienne z tym przedrostkiem (i zdejmuje go po drodze). Bez tego
testy integracyjne same się pomijają (`XCTSkip`).

`EMMA_UI_EXPECT_CLIENT` / `EMMA_UI_EXPECT_CASE` wskazują, co ma się pojawić na
ekranie. Wpisujemy tam dane z bazy, nie z fikstur — inaczej test nie odróżni
odczytu z backendu od atrapy.

**Uwaga o symulatorze:** jeśli testy interfejsu padają na geometrii klawiatury
(`klawiatura programowa poza ekranem`) albo na „Failed to create a bundle
instance”, symulator jest w złym stanie — `xcrun simctl shutdown all` i powtórz
przebieg. Sprawdzone 2026-09-14: po restarcie ten sam test przechodzi.

Bez tych zmiennych testy integracyjne są pomijane, a pełny zestaw Demo
(`swift test`, `xcodebuild test -only-testing:EmmaTests`, UI w Demo) działa
niezależnie od backendu.

## 5. Sprawdź, że to naprawdę zapis w bazie

```bash
sqlite3 /tmp/emma-live/crm.sqlite3 \
  "SELECT installation_id, device_name, revoked_at FROM mobile_sessions;"
sqlite3 /tmp/emma-live/crm.sqlite3 \
  "SELECT action, meta_json FROM audit_log WHERE action LIKE 'mobile%';"
```

## 6. Sprzątanie

```bash
pkill -f "dist/server/entry.mjs"   # zatrzymaj backend
rm -rf /tmp/emma-live              # usuń bazę i sekret
```
