#!/usr/bin/env python3
"""Kontrola struktury kontraktu API (`docs/ios/api/emma-mobile-api.yaml`).

Po co: w tym środowisku nie ma narzędzia do walidacji OpenAPI (brak `pyyaml`,
`pip`, Ruby'ego i sieci). Ten skrypt sprawdza to, co da się sprawdzić bez
pełnego parsera:

  * brak tabulatorów (YAML ich nie dopuszcza we wcięciach),
  * brak powtórzonych kluczy ścieżek (duplikat po cichu nadpisuje pierwszą definicję),
  * kompletność odwołań `$ref` do schematów, odpowiedzi i parametrów.

Czego NIE robi: nie jest walidatorem OpenAPI. Nie sprawdza zgodności ze
specyfikacją, typów pól, poprawności wyrażeń `pattern` ani przykładów.
Pełną walidację należy wykonać na Macu (`npx @redocly/cli lint` albo
`swagger-cli validate`) i dopisać wynik do raportu.
"""

from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path

SPEC = Path(__file__).resolve().parent.parent.parent / "docs/ios/api/emma-mobile-api.yaml"


def main() -> int:
    if not SPEC.exists():
        print(f"[BŁĄD] Brak pliku kontraktu: {SPEC}")
        return 2

    text = SPEC.read_text(encoding="utf-8")
    lines = text.split("\n")
    problems: list[str] = []

    # 1. Tabulatory.
    for number, line in enumerate(lines, start=1):
        if "\t" in line:
            problems.append(f"{number}: tabulator w YAML")

    # 2. Powtórzone klucze ścieżek.
    path_keys = re.findall(r"^  (/[^:]*):\s*$", text, re.MULTILINE)
    duplicates = [key for key, count in Counter(path_keys).items() if count > 1]
    for key in duplicates:
        problems.append(f"powtórzony klucz ścieżki: {key} (druga definicja nadpisuje pierwszą)")

    # 3. Kompletność odwołań.
    declared: dict[str, set[str]] = {"schemas": set(), "responses": set(), "parameters": set()}
    section: str | None = None
    for line in lines:
        header = re.match(r"^  (schemas|responses|parameters):\s*$", line)
        if header:
            section = header.group(1)
            continue
        if re.match(r"^  \w", line) and not line.startswith("    "):
            section = None
        if section:
            entry = re.match(r"^    (\w+):\s*$", line)
            if entry:
                declared[section].add(entry.group(1))

    references = set(re.findall(r"#/components/(schemas|responses|parameters)/(\w+)", text))
    for kind, name in sorted(references):
        if name not in declared[kind]:
            problems.append(f"odwołanie do nieistniejącego elementu: {kind}/{name}")

    paths = len(path_keys) - (len(duplicates) and sum(1 for _ in duplicates) or 0)
    operations = len(re.findall(r"^    (get|post|put|patch|delete):", text, re.MULTILINE))

    print(f"Kontrakt API: {len(path_keys)} ścieżek, {operations} operacji, {len(declared['schemas'])} schematów")
    print(f"Odwołania $ref: {len(references)}, wszystkie rozwiązane: {'tak' if not problems else 'nie'}")

    if problems:
        print("\nProblemy:")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print("Uwaga: to kontrola struktury, nie walidacja OpenAPI.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
