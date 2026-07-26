#!/usr/bin/env python3
"""Quality dashboard: aggregate the metrics database into a local HTML report.

Usage:
  dashboard.py <db_path> [--out FILE] [--serve [PORT]] [--json]

Aggregates violations, corrections, sessions, and learned instincts across
every project recorded in the database, so quality is visible per repository
and across repositories. The output is a single self-contained HTML file
served from localhost - nothing leaves the machine.
"""
import html
import json
import sqlite3
import sys
import webbrowser
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DEFAULT_PORT = 8787


def _query(conn: sqlite3.Connection, sql: str, params: tuple = ()) -> list[tuple]:
    try:
        return conn.execute(sql, params).fetchall()
    except sqlite3.Error:
        return []


QUERIES = {
    "projects": """
        SELECT project_hash, COUNT(*) AS violations, SUM(blocked) AS blocked,
               COUNT(DISTINCT rule) AS distinct_rules
        FROM violations GROUP BY project_hash ORDER BY violations DESC
    """,
    "top_rules": """
        SELECT rule, severity, COUNT(*) AS hits, SUM(blocked) AS blocked
        FROM violations GROUP BY rule, severity ORDER BY hits DESC LIMIT 15
    """,
    "trend": """
        SELECT date(timestamp) AS day, COUNT(*) AS violations, SUM(blocked) AS blocked
        FROM violations WHERE timestamp > datetime('now','-30 days')
        GROUP BY day ORDER BY day
    """,
    "corrections": """
        SELECT rule, action, COUNT(*) AS hits
        FROM corrections GROUP BY rule, action ORDER BY hits DESC LIMIT 15
    """,
    "instincts": """
        SELECT rule, status, COUNT(DISTINCT project_hash) AS projects, SUM(occurrences)
        FROM instincts GROUP BY rule, status ORDER BY projects DESC, rule
    """,
    "sessions": """
        SELECT COUNT(*), COALESCE(SUM(violations_blocked), 0),
               COALESCE(SUM(violations_warned), 0), COALESCE(SUM(writes_count), 0)
        FROM sessions
    """,
}


def collect(conn: sqlite3.Connection) -> dict:
    data = {name: _query(conn, sql) for name, sql in QUERIES.items()}
    data["generated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    return data


def _debt_score(data: dict) -> tuple[int, str]:
    """Blocked-violations per write, mapped to a 0-100 score (higher is better)."""
    sessions = data["sessions"][0] if data["sessions"] else (0, 0, 0, 0)
    _count, blocked, warned, writes = sessions
    if not writes:
        return 100, "no writes recorded yet"
    ratio = (blocked + warned * 0.3) / writes
    score = max(0, min(100, round(100 - ratio * 100)))
    return score, f"{blocked} blocked + {warned} warned over {writes} writes"


def _rows(rows: list[tuple], cols: int) -> str:
    if not rows:
        return f'<tr><td colspan="{cols}" class="empty">no data yet</td></tr>'
    out = []
    for row in rows:
        cells = "".join(
            f"<td>{'' if value is None else html.escape(str(value))}</td>" for value in row
        )
        out.append(f"<tr>{cells}</tr>")
    return "".join(out)


def _sparkline(trend: list[tuple]) -> str:
    if not trend:
        return '<p class="empty">no activity in the last 30 days</p>'
    values = [row[1] for row in trend]
    peak = max(values) or 1
    bars = "".join(
        f'<div class="bar" style="height:{max(4, round(value / peak * 100))}%" '
        f'title="{html.escape(str(row[0]))}: {value} violations"></div>'
        for row, value in zip(trend, values)
    )
    return f'<div class="spark">{bars}</div>'


CSS = """
:root { color-scheme: light dark; --bg:#fff; --fg:#111; --muted:#666; --line:#e3e3e3; --accent:#3b6ea5; }
@media (prefers-color-scheme: dark) { :root { --bg:#14161a; --fg:#e8e8e8; --muted:#9aa0a6; --line:#2a2e35; --accent:#7aa7d9; } }
* { box-sizing:border-box; } body { margin:0; padding:2rem; background:var(--bg); color:var(--fg);
  font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
h1 { font-size:1.5rem; margin:0 0 .25rem; } h2 { font-size:1.05rem; margin:2rem 0 .6rem; }
.sub { color:var(--muted); margin:0 0 1.5rem; font-size:.9rem; }
.cards { display:grid; grid-template-columns:repeat(auto-fit,minmax(190px,1fr)); gap:1rem; }
.card { border:1px solid var(--line); border-radius:10px; padding:1rem; }
.card .n { font-size:2rem; font-weight:600; } .card .l { color:var(--muted); font-size:.85rem; }
.wrap { overflow-x:auto; } table { border-collapse:collapse; width:100%; min-width:480px; }
th,td { text-align:left; padding:.45rem .7rem; border-bottom:1px solid var(--line); font-size:.9rem; }
th { color:var(--muted); font-weight:600; } td.empty,.empty { color:var(--muted); font-style:italic; }
.spark { display:flex; align-items:flex-end; gap:2px; height:90px; border-bottom:1px solid var(--line); }
.bar { flex:1; background:var(--accent); border-radius:2px 2px 0 0; min-width:3px; }
footer { margin-top:2.5rem; color:var(--muted); font-size:.8rem; }
"""

TEMPLATE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Craftsman Quality Dashboard</title><style>{css}</style></head><body>
<h1>Craftsman Quality Dashboard</h1>
<p class="sub">Generated {generated_at} - local data only, nothing is sent anywhere.</p>

<div class="cards">
  <div class="card"><div class="n">{score}</div><div class="l">quality score ({score_basis})</div></div>
  <div class="card"><div class="n">{project_count}</div><div class="l">repositories tracked</div></div>
  <div class="card"><div class="n">{total_violations}</div><div class="l">violations recorded</div></div>
  <div class="card"><div class="n">{total_blocked}</div><div class="l">blocked before landing</div></div>
</div>

<h2>Violations over the last 30 days</h2>
{spark}

<h2>Per repository</h2>
<div class="wrap"><table>
<thead><tr><th>Project</th><th>Violations</th><th>Blocked</th><th>Distinct rules</th></tr></thead>
<tbody>{projects}</tbody></table></div>

<h2>Most violated rules</h2>
<div class="wrap"><table>
<thead><tr><th>Rule</th><th>Severity</th><th>Hits</th><th>Blocked</th></tr></thead>
<tbody>{top_rules}</tbody></table></div>

<h2>Corrections applied</h2>
<div class="wrap"><table>
<thead><tr><th>Rule</th><th>Action</th><th>Count</th></tr></thead>
<tbody>{corrections}</tbody></table></div>

<h2>Learned instincts</h2>
<div class="wrap"><table>
<thead><tr><th>Rule</th><th>Status</th><th>Projects</th><th>Corrections</th></tr></thead>
<tbody>{instincts}</tbody></table></div>

<footer>Source: {db}</footer>
</body></html>
"""


def render(data: dict, db_path: str) -> str:
    score, basis = _debt_score(data)
    projects = data["projects"]
    return TEMPLATE.format(
        css=CSS,
        generated_at=data["generated_at"],
        score=score,
        score_basis=basis,
        project_count=len(projects),
        total_violations=sum(row[1] or 0 for row in projects),
        total_blocked=sum(row[2] or 0 for row in projects),
        spark=_sparkline(data["trend"]),
        projects=_rows([(row[0][:12], row[1], row[2], row[3]) for row in projects], 4),
        top_rules=_rows(data["top_rules"], 4),
        corrections=_rows(data["corrections"], 3),
        instincts=_rows(data["instincts"], 4),
        db=db_path,
    )


class _SingleFileHandler(SimpleHTTPRequestHandler):
    """Serves exactly one HTML file.

    The default handler roots at a directory, and the dashboard sits next to
    metrics.db: any script running in the page (or any other local process)
    could then fetch the whole cross-project history over 127.0.0.1. Only the
    rendered page is reachable here; everything else is 404.
    """

    page_path: Path

    def do_GET(self) -> None:
        if self.path.split("?")[0] not in ("/", f"/{self.page_path.name}"):
            self.send_error(404)
            return
        body = self.page_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args) -> None:
        return


def _serve(out_path: Path, port: int) -> None:
    handler = type("BoundHandler", (_SingleFileHandler,), {"page_path": out_path})
    url = f"http://127.0.0.1:{port}/{out_path.name}"
    with ThreadingHTTPServer(("127.0.0.1", port), handler) as httpd:
        print(f"Serving {url} (Ctrl+C to stop)")
        try:
            webbrowser.open(url)
        except Exception:
            pass
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped")


def _parse_port(argv: list[str]) -> int:
    index = argv.index("--serve")
    if len(argv) > index + 1 and argv[index + 1].isdigit():
        return int(argv[index + 1])
    return DEFAULT_PORT


def _load(db_path: str) -> dict:
    if not Path(db_path).is_file():
        print(f"error: metrics database not found: {db_path}", file=sys.stderr)
        sys.exit(1)
    conn = sqlite3.connect(db_path)
    try:
        return collect(conn)
    finally:
        conn.close()


def _dump_json(data: dict) -> None:
    json.dump({key: [list(row) for row in value] if isinstance(value, list) else value
               for key, value in data.items()}, sys.stdout, indent=2)
    print()


def _output_path(db_path: str, argv: list[str]) -> Path:
    if "--out" in argv:
        return Path(argv[argv.index("--out") + 1])
    return Path(db_path).parent / "dashboard.html"


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    db_path = sys.argv[1]
    data = _load(db_path)

    if "--json" in sys.argv:
        _dump_json(data)
        return

    out = _output_path(db_path, sys.argv)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render(data, db_path))
    print(f"dashboard: {out}")

    if "--serve" in sys.argv:
        _serve(out, _parse_port(sys.argv))


if __name__ == "__main__":
    main()
