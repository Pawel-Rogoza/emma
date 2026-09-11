# BASELINE — etap 00

Audyt wykonany: 2026-11-09 (czas lokalny maszyny `forest`).
Autor audytu: model wdrażający. Dokument opisuje **stan faktyczny**, nie plan.

## 1. Środowisko wykonawcze

| Element | Zmierzona wartość |
| --- | --- |
| System | CachyOS Linux, kernel `7.2.3-1-cachyos`, x86_64 |
| macOS / Xcode | **brak**. `sw_vers` nie istnieje, `xcodebuild` nie istnieje |
| Swift / SwiftUI | **brak natywnego** toolchainu w systemie (`swift` nie ma w PATH) |
| Dodatkowy toolchain | Swift 6.1 for Ubuntu 24.04 zainstalowany lokalnie w `~/.local/swift` **tylko do weryfikacji logiki i składni** (patrz `BUILD_AND_DEVICE_STATUS.md`) |
| Symulatory iOS | **brak** (wymagają macOS + Xcode) |
| Fizyczny iPhone | **brak dostępu** |
| Docker | CLI obecny, **demon nie działa** (`/var/run/docker.sock` nie istnieje) → obraz `swift:6.1` nie był dostępny |
| sudo | brak hasła → instalacje wyłącznie w katalogu domowym |
| Sieć | działa (GitHub API 200) |
| Node/npm/pnpm/python3/jq | obecne | 
| XcodeGen / Tuist / mint | **nieobecne** (oczekiwane; narzędzie macOS) |

**Wniosek dla odbioru:** żadna kompilacja SwiftUI, żaden test na symulatorze iOS i żaden test
na fizycznym iPhonie nie może być wykonany w tym środowisku. Wszystkie takie bramki są
oznaczone `not_run` i **nie mogą** być oznaczone PASS. Zgodnie z §1.13 planu.

## 2. Referencja designu — weryfikacja integralności

Sprawdzono sumy kontrolne plików referencyjnych wobec `reference/manifest.json`:

| Plik | sha256 (zmierzony) | zgodność z manifestem |
| --- | --- | --- |
| `reference/prototype/app.js` | `f37d2ddb…cc2bad` | ✅ zgodny |
| `reference/prototype/index.html` | `448a068b…d987a0` | ✅ zgodny |
| `reference/prototype/style.css` | `98625267…3d6b72` | ✅ zgodny |
| `reference/previous-plan/Emma-Legacy-Voice-Plan.md` | `79ee0295…dbd024` | ✅ zgodny |

Commit referencyjny: `b97685b5e2c2cd3d6f78b172b9c0b5cee114270b`, opublikowana wersja 5.
Referencja jest **kompletna i niezmieniona**. Reprodukcja:

```bash
cd reference/prototype && sha256sum app.js index.html style.css
jq -r '.files[] | "\(.path) \(.sha256)"' reference/manifest.json
```

## 3. Audyt backendu kancelarii — wynik: `blocked_external`

Poprzedni plan wskazywał backend `Pawel-Rogoza/adwokat-app-project` na SHA
`43f7f9bd854d448daf84cc8f609282f09f6ffa18`. Weryfikacja na **aktualnym** stanie:

```bash
git ls-remote https://github.com/Pawel-Rogoza/adwokat-app-project.git
# → fatal: could not read Username for 'https://github.com'  (brak dostępu, repo prywatne)

curl -sS -o /dev/null -w '%{http_code}\n' \
  https://api.github.com/repos/Pawel-Rogoza/adwokat-app-project   # → 404 (prywatne lub nieistniejące)
curl -sS -o /dev/null -w '%{http_code}\n' \
  https://api.github.com/repos/Pawel-Rogoza/adwokat               # → 404
curl -sS https://api.github.com/users/Pawel-Rogoza                # → 200 (konto istnieje, publiczne)
```

Ustalenia:

1. Konto `Pawel-Rogoza` istnieje i jest publiczne, ale oba repozytoria zwracają 404 dla
   nieuwierzytelnionego klienta, a `git ls-remote` żąda poświadczeń. Repozytorium jest
   **prywatne** albo nie istnieje pod tą nazwą.
2. **Nie wykonano** nowego audytu kodu backendu. Historyczne ustalenia z załącznika
   (`case_actions`, race w akcjach, paginacja ostatniej historii, daty, helper WhatsApp)
   pozostają **niezweryfikowane** i nie są tu powtarzane jako fakty.
3. SHA `43f7f9bd…` **nie zostało potwierdzone**. Nie wiadomo, czy jest aktualne.
4. Brak dostępu do backendu **nie blokuje** M1. Warstwa sieciowa jest zaprojektowana
   (nie zaimplementowana jako live), kontrakty są oznaczone jako projektowane.
5. Odblokowanie: właściciel udostępnia repozytorium (read-only deploy key lub konto
   maszyny) albo wkleja `git rev-parse HEAD`, drzewo plików i schemat DB. Wtedy etap 07
   wykonuje się na rzeczywistym SHA.

Reprodukcja powyższego audytu: `ios/scripts/audit-backend.sh` (dodany w etapie 01).

## 4. Audyt referencji UI — co jest wzorcem, a co nie

`index.html` zawiera **wyłącznie dekorację podglądu**: `.iphone-preview`, `.statusbar`
z godziną `9:41`, `.island` (sztuczna wyspa), `.device-indicators`, `.home-indicator`,
`.preview-caption`. Zgodnie z §1.4 planu **żaden z tych elementów nie jest przenoszony do
aplikacji iOS** — zapewnia je urządzenie.

Warstwa CSS jest kaskadowa i zawiera martwy kod desktopowy. Rozpoznane warstwy:

| Linie `style.css` | Rola | Czy obowiązuje? |
| --- | --- | --- |
| 2 | baza v1 (paleta, typografia) + `.studio`/`.intro`/`.details` (landing desktop) | częściowo: tokeny tak, layout nie |
| 4 | „workspace extension”: `.workspace`, `.sidebar`, `#desktop-nav`, `.work-panel` | **nie** — to odrzucony desktopowy CRM |
| 11–14 | `.iphone-preview` — kanoniczna prezentacja | **tak**, po odjęciu ramki/statusbaru |
| 16–24 | komunikator i composer (ostatnie nadpisania) | **tak** — rozstrzygają wygląd czatu |
| 5–8, 25, 28 | media queries dla `.workspace`/`.studio` | **nie** |
| 9, 13 | `max-width:365px` — adaptacja małych ekranów | **tak** jako wzorzec adaptacji |

Martwe selektory, które **nie** określają aktualnego UI: `.studio`, `.intro`, `.details`,
`.brandmark`, `.workspace`, `.sidebar`, `#desktop-nav`, `.work-panel`, `.team-presence`,
`.timeline>span`, `.message-bubble`/`.message-time`/`.chat-row`/`.chat-emma`/`.chat-context`/
`.translation`/`.compose`/`.mic-main` (zastąpione przez `.chat-message`, `.messenger-row`,
`.chat-composer`, `.assistant-compose`).

Zasada odbioru: **obowiązuje wynik kaskady**, nie pierwszy znaleziony selektor (§2.1 planu).

## 5. Stan repozytorium projektu

`/home/pawel/Projekty/Emma` **nie było repozytorium git** (brak `.git`). W celu prowadzenia
małych, identyfikowalnych przyrostów zainicjowano lokalne repozytorium (`git init`) i
wykonywane są commity po każdym etapie. Nie tworzono zdalnego repo ani fikcyjnych PR-ów.

## 6. Macierz: istnieje / do adaptacji / do utworzenia (stan wejściowy)

| Obszar | Stan na wejściu |
| --- | --- |
| Projekt Xcode (`ios/`) | **do utworzenia** (nie istniał żaden plik Swift) |
| Swift/SwiftUI źródła | **do utworzenia** |
| Testy | **do utworzenia** |
| Design tokens | **istnieją jako CSS** → do przeniesienia i zamrożenia |
| Procesy demo (dane, formularze, filtry) | **istnieją w `app.js`** → do odtworzenia natywnie |
| Voice | **istnieje jako Web Speech API** → do zaprojektowania od nowa natywnie |
| Backend / API | **niezweryfikowane** (`blocked_external`) |
| Konta ElevenLabs / Qwen / Meta | **brak** → `blocked_external` |
| Dokumentacja | **do utworzenia** (ten plik i pozostałe w `docs/ios/`) |

## 7. Następny krok

Etap 01: `ios/project.yml` (XcodeGen jako jedyne źródło konfiguracji), shared schemes
`Emma-Demo` / `Emma-Staging` / `Emma-Production`, `AppDependencies`, `.xcconfig` bez
sekretów, skrypt generacji z kontrolą narzędzi, `README-XCODE.md`.
