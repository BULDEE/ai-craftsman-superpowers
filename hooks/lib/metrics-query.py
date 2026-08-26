#!/usr/bin/env python3
"""Parameterized SQLite query helper - eliminates SQL injection in metrics-db.sh.

Usage: metrics-query.py [--script|--raw] <db_path> <query> [param1] [param2] ...

Each positional arg after the query becomes a bind parameter (?).
For SELECT queries, results are printed to stdout with column headers.
For INSERT/UPDATE/DELETE queries, changes are committed silently.

--script executes a multi-statement DDL/migration script (no parameters):
the fallback metrics-db.sh uses when the sqlite3 CLI is absent.
--raw prints rows the way the sqlite3 CLI does (columns joined with |,
nothing on an empty result), so shell callers parse both paths identically.
"""
import sqlite3
import sys


def _format_table(headers: list[str], rows: list[tuple]) -> str:
    """Format rows as aligned columns with headers (mimics sqlite3 -header -column)."""
    widths = [len(header) for header in headers]
    for row in rows:
        for i, val in enumerate(row):
            widths[i] = max(widths[i], len(str(val) if val is not None else ""))

    lines = []
    lines.append("  ".join(h.ljust(widths[i]) for i, h in enumerate(headers)))
    lines.append("  ".join("-" * width for width in widths))
    for row in rows:
        lines.append("  ".join(str(v if v is not None else "").ljust(widths[i]) for i, v in enumerate(row)))
    return "\n".join(lines)


def _parse_args() -> tuple[str, str, str, list[str]]:
    argv = sys.argv[1:]
    mode = "default"
    if argv and argv[0] in ("--script", "--raw"):
        mode = argv[0][2:]
        argv = argv[1:]
    if len(argv) < 2:
        print("Usage: metrics-query.py [--script|--raw] <db_path> <query> [params...]", file=sys.stderr)
        sys.exit(1)
    if mode == "script" and argv[2:]:
        print("metrics-query.py: --script takes no bind parameters", file=sys.stderr)
        sys.exit(1)
    return mode, argv[0], argv[1], argv[2:]


def _execute_query(mode: str, db_path: str, query: str, params: list[str]) -> None:
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        if mode == "script":
            cur.executescript(query)
            conn.commit()
            return
        cur.execute(query, params)
        if mode == "raw":
            for row in cur.fetchall():
                print("|".join("" if value is None else str(value) for value in row))
            conn.commit()
            return
        query_type = query.strip().split()[0].upper() if query.strip() else ""
        if query_type == "SELECT":
            _print_select_results(cur)
        else:
            conn.commit()
    finally:
        conn.close()


def _print_select_results(cur: sqlite3.Cursor) -> None:
    rows = cur.fetchall()
    if rows and cur.description:
        headers = [column[0] for column in cur.description]
        if len(headers) == 1 and len(rows) == 1:
            print(rows[0][0] if rows[0][0] is not None else 0)
        else:
            print(_format_table(headers, rows))
    elif not rows and cur.description and len(cur.description) == 1:
        print(0)


def main() -> None:
    mode, db_path, query, params = _parse_args()
    _execute_query(mode, db_path, query, params)


if __name__ == "__main__":
    main()
