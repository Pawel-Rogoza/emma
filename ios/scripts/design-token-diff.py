#!/usr/bin/env python3
"""Porównanie komponentu Swift z regułą CSS referencji.

Po co: ręczne porównywanie 40 komponentów z kaskadą CSS jest wolne i łatwo coś
przeoczyć. To narzędzie robi to systematycznie: dla wskazanego komponentu wypisuje
**wartości użyte w Swift** (rozwiązane z tokenów na liczby i kolory) obok
**wartości z referencji** dla podanych selektorów, a na końcu wypisuje różnice.

Jak to czytać — i czego to NIE jest:
  * To nie jest renderowanie ani kontrola typów. To porównanie liczb i kolorów.
  * „Różnica” nie zawsze jest błędem: referencja ma warstwy wyłączone z aplikacji
    (`.studio`, `.workspace`, `.details`), a kaskada nakłada reguły w kolejności.
    Dlatego narzędzie pokazuje wartości, a decyzję podejmuje człowiek.
  * Wartości, które w referencji pochodzą z warstwy wyłączonej, są oznaczone.

Użycie:
    python3 ios/scripts/design-token-diff.py            # wszystkie komponenty z tabeli
    python3 ios/scripts/design-token-diff.py voiceDock  # jeden komponent
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "Emma"
CSS = ROOT.parent / "reference/prototype/style.css"

# Warstwy referencji wyłączone z aplikacji (podgląd HTML / pulpit).
DEAD_LAYERS = (".studio", ".intro", ".details", ".workspace", ".sidebar", "#desktop-nav", ".work-panel")

# Kolory spoza referencji przyjęte świadomie: każdy ma wpis w
# docs/ios/DESIGN_DEVIATIONS.md. Wzorca nie zmieniamy, żeby je ukryć — wyjątek
# jest jawny tutaj i w rejestrze.
REGISTERED_COLOURS = {
    "#1DAA61": "D-37",  # EmmaTheme.chatGreen — zieleń WhatsAppa na liście rozmów
}

# Komponent → (selektory referencji, plik Swift, znacznik w pliku)
COMPONENTS: dict[str, tuple[list[str], str, str]] = {
    "taskRow": ([".task-row", ".task-check", ".task-body b", ".task-body span", ".task-date"],
                "DesignSystem/EmmaComponents.swift", "struct TaskRow"),
    "eventRow": ([".event-row", ".event-time", ".event-row b", ".event-row small"],
                 "Features/Shared/EventRow.swift", "struct EventRow"),
    "quickActions": ([".quick-actions button", ".quick-actions svg", ".quick-actions span"],
                     "Features/ClientCard/ClientCardScreen.swift", "quickActions"),
    "clientHero": ([".client-hero>.avatar", ".client-hero h1", ".client-hero p"],
                   "Features/ClientCard/ClientCardScreen.swift", "hero"),
    "linkedCase": ([".linked-case", ".linked-case b", ".linked-case small", ".linked-case>svg"],
                   "Features/ClientCard/ClientCardScreen.swift", "linkedCase"),
    "infoList": ([".info-list", ".info-list>div", ".info-list b", ".info-list button"],
                 "DesignSystem/EmmaComponents.swift", "struct InfoList"),
    "caseEmma": ([".case-emma", ".case-emma b", ".case-emma small", ".case-emma>svg", ".case-emma>.orb"],
                 "Features/Case/CaseScreen.swift", "func emmaCard"),
    "voiceDock": (["#assistant-dock", ".voice-controls-row", ".assistant-compose", ".mic-button"],
                  "Features/Shared/VoiceDock.swift", "struct VoiceDock"),
    "emmaAction": ([".emma-action", ".emma-action h3", ".action-meta", ".emma-action-heading"],
                   "Features/Shared/EmmaActionCard.swift", "struct EmmaActionCard"),
    "emmaTurn": ([".emma-turn", ".emma-turn p", ".emma-turn>span", ".emma-turn.from-user"],
                 "Features/Assistant/AssistantScreen.swift", "turn"),
    "threadRow": ([".thread-open", ".thread-title b", ".thread-title time", ".thread-preview"],
                  "Features/Shared/MessagingComponents.swift", "struct ConversationRow"),
    "bubble": ([".chat-message", ".chat-message>p", ".bubble-meta", ".quoted-message"],
               "Features/Shared/MessagingComponents.swift", "struct MessageBubble"),
    "dayCell": ([".day", ".day b", ".day.selected", ".days"],
                "Features/Calendar/CalendarScreen.swift", "dayCell"),
    "searchField": ([".search", ".search input"], "DesignSystem/EmmaComponents.swift", "struct SearchField"),
}


def colour_tokens() -> dict[str, str]:
    text = (SWIFT / "DesignSystem/EmmaTheme.swift").read_text(encoding="utf-8")
    out: dict[str, str] = {}
    for name, hexa in re.findall(r"public static let (\w+) = Color\(hex: 0x([0-9A-Fa-f]{6})\)", text):
        out[name] = "#" + hexa.upper()
    for name, base in re.findall(r"public static let (\w+) = Color\.(white|black)", text):
        out[name] = "#FFFFFF" if base == "white" else "#000000"
    return out


def number_tokens() -> dict[str, str]:
    text = (SWIFT / "DesignSystem/EmmaMetrics.swift").read_text(encoding="utf-8")
    return {name: value for name, value in re.findall(r"public static let (\w+)(?::\s*\w+)?\s*=\s*([\d.]+)", text)}


def typography_styles() -> dict[str, str]:
    """Style nazwane → rozmiar i waga zadeklarowane w EmmaTypography."""
    text = (SWIFT / "DesignSystem/EmmaTypography.swift").read_text(encoding="utf-8")
    out: dict[str, str] = {}
    for name, expr in re.findall(r"public static var (\w+): Font \{ ([^}]+) \}", text):
        size = re.search(r"(?:ui|heading|body\(for: [^,]+, size:)\((\d+)", expr)
        weight = re.search(r"\.(\w+)\)", expr)
        out[name] = f"{size.group(1) if size else '?'}pt" + (f"/{weight.group(1)}" if weight else "")
    return out


def css_variables() -> dict[str, str]:
    """Zmienne z `:root`. Kaskada: późniejsza deklaracja wygrywa."""
    text = CSS.read_text(encoding="utf-8")
    variables: dict[str, str] = {}
    for block in re.finditer(r":root\{([^{}]*)\}", text):
        for name, value in re.findall(r"(--[\w-]+)\s*:\s*([^;]+)", block.group(1)):
            variables[name] = value.strip()
    return variables


def whole_css() -> str:
    """Cała referencja bez warstw wyłączonych z aplikacji."""
    text = CSS.read_text(encoding="utf-8")
    for layer in DEAD_LAYERS:
        text = re.sub(rf"[^{{}}]*{re.escape(layer)}[^{{}}]*\{{[^{{}}]*\}}", "", text)
    return text


def css_rules() -> dict[str, list[str]]:
    text = CSS.read_text(encoding="utf-8")
    rules: dict[str, list[str]] = {}
    for block in re.finditer(r"([^{}]+)\{([^{}]*)\}", text):
        selector_text = block.group(1).strip()
        if any(layer in selector_text for layer in DEAD_LAYERS):
            continue
        for selector in (s.strip() for s in selector_text.split(",")):
            rules.setdefault(selector, []).append(block.group(2))
    return rules


def css_properties(
    selector: str,
    rules: dict[str, list[str]],
    variables: dict[str, str] | None = None,
) -> dict[str, str]:
    properties: dict[str, str] = {}
    for body in rules.get(selector, []):
        for match in re.finditer(r"([a-z-]+)\s*:\s*([^;]+)", body):
            key, value = match.group(1).strip(), match.group(2).strip()
            # Bierzemy także `border-top`, `border-color` itd. — inaczej gubimy obramowania.
            if not (key in {"background", "color", "border-radius", "padding", "gap",
                            "font-size", "font-weight", "min-height", "width", "height", "margin"}
                    or key.startswith("border")):
                continue
            if variables:
                for name, replacement in variables.items():
                    value = value.replace(f"var({name})", replacement)
            properties.setdefault(key, value)
    return properties


def swift_component(path: Path, marker: str) -> str:
    text = path.read_text(encoding="utf-8")
    index = text.find(marker)
    if index < 0:
        return ""
    return text[index:index + 4000]


def swift_values(body: str, colours: dict[str, str], numbers: dict[str, str]) -> list[str]:
    found: list[str] = []
    for name in dict.fromkeys(re.findall(r"EmmaTheme\.(\w+)", body)):
        found.append(f"EmmaTheme.{name} = {colours.get(name, '?')}")
    for name in dict.fromkeys(re.findall(r"EmmaRadii\.(\w+)", body)):
        found.append(f"EmmaRadii.{name} = {numbers.get(name, '?')}pt")
    for name in dict.fromkeys(re.findall(r"EmmaSpacing\.(\w+)", body)):
        found.append(f"EmmaSpacing.{name} = {numbers.get(name, '?')}pt")
    for name in dict.fromkeys(re.findall(r"EmmaTypography\.(\w+)", body)):
        found.append(f"EmmaTypography.{name} = {typography_styles().get(name, '?')}")
    for size in re.findall(r"\.system\(size: (\d+)", body):
        found.append(f"ikona .system(size: {size})")
    for pad in re.findall(r"\.padding\((?:EdgeInsets\([^)]*\)|(\d+))", body):
        if pad:
            found.append(f".padding({pad})")
    return found


def main() -> int:
    wanted = sys.argv[1:] or list(COMPONENTS)
    colours, numbers, rules = colour_tokens(), number_tokens(), css_rules()
    variables = css_variables()
    unknown = [name for name in wanted if name not in COMPONENTS]
    if unknown:
        print(f"Nieznane komponenty: {', '.join(unknown)}")
        print("Dostępne: " + ", ".join(sorted(COMPONENTS)))
        return 2

    for name in wanted:
        selectors, relative, marker = COMPONENTS[name]
        body = swift_component(SWIFT / relative, marker)
        print(f"\n=== {name} · {relative} ===")
        if not body:
            print(f"  [BŁĄD] nie znalazłem znacznika „{marker}” w pliku")
            continue

        swift_hexes = {v.split(" = ")[1] for v in swift_values(body, colours, numbers) if " = #" in v}
        css_hexes: set[str] = set()
        # Dokładamy selektorów potomnych (np. `.voice-controls-row .text-button`),
        # bo wartości często siedzą w nich, a nie w samym bloku komponentu.
        extra = [s for s in rules if any(s.startswith(sel + " ") or s.startswith(sel + ":") for sel in selectors)]
        for selector in selectors + sorted(extra):
            expected = css_properties(selector, rules, variables)
            pretty = ", ".join(f"{k}:{v}" for k, v in expected.items())
            print(f"  CSS {selector:34} {pretty}")
            css_hexes |= set(re.findall(r"#[0-9a-fA-F]{6}", pretty.upper())) | {
                value.upper() for value in re.findall(r"#[0-9a-fA-F]{3,6}", pretty)}

        print("  Swift:")
        for value in swift_values(body, colours, numbers):
            print(f"    {value}")

        # Dwa poziomy pewności:
        #  1) kolory, których nie ma w CAŁEJ referencji → błąd (kolor wymyślony),
        #  2) kolory istniejące w referencji, ale poza regułami tego komponentu →
        #     token współdzielony (np. `muted`); wymaga oka, nie jest automatycznym błędem.
        all_css_hexes = {"#" + h.upper() for h in re.findall(r"#([0-9a-fA-F]{6})", whole_css())}
        registered = {hexa for hexa in swift_hexes
                      if hexa.upper() not in all_css_hexes and hexa.upper() in REGISTERED_COLOURS}
        invented = {hexa for hexa in swift_hexes
                    if hexa.upper() not in all_css_hexes and hexa.upper() not in REGISTERED_COLOURS}
        elsewhere = {hexa for hexa in swift_hexes
                     if hexa.upper() in all_css_hexes and hexa.upper() not in {h.upper() for h in css_hexes}}

        if invented:
            print(f"  ✗ kolory spoza referencji (błąd): {', '.join(sorted(invented))}")
        if registered:
            print("  · kolory spoza referencji, zarejestrowane: "
                  + ", ".join(f"{h} ({REGISTERED_COLOURS[h.upper()]})" for h in sorted(registered)))
        if elsewhere:
            print(f"  · kolory spoza reguł tego komponentu (token współdzielony): {', '.join(sorted(elsewhere))}")
        if not invented and not elsewhere and not registered:
            print("  ✓ wszystkie kolory użyte w Swift są w regułach tego komponentu")

    return 0


if __name__ == "__main__":
    sys.exit(main())
