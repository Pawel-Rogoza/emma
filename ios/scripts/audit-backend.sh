#!/usr/bin/env bash
# Audyt backendu kancelarii bez dostępu do repozytorium (§ etap 00).
# Skrypt niczego nie modyfikuje i nie wymaga poświadczeń.
set -uo pipefail

REPO_PRIMARY="Pawel-Rogoza/adwokat-app-project"
REPO_ALT="Pawel-Rogoza/adwokat"
LEGACY_SHA="43f7f9bd854d448daf84cc8f609282f09f6ffa18"
PROTOTYPE_SHA="b97685b5e2c2cd3d6f78b172b9c0b5cee114270b"

printf 'Emma · audyt backendu i referencji\n'
printf 'Data: %s\n\n' "$(date -Iseconds)"

printf '== 1. Referencja designu (lokalna) ==\n'
if [[ -d reference/prototype ]]; then
  ( cd reference/prototype && sha256sum app.js index.html style.css )
  printf 'Oczekiwany commit prototypu: %s\n' "$PROTOTYPE_SHA"
  if [[ -f reference/manifest.json ]] && command -v jq >/dev/null; then
    jq -r '.files[] | "manifest: \(.path) \(.sha256)"' reference/manifest.json
  fi
else
  printf 'Brak katalogu reference/prototype.\n'
fi
printf '\n'

printf '== 2. Widoczność repozytoriów backendu (GitHub API, bez poświadczeń) ==\n'
for slug in "$REPO_PRIMARY" "$REPO_ALT"; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "https://api.github.com/repos/$slug")"
  case "$code" in
    200) printf '  %-40s HTTP %s — publiczne, audyt możliwy\n' "$slug" "$code" ;;
    404) printf '  %-40s HTTP %s — prywatne albo nie istnieje (audyt niemożliwy)\n' "$slug" "$code" ;;
    403) printf '  %-40s HTTP %s — rate limit albo blokada\n' "$slug" "$code" ;;
    *)   printf '  %-40s HTTP %s\n' "$slug" "$code" ;;
  esac
done
printf '\n'

printf '== 3. Dostęp git (bez poświadczeń) ==\n'
for slug in "$REPO_PRIMARY" "$REPO_ALT"; do
  if out="$(GIT_TERMINAL_PROMPT=0 git ls-remote "https://github.com/$slug.git" 2>&1)"; then
    printf '  %s: osiągalne\n' "$slug"
    printf '%s\n' "$out" | head -5
  else
    printf '  %s: brak dostępu — %s\n' "$slug" "$(printf '%s' "$out" | head -1)"
  fi
done
printf '\n'

printf '== 4. Weryfikacja historycznego SHA ==\n'
printf 'Poprzedni plan podawał SHA: %s\n' "$LEGACY_SHA"
printf 'Status: NIEZWERYFIKOWANE — brak dostępu do repozytorium.\n'
printf 'Nie potwierdzono, że to SHA jest aktualne ani że opisane pliki istnieją.\n\n'

printf '== 5. Jak odblokować ==\n'
cat <<'EOF'
Właściciel wykonuje jedno z poniższych:
  a) dodaje read-only deploy key lub konto maszyny do repozytorium, albo
  b) wkleja wynik poleceń:
       git -C <repo> rev-parse HEAD
       git -C <repo> ls-files | head -200
       sqlite3 <baza> ".schema" | head -200
  c) albo oznacza audyt jako niewykonalny i utrzymuje status blocked_external.

Brak dostępu do backendu NIE blokuje M1 (etapy 01–06) ani prac niezależnych.
EOF
