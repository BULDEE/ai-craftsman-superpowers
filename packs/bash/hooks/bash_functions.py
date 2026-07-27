#!/usr/bin/env python3
"""Structural checks over shell functions.

Usage:
  bash_functions.py length <file>   SH002      function longer than MAX_LINES
  bash_functions.py locals <file>   WARN-SH001 assigns without declaring local

One scanner for both. They each carried their own copy of the same naive brace
counting, inside a `python3 -c "..."` string in the validator, and so each
carried the same two bugs: a brace inside an embedded python, jq or awk
snippet counted as a shell brace, and a function whose end was therefore never
found fell back to measuring header-to-header, charging the comments and blank
lines between two functions to the first one.

A function whose end cannot be located is now reported as nothing rather than
as a guess. Blocking a write on an invented length is what teaches a developer
to suppress the rule, and a suppressed rule enforces nothing.
"""
import re
import sys
from pathlib import Path

MAX_LINES = 30

HEADER_RE = re.compile(r"^(\w[\w_-]*)\s*\(\)\s*\{?\s*$|^(\w[\w_-]*)\(\)\s*\{")
DQ_SPAN = re.compile(r'"[^"]*"')
SQ_SPAN = re.compile(r"'[^']*'")
ASSIGN_RE = re.compile(r"^[a-zA-Z_]\w*=")
QUOTES = ('"', "'")


def _code_only(line: str) -> str:
    text = line.replace('\\"', "").replace("\\'", "")
    return DQ_SPAN.sub("", SQ_SPAN.sub("", text)).split("#", 1)[0]


def _opening_quote(code: str) -> str:
    """Whichever quote is left unbalanced once the complete spans are gone. It
    is the one opening a string that runs past the end of the line."""
    for mark in QUOTES:
        if code.count(mark) % 2 == 1:
            return mark
    return ""


class _Scan:
    def __init__(self):
        self.quote = ""
        self.name = None
        self.start = 0
        self.depth = 0
        self.body = []

    def open_function(self, stripped, code, number):
        match = HEADER_RE.match(stripped)
        self.name = match.group(1) or match.group(2)
        self.start = number
        self.body = []
        self.depth = code.count("{") - code.count("}")

    def closes_string(self, stripped):
        return stripped.replace("\\" + self.quote, "").count(self.quote) % 2 == 1


def iter_functions(lines: list):
    """Yield (name, start, end, body) per function whose braces balance. One
    that never closes is skipped, never estimated."""
    scan = _Scan()
    for number, raw in enumerate(lines, 1):
        stripped = raw.strip()
        if scan.quote:
            if scan.closes_string(stripped):
                scan.quote = ""
            continue

        code = _code_only(stripped)
        if scan.depth == 0 and HEADER_RE.match(stripped):
            scan.open_function(stripped, code, number)
        elif scan.name is not None:
            scan.body.append(stripped)
            scan.depth += code.count("{") - code.count("}")
            if scan.depth <= 0:
                yield scan.name, scan.start, number, scan.body
                scan.name, scan.depth = None, 0
        scan.quote = _opening_quote(code)


def check_length(lines: list) -> None:
    for name, start, end, _ in iter_functions(lines):
        length = end - start + 1
        if length > MAX_LINES:
            print(f"line {start}: function {name}() is {length} lines - consider extracting")


def check_locals(lines: list) -> None:
    for name, start, _, body in iter_functions(lines):
        has_local = any("local " in line for line in body)
        assigns = any(ASSIGN_RE.match(line) for line in body if not line.startswith("#"))
        if assigns and not has_local:
            print(f"line {start}: function {name}() assigns variables without local declarations")


COMMANDS = {"length": check_length, "locals": check_locals}


def main() -> int:
    if len(sys.argv) < 3 or sys.argv[1] not in COMMANDS:
        print("Usage: bash_functions.py length|locals <file>", file=sys.stderr)
        return 1
    try:
        lines = Path(sys.argv[2]).read_text(errors="ignore").split("\n")
    except OSError:
        return 0
    COMMANDS[sys.argv[1]](lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
