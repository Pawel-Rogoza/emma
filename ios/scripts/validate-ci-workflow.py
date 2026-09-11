#!/usr/bin/env python3
"""Kontrola struktury workflow GitHub Actions dla macOS.

Po co: workflow jest jedyną drogą do prawdziwej kompilacji SwiftUI bez Maca,
a w tym środowisku **nie da się go uruchomić**. Zamiast zatem twierdzić, że
„działa”, sprawdzamy to, co da się sprawdzić bez runnera:

  * brak tabulatorów i wcięć łamiących bloki `run: |` (najczęstszy błąd YAML,
    który kończy blok skryptu w środku i psuje cały przebieg),
  * obecność kluczowych elementów: runner macOS, kroki generowania projektu
    i publikacji artefaktów,
  * istnienie plików i skryptów, do których workflow się odwołuje,
  * brak sekretów i kluczy wpisanych wprost w pliku.

Czego NIE robi: nie jest walidatorem YAML ani GitHub Actions. Nie sprawdzi
poprawności wyrażeń `${{ … }}`, dostępności akcji ani nazw symulatorów na runnerze.
Pierwszy przebieg w GitHubie jest dopiero prawdziwym testem — i tak trzeba go opisać.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
WORKFLOW = ROOT / ".github/workflows/ios-macos.yml"

# Pliki, których workflow potrzebuje po stronie repozytorium.
REQUIRED_PATHS = [
    "ios/project.yml",
    "ios/scripts/generate-project.sh",
    "ios/scripts/verify-linux-logic.sh",
    "ios/EmmaUITests/ScreenshotCaptureUITests.swift",
]

# Wzorce, które nigdy nie powinny trafić do workflow.
SECRET_PATTERNS = [
    (r"sk-[A-Za-z0-9]{10,}", "wygląda na klucz API"),
    (r"(?i)\b(api[_-]?key|secret|token)\s*[:=]\s*['\"][^'\"{$][^'\"]{6,}", "wartość sekretu wpisana wprost"),
    (r"ELEVENLABS_[A-Z_]*KEY", "nazwa klucza dostawcy w workflow"),
]


def main() -> int:
    if not WORKFLOW.exists():
        print(f"[BŁĄD] Brak pliku workflow: {WORKFLOW}")
        return 2

    text = WORKFLOW.read_text(encoding="utf-8")
    lines = text.split("\n")
    problems: list[str] = []

    # 1. Tabulatory (YAML ich nie dopuszcza we wcięciach).
    for number, line in enumerate(lines, start=1):
        if "\t" in line:
            problems.append(f"{number}: tabulator w YAML")

    # 2. Bloki skryptów: każda niepusta linia musi być głębiej wcięta niż `run:`.
    index = 0
    while index < len(lines):
        header = re.match(r"^(\s*)run: \|\s*$", lines[index])
        if not header:
            index += 1
            continue
        base = len(header.group(1))
        cursor = index + 1
        while cursor < len(lines):
            line = lines[cursor]
            if line.strip() == "":
                cursor += 1
                continue
            indent = len(line) - len(line.lstrip(" "))
            if indent <= base:
                break
            cursor += 1
        index = cursor

    # 3. Elementy obowiązkowe.
    required_fragments = {
        "runner macOS": r"runs-on:\s*macos-\d+",
        "wyzwalacz ręczny": r"workflow_dispatch:",
        "instalacja XcodeGen": r"brew install xcodegen",
        "generowanie projektu": r"\./scripts/generate-project\.sh",
        "kontrola typów (build)": r"xcodebuild build",
        "testy jednostkowe": r"xcodebuild test[\s\S]{0,400}only-testing:EmmaTests",
        "zrzuty ekranu": r"only-testing:EmmaUITests/ScreenshotCaptureUITests",
        "publikacja artefaktów": r"actions/upload-artifact@v\d+",
        "podsumowanie przebiegu": r"GITHUB_STEP_SUMMARY",
    }
    for description, pattern in required_fragments.items():
        if not re.search(pattern, text, re.MULTILINE):
            problems.append(f"brak elementu: {description}")

    # 4. Pliki, na których workflow polega.
    for relative in REQUIRED_PATHS:
        if not (ROOT / relative).exists():
            problems.append(f"workflow odwołuje się do nieistniejącego pliku: {relative}")

    # 5. Sekrety wpisane wprost.
    for pattern, description in SECRET_PATTERNS:
        for match in re.finditer(pattern, text):
            line_number = text[: match.start()].count("\n") + 1
            problems.append(f"{line_number}: {description}")

    # Zadania liczymy wyłącznie wewnątrz sekcji `jobs:` — inaczej do wyniku wchodzą
    # klucze wyzwalaczy (`push`, `pull_request`) leżące na tym samym poziomie wcięcia.
    jobs_section = text.split("\njobs:\n", 1)[-1]
    jobs = len(re.findall(r"^  [a-zA-Z0-9_-]+:\s*$", jobs_section, re.MULTILINE))
    steps = len(re.findall(r"^      - name:", text, re.MULTILINE))
    print(f"Workflow: {jobs} zadanie, {steps} kroków, {len(lines)} linii")

    if problems:
        print("\nProblemy:")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print("Struktura workflow: bez zastrzeżeń (to nie jest walidacja GitHub Actions).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
