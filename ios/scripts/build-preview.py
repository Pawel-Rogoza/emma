#!/usr/bin/env python3
"""Podgląd aplikacji Emma dla Linuksa — HTML z prawdziwych danych i tokenów.

CO TO JEST
    Strona pokazująca: (1) dane demo wypisane **prawdziwym kodem aplikacji**
    (`MockRepository`, `DemoFixtures`, `DateTextFormatter`, `EmmaBriefing`),
    (2) układ pięciu zakładek odtworzony z referencji, (3) wszystkie stany
    z en-ów aplikacji, (4) arkusz tokenów odczytany z `EmmaTheme`,
    `EmmaTypography`, `EmmaMetrics` i `EmmaOrb`, oraz (5) prawdziwe pliki
    czcionek z `Emma/Resources/Fonts`.

CZEGO TO NIE JEST
    * To **nie jest** render SwiftUI ani zrzut ekranu iPhone'a. Układ jest
      odtworzony w HTML na podstawie referencji, więc nie dowodzi, jak dokładnie
      ułoży się SwiftUI (odstępy, zawijanie, animacje, gesty).
    * To **nie jest** dowód kompilacji widoków — ta nadal wymaga macOS/Xcode.
    * Dane i napisy są prawdziwe, układ jest rekonstrukcją. Rozdzielenie tych
      dwóch rzeczy jest w podglądzie widoczne w nagłówku każdej sekcji.

Użycie:
    python3 ios/scripts/build-preview.py                # uruchamia eksporter
    python3 ios/scripts/build-preview.py --json plik.json
"""

from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "Emma"
OUT = ROOT / ".preview"


# --------------------------------------------------------------------------- #
# Tokeny projektowe czytane z kodu Swift
# --------------------------------------------------------------------------- #

def read(path: str) -> str:
    return (SWIFT / path).read_text(encoding="utf-8")


def doc_for(text: str, position: int) -> str:
    """Komentarz `///` bezpośrednio nad deklaracją."""
    lines = text[:position].split("\n")
    collected = []
    for line in reversed(lines):
        stripped = line.strip()
        if stripped.startswith("///"):
            collected.append(stripped[3:].strip())
        elif stripped == "" and not collected:
            continue
        else:
            break
    return " ".join(reversed(collected))


def colour_tokens() -> list[dict[str, str]]:
    text = read("DesignSystem/EmmaTheme.swift")
    tokens = []
    for match in re.finditer(r"public static let (\w+) = Color\(hex: 0x([0-9A-Fa-f]{6})\)", text):
        tokens.append({
            "name": match.group(1),
            "hex": "#" + match.group(2).upper(),
            "doc": doc_for(text, match.start()),
        })
    return tokens


def typography_tokens() -> list[dict[str, str]]:
    text = read("DesignSystem/EmmaTypography.swift")
    tokens = []
    for match in re.finditer(r"public static var (\w+): Font \{([^}]*)\}", text):
        expression = match.group(2).strip()
        size = re.search(r"(?:ui|heading)\((\d+)", expression) or re.search(r"size: (\d+)", expression)
        weight = re.search(r"\.(regular|medium|semibold|bold)\b", expression)
        tokens.append({
            "name": match.group(1),
            "size": size.group(1) if size else "?",
            "weight": weight.group(1) if weight else "regular",
            "expr": expression.split("\n")[0].strip(),
            "doc": doc_for(text, match.start()),
        })
    return tokens


def metrics_tokens() -> dict[str, list[dict[str, str]]]:
    text = read("DesignSystem/EmmaMetrics.swift")
    result: dict[str, list[dict[str, str]]] = {}
    for enum_name in ("EmmaRadii", "EmmaSpacing", "EmmaMetrics"):
        start = text.find(f"enum {enum_name} {{")
        if start == -1:
            continue
        depth, index = 0, text.index("{", start)
        for position in range(index, len(text)):
            if text[position] == "{":
                depth += 1
            elif text[position] == "}":
                depth -= 1
                if depth == 0:
                    body = text[start:position]
                    break
        result[enum_name] = [
            {"name": m.group(1), "value": m.group(2), "doc": doc_for(body, m.start())}
            for m in re.finditer(r"public static let (\w+)(?::\s*\w+)?\s*=\s*([\d.]+)", body)
        ]
    return result


def orb_tokens() -> dict[str, object]:
    text = read("DesignSystem/EmmaOrb.swift")
    sizes = {
        name: int(value)
        for name, value in re.findall(r"case \.(\w+): return (\d+)", text)
    }
    stops = re.findall(r"\(([\d.]+), 0x([0-9A-Fa-f]{6})\)", text)
    return {"sizes": sizes, "stops": [(float(location), "#" + hexa.upper()) for location, hexa in stops]}


def enum_states() -> list[dict[str, object]]:
    """En-umy z rdzenia wraz z ich `displayName` — stany, które musi obsłużyć UI."""
    states = []
    for path in sorted((SWIFT / "Core").rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for match in re.finditer(r"public enum (\w+)[^{]*\{", text):
            name = match.group(1)
            depth, start = 0, text.index("{", match.start())
            for position in range(start, len(text)):
                if text[position] == "{":
                    depth += 1
                elif text[position] == "}":
                    depth -= 1
                    if depth == 0:
                        body = text[start:position]
                        break
            names = dict(re.findall(r"var displayName: String \{[^}]*switch self \{(.*?)\n        \}", body, re.S) and [] or [])
            names = dict(re.findall(r"case \.(\w+): return \"([^\"]+)\"", body))
            if not names:
                continue
            # Kolejność z deklaracji przypadków, nie z implementacji `displayName`.
            order = [case for case in re.findall(r"^\s*case (\w+)", body, re.M) if case in names]
            states.append({
                "enum": name,
                "file": str(path.relative_to(SWIFT)),
                "cases": [{"case": case, "label": names[case]} for case in order],
            })
    return states


# --------------------------------------------------------------------------- #
# Dane z aplikacji
# --------------------------------------------------------------------------- #

def export_payload(json_path: Path | None) -> dict:
    if json_path:
        return json.loads(json_path.read_text(encoding="utf-8"))
    swift = shutil.which("swift") or str(Path.home() / ".local/swift/usr/bin/swift")
    completed = subprocess.run(
        [swift, "run", "EmmaPreviewExport"],
        cwd=ROOT, capture_output=True, text=True,
    )
    if completed.returncode != 0:
        print("Eksporter danych nie powiódł się:", file=sys.stderr)
        print(completed.stderr[-4000:], file=sys.stderr)
        raise SystemExit(2)
    return json.loads(completed.stdout)


# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

def escaped(value: object) -> str:
    return html.escape(str(value))


def initials(client: dict) -> str:
    return escaped(client.get("initials") or client["displayName"][:2].upper())


class Renderer:
    def __init__(self, payload: dict, colours: list[dict], typography: list[dict],
                 metrics: dict, orb: dict, states: list[dict]):
        self.data = payload
        self.colours = colours
        self.typography = typography
        self.metrics = metrics
        self.orb = orb
        self.states = states
        self.colour = {token["name"]: token["hex"] for token in colours}
        self.radius = {t["name"]: t["value"] for t in metrics.get("EmmaRadii", [])}
        self.space = {t["name"]: t["value"] for t in metrics.get("EmmaSpacing", [])}
        self.metric = {t["name"]: t["value"] for t in metrics.get("EmmaMetrics", [])}
        self.labels = payload["labels"]

    # --- pomocnicze ------------------------------------------------------- #

    def c(self, name: str, fallback: str = "#000000") -> str:
        return self.colour.get(name, fallback)

    def orb_css(self, diameter: str) -> str:
        stops = ", ".join(
            f"{hexa} {location * 100:.0f}%" for location, hexa in self.orb["stops"]
        )
        return (f"background: radial-gradient(circle at 28% 24%, {stops});"
                f"width: {diameter}; height: {diameter}; border-radius: 50%;"
                f"box-shadow: 0 2px 6px rgba(156,191,221,0.18);")

    def tab_bar(self, active: str, unread: int) -> str:
        tabs = [("dzisiaj", "Dzisiaj", "house"), ("klienci", "Klienci", "person.2"),
                ("emma", "Emma", "sparkles"), ("rozmowy", "Rozmowy", "bubble.left.and.bubble.right"),
                ("kalendarz", "Kalendarz", "calendar")]
        cells = []
        for key, label, _icon in tabs:
            is_active = key == active
            badge = ""
            if key == "rozmowy" and unread:
                badge = f'<span class="badge">{unread}</span>'
            klass = "tab emma-chip" if key == "emma" else "tab"
            cells.append(
                f'<div class="{klass}{" active" if is_active else ""}">'
                f'<span class="dot"></span><span>{escaped(label)}</span>{badge}</div>'
            )
        return f'<nav class="tabbar">{"".join(cells)}</nav>'

    # --- sekcje ekranów --------------------------------------------------- #

    def screen_today(self) -> str:
        summary = self.data["todaySummary"]
        tasks = ""
        for task in summary["tasksDueToday"]:
            urgent = task.get("priority") == "urgent"
            tasks += f'''
            <div class="task-row">
              <div class="task-check"></div>
              <div class="task-body">
                <b>{escaped(task["title"])}</b>
                <span>{escaped(self.labels["owner"])} · {escaped(task.get("dueDate", ""))}</span>
              </div>
              <div class="task-date{' urgent' if urgent else ''}">{escaped(task.get("dueDate", ""))}</div>
            </div>'''

        cases = ""
        for legal_case in self.data["cases"]:
            client = next((c for c in self.data["clients"] if c["id"] == legal_case["clientID"]), None)
            cases += f'''
            <article class="case-card">
              <div class="case-card-head"><span>{escaped(legal_case["number"])}</span>
                <span class="pill">{escaped(legal_case["status"])}</span></div>
              <h3>{escaped(legal_case["title"])}</h3>
              <p>{escaped(client["displayName"] if client else "")} · {escaped(legal_case.get("owner", ""))}</p>
            </article>'''

        next_consultation = summary["nextConsultation"]
        consultation = ""
        if next_consultation:
            client = next((c for c in self.data["clients"] if c["id"] == next_consultation["clientID"]), None)
            consultation = f'''
            <article class="meeting">
              <div class="meeting-top"><span>{escaped(summary["nextConsultationLabel"])}</span>
                <span>{escaped(next_consultation["kind"])}</span></div>
              <h3>{escaped(next_consultation["title"])}</h3>
              <p>{escaped(client["displayName"] if client else "")}</p>
            </article>'''

        return f'''
        <section class="phone" id="dzisiaj">
          <div class="phone-head"><h3>Dzisiaj <span class="src">dane: eksport · układ: rekonstrukcja</span></h3></div>
          <div class="screen">
            <p class="kicker">{escaped(self.labels["kicker"])}</p>
            <h1 class="welcome">Dzień dobry, {escaped(self.labels["owner"] + "u")}</h1>
            <div class="emma-card">
              <div class="emma-top"><div style="{self.orb_css("37px")}"></div>
                <b>Briefing Emmy</b><button class="text-button">Odsłuchaj</button></div>
              <p class="briefing">{escaped(summary["briefing"]).replace(chr(10), "<br>")}</p>
            </div>
            <div class="stats">
              <div><b>{summary["leadCount"]}</b><span>w kontakcie</span></div>
              <div><b>{summary["activeCaseCount"]}</b><span>prowadzone sprawy</span></div>
              <div><b>{len(summary["tasksDueToday"])}</b><span>zadania na dziś</span></div>
            </div>
            <div class="section-head"><h2>Najbliższa konsultacja</h2></div>
            {consultation or '<p class="empty">Brak zaplanowanej konsultacji.</p>'}
            <div class="section-head"><h2>Zadania na dziś</h2><span class="count">{escaped(summary["tasksDueTodayLabel"])}</span></div>
            {tasks or '<p class="empty">Wszystkie zadania wykonane.</p>'}
            <div class="section-head"><h2>Prowadzone sprawy</h2></div>
            {cases}
          </div>
          {self.tab_bar("dzisiaj", self.data["unreadTotal"])}
        </section>'''

    def screen_clients(self) -> str:
        rows = ""
        for client in self.data["clients"]:
            owner = self.labels["unassigned"] if client.get("ownerID") is None else self.labels["owner"]
            rows += f'''
            <button class="person">
              <span class="avatar">{initials(client)}</span>
              <span class="person-info">
                <b>{escaped(client["displayName"])}</b>
                <span>{escaped(client["topic"])}</span>
                <small>{escaped(client["language"].upper())} · {escaped(owner)}</small>
              </span>
              <span class="chip">{escaped(client["stage"])}</span>
            </button>'''
        return f'''
        <section class="phone" id="klienci">
          <div class="phone-head"><h3>Klienci <span class="src">dane: eksport · układ: rekonstrukcja</span></h3></div>
          <div class="screen">
            <div class="search"><span class="search-icon"></span><span class="search-text">Szukaj klienta, sprawy, tematu</span></div>
            <div class="section-head"><h2>Wszyscy klienci</h2><span class="count">{escaped(self.labels["clientCount"])}</span></div>
            {rows}
          </div>
          {self.tab_bar("klienci", self.data["unreadTotal"])}
        </section>'''

    def screen_emma(self) -> str:
        voice_states = next((s for s in self.states if s["enum"] == "VoiceConnectionState"), None)
        turn_states = next((s for s in self.states if s["enum"] == "TurnState"), None)
        chips = ""
        for state in (voice_states["cases"] if voice_states else []):
            chips += f'<span class="state-chip">{escaped(state["label"])}</span>'
        turn_chips = ""
        for state in (turn_states["cases"] if turn_states else []):
            turn_chips += f'<span class="state-chip">{escaped(state["label"])}</span>'
        return f'''
        <section class="phone" id="emma">
          <div class="phone-head"><h3>Emma <span class="src">dane: eksport · układ: rekonstrukcja</span></h3></div>
          <div class="screen">
            <div class="emma-intro">
              <div style="{self.orb_css("100px")}"></div>
              <h1>Emma</h1>
              <p>Powiedz, co mam przygotować. Nie wyślę niczego bez Twojej zgody.</p>
            </div>
            <div class="emma-turn from-emma">
              <span class="turn-label">Emma</span>
              <p>Scenariusz mocka: <b>{escaped(self.data["voiceScenario"])}</b>. Konsultacja z Oleną
              jest dziś o {escaped(self.labels["clock"])}; mam przygotować notatki i kolejne kroki?</p>
            </div>
            <div class="emma-turn from-user">
              <span class="turn-label">Ty</span>
              <p>Tak, przygotuj. Nie wysyłaj nic do klientki.</p>
            </div>
            <article class="emma-action">
              <div class="emma-action-heading"><span>Przygotowana akcja</span><span>Wiadomość</span></div>
              <h3>Projekt wiadomości do Oleny</h3>
              <p class="action-body">Dzień dobry, potwierdzam dzisiejszą konsultację. Przygotuję notatki
              i prześlę listę dokumentów.</p>
              <p class="action-meta">Wymaga Twojej zgody · nic nie zostało wysłane</p>
              <div class="action-buttons"><button class="primary-button">Zatwierdź i wyślij</button>
                <button class="secondary-button">Popraw</button></div>
            </article>
            <div class="assistant-compose">
              <div style="{self.orb_css("25px")}"></div>
              <span>Napisz albo powiedz…</span>
              <button class="mic-button" aria-label="Mikrofon"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3Z" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M6 11a6 6 0 0 0 12 0M12 17v4" fill="none" stroke="currentColor" stroke-width="1.6"/></svg></button>
            </div>
            <div class="state-strip"><b>Stany połączenia</b>{chips}</div>
            <div class="state-strip"><b>Stany tury</b>{turn_chips}</div>
            <div class="assistant-dock">
              <div class="voice-controls-row"><span>Nieaktywna</span>
                <button class="text-button">Zakończ</button></div>
              <div class="dock-line">Mikrofon nie jest otwarty, dopóki nie dotkniesz przycisku.</div>
            </div>
          </div>
          {self.tab_bar("emma", self.data["unreadTotal"])}
        </section>'''

    def screen_threads(self) -> str:
        rows = ""
        for thread in self.data["threads"]:
            client = next((c for c in self.data["clients"] if c["id"] == thread.get("clientID")), None)
            messages = self.data["messagesByThread"].get(thread["id"], [])
            last = messages[-1] if messages else None
            unread = self.data["unreadByThread"].get(thread["id"], 0)
            preview = (last or {}).get("text", "Brak wiadomości")
            rows += f'''
            <button class="thread-row">
              <span class="avatar">{initials(client) if client else "?"}</span>
              <span class="thread-info">
                <span class="thread-title"><b>{escaped(client["displayName"]) if client else "Rozmowa"}</b>
                  <time>{escaped((last or {}).get("time", ""))}</time></span>
                <span class="thread-preview">{escaped(preview)}</span>
              </span>
              {f'<span class="badge">{unread}</span>' if unread else ''}
            </button>'''
        return f'''
        <section class="phone" id="rozmowy">
          <div class="phone-head"><h3>Rozmowy <span class="src">dane: eksport · układ: rekonstrukcja</span></h3></div>
          <div class="screen">
            <div class="section-head"><h2>Rozmowy</h2><span class="count">{escaped(self.labels["caseCount"])}</span></div>
            <div class="notice">Bez etykiet pilności — decyzja projektowa z planu (§3.3 pkt 4).
              Liczba nieprzeczytanych: {self.data["unreadTotal"]}.</div>
            {rows}
          </div>
          {self.tab_bar("rozmowy", self.data["unreadTotal"])}
        </section>'''

    def screen_thread_open(self) -> str:
        thread = self.data["threads"][0] if self.data["threads"] else None
        if not thread:
            return ""
        client = next((c for c in self.data["clients"] if c["id"] == thread.get("clientID")), None)
        bubbles = ""
        for message in self.data["messagesByThread"].get(thread["id"], []):
            outgoing = message.get("direction") == "out"
            quote = ""
            if message.get("quote"):
                quote = f'''<div class="quoted-message"><b>{escaped(message["quote"].get("author", ""))}</b>
                  <span>{escaped(message["quote"].get("text", ""))}</span></div>'''
            translation = ""
            if message.get("translation"):
                translation = f'''<details class="bubble-translation"><summary>Tłumaczenie</summary>
                  <p>{escaped(message["translation"])}</p></details>'''
            bubbles += f'''
            <article class="chat-message {'outgoing' if outgoing else 'incoming'}">
              {quote}<p>{escaped(message["text"])}</p>{translation}
              <div class="bubble-meta"><time>{escaped(message.get("time", ""))}</time></div>
            </article>'''
        return f'''
        <section class="phone" id="watek">
          <div class="phone-head"><h3>Otwarty wątek <span class="src">dane: eksport · układ: rekonstrukcja</span></h3></div>
          <div class="screen">
            <div class="back-header"><b>{escaped(client["displayName"]) if client else ""}</b>
              <span>{escaped(client["topic"] if client else "")}</span></div>
            <p class="chat-day">{escaped(self.labels["dayLabel"])}</p>
            {bubbles}
            <p class="unread-divider">Nowe wiadomości</p>
            <div class="composer"><span>Napisz wiadomość…</span></div>
          </div>
          {self.tab_bar("rozmowy", self.data["unreadTotal"])}
        </section>'''

    def screen_case(self) -> str:
        legal_case = self.data["cases"][0] if self.data["cases"] else None
        if not legal_case:
            return ""
        client = next((c for c in self.data["clients"] if c["id"] == legal_case["clientID"]), None)
        events = [e for e in self.data["events"] if e.get("caseID") == legal_case["id"]]
        tasks = [t for t in self.data["tasks"] if t.get("caseID") == legal_case["id"]]
        notes = [n for n in self.data["notes"] if n.get("caseID") == legal_case["id"]]
        activity = [a for a in self.data["activity"] if a.get("caseID") == legal_case["id"]]

        event_rows = "".join(
            f'''<article class="event-row"><span class="event-time">{escaped(e["time"]["hhmm"] if isinstance(e["time"], dict) else e["time"])}</span>
            <span class="event-body"><b>{escaped(e["title"])}</b><small>{escaped(e["status"])} · {escaped(e["kind"])}</small></span></article>'''
            for e in events
        )
        task_rows = "".join(
            f'''<div class="task-row"><div class="task-check{' done' if t.get("isDone") else ''}"></div>
            <div class="task-body"><b>{escaped(t["title"])}</b><span>{escaped(t.get("dueDate", ""))}</span></div></div>'''
            for t in tasks
        )
        note_rows = "".join(
            f'<div class="note"><b>{escaped(n.get("title", ""))}</b><p>{escaped(n.get("text", ""))}</p></div>'
            for n in notes
        )
        activity_rows = "".join(
            f'<div class="activity-row"><span class="activity-marker"></span><p>{escaped(a.get("text", ""))}</p>'
            f'<small>{escaped(a.get("createdAt", ""))}</small></div>'
            for a in activity
        )
        return f'''
        <section class="phone" id="sprawa">
          <div class="phone-head"><h3>Sprawa <span class="src">dane: eksport · układ: rekonstrukcja</span></h3></div>
          <div class="screen">
            <div class="back-header"><b>{escaped(legal_case["number"])}</b><span>PROWADZONA SPRAWA</span></div>
            <div class="case-title"><span class="pill">{escaped(legal_case["status"])}</span>
              <h1>{escaped(legal_case["title"])}</h1>
              <p>{escaped(client["displayName"]) if client else ""} · Opiekun: {escaped(legal_case.get("owner", ""))}</p></div>
            <button class="case-emma"><div style="{self.orb_css("32px")}"></div>
              <span><b>Przygotuj mnie do tej sprawy</b><small>Emma · notatki, terminy, kolejne kroki</small></span>
              <span class="sound-icon"></span></button>
            <div class="segments"><span class="active">Przegląd</span><span>Zadania</span><span>Notatki</span><span>Historia</span></div>
            <div class="card prose-card"><h3>Zakres sprawy</h3><p>{escaped(legal_case.get("summary", ""))}</p></div>
            <div class="section-head"><h2>Kolejny termin</h2></div>
            {event_rows or '<p class="empty">Brak kolejnego terminu.</p>'}
            <div class="section-head"><h2>Otwarte zadania</h2></div>
            <div class="card task-group">{task_rows or '<div class="empty">Wszystkie zadania wykonane.</div>'}</div>
            <div class="section-head"><h2>Ostatnia notatka</h2></div>
            {note_rows or '<p class="empty">Brak notatek.</p>'}
            <div class="section-head"><h2>Historia</h2></div>
            {activity_rows}
          </div>
          {self.tab_bar("klienci", self.data["unreadTotal"])}
        </section>'''

    def screen_calendar(self) -> str:
        days = []
        weekday_names = ["Pn", "Wt", "Śr", "Cz", "Pt", "So", "Nd"]
        event_days = {e["day"] for e in self.data["events"]}
        for index in range(7):
            day_number = 7 + index
            iso = f"2026-09-{day_number:02d}"
            selected = iso == self.data["referenceDay"]
            has_event = iso in event_days
            days.append(f'''<div class="day{' selected' if selected else ''}">
              <span>{weekday_names[index]}</span><b>{day_number}</b>
              <i class="{'has-event' if has_event else ''}"></i></div>''')
        event_rows = "".join(
            f'''<article class="event-row"><span class="event-time">{escaped(e["time"]["hhmm"] if isinstance(e["time"], dict) else e["time"])}</span>
            <span class="event-body"><b>{escaped(e["title"])}</b>
            <small>{escaped(e["day"])} · {escaped(e["status"])}</small></span></article>'''
            for e in self.data["events"]
        )
        return f'''
        <section class="phone" id="kalendarz">
          <div class="phone-head"><h3>Kalendarz <span class="src">dane: eksport · układ: rekonstrukcja</span></h3></div>
          <div class="screen">
            <div class="cal-head"><h1>{escaped(self.labels["monthTitle"])}</h1>
              <span class="week-controls">‹ ›</span></div>
            <div class="days">{"".join(days)}</div>
            <div class="section-head"><h2>Plan tygodnia</h2><span class="count">{escaped(self.labels["taskCount"])}</span></div>
            {event_rows or '<p class="empty">Brak wydarzeń w tym tygodniu.</p>'}
          </div>
          {self.tab_bar("kalendarz", self.data["unreadTotal"])}
        </section>'''

    # --- arkusze ---------------------------------------------------------- #

    def screen_states(self) -> str:
        blocks = ""
        for state in self.states:
            rows = "".join(
                f'<tr><td><code>{escaped(case["case"])}</code></td><td>{escaped(case["label"])}</td></tr>'
                for case in state["cases"]
            )
            blocks += f'''
            <article class="state-card">
              <h3>{escaped(state["enum"])}</h3>
              <p class="src">{escaped(state["file"])} · {len(state["cases"])} stanów</p>
              <table>{rows}</table>
            </article>'''
        return f'<section id="stany"><h2>Stany z kodu aplikacji</h2>'\
               f'<p class="lead">Nazwy pochodzą z `displayName` w rdzeniu — to te same napisy, '\
               f'które zobaczy użytkownik. Liczba stanów pokazuje, ile zachowań musi obsłużyć UI.</p>'\
               f'<div class="state-grid">{blocks}</div></section>'

    def screen_tokens(self) -> str:
        swatches = "".join(
            f'''<div class="swatch"><span style="background:{token["hex"]}"></span>
            <b>EmmaTheme.{escaped(token["name"])}</b><code>{token["hex"]}</code>
            <small>{escaped(token["doc"])}</small></div>'''
            for token in self.colours
        )
        type_rows = "".join(
            f'''<tr><td>{escaped(t["name"])}</td><td>{escaped(t["size"])} pt</td>
            <td>{escaped(t["weight"])}</td><td><code>{escaped(t["expr"])}</code></td>
            <td class="src">{escaped(t["doc"])}</td></tr>'''
            for t in self.typography
        )
        metric_cards = ""
        for enum_name, tokens in self.metrics.items():
            rows = "".join(
                f'<tr><td>{escaped(t["name"])}</td><td>{escaped(t["value"])}</td>'
                f'<td class="src">{escaped(t["doc"])}</td></tr>'
                for t in tokens
            )
            metric_cards += f'<article class="state-card"><h3>{escaped(enum_name)}</h3><table>{rows}</table></article>'
        orb_sizes = "".join(
            f'<div class="orb-size"><span style="{self.orb_css(f"{size}px")}"></span>'
            f'<b>.{escaped(name)}</b><code>{size} pt</code></div>'
            for name, size in self.orb["sizes"].items()
        )
        return f'''<section id="tokeny">
          <h2>Tokeny odczytane z kodu</h2>
          <p class="lead">Każdy kolor ma komentarz z regułą referencji, z której pochodzi.
          Wartości są czytane z <code>EmmaTheme.swift</code>, <code>EmmaTypography.swift</code>,
          <code>EmmaMetrics.swift</code> i <code>EmmaOrb.swift</code> — ten arkusz rozjedzie się
          z kodem tylko wtedy, gdy rozjedzie się kod.</p>
          <h3>Kolory ({len(self.colours)})</h3>
          <div class="swatch-grid">{swatches}</div>
          <h3>Orb</h3><div class="orb-grid">{orb_sizes}</div>
          <h3>Typografia</h3>
          <table class="wide"><tr><th>Styl</th><th>Rozmiar</th><th>Waga</th><th>Zapis w kodzie</th><th>Reguła referencji</th></tr>{type_rows}</table>
          <h3>Miary</h3><div class="state-grid">{metric_cards}</div>
        </section>'''

    # --- strona ----------------------------------------------------------- #

    def page(self) -> str:
        data = self.data
        facts = [
            ("Zestaw danych", f'{data["fixtureName"]} — {data["fixtureSummary"]}'),
            ("Dzień referencyjny", f'{data["referenceDay"]} · {data["labels"]["kicker"]} · {data["labels"]["clock"]}'),
            ("Zalogowany", f'{data["currentUser"]["displayName"]} ({data["currentUser"]["id"]})'),
            ("Scenariusz głosu", data["voiceScenario"]),
            ("Dane", f'{len(data["clients"])} klientów · {len(data["cases"])} spraw · {len(data["tasks"])} zadań · '
                     f'{len(data["events"])} wydarzeń · {len(data["threads"])} rozmów · '
                     f'{sum(len(v) for v in data["messagesByThread"].values())} wiadomości'),
            ("Nieprzeczytane", f'{data["unreadTotal"]} ({data["todaySummary"]["unreadLabel"]})'),
        ]
        fact_rows = "".join(
            f'<tr><th>{escaped(key)}</th><td>{escaped(value)}</td></tr>' for key, value in facts
        )
        return f'''<!doctype html>
<html lang="pl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Emma — podgląd dla Linuksa</title>
<style>{self.stylesheet()}</style>
</head>
<body>
<header class="page-head">
  <h1>Emma — podgląd dla Linuksa</h1>
  <p class="lead">Wygenerowany z kodu aplikacji: dane, napisy, stany i tokeny pochodzą
  z prawdziwych plików źródłowych. Układ ekranów jest <b>rekonstrukcją</b> referencji w HTML.</p>
  <div class="honesty">
    <div class="yes"><b>Co ten podgląd pokazuje</b>
      <ul>
        <li>dane demo czytane przez <code>MockRepository</code> — tę samą drogę co ekrany,</li>
        <li>napisy z <code>DateTextFormatter</code>, <code>EmmaPlural</code>, <code>EmmaBriefing</code>,</li>
        <li>wszystkie stany z en-ów rdzenia wraz z ich <code>displayName</code>,</li>
        <li>tokeny projektowe i prawdziwe pliki czcionek DM Sans / Manrope,</li>
        <li>struktura pięciu zakładek, kolejność i hierarchia treści.</li>
      </ul>
    </div>
    <div class="no"><b>Czego nie pokazuje</b>
      <ul>
        <li>nie jest renderem SwiftUI — dokładny układ, zawijanie i animacje zobaczysz na Macu,</li>
        <li>nie jest zrzutem ekranu iPhone'a i nie ma tu ramki telefonu ani sztucznego paska systemowego,</li>
        <li>nie dowodzi kompilacji widoków (ta wymaga macOS/Xcode),</li>
        <li>nie pokazuje zachowań dotykowych, VoiceOver ani Dynamic Type (D-13 sprawdzisz na urządzeniu).</li>
      </ul>
    </div>
  </div>
  <table class="facts">{fact_rows}</table>
</header>

<main>
{self.screen_today()}
{self.screen_clients()}
{self.screen_emma()}
{self.screen_threads()}
{self.screen_thread_open()}
{self.screen_case()}
{self.screen_calendar()}
{self.screen_states()}
{self.screen_tokens()}
</main>
<footer><p>Plik wygenerowany przez <code>ios/scripts/build-preview.py</code>.
Podgląd nie zastępuje builda na macOS — patrz <code>docs/ios/BUILD_AND_DEVICE_STATUS.md</code>.</p></footer>
</body>
</html>'''

    def stylesheet(self) -> str:
        """Style podglądu — wartości podstawiane z tokenów odczytanych z Swift."""
        return STYLESHEET % {
            "ink": self.c("ink", "#152337"),
            "muted": self.c("muted", "#687688"),
            "mutedSoft": self.c("mutedSoft", "#7A8492"),
            "bg": self.c("bg", "#EEF1F5"),
            "surface": self.c("surface", "#FFFFFF"),
            "border": self.c("cardBorder", "#E8ECF0"),
            "emmaCard": self.c("emmaCard", "#14263C"),
            "emmaCardText": self.c("emmaCardText", "#DBE3ED"),
            "accent": self.c("accent", "#1B314D"),
            "tabBar": self.c("tabBarBackground", "#FFFFFF"),
            "tabActive": self.c("tabActive", "#1C314B"),
            "tabInactive": self.c("tabInactive", "#8A97A8"),
            "emmaChip": self.c("tabEmmaChip", "#1C314B"),
            "badge": self.c("unreadBadge", "#365D98"),
            "bubbleIn": self.c("bubbleIncoming", "#FFFFFF"),
            "bubbleOut": self.c("bubbleOutgoing", "#DFE8F1"),
            "bubbleMeta": self.c("bubbleMeta", "#738398"),
            "quoteBg": self.c("quoteBackground", "#EAF0F6"),
            "quoteRule": self.c("quoteRule", "#7895B5"),
            "pill": self.c("pillNeutralBackground", "#EEF1F5"),
            "pillText": self.c("pillNeutralText", "#5A6878"),
            "primaryButton": self.c("primaryButton", "#1B314D"),
            "primaryButtonText": self.c("primaryButtonText", "#FFFFFF"),
            "secondaryButton": self.c("secondaryButton", "#EDF0F5"),
            "secondaryButtonText": self.c("secondaryButtonText", "#365373"),
            "controlBg": self.c("controlBackground", "#E9EDF2"),
            "radiusCard": self.radius.get("card", "17"),
            "radiusBubble": self.radius.get("bubble", "17"),
            "radiusBubbleTail": self.radius.get("bubbleTail", "5"),
            "radiusEmmaCard": self.radius.get("emmaCard", "21"),
            "radiusActionCard": self.radius.get("actionCard", "15"),
            "radiusCaseEmma": self.radius.get("caseEmmaCard", "14"),
            "radiusSearch": self.radius.get("search", "11"),
            "radiusDay": self.radius.get("dayCell", "15"),
            "radiusButton": self.radius.get("button", "12"),
            "radiusChip": self.radius.get("pill", "6"),
            "radiusAvatar": self.radius.get("avatar", "41"),
            "screenW": self.metric.get("referenceContentWidth", "398"),
            "tabBarH": self.metric.get("tabBarHeight", "74"),
        }


STYLESHEET = """@font-face { font-family: 'DM Sans'; src: url('fonts/DMSans-Regular.ttf'); font-weight: 400; }
@font-face { font-family: 'DM Sans'; src: url('fonts/DMSans-Medium.ttf'); font-weight: 500; }
@font-face { font-family: 'DM Sans'; src: url('fonts/DMSans-SemiBold.ttf'); font-weight: 600; }
@font-face { font-family: 'Manrope'; src: url('fonts/Manrope-Bold.ttf'); font-weight: 700; }
@font-face { font-family: 'Manrope'; src: url('fonts/Manrope-ExtraBold.ttf'); font-weight: 800; }

:root { --ink: %(ink)s; --muted: %(muted)s; --surface: %(surface)s; }
* { box-sizing: border-box; }
body { margin: 0; padding: 28px 22px 60px; background: %(bg)s; color: var(--ink);
  font-family: 'DM Sans', -apple-system, system-ui, sans-serif; font-size: 15px; line-height: 1.5; }
code { font-family: ui-monospace, 'SF Mono', Menlo, monospace; font-size: 0.86em; }
h1, h2, h3 { font-family: 'Manrope', system-ui, sans-serif; margin: 0; letter-spacing: -0.4px; }
.page-head { max-width: 1180px; margin: 0 auto 26px; }
.page-head h1 { font-size: 30px; font-weight: 800; }
.lead { color: #46566b; max-width: 78ch; }
.honesty { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin: 18px 0; }
.honesty > div { padding: 14px 16px; border-radius: 12px; border: 1px solid; }
.honesty .yes { background: #EAF6EE; border-color: #BFE0C9; }
.honesty .no { background: #FBF2E4; border-color: #E8D3AC; }
.honesty ul { margin: 8px 0 0; padding-left: 20px; }
.facts { border-collapse: collapse; width: 100%%%%; background: #fff; border-radius: 12px; overflow: hidden; }
.facts th, .facts td { text-align: left; padding: 9px 14px; border-bottom: 1px solid #EDF0F4; font-weight: 400; }
.facts th { width: 190px; color: #5B6B80; }
main { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 20px; max-width: 1180px; margin: 0 auto; }
main > section:not(.phone) { grid-column: 1 / -1; }
.phone { background: var(--surface); border-radius: 20px; border: 1px solid #E1E7EE; overflow: hidden; }
.phone-head { padding: 10px 14px; background: #F5F7F9; border-bottom: 1px solid #E3E9F0; }
.phone-head h3 { font-size: 14px; }
.src { color: %(mutedSoft)s; font-weight: 400; font-size: 11px; }
.screen { width: %%(screenW)px; max-width: 100%%%%; padding: 18px 20px 0; }
.kicker { font-size: 11px; letter-spacing: 1.5px; font-weight: 600; color: %(mutedSoft)s; margin: 0 0 6px; }
.welcome { font-family: 'Manrope'; font-weight: 800; font-size: 25px; letter-spacing: -0.9px; margin: 0 0 16px; }
.emma-card { background: %(emmaCard)s; color: #fff; border-radius: %(radiusEmmaCard)spt; padding: 18px 20px; }
.emma-card .emma-top { display: flex; align-items: center; gap: 10px; font-size: 15px; }
.emma-card p, .briefing { color: %(emmaCardText)s; font-size: 15px; margin: 12px 0 15px; }
.text-button { margin-left: auto; background: none; border: 0; color: #BFD3E8; font: inherit; cursor: pointer; }
.stats { display: flex; gap: 10px; margin: 16px 0; }
.stats > div { flex: 1; background: var(--surface); border: 1px solid %(border)s; border-radius: %(radiusCard)spt; padding: 12px; }
.stats b { display: block; font-size: 22px; font-family: 'Manrope'; }
.stats span { color: %(mutedSoft)s; font-size: 11px; }
.section-head { display: flex; align-items: baseline; gap: 10px; margin: 20px 0 9px; }
.section-head h2 { font-size: 16px; font-weight: 600; font-family: 'DM Sans'; }
.section-head .count { color: %(mutedSoft)s; font-size: 12px; }
.meeting, .case-card, .card, .state-card { background: var(--surface); border: 1px solid %(border)s;
  border-radius: %(radiusCard)spt; padding: 15px; margin-bottom: 11px; }
.meeting-top, .case-card-head { display: flex; justify-content: space-between; font-size: 11px; color: %(muted)s; }
.meeting h3, .case-card h3, .card h3 { font-size: 16px; margin: 8px 0 4px; }
.meeting p, .case-card p { margin: 0; color: %(mutedSoft)s; font-size: 12px; }
.pill, .chip { background: %(pill)s; color: %(pillText)s; border-radius: %(radiusChip)spt;
  padding: 3px 8px; font-size: 11px; }
.task-row { display: flex; align-items: flex-start; gap: 11px; background: var(--surface);
  border: 1px solid #EDF0F4; border-radius: %(radiusCard)spt; padding: 14px 15px; margin-bottom: 11px; }
.task-check { width: 24px; height: 24px; border-radius: 8px; border: 1px solid #CBD4DF; background: #fff; flex: none; }
.task-check.done { background: #EDF4EF; border-color: #4B7966; }
.task-body { flex: 1; }
.task-body b { display: block; font-size: 13px; font-weight: 550; }
.task-body span { color: #8A95A3; font-size: 11px; }
.task-date { font-size: 10px; color: #8B96A5; }
.task-date.urgent { background: #FBF0E3; color: #A47740; border-radius: %(radiusChip)spt; padding: 5px 7px; }
.empty { color: %(mutedSoft)s; font-size: 13px; }
.search { display: flex; align-items: center; gap: 8px; background: %(controlBg)s;
  border-radius: %(radiusSearch)spt; padding: 9px 12px; margin: 15px 0; min-height: 43px; }
.search-icon { width: 17px; height: 17px; border: 1.5px solid #8793A1; border-radius: 50%%%%; }
.search-text { color: %(muted)s; font-size: 13px; }
.person { display: flex; align-items: center; gap: 12px; width: 100%%%%; text-align: left;
  background: var(--surface); border: 1px solid %(border)s; border-radius: %(radiusCard)spt;
  padding: 12px 14px; margin-bottom: 10px; font: inherit; color: inherit; cursor: pointer; }
.avatar { width: 41px; height: 41px; border-radius: %(radiusAvatar)spt; background: #EDF2F8;
  display: grid; place-items: center; font-weight: 600; flex: none; color: #4A6A8F; }
.person-info { flex: 1; }
.person-info b { display: block; font-size: 15px; font-weight: 600; }
.person-info span { display: block; color: %(muted)s; font-size: 12px; }
.person-info small { color: %(mutedSoft)s; font-size: 11px; }
.emma-intro { text-align: center; padding: 14px 0 20px; }
.emma-intro h1 { font-size: 25px; margin: 12px 0 6px; }
.emma-intro p { color: %(muted)s; font-size: 13px; margin: 0 auto; max-width: 32ch; }
.emma-turn { border-radius: 15px; padding: 12px 14px; margin-bottom: 10px; font-size: 14px; }
.emma-turn.from-emma { background: #EFF3F8; }
.emma-turn.from-user { background: %(quoteBg)s; }
.turn-label { display: block; font-size: 11px; color: %(mutedSoft)s; margin-bottom: 4px; }
.emma-turn p { margin: 0; line-height: 1.6; }
.emma-action { background: var(--surface); border: 1px solid #CCDBE9; border-radius: %(radiusActionCard)spt; padding: 16px; }
.emma-action-heading { display: flex; gap: 7px; font-size: 11px; color: #617F9F; }
.emma-action h3 { font-size: 15px; margin: 10px 0 8px; }
.action-body { background: #FAFCFE; border: 1px solid #DBE5EE; border-radius: 10px; padding: 12px; font-size: 14px; }
.action-meta { color: #8796A6; font-size: 11px; }
.action-buttons { display: flex; gap: 8px; margin-top: 12px; }
.primary-button { background: %(primaryButton)s; color: %(primaryButtonText)s; border: 0;
  border-radius: %(radiusButton)spt; padding: 12px 16px; min-height: 44px; font: inherit; font-size: 13px; cursor: pointer; }
.secondary-button { background: %(secondaryButton)s; color: %(secondaryButtonText)s; border: 0;
  border-radius: %(radiusButton)spt; padding: 12px 16px; min-height: 44px; font: inherit; font-size: 13px; cursor: pointer; }
.assistant-compose { display: flex; align-items: center; gap: 10px; background: #fff; border: 1px solid #D8E3EE;
  border-radius: 14px; padding: 6px; margin-top: 14px; }
.assistant-compose span { flex: 1; color: %(mutedSoft)s; font-size: 14px; }
.mic-button { background: #EAF0F6; color: #4C7399; border: 0; border-radius: 11px;
  width: 39px; height: 39px; display: grid; place-items: center; cursor: pointer; }
.mic-button svg { width: 18px; height: 18px; }
.assistant-dock { background: #F5F7F9; border-top: 1px solid #E3E9F0; margin: 16px -20px 0; padding: 4px 18px 13px; }
.voice-controls-row { display: flex; align-items: center; font-size: 10px; color: #8A9AAC; padding: 8px 4px 0; }
.voice-controls-row .text-button { color: #8196AD; }
.dock-line { font-size: 11px; color: %(mutedSoft)s; padding: 6px 4px 0; }
.state-strip { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; margin-top: 14px; font-size: 11px; }
.state-chip { background: #EDF2F8; color: #45607F; border-radius: 6px; padding: 4px 8px; }
.thread-row { display: flex; align-items: center; gap: 12px; width: 100%%%%; text-align: left;
  background: var(--surface); border: 1px solid %(border)s; border-radius: %(radiusCard)spt;
  padding: 12px 14px; margin-bottom: 10px; font: inherit; color: inherit; cursor: pointer; }
.thread-info { flex: 1; min-width: 0; }
.thread-title { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
.thread-title b { font-size: 16px; font-weight: 500; letter-spacing: -0.3px; }
.thread-title time { color: #7A8594; font-size: 12px; }
.thread-preview { display: block; color: #6C798A; font-size: 14px; overflow: hidden;
  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
.badge { background: %(badge)s; color: #fff; border-radius: 10px; min-width: 20px; height: 20px;
  display: grid; place-items: center; font-size: 11px; padding: 0 6px; }
.notice { background: #F4F7FA; border: 1px solid #E1E7EE; border-radius: 10px; padding: 10px 12px;
  font-size: 12px; color: #5B6B80; margin-bottom: 14px; }
.back-header { padding: 4px 0 14px; }
.back-header b { display: block; font-size: 13px; font-weight: 600; }
.back-header span { color: %(mutedSoft)s; font-size: 12px; letter-spacing: 1px; }
.chat-day { text-align: center; color: #788697; font-size: 12px; margin: 12px 0; }
.chat-message { background: %(bubbleIn)s; border: 1px solid %(border)s; border-radius: %(radiusBubble)spt;
  border-bottom-left-radius: %(radiusBubbleTail)spt; padding: 12px 12px 5px; margin-bottom: 12px; max-width: 82%%%%; }
.chat-message.outgoing { background: %(bubbleOut)s; margin-left: auto; border-bottom-left-radius: %(radiusBubble)spt;
  border-bottom-right-radius: %(radiusBubbleTail)spt; }
.chat-message > p { font-size: 16px; margin: 0 0 6px; }
.bubble-translation { margin-top: 9px; border-top: 1px solid #E1E7EE; padding-top: 8px;
  font-size: 13px; color: #627790; }
.bubble-translation summary { cursor: pointer; padding: 3px 0 5px; min-height: 28px; }
.bubble-translation p { font-size: 14px; line-height: 1.5; margin: 5px 0; color: #4E6178; white-space: pre-wrap; }
.bubble-meta { display: flex; gap: 5px; color: %(bubbleMeta)s; font-size: 11px; min-height: 25px; align-items: center; }
.quoted-message { background: %(quoteBg)s; border-left: 3px solid %(quoteRule)s; border-radius: %(radiusBubbleTail)spt;
  padding: 8px 10px; margin-bottom: 8px; font-size: 13px; }
.quoted-message b { display: block; color: #526F91; font-size: 12px; }
.unread-divider { text-align: center; color: #365D98; font-size: 12px; margin: 16px 0; }
.composer { border: 1px solid #D8E3EE; border-radius: 14px; padding: 12px; color: %(mutedSoft)s;
  font-size: 16px; margin-bottom: 18px; }
.case-title h1 { font-size: 25px; letter-spacing: -0.9px; margin: 10px 0 6px; }
.case-title p { color: %(muted)s; font-size: 13px; margin: 0 0 14px; }
.case-emma { display: flex; align-items: center; gap: 11px; width: 100%%%%; text-align: left;
  border: 1px solid #DFE7EF; background: linear-gradient(110deg, #EAF0F6, #F6F8FA);
  border-radius: %(radiusCaseEmma)spt; padding: 14px; font: inherit; color: inherit; cursor: pointer; }
.case-emma b { display: block; font-size: 13px; font-weight: 550; }
.case-emma small { display: block; font-size: 10px; color: #8494A7; margin-top: 5px; }
.sound-icon { width: 18px; height: 18px; border: 1.5px solid #557799; border-radius: 4px; }
.segments { display: flex; gap: 6px; margin: 16px 0 14px; font-size: 12px; }
.segments span { padding: 7px 12px; border-radius: 8px; background: %(controlBg)s; color: %(muted)s; }
.segments .active { background: %(accent)s; color: #fff; }
.prose-card p { font-size: 14px; margin: 6px 0 0; }
.event-row { display: flex; gap: 13px; align-items: flex-start; background: var(--surface);
  border: 1px solid %(border)s; border-radius: %(radiusCard)spt; padding: 15px; margin-bottom: 10px; }
.event-time { font-size: 14px; font-weight: 600; }
.event-body b { display: block; font-size: 13px; font-weight: 550; }
.event-body small { color: #8692A2; font-size: 11px; }
.task-group { padding: 6px 15px; }
.task-group .task-row { border: 0; border-bottom: 1px solid #EDF0F4; border-radius: 0;
  padding: 14px 0; margin: 0; background: none; }
.note { border: 1px solid %(border)s; border-radius: %(radiusCard)spt; padding: 14px; margin-bottom: 10px; background: #fff; }
.note p { margin: 6px 0 0; font-size: 13px; color: #46566B; }
.activity-row { display: grid; grid-template-columns: 12px 1fr; gap: 4px 10px; padding: 3px 0 20px; }
.activity-marker { width: 7px; height: 7px; border-radius: 50%%%%; background: #A6B5C7;
  border: 2px solid #EDF1F5; margin-top: 6px; }
.activity-row p { grid-column: 2; margin: 0 0 5px; color: #5D7086; font-size: 12px; }
.activity-row small { grid-column: 2; color: #8C98A7; font-size: 10px; }
.cal-head { display: flex; align-items: baseline; justify-content: space-between; }
.cal-head h1 { font-size: 22px; }
.week-controls { color: #69819B; }
.days { display: flex; gap: 4px; margin: 20px 0 24px; }
.day { flex: 1; text-align: center; padding: 10px 0; border-radius: %(radiusDay)spt;
  font-size: 11px; color: #8D97A4; min-height: 75px; }
.day b { display: block; font-size: 17px; color: var(--ink); }
.day i { display: block; width: 3px; height: 3px; background: transparent; margin: 7px auto 0; border-radius: 100%%%%; }
.day i.has-event { background: #8BA0B7; }
.day.selected { background: #1C314B; color: #BFCCDF; }
.day.selected b { color: #fff; }
.day.selected i.has-event { background: #D7E2ED; }
.tabbar { display: flex; align-items: center; justify-content: space-around; height: %(tabBarH)s;
  border-top: 1px solid #E3E9F0; background: %(tabBar)s; margin-top: 20px; }
.tab { display: flex; flex-direction: column; align-items: center; gap: 4px; font-size: 10px;
  color: %(tabInactive)s; position: relative; }
.tab.active { color: %(tabActive)s; font-weight: 600; }
.tab .dot { width: 18px; height: 18px; border-radius: 6px; background: #E5EBF2; }
.tab.emma-chip .dot { background: %(emmaChip)s; border-radius: 50%%%%; }
.tab.emma-chip.active .dot { background: #223B5C; }
.tab .badge { position: absolute; top: -6px; right: -10px; }
main > section:not(.phone) h2 { font-size: 22px; margin-bottom: 6px; }
.state-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 14px; }
.state-card table, .wide { width: 100%%%%; border-collapse: collapse; font-size: 13px; }
.state-card td, .state-card th, .wide td, .wide th { text-align: left; padding: 5px 8px; border-bottom: 1px solid #EDF0F4; }
.wide code { color: #3D5875; }
.swatch-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 10px; margin: 12px 0 22px; }
.swatch { background: #fff; border: 1px solid #E1E7EE; border-radius: 10px; padding: 10px; font-size: 12px; }
.swatch span { display: block; height: 26px; border-radius: 6px; margin-bottom: 8px; border: 1px solid rgba(0,0,0,.06); }
.swatch b { display: block; overflow-wrap: anywhere; font-size: 11px; line-height: 1.35; }
.swatch code { color: #5B6B80; }
.swatch small { display: block; color: #7A8492; margin-top: 4px; }
.orb-grid { display: flex; gap: 18px; align-items: flex-end; margin: 12px 0 22px; flex-wrap: wrap; }
.orb-size { text-align: center; font-size: 12px; }
.orb-size b { display: block; margin-top: 8px; }
.orb-size code { color: #5B6B80; }
footer { max-width: 1180px; margin: 30px auto 0; color: #5B6B80; font-size: 13px; }
@media (max-width: 700px) { .honesty { grid-template-columns: 1fr; } }
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Buduje podgląd HTML dla Linuksa.")
    parser.add_argument("--json", type=Path, help="użyj gotowego eksportu zamiast uruchamiać Swift")
    parser.add_argument("--out", type=Path, default=OUT / "index.html")
    arguments = parser.parse_args()

    payload = export_payload(arguments.json)
    renderer = Renderer(
        payload=payload,
        colours=colour_tokens(),
        typography=typography_tokens(),
        metrics=metrics_tokens(),
        orb=orb_tokens(),
        states=enum_states(),
    )

    arguments.out.parent.mkdir(parents=True, exist_ok=True)
    arguments.out.write_text(renderer.page(), encoding="utf-8")

    # Prawdziwe czcionki z aplikacji — podgląd nie zgaduje kroju pisma.
    fonts_out = arguments.out.parent / "fonts"
    fonts_out.mkdir(exist_ok=True)
    for font in (SWIFT / "Resources/Fonts").glob("*.ttf"):
        shutil.copy2(font, fonts_out / font.name)

    size = arguments.out.stat().st_size
    print(f"Podgląd: {arguments.out} ({size // 1024} kB)")
    print(f"Czcionki: {fonts_out} ({len(list(fonts_out.glob('*.ttf')))} plików)")
    print(f"Stany z kodu: {sum(len(s['cases']) for s in renderer.states)} w {len(renderer.states)} en-umach")
    print(f"Tokeny: {len(renderer.colours)} kolorów, {len(renderer.typography)} stylów tekstu")
    return 0


if __name__ == "__main__":
    sys.exit(main())
