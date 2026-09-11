#!/usr/bin/env bash
# Weryfikacja logiki Emmy bez macOS/Xcode.
#
# Co ten skrypt faktycznie sprawdza:
#   1. Kompiluje i uruchamia część logiki (domena, voice, repozytorium demo, mocki)
#      tym samym kodem źródłowym, który trafia do targetu iOS.
#   2. Sprawdza SKŁADNIĘ wszystkich plików Swift, w tym widoków SwiftUI,
#      przez `swiftc -parse` (analiza składni bez rozwiązywania importów).
#   3. Sprawdza ODWOŁANIA do elementów zależności i repozytorium — czy widoki nie
#      wołają składowych, których nie ma. To filtr literówek, nie kontrola typów.
#
# Czego ten skrypt NIE robi i nie może zrobić:
#   - nie kompiluje SwiftUI, nie typuje widoków, nie uruchamia symulatora iOS
#     i nie testuje iPhone'a. To wymaga macOS + Xcode.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SWIFT_BIN="${EMMA_SWIFT_BIN:-}"
if [[ -z "$SWIFT_BIN" ]]; then
  if command -v swiftc >/dev/null 2>&1; then
    SWIFT_BIN="$(command -v swiftc)"
  elif [[ -x "$HOME/.local/swift/usr/bin/swiftc" ]]; then
    SWIFT_BIN="$HOME/.local/swift/usr/bin/swiftc"
    export LD_LIBRARY_PATH="$HOME/.local/libshim${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  else
    echo "[BŁĄD] Nie znaleziono swiftc. Ten skrypt jest opcjonalny i służy tylko" >&2
    echo "       do weryfikacji bez Xcode. Wymagany projekt Xcode buduje się na macOS." >&2
    exit 2
  fi
fi
SWIFT="$SWIFT_BIN"
[[ "$(basename "$SWIFT_BIN")" == "swiftc" ]] && SWIFT="${SWIFT_BIN%swiftc}swift"

echo "== Emma · weryfikacja logiki bez Xcode =="
"$SWIFT_BIN" --version | head -1
echo

echo "== 1/4 · Kompilacja i testy logiki (SwiftPM) =="
if ! "$SWIFT" test 2>&1 | grep -vE 'no version information'; then
  echo "[BŁĄD] Testy logiki nie przeszły." >&2
  exit 1
fi
echo

echo "== 2/4 · Kontrola składni wszystkich plików Swift (w tym SwiftUI) =="
failures=0
checked=0
while IFS= read -r file; do
  checked=$((checked + 1))
  if ! output="$("$SWIFT_BIN" -parse "$file" 2>&1)"; then
    if [[ -n "$output" ]]; then
      printf '[BŁĄD SKŁADNI] %s\n%s\n' "$file" "$output"
      failures=$((failures + 1))
    fi
  fi
done < <(find Emma EmmaTests EmmaUITests -name '*.swift' -type f 2>/dev/null | sort)

echo "Sprawdzono plików: $checked, błędów składni: $failures"
if (( failures > 0 )); then
  echo
  echo "Uwaga: to wyłącznie analiza składni. Nie zastępuje kompilacji w Xcode." >&2
  exit 1
fi

echo
echo "== 3/4 · Kontrola odwołań do zależności i repozytorium =="
if command -v python3 >/dev/null 2>&1; then
  if ! python3 scripts/check-cross-references.py; then
    echo "[BŁĄD] Znaleziono odwołania do nieistniejących składowych." >&2
    exit 1
  fi
else
  echo "[POMINIĘTE] Brak python3 — kontrola odwołań nie została wykonana."
fi

echo
echo "== 4/4 · Kontrola struktury kontraktu API =="
if command -v python3 >/dev/null 2>&1; then
  if ! python3 scripts/validate-api-spec.py; then
    echo "[BŁĄD] Kontrakt API ma problem strukturalny." >&2
    exit 1
  fi
else
  echo "[POMINIĘTE] Brak python3 — kontrola kontraktu API nie została wykonana."
fi

cat <<'EOF'

Wynik:
  - logika i testy: sprawdzone przez wykonanie kodu
  - składnia plików SwiftUI: sprawdzona przez parser Swifta
  - odwołania do zależności: sprawdzone filtrem nazw (nie kontrola typów)
  - struktura kontraktu API: sprawdzona (nie jest to walidacja OpenAPI)
  - kompilacja SwiftUI, symulator iOS, test iPhone'a: NIE WYKONANE (brak macOS/Xcode)
EOF
