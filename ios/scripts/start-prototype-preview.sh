#!/usr/bin/env bash
# Uruchamia lokalny podgląd wzorca designu (prototypu HTML) na Linuksie.
#
# Po co: właściciel pracuje na Linuksie i nie ma Maca. SwiftUI nie działa poza
# platformami Apple, więc **nie da się** obejrzeć prawdziwej aplikacji — ale można
# obejrzeć zatwierdzony wzorzec, względem którego aplikacja jest oceniana.
#
# Uwaga na uczciwość: prototyp to wzorzec, a nie aplikacja. Wygląda podobnie,
# ale to inny kod. Podgląd nie jest dowodem, że interfejs SwiftUI działa.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROTOTYPE="$ROOT/reference/prototype"
PORT="${EMMA_PREVIEW_PORT:-8099}"

if [[ ! -f "$PROTOTYPE/index.html" ]]; then
  printf '[BŁĄD] Nie znaleziono prototypu w %s\n' "$PROTOTYPE" >&2
  exit 1
fi

if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -q ":$PORT "; then
  printf 'Port %s jest już zajęty — podgląd prawdopodobnie działa.\n' "$PORT"
  printf 'Otwórz: http://127.0.0.1:%s/\n' "$PORT"
  exit 0
fi

printf 'Emma · podgląd wzorca designu\n'
printf 'Katalog: %s\n' "$PROTOTYPE"
printf 'Adres:   http://127.0.0.1:%s/\n\n' "$PORT"
printf 'Zatrzymanie: Ctrl+C\n\n'

cd "$PROTOTYPE"
exec python3 -m http.server "$PORT" --bind 127.0.0.1
