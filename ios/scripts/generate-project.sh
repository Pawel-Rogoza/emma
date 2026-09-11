#!/usr/bin/env bash
# Generuje ios/Emma.xcodeproj z ios/project.yml (XcodeGen).
#
# Skrypt sprawdza narzędzia i podaje jasny komunikat braków. Nie instaluje
# automatycznie środowiska i nie zmienia globalnej konfiguracji Xcode (§14.1 pkt 3).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  printf '\n[BŁĄD] %s\n' "$1" >&2
  shift
  for line in "$@"; do printf '       %s\n' "$line" >&2; done
  printf '\n' >&2
  exit 1
}

printf 'Emma · generator projektu Xcode\n'
printf 'Katalog ios/: %s\n\n' "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "Ten skrypt wymaga macOS." \
    "Nie jestem w stanie wygenerować .xcodeproj na Linuksie: XcodeGen i Xcode są dostępne tylko na macOS." \
    "Na Linuksie można natomiast uruchomić: ./scripts/verify-linux-logic.sh" \
    "(kompiluje i testuje część logiki Swift bez SwiftUI)." \
    "Projekt jest reprodukowalny: na Macu wystarczy uruchomić ten skrypt."
fi

missing=()
command -v xcodegen >/dev/null 2>&1 || missing+=("xcodegen  (instalacja: brew install xcodegen)")
command -v xcodebuild >/dev/null 2>&1 || missing+=("xcodebuild (instalacja: Xcode z App Store)")
command -v xcrun >/dev/null 2>&1 || missing+=("xcrun      (część Xcode Command Line Tools)")

if ((${#missing[@]})); then
  fail "Brak wymaganych narzędzi:" "${missing[@]}"
fi

[[ -f project.yml ]] || fail "Nie znaleziono ios/project.yml."

printf 'xcodegen:   %s\n' "$(xcodegen --version 2>&1 | head -1)"
printf 'xcodebuild: %s\n\n' "$(xcodebuild -version 2>&1 | head -1)"

printf 'Generuję ios/Emma.xcodeproj …\n'
xcodegen generate --spec project.yml --project .

if [[ ! -d Emma.xcodeproj ]]; then
  fail "XcodeGen zakończył się bez błędu, ale Emma.xcodeproj nie powstał."
fi

printf '\nGotowe. Otwórz:\n'
printf '  open ios/Emma.xcodeproj\n'
printf 'lub zbuduj z linii poleceń:\n'
printf '  xcodebuild -list -project ios/Emma.xcodeproj\n'
printf '  xcodebuild -project ios/Emma.xcodeproj -scheme Emma-Demo \\\n'
printf '    -destination '"'"'generic/platform=iOS Simulator'"'"' \\\n'
printf '    -derivedDataPath .build/DerivedData build CODE_SIGNING_ALLOWED=NO\n'
