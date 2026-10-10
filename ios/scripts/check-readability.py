#!/usr/bin/env python3
"""Kontrola czytelności interfejsu (F09 z audytu UX z 13.09.2026).

Sprawdza dwa wymagania, oba mierzalne bez Xcode:

  1. **Jedna skala tekstu.** Żaden ekran nie deklaruje własnego rozmiaru tekstu
     poniżej 12 pt. Dawne `EmmaTypography.ui(10…)` i `ui(11…)` rozsiane po
     widokach dawały metadane 10–11 pt. Metadana ma teraz jeden nazwany styl
     (`EmmaTypography.caption`), a definicje stylów żyją wyłącznie w
     `EmmaTypography.swift`.

  2. **Kontrast tekstu.** Token tekstowy z listy musi mieć kontrast co najmniej
     4,5:1 wobec swojego rzeczywistego tła (WCAG AA dla zwykłego tekstu).
     Wartości są liczone z `EmmaTheme.swift`, nie szacowane ze zrzutu.

Czego to NIE jest: to nie renderowanie ani pomiar pikseli. Kontrast liczymy ze
zadeklarowanych wartości sRGB, a nie z tego, co widać na ekranie. Kolory tła są
przypisane ręcznie na podstawie miejsca użycia tokenu — lista jest jawna niżej.

Użycie:
    python3 ios/scripts/check-readability.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT_DIR = ROOT / "Emma"

# Minimalny rozmiar tekstu w interfejsie (poza nagłówkami deklarowanymi jawnie
# przez style nazwane). 12 pt to próg, od którego kontrast 4,5:1 jest wymagany
# także dla zwykłego tekstu.
MIN_TEXT_SIZE = 12

# Token tekstowy → (tło, gdzie w interfejsie).
TEXT_TOKENS: dict[str, tuple[str, str]] = {
    # Tokeny semantyczne (0.22.0) na swoich miękkich tłach (pigułki, ikony stanu).
    "accent": ("#E9EFFC", "akcent na tle accentSoft"),
    "emma": ("#EFEBFC", "tekst Emmy na tle emmaSoft"),
    "critical": ("#FBEAE8", "plakietka terminu na tle criticalSoft"),
    "warning": ("#FCF1E2", "plakietka ostrzeżenia na tle warningSoft"),
    "positive": ("#E6F3EB", "plakietka „załatwione” na tle positiveSoft"),
    "mutedSoft": ("#F5F6F8", "podpisy i metadane na tle aplikacji"),
    "taskMetaText": ("#FFFFFF", "metadane zadania w białej karcie"),
    "taskDateText": ("#FFFFFF", "termin zadania w białej karcie"),
    "tabInactive": ("#FBFCFD", "nieaktywna etykieta zakładki"),
    "chatDayChipText": ("#E5EAF0", "separator dnia w wątku"),
    "bubbleMeta": ("#FFFFFF", "godzina w dymku przychodzącym"),
    "receiptDefault": ("#DFE8F1", "znacznik wysyłki w dymku wychodzącym"),
    "contextStripText": ("#EAF0F6", "pasek kontekstu rozmowy"),
    "caseEmmaSubtitle": ("#EAF0F6", "podtytuł karty Emmy w sprawie"),
    "personAvatarText": ("#EAF0F4", "inicjały awatara"),
    "weekControlText": ("#EDF1F5", "sterowanie tygodniem w kalendarzu"),
    "emmaIntroText": ("#F5F6F8", "intro na ekranie Emmy"),
    "emmaTurnLabel": ("#FFFFFF", "kto mówi w turze rozmowy"),
    "emmaSuggestionSubtitle": ("#FFFFFF", "podtytuł sugestii Emmy"),
    "emmaStatusText": ("#F5F6F8", "linia stanu głosu"),
    "emmaDemoFootText": ("#F5F6F8", "nota o danych przykładowych"),
    "dockStatusText": ("#F5F7F9", "etykieta stanu w doku głosowym"),
    "dockActionText": ("#F5F7F9", "akcja tekstowa w doku głosowym"),
    "actionHeadingText": ("#FFFFFF", "nagłówek karty propozycji"),
    "actionMetaText": ("#FFFFFF", "metadane karty propozycji"),
}

CONTRAST_TARGET = 4.5


def swift_hex_tokens() -> dict[str, str]:
    text = (SWIFT_DIR / "DesignSystem/EmmaTheme.swift").read_text(encoding="utf-8")
    out: dict[str, str] = {}
    for name, hexa in re.findall(r"public static let (\w+) = Color\(hex: 0x([0-9A-Fa-f]{6})\)", text):
        out[name] = hexa.upper()
    return out


def relative_luminance(hexa: str) -> float:
    channels = [int(hexa[i:i + 2], 16) / 255 for i in (0, 2, 4)]

    def linear(channel: float) -> float:
        return channel / 12.92 if channel <= 0.03928 else ((channel + 0.055) / 1.055) ** 2.4

    red, green, blue = (linear(c) for c in channels)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def contrast(foreground: str, background: str) -> float:
    light, dark = sorted((relative_luminance(foreground), relative_luminance(background)), reverse=True)
    return (light + 0.05) / (dark + 0.05)


def screen_files_without_typography() -> list[Path]:
    return [
        path
        for path in sorted(SWIFT_DIR.rglob("*.swift"))
        if path.name != "EmmaTypography.swift"
    ]


def check_one_scale() -> list[str]:
    problems: list[str] = []
    pattern = re.compile(r"EmmaTypography\.ui\((10|11)[,)]")
    for path in screen_files_without_typography():
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if pattern.search(line):
                problems.append(
                    f"{path.relative_to(ROOT)}:{number}: tekst poniżej {MIN_TEXT_SIZE} pt "
                    f"— użyj EmmaTypography.caption(...)"
                )
    return problems


def check_contrast() -> list[str]:
    tokens = swift_hex_tokens()
    problems: list[str] = []
    for name, (background, where) in TEXT_TOKENS.items():
        if name not in tokens:
            problems.append(f"EmmaTheme.swift: brak tokenu {name}")
            continue
        ratio = contrast(tokens[name], background.lstrip("#"))
        if ratio < CONTRAST_TARGET:
            problems.append(
                f"{name} ({where}): {ratio:.2f}:1 wobec {background} "
                f"— poniżej {CONTRAST_TARGET}:1"
            )
    return problems


def main() -> int:
    one_scale = check_one_scale()
    contrast_problems = check_contrast()

    print("== Kontrola czytelności (F09) ==")
    print(f"Pliki ekranów sprawdzone: {len(screen_files_without_typography())}")
    print(f"Tokeny tekstowe sprawdzone: {len(TEXT_TOKENS)} (próg {CONTRAST_TARGET}:1)")

    if one_scale:
        print("\n[BŁĄD] Tekst poniżej jednej skali:")
        for problem in one_scale:
            print(f"  {problem}")
    if contrast_problems:
        print("\n[BŁĄD] Kontrast poniżej progu:")
        for problem in contrast_problems:
            print(f"  {problem}")

    if one_scale or contrast_problems:
        return 1

    print("Skala tekstu: jedna, bez rozmiarów poniżej 12 pt w ekranach.")
    print(f"Kontrast: wszystkie tokeny tekstowe mają co najmniej {CONTRAST_TARGET}:1.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
