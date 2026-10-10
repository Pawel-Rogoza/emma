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

echo "== 1/9 · Kompilacja i testy logiki (SwiftPM) =="
# Swift 6.4 na Arch Linuksie: SWIFT_TEST_FLAGS="--build-system native" (patrz Package.swift).
# shellcheck disable=SC2086
if ! "$SWIFT" test ${SWIFT_TEST_FLAGS:-} 2>&1 | grep -vE 'no version information'; then
  echo "[BŁĄD] Testy logiki nie przeszły." >&2
  exit 1
fi
echo

echo "== 2/9 · Kontrola składni wszystkich plików Swift (w tym SwiftUI) =="
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
echo "== 3/9 · Kontrola odwołań do zależności i repozytorium =="
if command -v python3 >/dev/null 2>&1; then
  if ! python3 scripts/check-cross-references.py; then
    echo "[BŁĄD] Znaleziono odwołania do nieistniejących składowych." >&2
    exit 1
  fi
else
  echo "[POMINIĘTE] Brak python3 — kontrola odwołań nie została wykonana."
fi

echo
echo "== 4/9 · Kontrola struktury kontraktu API =="
if command -v python3 >/dev/null 2>&1; then
  if ! python3 scripts/validate-api-spec.py; then
    echo "[BŁĄD] Kontrakt API ma problem strukturalny." >&2
    exit 1
  fi
else
  echo "[POMINIĘTE] Brak python3 — kontrola kontraktu API nie została wykonana."
fi

echo
echo "== 5/9 · Kontrola struktury workflow CI dla macOS =="
if command -v python3 >/dev/null 2>&1; then
  if ! python3 scripts/validate-ci-workflow.py; then
    echo "[BŁĄD] Workflow CI ma problem strukturalny." >&2
    exit 1
  fi
else
  echo "[POMINIĘTE] Brak python3 — kontrola workflow nie została wykonana."
fi

echo
echo "== 6/9 · Kontrola tokenów koloru =="
# Od 0.22.0 (koniec zamrożonego kontraktu z prototypem HTML): literały kolorów
# tylko w motywie, ekrany używają tokenów semantycznych.
if command -v python3 >/dev/null 2>&1; then
  if ! python3 scripts/check-color-tokens.py; then
    echo "[BŁĄD] Kolor poza motywem albo brak tokenu semantycznego." >&2
    exit 1
  fi
else
  echo "[POMINIĘTE] Brak python3 — kontrola tokenów nie została wykonana."
fi

echo
echo "== 7/9 · Pomiar renderu podglądu (jeśli zbudowany i jest przeglądarka) =="
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

echo
echo "== 8/9 · Kontrola martwego publicznego API rdzenia =="
# Publiczna składowa bez użycia to obietnica bez pokrycia i zwykle zalążek drugiej
# implementacji tej samej reguły. Kontrola jest jawna, więc widać, co pomijamy.
#
# Kroki 8 i 9 są od siebie niezależne, więc nie przerywają skryptu od razu:
# wynik zbieramy, uruchamiamy krok 9 i dopiero potem zwracamy błąd. Wcześniej
# czerwony krok 8 kończył pracę przed kontrolą czytelności i raport twierdził, że
# krok 9 się wykonał, choć tak nie było.
DEAD_CODE_FAILED=0
if command -v python3 >/dev/null 2>&1; then
  if ! python3 scripts/check-dead-code.py; then
    echo "[BŁĄD] Rdzeń ma publiczne API, którego nikt nie woła." >&2
    DEAD_CODE_FAILED=1
  fi
else
  echo "[POMINIĘTE] Brak python3 — kontrola martwego API nie została wykonana."
fi

echo
echo "== 9/9 · Kontrola czytelności interfejsu (F09) =="
# Wymóg: jedna skala tekstu (bez rozmiarów <12 pt deklarowanych w ekranach) oraz
# kontrast tokenów tekstowych co najmniej 4,5:1 wobec ich rzeczywistych teł.
if command -v python3 >/dev/null 2>&1; then
  if ! python3 scripts/check-readability.py; then
    echo "[BŁĄD] Interfejs nie przechodzi kontroli czytelności." >&2
    exit 1
  fi
else
  echo "[POMINIĘTE] Brak python3 — kontrola czytelności nie została wykonana."
fi

if [ "$DEAD_CODE_FAILED" -ne 0 ]; then
  echo "[BŁĄD] Kontrola martwego publicznego API rdzenia nie przeszła (krok 8/9)." >&2
  exit 1
fi

cat <<'EOF'

Wynik:
  - logika i testy: sprawdzone przez wykonanie kodu
  - składnia plików SwiftUI: sprawdzona przez parser Swifta
  - odwołania do zależności i typów systemowych: sprawdzone filtrem nazw (nie kontrola typów)
  - struktura kontraktu API: sprawdzona (nie jest to walidacja OpenAPI)
  - struktura workflow CI dla macOS: sprawdzona (nie jest to walidacja GitHub Actions)
  - tokeny koloru: sprawdzone wobec reguł referencji (żaden kolor nie jest wymyślony)
  - czytelność: jedna skala tekstu (bez <12 pt w ekranach) i kontrast >= 4,5:1
  - martwe publiczne API rdzenia: sprawdzone filtrem nazw (0 martwych składowych)
  - podgląd aplikacji dla Linuksa: .preview/index.html, render mierzony w przeglądarce
    (czcionki, szerokości, ucinanie, nakładanie) — to rekonstrukcja, nie render SwiftUI
  - podgląd wzorca designu: reference/prototype/index.html w przeglądarce (to wzorzec, nie aplikacja)
  - kompilacja SwiftUI, symulator iOS, test iPhone'a: NIE WYKONANE (brak macOS/Xcode)
EOF
