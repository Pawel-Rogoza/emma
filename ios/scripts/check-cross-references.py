#!/usr/bin/env python3
"""Kontrola odwołań między plikami — namiastka kompilatora na Linuksie.

Po co: w tym środowisku nie ma kompilatora Apple, więc `swiftc -parse` sprawdza
wyłącznie składnię. Typowy błąd integracji (wywołanie metody, której nie ma,
albo literówka w nazwie elementu zależności) przechodzi przez parser bez słowa.
Ten skrypt czyta **zadeklarowane** składowe typów współdzielonych i porównuje je
z **użyciami** w widokach.

Czego NIE robi — i co trzeba wiedzieć, czytając jego wynik:

  * nie sprawdza typów, liczby argumentów, etykiet wywołań ani przeciążeń,
  * typy deklarowane w jednym pliku (`EmmaRadii`, `EmmaSpacing`, `EmmaMetrics`)
    mają wspólny zbiór nazw, więc **nie wykryje** użycia `EmmaSpacing.avatar`
    zamiast `EmmaRadii.avatar` — taką pomyłkę wychwyci dopiero kompilator,
  * nie zna zmiennych lokalnych o nazwach `repository`, `voice`, `clock`.

To filtr literówek i braków, nie zamiennik kompilacji. Wynik „brak odwołań bez
deklaracji” znaczy dokładnie tyle, ile napisano: te nazwy istnieją.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "Emma"

# Typ współdzielony -> pliki, w których szukamy jego deklaracji.
DECLARATION_SOURCES = {
    "dependencies": ["App/AppDependencies.swift"],
    "repository": ["Core/Voice/VoiceServices.swift", "PreviewSupport/MockRepository.swift"],
    "voice": ["Core/Voice/VoiceSessionCoordinator.swift"],
    "clock": ["Core/Domain/ClockAndFormatting.swift"],
    "dateText": ["Core/Domain/ClockAndFormatting.swift"],
    # Statyczne tokeny design systemu i reguły odmiany — najczęstsze miejsce literówek
    # w widokach pisanych równolegle.
    "EmmaTheme": ["DesignSystem/EmmaTheme.swift"],
    "EmmaTypography": ["DesignSystem/EmmaTypography.swift"],
    "EmmaRadii": ["DesignSystem/EmmaMetrics.swift"],
    "EmmaSpacing": ["DesignSystem/EmmaMetrics.swift"],
    "EmmaMetrics": ["DesignSystem/EmmaMetrics.swift"],
    "EmmaPlural": ["Core/Domain/ClockAndFormatting.swift"],
}

MEMBER_PATTERN = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:public\s+|private(?:\(set\))?\s+|internal\s+|fileprivate\s+|static\s+|final\s+|override\s+|nonisolated\s+)*"
    r"(?:func|var|let)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)

USAGE_PATTERN = re.compile(
    r"\b(dependencies|repository|voice|clock|dateText|EmmaTheme|EmmaTypography|EmmaRadii|EmmaSpacing|EmmaMetrics|EmmaPlural)"
    r"\.([A-Za-z_][A-Za-z0-9_]*)"
)

# Nazwy, które nie są składowymi, a pojawiają się w łańcuchach (np. przez zmienną lokalną).
IGNORED_USAGES = {
    ("repository", "self"),
    ("voice", "self"),
}


def declared_members(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    members = set(MEMBER_PATTERN.findall(text))
    # Składowe syntetyzowane przez Swift (np. inicjalizator struktur) i właściwości
    # generowane przez makra Observera nie mają jawnej deklaracji `var`.
    return members


def main() -> int:
    members: dict[str, set[str]] = {}
    for name, relative_paths in DECLARATION_SOURCES.items():
        collected: set[str] = set()
        for relative in relative_paths:
            path = ROOT / relative
            if not path.exists():
                print(f"BLAD: brak pliku deklaracji {relative} dla '{name}'")
                return 2
            collected |= declared_members(path)
        members[name] = collected

    problems: list[str] = []
    checked = 0

    for path in sorted(ROOT.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            for holder, member in USAGE_PATTERN.findall(line):
                # Pomijamy dostęp do składowych własnych obiektów przekazanych jako
                # parametr o tej samej nazwie (np. `repository.clients` w protokole).
                if (holder, member) in IGNORED_USAGES:
                    continue
                if holder in ("repository", "voice", "clock", "EmmaTheme", "EmmaTypography", "EmmaRadii", "EmmaSpacing", "EmmaMetrics", "EmmaPlural") and (
                    path.match("Core/*") or path.match("DesignSystem/*")
                ):
                    # Deklaracje protokołów i implementacji w rdzeniu: tam `repository`
                    # i `voice` bywają nazwami parametrów, nie zależnościami widoku.
                    continue
                if member not in members[holder] and member.lower() not in {
                    m.lower() for m in members[holder]
                }:
                    checked += 1
                    problems.append(
                        f"{path.relative_to(ROOT)}:{line_number}: {holder}.{member} nie istnieje "
                        f"w zadeklarowanych składowych"
                    )

    # Odwołania wewnątrz łańcuchów widoków: sprawdzenie tylko dla nazw jednoznacznych,
    # żeby nie zgłaszać fałszywych alarmów na zmiennych lokalnych.
    if problems:
        print("Znalezione odwołania bez deklaracji:")
        for problem in problems:
            print(f"  - {problem}")
        print(f"\nRazem: {len(problems)}")
        return 1

    print(f"Odwołania do zależności: sprawdzono, brak odwołań bez deklaracji ({checked} kandydatów).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
