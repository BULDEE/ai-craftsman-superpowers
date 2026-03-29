#!/usr/bin/env python3
"""Parameterized SQLite write helper — eliminates SQL injection in metrics-db.sh.

Usage: metrics-query.py <db_path> <query> [param1] [param2] ...

Each positional arg after the query becomes a bind parameter (?).
"""
import sqlite3
import sys


def main():
    if len(sys.argv) < 3:
        print("Usage: metrics-query.py <db_path> <query> [params...]", file=sys.stderr)
        sys.exit(1)

    db_path = sys.argv[1]
    query = sys.argv[2]
    params = sys.argv[3:]

    conn = sqlite3.connect(db_path)
    try:
        conn.execute(query, params)
        conn.commit()
    finally:
        conn.close()


if __name__ == "__main__":
    main()
