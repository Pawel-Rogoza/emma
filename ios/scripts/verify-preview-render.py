#!/usr/bin/env python3
"""Pomiar renderu podglądu — zamiast oceny „na oko”.

Po co: podgląd HTML trzeba sprawdzić tak samo jak kod, a nie tylko na niego spojrzeć.
Ten skrypt uruchamia **prawdziwy render** strony w przeglądarce (headless Firefox)
i mierzy to, czego nie widać w źródle HTML:

  * czy wczytały się prawdziwe czcionki z aplikacji (DM Sans, Manrope),
  * czy nic nie wystaje poza szerokość okna (poziomy pasek przewijania),
  * czy tekst nie jest ucinany w kontenerach o stałej wysokości,
  * czy elementy nie nachodzą na siebie (przecięcia prostokątów rodzeństwa),
  * czy nie ma „pustych” kart o zerowej wysokości,
  * czy tłumaczenie jest zwinięte, jak `<details>` w referencji,
  * ile jest sekcji, zakładek i jak wysokie są kolumny ekranów.

Jak to działa: kopia strony dostaje wstrzyknięty skrypt, który mierzy układ
i odsyła wynik na lokalny serwer (`POST /report`). Serwer zapisuje JSON,
a skrypt wypisuje raport. Bez przeglądarki nie ma pomiaru — zgłaszamy to jawnie,
a nie udajemy, że podgląd jest sprawdzony.

Użycie:
    python3 ios/scripts/verify-preview-render.py [--port 8097] [--preview .preview/index.html]
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

MEASURE_SCRIPT = r"""
<script>
(async function () {
  // Bez tego wszystkie czcionki są w stanie „loading” i pomiar kłamie.
  if (document.fonts && document.fonts.ready) { try { await document.fonts.ready; } catch (e) {} }
  function box(el) {
    const r = el.getBoundingClientRect();
    return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) };
  }
  function describe(el) {
    const cls = (el.className || "").toString().trim().split(/\s+/).slice(0, 2).join(".");
    return el.tagName.toLowerCase() + (cls ? "." + cls : "");
  }
  function text(el) {
    return (el.textContent || "").trim().replace(/\s+/g, " ").slice(0, 60);
  }

  const report = {
    viewport: { w: window.innerWidth, h: window.innerHeight },
    document: {
      scrollWidth: document.documentElement.scrollWidth,
      scrollHeight: document.documentElement.scrollHeight
    },
    fonts: [...document.fonts].map(f => f.family + " " + f.weight + " " + f.status),
    screens: [...document.querySelectorAll("section.phone")].map(s => ({
      id: s.id, box: box(s), tabs: [...s.querySelectorAll(".tabbar .tab")].map(t => text(t))
    })),
    clipped: [],
    overflowing: [],
    emptyCards: [],
    overlaps: [],
    // Tłumaczenia wiadomości zostały usunięte z interfejsu (decyzja właściciela) —
    // brak elementów details.bubble-translation w podglądzie jest zgodny z aplikacją.
    transparentBackgrounds: [],
    unreadBadges: document.querySelectorAll(".tabbar .badge, .thread-row .badge").length,
    counts: {
      screens: document.querySelectorAll("section.phone").length,
      cards: document.querySelectorAll(".phone article, .phone .card, .phone .task-row").length,
      stateRows: document.querySelectorAll(".state-card tr").length,
      swatches: document.querySelectorAll(".swatch").length,
      tableRows: document.querySelectorAll("table tr").length
    }
  };

  // 1. Poziome wystawanie poza okno.
  if (document.documentElement.scrollWidth > window.innerWidth + 1) {
    report.overflowing.push({
      element: "documentElement",
      scrollWidth: document.documentElement.scrollWidth,
      viewport: window.innerWidth
    });
  }

  const candidates = [...document.querySelectorAll("body *")];
  for (const el of candidates) {
    const style = getComputedStyle(el);
    if (style.display === "none" || style.visibility === "hidden") continue;
    const b = box(el);

    // 2. Tekst ucinany: treść szersza niż pudełko przy widocznym przelewie.
    const hasOwnBox = style.display === "block" || style.display === "flex" || style.display === "grid";
    if (hasOwnBox && el.clientWidth > 0 && el.children.length === 0 && el.textContent.trim() &&
        el.scrollWidth > el.clientWidth + 2 && style.overflowX === "visible") {
      report.clipped.push({ element: describe(el), text: text(el),
        scrollWidth: el.scrollWidth, clientWidth: el.clientWidth, box: b });
    }

    // 3. Elementy szersze niż okno.
    if (b.w > window.innerWidth + 1 && style.position !== "fixed") {
      report.overflowing.push({ element: describe(el), box: b, viewport: window.innerWidth, text: text(el) });
    }

    // 4. Puste karty: widoczne kontenery o zerowym rozmiarze.
    if (/emma-card|card|task-row|event-row|thread-row|person|chat-message|swatch|state-card|meeting|case-card/.test(
        (el.className || "").toString()) && (b.h < 4 || b.w < 4)) {
      report.emptyCards.push({ element: describe(el), box: b, text: text(el) });
    }

    // 5. Tło przezroczyste w kartach, które powinny mieć tło.
    const classes = (el.className || "").toString().split(/\s+/);
    const groupedTaskRow = classes.includes("task-row") && el.closest(".task-group") !== null;
    const needsBackground = !groupedTaskRow && ["emma-card", "task-row", "event-row",
      "chat-message", "swatch", "quoted-message"].some(c => classes.includes(c));
    if (needsBackground &&
        (style.backgroundColor === "rgba(0, 0, 0, 0)" || style.backgroundColor === "transparent") &&
        style.backgroundImage === "none") {
      report.transparentBackgrounds.push({ element: describe(el), text: text(el) });
    }
  }

  // 6. Nachodzenie rodzeństwa wewnątrz kolumn ekranów (poza celowymi nakładkami).
  for (const screen of document.querySelectorAll("section.phone .screen")) {
    const children = [...screen.children].filter(el => {
      const s = getComputedStyle(el);
      return s.display !== "none" && s.position === "static";
    });
    for (let i = 0; i < children.length; i++) {
      for (let j = i + 1; j < children.length; j++) {
        const a = children[i].getBoundingClientRect(), c = children[j].getBoundingClientRect();
        const overlapW = Math.min(a.right, c.right) - Math.max(a.left, c.left);
        const overlapH = Math.min(a.bottom, c.bottom) - Math.max(a.top, c.top);
        if (overlapW > 2 && overlapH > 2) {
          report.overlaps.push({
            screen: screen.parentElement.id,
            first: describe(children[i]), second: describe(children[j]),
            overlap: { w: Math.round(overlapW), h: Math.round(overlapH) }
          });
        }
      }
    }
  }

  fetch("/report", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(report)
  });
})();
</script>
"""


class Handler(BaseHTTPRequestHandler):
    report: dict | None = None

    def do_GET(self) -> None:  # noqa: N802
        path = self.server.preview_root / self.path.lstrip("/")  # type: ignore[attr-defined]
        if self.path == "/" or not path.exists() or path.is_dir():
            path = self.server.preview_root / "index.html"  # type: ignore[attr-defined]
        if not path.exists():
            self.send_error(404)
            return
        body = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8" if path.suffix == ".html" else "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        Handler.report = json.loads(self.rfile.read(length))
        self.send_response(204)
        self.end_headers()

    def log_message(self, *_: object) -> None:
        pass


def main() -> int:
    parser = argparse.ArgumentParser(description="Mierzy render podglądu w przeglądarce.")
    parser.add_argument("--port", type=int, default=8097)
    parser.add_argument("--preview", type=Path, default=ROOT / ".preview/index.html")
    parser.add_argument("--timeout", type=float, default=45.0)
    arguments = parser.parse_args()

    firefox = shutil.which("firefox")
    if firefox is None:
        print("BLAD: brak przeglądarki (firefox) — nie mogę zmierzyć renderu.")
        print("To nie znaczy, że podgląd jest zły: znaczy, że nie został sprawdzony.")
        return 2

    if not arguments.preview.exists():
        print(f"BLAD: brak pliku podglądu {arguments.preview}")
        return 2

    with tempfile.TemporaryDirectory() as directory:
        served = Path(directory)
        for item in arguments.preview.parent.iterdir():
            if item.is_file():
                shutil.copy2(item, served / item.name)
        fonts = arguments.preview.parent / "fonts"
        if fonts.is_dir():
            shutil.copytree(fonts, served / "fonts", dirs_exist_ok=True)

        page = (served / "index.html").read_text(encoding="utf-8")
        page = page.replace("</body>", MEASURE_SCRIPT + "</body>")
        (served / "index.html").write_text(page, encoding="utf-8")

        server = HTTPServer(("127.0.0.1", arguments.port), Handler)
        server.preview_root = served  # type: ignore[attr-defined]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        try:
            subprocess.run(
                [firefox, "--headless", "--window-size=1500,1200",
                 f"http://127.0.0.1:{arguments.port}/"],
                capture_output=True, timeout=arguments.timeout,
            )
        except subprocess.TimeoutExpired:
            pass
        finally:
            server.shutdown()

    report = Handler.report
    if report is None:
        print("BLAD: przeglądarka nie odesłała pomiaru (strona się nie wykonała).")
        return 2

    problems: list[str] = []

    loaded = [f for f in report["fonts"] if f.endswith("loaded")]
    print(f"Czcionki wczytane: {len(loaded)}/{len(report['fonts'])}")
    for font in report["fonts"]:
        print(f"  · {font}")
    if len(loaded) < 5:
        problems.append(f"wczytano {len(loaded)} z {len(report['fonts'])} czcionek")

    print(f"\nDokument: {report['document']['scrollWidth']}×{report['document']['scrollHeight']} px, "
          f"okno {report['viewport']['w']}×{report['viewport']['h']}")
    if report["document"]["scrollWidth"] > report["viewport"]["w"] + 1:
        problems.append("dokument szerszy niż okno (poziome przewijanie)")

    print(f"\nEkrany ({report['counts']['screens']}):")
    for screen in report["screens"]:
        tabs = ", ".join(screen["tabs"])
        print(f"  · {screen['id']}: {screen['box']['w']}×{screen['box']['h']} px, zakładki: {tabs}")
        if screen["box"]["h"] < 300:
            problems.append(f"ekran {screen['id']} ma tylko {screen['box']['h']} px wysokości")
        if len(screen["tabs"]) != 5:
            problems.append(f"ekran {screen['id']} ma {len(screen['tabs'])} zakładek, oczekiwano 5")

    print(f"\nZawartość: {report['counts']['cards']} kart, {report['counts']['stateRows']} wierszy stanów, "
          f"{report['counts']['swatches']} próbek kolorów, {report['counts']['tableRows']} wierszy tabel, "
          f"{report['unreadBadges']} plakietek nieprzeczytanych")

    for key, label in (("overflowing", "Wystaje poza szerokość"),
                       ("clipped", "Tekst ucięty"),
                       ("emptyCards", "Puste karty"),
                       ("overlaps", "Nachodzące elementy"),
                       ("transparentBackgrounds", "Karty bez tła")):
        entries = report[key]
        print(f"\n{label}: {len(entries)}")
        for entry in entries[:8]:
            print(f"  ! {json.dumps(entry, ensure_ascii=False)[:200]}")
        if entries:
            problems.append(f"{label.lower()}: {len(entries)}")

    print()
    if problems:
        print("WYNIK: problemy do naprawy:")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print("WYNIK: render bez zastrzeżeń (czcionki, szerokości, ucinanie, nakładanie, tła).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
