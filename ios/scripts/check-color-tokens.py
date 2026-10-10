#!/usr/bin/env python3
"""Kontrola tokenów koloru (od 0.22.0, po zakończeniu zamrożonego kontraktu).

Wcześniej `design-token-diff.py` odrzucał każdy kolor, którego nie było
w CSS prototypu HTML. Redesign na iOS 26 kończy tamten kontrakt: kolory mają
znaczenie (akcent, Emma, krytyczny, ostrzeżenie, gotowe), a nie pochodzenie.

Ta bramka pilnuje dwóch rzeczy:

  1. **Literały tylko w motywie.** `Color(hex:)`, `Color(red:…)` i `UIColor(red:…)`
     wolno pisać wyłącznie w `DesignSystem/EmmaTheme.swift` (oraz w renderze
     postaci Emmy, `EmmaOrb.swift`, który ma własny gradient światła). Ekrany
     używają tokenów `EmmaTheme`.
  2. **Semantyka istnieje.** Motyw definiuje tokeny semantyczne, na które
     wskazują starsze nazwy.

Użycie:
    python3 ios/scripts/check-color-tokens.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "Emma"
THEME = SWIFT / "DesignSystem/EmmaTheme.swift"

ALLOWED_LITERAL_FILES = {
    "DesignSystem/EmmaTheme.swift",
    "DesignSystem/EmmaOrb.swift",
}

LITERAL = re.compile(r"\bColor\(\s*(hex:|red:|\.sRGB)|\bUIColor\(\s*red:")

SEMANTIC = ("accent", "emma", "critical", "warning", "positive")


def main() -> int:
    problems: list[str] = []
    for path in sorted(SWIFT.rglob("*.swift")):
        relative = path.relative_to(SWIFT).as_posix()
        if relative in ALLOWED_LITERAL_FILES:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if line.lstrip().startswith("//"):
                continue
            if LITERAL.search(line):
                problems.append(f"{relative}:{number}: literał koloru poza motywem — użyj tokenu EmmaTheme")

    theme = THEME.read_text(encoding="utf-8")
    for name in SEMANTIC:
        if not re.search(rf"public static let {name} = ", theme):
            problems.append(f"EmmaTheme.swift: brak tokenu semantycznego `{name}`")

    print("== Kontrola tokenów koloru ==")
    if problems:
        print("[BŁĄD]")
        for problem in problems:
            print(f"  {problem}")
        return 1
    print(f"Literały kolorów tylko w motywie; tokeny semantyczne: {', '.join(SEMANTIC)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
