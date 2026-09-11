#!/usr/bin/env bash
#
# Uruchamia podgląd aplikacji przygotowany dla Linuksa.
#
# Co robi: generuje stronę z prawdziwych danych i tokenów aplikacji
# (`build-preview.py`) i wystawia ją lokalnie.
#
# Czym to NIE jest: to nie jest build aplikacji ani render SwiftUI. Układ ekranów
# jest rekonstrukcją referencji w HTML — patrz nagłówek `build-preview.py`.
#
# Użycie:
#   ./scripts/start-preview.sh            # zbuduj i podaj na porcie 8098
#   PORT=9000 ./scripts/start-preview.sh  # inny port

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8098}"

# Swift z instalacji lokalnej, jeśli nie ma go w PATH.
if ! command -v swift >/dev/null 2>&1 && [ -x "$HOME/.local/swift/usr/bin/swift" ]; then
  export PATH="$HOME/.local/swift/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$HOME/.local/libshim${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

echo "Buduję podgląd z kodu aplikacji…"
python3 "$ROOT/scripts/build-preview.py"

if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$PORT" 2>/dev/null | grep -q ":$PORT"; then
  echo "Port $PORT jest już zajęty — otwórz istniejący podgląd albo ustaw PORT=…"
  exit 1
fi

echo
echo "Podgląd: http://127.0.0.1:$PORT/"
echo "To nie jest render SwiftUI — szczegóły w nagłówku strony."
echo
exec python3 -m http.server "$PORT" --directory "$ROOT/.preview" --bind 127.0.0.1
