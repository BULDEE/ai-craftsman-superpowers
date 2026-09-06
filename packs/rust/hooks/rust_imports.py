#!/usr/bin/env python3
"""Prints the layer segments a Rust file imports, one per line.

A `use` statement runs to its semicolon, and rustfmt writes the grouped form by
default, spread over several lines when it is long:

    use crate::{
        domain::customer::CustomerId,
        infrastructure::PostgresStore,
    };

A pattern anchored on the segment right after `use` sees none of those, which
is how a domain module importing infrastructure through a group passed. Each
statement is joined back into one line before it is read, so the shape rustfmt
chose stops mattering.

Usage: rust_imports.py <file> <segment> [<segment>...]
Exits 0 and prints the matching statements, or exits 1 when there are none.
"""

from __future__ import annotations

import re
import sys

USE_RE = re.compile(r"^\s*(?:pub\s+)?use\s[^;]*;", re.M)


def matching_uses(source: str, segments: list) -> list:
    # A comment mentioning infrastructure is not an import of it.
    code = re.sub(r"//[^\n]*", "", source)
    code = re.sub(r"/\*.*?\*/", "", code, flags=re.S)
    pattern = re.compile(r"\b(%s)\b" % "|".join(re.escape(s) for s in segments))
    found = []
    for statement in USE_RE.findall(code):
        flat = " ".join(statement.split())
        if pattern.search(flat):
            found.append(flat)
    return found


def main() -> int:
    if len(sys.argv) < 3:
        return 1
    try:
        with open(sys.argv[1], encoding="utf-8", errors="replace") as handle:
            source = handle.read()
    except OSError:
        return 1
    found = matching_uses(source, sys.argv[2:])
    for statement in found:
        print(statement)
    return 0 if found else 1


if __name__ == "__main__":
    sys.exit(main())
