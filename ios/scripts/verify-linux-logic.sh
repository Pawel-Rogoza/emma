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

echo "== 1/7 · Kompilacja i testy logiki (SwiftPM) =="
if ! "$SWIFT" test 2>&1 | grep -vE 'no version information'; then
  echo "[BŁĄD] Testy logiki nie przeszły." >&2
  exit 1
fi
echo

echo "== 2/7 · Kontrola składni wszystkich plików Swift (w tym SwiftUI) =="
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
echo "== 3/7 · Kontrola odwołań do zależności i repozytorium =="
if command -v python3 >/dev/null 2>&1; then
  if ! python3 scripts/check-cross-references.py; then
    echo "[BŁĄD] Znaleziono odwołania do nieistniejących składowych." >&2
    exit 1
  fi
else
  echo "[POMINIĘTE] Brak python3 — kontrola odwołań nie została wykonana."
fi

echo
echo "== 4/7 · Kontrola struktury kontraktu API =="
if command -v python3 >/dev/null 2>&1; then
  if ! python3 scripts/validate-api-spec.py; then
    echo "[BŁĄD] Kontrakt API ma problem strukturalny." >&2
    exit 1
  fi
else
  echo "[POMINIĘTE] Brak python3 — kontrola kontraktu API nie została wykonana."
fi

echo
echo "== 5/7 · Kontrola struktury workflow CI dla macOS =="
if command -v python3 >/dev/null 2>&1; then
  if ! python3 scripts/validate-ci-workflow.py; then
    echo "[BŁĄD] Workflow CI ma problem strukturalny." >&2
    exit 1
  fi
else
  echo "[POMINIĘTE] Brak python3 — kontrola workflow nie została wykonana."
fi

echo
echo "== 6/7 · Kontrola tokenów koloru wobec referencji =="
# Wymóg: żaden kolor użyty w Swift nie może być wymyślony — każdy musi mieć
# odpowiednik w regułach referencji. Kategoria „✗ kolory spoza referencji” to błąd.
if command -v python3 >/dev/null 2>&1; then
  token_report="$(python3 scripts/design-token-diff.py 2>&1)"
  invented="$(printf '%s\n' "$token_report" | grep -c '✗ kolory spoza referencji' || true)"
  shared="$(printf '%s\n' "$token_report" | grep -c '· kolory spoza reguł' || true)"
  echo "Kolory spoza referencji: $invented · tokeny współdzielone (do oka): $shared"
  if (( invented > 0 )); then
    printf '%s\n' "$token_report" | grep '✗ kolory spoza referencji' | sed 's/^/  /'
    echo "[BŁĄD] Kolor użyty w kodzie nie występuje w referencji." >&2
    exit 1
  fi
else
  echo "[POMINIĘTE] Brak python3 — kontrola tokenów nie została wykonana."
fi

echo
echo "== 7/7 · Pomiar renderu podglądu (jeśli zbudowany i jest przeglądarka) =="
# Ten krok mierzy PRAWDZIWY render strony podglądu: czcionki, wystawanie poza okno,
# ucinanie tekstu, nachodzenie elementów. Bez przeglądarki mówimy wprost, że
# podgląd nie został zmierzony — a nie że jest poprawny.
if [[ ! -f .preview/index.html ]]; then
  echo "[POMINIĘTE] Nie ma .preview/index.html — zbuduj: python3 scripts/build-preview.py"
elif ! command -v firefox >/dev/null 2>&1; then
  echo "[POMINIĘTE] Brak przeglądarki (firefox) — renderu nie zmierzono."
elif ! command -v python3 >/dev/null 2>&1; then
  echo "[POMINIĘTE] Brak python3 — renderu nie zmierzono."
else
  if ! python3 scripts/verify-preview-render.py; then
    echo "[BŁĄD] Render podglądu ma defekty (patrz raport wyżej)." >&2
    exit 1
  fi
fi

cat <<'EOF'

Wynik:
  - logika i testy: sprawdzone przez wykonanie kodu
  - składnia plików SwiftUI: sprawdzona przez parser Swifta
  - odwołania do zależności i typów systemowych: sprawdzone filtrem nazw (nie kontrola typów)
  - struktura kontraktu API: sprawdzona (nie jest to walidacja OpenAPI)
  - struktura workflow CI dla macOS: sprawdzona (nie jest to walidacja GitHub Actions)
  - tokeny koloru: sprawdzone wobec reguł referencji (żaden kolor nie jest wymyślony)
  - podgląd aplikacji dla Linuksa: .preview/index.html, render mierzony w przeglądarce
    (czcionki, szerokości, ucinanie, nakładanie) — to rekonstrukcja, nie render SwiftUI
  - podgląd wzorca designu: reference/prototype/index.html w przeglądarce (to wzorzec, nie aplikacja)
  - kompilacja SwiftUI, symulator iOS, test iPhone'a: NIE WYKONANE (brak macOS/Xcode)
EOF
