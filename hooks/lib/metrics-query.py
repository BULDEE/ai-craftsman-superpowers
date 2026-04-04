#!/usr/bin/env python3
"""Parameterized SQLite query helper — eliminates SQL injection in metrics-db.sh.

Usage: metrics-query.py <db_path> <query> [param1] [param2] ...

Each positional arg after the query becomes a bind parameter (?).
For SELECT queries, results are printed to stdout with column headers.
For INSERT/UPDATE/DELETE queries, changes are committed silently.
"""
import sqlite3
import sys


def _format_table(headers: list[str], rows: list[tuple]) -> str:
    """Format rows as aligned columns with headers (mimics sqlite3 -header -column)."""
    widths = [len(h) for h in headers]
    for row in rows:
        for i, val in enumerate(row):
            widths[i] = max(widths[i], len(str(val) if val is not None else ""))

    lines = []
    lines.append("  ".join(h.ljust(widths[i]) for i, h in enumerate(headers)))
    lines.append("  ".join("-" * w for w in widths))
    for row in rows:
        lines.append("  ".join(str(v if v is not None else "").ljust(widths[i]) for i, v in enumerate(row)))
    return "\n".join(lines)


def _parse_args() -> tuple[str, str, list[str]]:
    if len(sys.argv) < 3:
        print("Usage: metrics-query.py <db_path> <query> [params...]", file=sys.stderr)
        sys.exit(1)
    return sys.argv[1], sys.argv[2], sys.argv[3:]


def _execute_query(db_path: str, query: str, params: list[str]) -> None:
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        cur.execute(query, params)
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
        headers = [d[0] for d in cur.description]
        if len(headers) == 1 and len(rows) == 1:
            print(rows[0][0] if rows[0][0] is not None else 0)
        else:
            print(_format_table(headers, rows))
    elif not rows and cur.description and len(cur.description) == 1:
        print(0)


def main() -> None:
    db_path, query, params = _parse_args()
    _execute_query(db_path, query, params)


if __name__ == "__main__":
    main()
