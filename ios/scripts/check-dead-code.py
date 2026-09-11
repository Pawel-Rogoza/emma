#!/usr/bin/env python3
"""Kontrola martwego publicznego API rdzenia.

Po co: publiczna składowa w rdzeniu bez ani jednego użycia to obietnica, której nikt
nie sprawdził — a przy okazji miejsce, w którym łatwo powstać mogą **dwie**
implementacje tej samej reguły (jedna używana, druga „na przyszłość”). Ten skrypt
zamienia „chyba nikt tego nie woła” na liczbę.

Jak liczy: dla każdej publicznej składowej `Emma/Core/**` zlicza wystąpienia jej nazwy
we **wszystkich** źródłach Swift w repozytorium (aplikacja, testy, testy UI, eksporter
podglądu) i odejmuje jedno na samą deklarację.

Czego to NIE jest:
  * kontrola typów ani kompilator — to wyszukiwanie nazw,
  * komentarze liczą się jak użycie (świadomie: komentarz cytujący nazwę to sygnał,
    że ktoś tę nazwę widział — ale to znaczy, że wynik jest **zaniżony**, nie zawyżony),
  * składowe wymagane przez protokoły (`description`, `id`) mogą wyjść jako martwe,
    choć są wołane pośrednio — dlatego lista `ALLOWED` jest jawna, a nie ukryta.

Użycie:
    python3 ios/scripts/check-dead-code.py
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ["Emma", "EmmaTests", "EmmaUITests", "EmmaPreview"]

# Składowe wołane pośrednio (protokoły, interpolacja tekstu, synteza) — nie są martwe.
ALLOWED = {
    "description",   # CustomStringConvertible: wołane przez interpolację i `print`
    "id",            # Identifiable: wołane przez SwiftUI
    "debugDescription",
    "hash",
    "body",          # View.body: wołane przez SwiftUI
}


def declarations() -> list[tuple[pathlib.Path, str]]:
    found: list[tuple[pathlib.Path, str]] = []
    for path in sorted((ROOT / "Emma/Core").rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for match in re.finditer(r"^[ \t]*public (?:static )?(?:func|var|let) (\w+)", text, re.M):
            found.append((path, match.group(1)))
    return found


def main() -> int:
    files = [f for source in SOURCES for f in sorted((ROOT / source).rglob("*.swift"))]
    texts = {path: path.read_text(encoding="utf-8") for path in files}

    dead: list[tuple[pathlib.Path, str]] = []
    checked = 0
    for path, name in declarations():
        if name in ALLOWED:
            continue
        checked += 1
        occurrences = sum(len(re.findall(rf"\b{re.escape(name)}\b", text)) for text in texts.values())
        # Jedno wystąpienie to sama deklaracja.
        if occurrences - 1 <= 0:
            dead.append((path, name))

    if dead:
        print("Martwe publiczne API rdzenia (nikt nie woła — ani aplikacja, ani testy):")
        for path, name in dead:
            print(f"  - {path.relative_to(ROOT)}: {name}")
        print(f"\nRazem: {len(dead)}")
        print("\nCo z tym zrobić: wpiąć w kod albo usunąć. Zostawienie „na przyszłość”")
        print("kończy się drugą implementacją tej samej reguły.")
        return 1

    print(f"Martwe publiczne API rdzenia: brak (sprawdzono {checked} składowych, "
          f"pominięto {len(ALLOWED)} wymaganych przez protokoły).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
