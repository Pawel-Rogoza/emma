#!/usr/bin/env python3
"""Kontrola odwołań między plikami — namiastka kompilatora na Linuksie.

Po co: w tym środowisku nie ma kompilatora Apple, więc `swiftc -parse` sprawdza
wyłącznie składnię. Typowy błąd integracji (wywołanie metody, której nie ma,
albo literówka w nazwie elementu zależności) przechodzi przez parser bez słowa.
Ten skrypt czyta **zadeklarowane** składowe typów współdzielonych i porównuje je
z **użyciami** w widokach.

Czego NIE robi — i co trzeba wiedzieć, czytając jego wynik:

  * nie sprawdza typów, liczby argumentów, etykiet wywołań ani przeciążeń,
  * dla typów z jednego pliku (`EmmaRadii`, `EmmaSpacing`, `EmmaMetrics`) czyta
    zawężony zakres danego typu, więc rozpoznaje `EmmaSpacing.avatar` jako błąd —
    ale nie sprawdza, czy użyta wartość ma właściwy typ,
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
    # `BackendRepository.swift`: widoki rzutują `dependencies.repository as? BackendRepository`
    # i wołają składowe dostępne tylko na serwerze (np. `askEmma`, `voiceUsage`).
    "repository": [
        "Core/Voice/VoiceServices.swift",
        "PreviewSupport/MockRepository.swift",
        "Core/Data/BackendRepository.swift",
    ],
    "voice": ["Core/Voice/VoiceSessionCoordinator.swift"],
    "clock": ["Core/Domain/ClockAndFormatting.swift"],
    "dataset": ["PreviewSupport/DemoFixtures.swift"],
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

# Rozszerzenia typów systemowych: `Color`, `Font` itd. Człon wolno użyć tylko wtedy,
# gdy jest zadeklarowany w rozszerzeniu albo należy do typów systemowych z listy niżej.
# Bez tego filtra `Color.emmaDockStatusText` (nigdy nie zadeklarowane) przeszło jako poprawne.
SYSTEM_TYPE_HOLDERS = {"Color", "Font", "Image", "ShapeStyle"}

SYSTEM_MEMBERS = {
    "Color": {"white", "black", "clear", "primary", "secondary", "accentColor", "gray", "red",
              "green", "blue", "orange", "yellow", "purple", "pink", "brown", "cyan", "indigo",
              "mint", "teal", "redacted"},
    "Font": {"Weight", "system", "custom", "body", "title", "title2", "title3", "headline",
             "subheadline", "caption", "caption2", "footnote", "callout", "largeTitle"},
    "Image": set(),
    "ShapeStyle": set(),
}

SYSTEM_USAGE_PATTERN = re.compile(r"\b(Color|Font|Image|ShapeStyle)\.([A-Za-z_][A-Za-z0-9_]*)")

# Typy, których deklaracje trzeba czytać w zawężeniu do jednego typu (patrz `declared_members`).
ENUM_SCOPED_HOLDERS = {"EmmaRadii", "EmmaSpacing", "EmmaMetrics", "EmmaTheme", "EmmaTypography", "EmmaPlural"}

MEMBER_PATTERN = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:public\s+|private(?:\(set\))?\s+|internal\s+|fileprivate\s+|static\s+|final\s+|override\s+|nonisolated\s+|weak\s+)*"
    r"(?:func|var|let)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)

USAGE_PATTERN = re.compile(
    r"\b(dependencies|repository|voice|clock|dataset|dateText|EmmaTheme|EmmaTypography|EmmaRadii|EmmaSpacing|EmmaMetrics|EmmaPlural)"
    r"\.([A-Za-z_][A-Za-z0-9_]*)"
)

# Nazwy, które nie są składowymi, a pojawiają się w łańcuchach (np. przez zmienną lokalną).
IGNORED_USAGES = {
    ("repository", "self"),
    ("voice", "self"),
}


def strip_string_literals(line: str) -> str:
    """Usuwa treść literałów tekstowych, zostawiając kod z interpolacji `\\( ... )`.

    Bez tego nazwy symboli SF w rodzaju `"clock.badge.exclamationmark"` wyglądają
    jak odwołanie `clock.badge`. Interpolacja to kod, więc `"\\(clock.now)"` dalej
    podlega kontroli. Działa w obrębie jednej linii; literały wieloliniowe (trzy cudzysłowy) nie są śledzone.
    """
    out: list[str] = []
    index, length = 0, len(line)
    in_string = False
    while index < length:
        char = line[index]
        if not in_string:
            if char == '"':
                in_string = True
                out.append('""')
            else:
                out.append(char)
            index += 1
            continue
        if char == "\\" and index + 1 < length and line[index + 1] == "(":
            depth, start = 1, index + 2
            index = start
            while index < length and depth:
                if line[index] == "(":
                    depth += 1
                elif line[index] == ")":
                    depth -= 1
                index += 1
            out.append(" " + strip_string_literals(line[start:index - 1]) + " ")
            continue
        if char == "\\":
            index += 2
            continue
        if char == '"':
            in_string = False
        index += 1
    return "".join(out)


def extension_members(path: Path, type_name: str) -> set[str]:
    """Składowe zadeklarowane w `extension <Typ> { ... }` danego pliku."""
    text = path.read_text(encoding="utf-8")
    collected: set[str] = set()
    start = 0
    while (found := text.find(f"extension {type_name} {{", start)) != -1:
        depth, index = 0, text.index("{", found)
        for position in range(index, len(text)):
            if text[position] == "{":
                depth += 1
            elif text[position] == "}":
                depth -= 1
                if depth == 0:
                    collected |= set(MEMBER_PATTERN.findall(text[found:position]))
                    start = position
                    break
        else:
            break
    return collected


def declared_members(path: Path, scope: str | None = None) -> set[str]:
    """Składowe zadeklarowane w pliku.

    `scope` zawęża odczyt do jednego typu — konieczne dla `EmmaMetrics.swift`,
    gdzie `EmmaRadii`, `EmmaSpacing` i `EmmaMetrics` leżą w jednym pliku.
    Bez zawężenia `EmmaSpacing.avatar` przeszłoby jako poprawne, bo `avatar`
    istnieje w `EmmaRadii`.
    """
    text = path.read_text(encoding="utf-8")
    if scope is not None:
        start = text.find(f"enum {scope} {{")
        if start == -1:
            start = text.find(f"struct {scope} {{")
        if start == -1:
            return set()
        depth = 0
        index = text.index("{", start)
        for position in range(index, len(text)):
            if text[position] == "{":
                depth += 1
            elif text[position] == "}":
                depth -= 1
                if depth == 0:
                    text = text[start:position]
                    break
    return set(MEMBER_PATTERN.findall(text))


def main() -> int:
    members: dict[str, set[str]] = {}
    for name, relative_paths in DECLARATION_SOURCES.items():
        collected: set[str] = set()
        for relative in relative_paths:
            path = ROOT / relative
            if not path.exists():
                print(f"BLAD: brak pliku deklaracji {relative} dla '{name}'")
                return 2
            collected |= declared_members(path, scope=name if name in ENUM_SCOPED_HOLDERS else None)
        members[name] = collected

    system_members: dict[str, set[str]] = {name: set() for name in SYSTEM_TYPE_HOLDERS}
    for path in sorted(ROOT.rglob("*.swift")):
        for name in SYSTEM_TYPE_HOLDERS:
            system_members[name] |= extension_members(path, name)

    problems: list[str] = []
    checked = 0

    for path in sorted(ROOT.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            line = strip_string_literals(line)
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
                checked += 1
                if member not in members[holder] and member.lower() not in {
                    m.lower() for m in members[holder]
                }:
                    problems.append(
                        f"{path.relative_to(ROOT)}:{line_number}: {holder}.{member} nie istnieje "
                        f"w zadeklarowanych składowych"
                    )
            for holder, member in SYSTEM_USAGE_PATTERN.findall(line):
                if member in SYSTEM_MEMBERS[holder] or member in system_members[holder]:
                    continue
                checked += 1
                problems.append(
                    f"{path.relative_to(ROOT)}:{line_number}: {holder}.{member} nie jest ani "
                    f"składową systemową, ani zadeklarowaną w rozszerzeniu {holder}"
                )

    # Odwołania wewnątrz łańcuchów widoków: sprawdzenie tylko dla nazw jednoznacznych,
    # żeby nie zgłaszać fałszywych alarmów na zmiennych lokalnych.
    if problems:
        print("Znalezione odwołania bez deklaracji:")
        for problem in problems:
            print(f"  - {problem}")
        print(f"\nRazem: {len(problems)}")
        return 1

    print(
        f"Odwołania do zależności i typów systemowych: sprawdzono {checked} odwołań, "
        f"brak odwołań bez deklaracji "
        f"(rozszerzenia: {', '.join(f'{k}: {len(v)}' for k, v in sorted(system_members.items()) if v)})."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
