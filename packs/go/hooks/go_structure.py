#!/usr/bin/env python3
"""Structural metrics for Go, and the Go rules that need to see a function.

Why this exists next to hooks/lib/structural_metrics.py rather than inside it:
that extractor keys on the word `function` and on control heads that open with
a parenthesis. Go writes `func` and `if err != nil {`, so the shared scanner
finds no functions and no control blocks in a Go file and reports it clean.
Its parameter counter reads the last balanced group of a header, which in Go is
the return tuple, not the parameters. Rather than fork a shared file that PHP
and TypeScript depend on, the Go pack brings its own scanner, exactly as
packs/python brings its own AST pass.

Emits one `RULE|message` line per finding:
  NEST001, LOC001, GOD001, PARAM001  core-owned structure rules
  GO001                              panic outside main / outside Must*
  GO002                              context.Context not the first parameter
  WARN-GO001                         naked return with named results

Usage: go_structure.py <file>
"""

from __future__ import annotations

import re
import sys

NEST_MAX = 3
LOC_MAX = 50
STRUCT_LOC_MAX = 300
PARAM_MAX = 3

MAX_SOURCE_BYTES = 512 * 1024

FUNC_RE = re.compile(r"\bfunc\b\s*(?:\(\s*[^)]*\)\s*)?(\w+)?\s*\(")
TYPE_STRUCT_RE = re.compile(r"\btype\s+(\w+)\s+(?:struct|interface)\b")
# No parenthesis required, and `select` included: Go's control heads carry none
# of the punctuation the shared scanner keys on.
CONTROL_RE = re.compile(r"(?:^|[^.\w])(if|for|switch|select)\b|\belse\b")
PANIC_RE = re.compile(r"(?:^|[^.\w])panic\s*\(")
NAKED_RETURN_RE = re.compile(r"^\s*return\s*$")


# --- Blanking out strings and comments ---------------------------------------
#
# Offsets and line breaks are preserved so every position computed on the
# blanked text still points at the right line of the original file.

def _blank_outside(source, cursor, out):
    """Consume one character of code. Returns (next cursor, new state)."""
    char = source[cursor]
    peek = source[cursor + 1] if cursor + 1 < len(source) else ""
    if char == "/" and peek == "/":
        out.append("  ")
        return cursor + 2, "line"
    if char == "/" and peek == "*":
        out.append("  ")
        return cursor + 2, "block"
    if char in ("'", '"', "`"):
        out.append(" ")
        return cursor + 1, char
    out.append(char)
    return cursor + 1, None


def _blank_comment(source, cursor, out, state):
    char = source[cursor]
    peek = source[cursor + 1] if cursor + 1 < len(source) else ""
    if state == "line":
        out.append("\n" if char == "\n" else " ")
        return cursor + 1, None if char == "\n" else "line"
    if char == "*" and peek == "/":
        out.append("  ")
        return cursor + 2, None
    out.append("\n" if char == "\n" else " ")
    return cursor + 1, "block"


def _blank_literal(source, cursor, out, state):
    char = source[cursor]
    peek = source[cursor + 1] if cursor + 1 < len(source) else ""
    if state != "`" and char == "\\" and peek:
        out.append("  ")
        return cursor + 2, state
    if char == state:
        out.append(" ")
        return cursor + 1, None
    out.append("\n" if char == "\n" else " ")
    return cursor + 1, state


def blank_literals(source: str) -> str:
    """Blank strings, runes and comments, keeping offsets and line breaks."""
    out: list[str] = []
    cursor, state = 0, None
    while cursor < len(source):
        if state is None:
            cursor, state = _blank_outside(source, cursor, out)
        elif state in ("line", "block"):
            cursor, state = _blank_comment(source, cursor, out, state)
        else:
            cursor, state = _blank_literal(source, cursor, out, state)
    return "".join(out)


# --- Header parsing -----------------------------------------------------------

def line_of(source: str, position: int) -> int:
    return source.count("\n", 0, position) + 1


def _balanced_group(header: str, start: int) -> str:
    """Text inside the parentheses opening at `start`, or "" when unbalanced."""
    depth = 0
    for index in range(start, len(header)):
        if header[index] == "(":
            depth += 1
        elif header[index] == ")":
            depth -= 1
            if depth == 0:
                return header[start + 1:index]
    return ""


def parameter_list(header: str) -> list[str]:
    """Parameters of the group that follows the function name.

    Go's return tuple is a second balanced group on the same header, so reading
    the last group would count return values instead of parameters.
    """
    match = FUNC_RE.search(header)
    if not match:
        return []
    inner = _balanced_group(header, header.index("(", match.end() - 1)).strip()
    if not inner:
        return []
    parts, depth, current = [], 0, ""
    for char in inner:
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(current.strip())
            current = ""
            continue
        current += char
    parts.append(current.strip())
    return parts


def has_named_results(header: str) -> bool:
    """True when the header declares named return values: `(n int, err error)`."""
    groups = re.findall(r"\(([^()]*)\)", header)
    if len(groups) < 2:
        return False
    results = groups[-1].strip()
    if not results or " " not in results:
        return False
    return bool(re.match(r"^\w+(\s+[\w\[\]*.]+)?\s*(,|$)", results))


# --- Brace scan ---------------------------------------------------------------

class _Scan:
    """Mutable state of one pass over a file, kept out of the argument lists."""

    def __init__(self, source: str) -> None:
        self.source = source
        self.findings: list[tuple[str, str]] = []
        self.stack: list[dict] = []
        self.control_depth = 0
        self.seen_nest: set[int] = set()

    def report(self, rule: str, message: str) -> None:
        self.findings.append((rule, message))


def _open_func(scan: _Scan, cursor: int, header: str, name: str | None) -> None:
    params = parameter_list(header)
    if len(params) > PARAM_MAX:
        scan.report("PARAM001",
                    "line %d: %s() has %d parameters (max %d): pass a struct"
                    % (line_of(scan.source, cursor), name or "closure", len(params), PARAM_MAX))
    positions = [i for i, param in enumerate(params)
                 if re.search(r"\bcontext\.Context\b", param)]
    if positions and positions[0] != 0:
        scan.report("GO002",
                    "line %d: %s() takes context.Context as parameter %d: it goes first"
                    % (line_of(scan.source, cursor), name or "closure", positions[0] + 1))


def _open_control(scan: _Scan, cursor: int) -> None:
    scan.control_depth += 1
    if scan.control_depth < NEST_MAX:
        return
    line_number = line_of(scan.source, cursor)
    if line_number in scan.seen_nest:
        return
    scan.seen_nest.add(line_number)
    scan.report("NEST001",
                "line %d: control flow nested %d levels deep: extract a function "
                "or return early" % (line_number, scan.control_depth))


def _open_brace(scan: _Scan, cursor: int, header: str) -> None:
    func_match = FUNC_RE.search(header)
    struct_match = TYPE_STRUCT_RE.search(header)
    if func_match:
        kind, name = "func", func_match.group(1)
        _open_func(scan, cursor, header, name)
    elif struct_match:
        kind, name = "struct", struct_match.group(1)
    elif CONTROL_RE.search(header):
        kind, name = "control", None
        _open_control(scan, cursor)
    else:
        kind, name = "other", None
    scan.stack.append({"kind": kind, "open": cursor, "name": name})


def _close_brace(scan: _Scan, cursor: int) -> None:
    if not scan.stack:
        return
    frame = scan.stack.pop()
    span = line_of(scan.source, cursor) - line_of(scan.source, frame["open"])
    if frame["kind"] == "control":
        scan.control_depth = max(0, scan.control_depth - 1)
    elif frame["kind"] == "func" and span > LOC_MAX:
        scan.report("LOC001",
                    "line %d: %s() body is %d lines (max %d): extract a function"
                    % (line_of(scan.source, frame["open"]), frame["name"] or "closure",
                       span, LOC_MAX))
    elif frame["kind"] == "struct" and span > STRUCT_LOC_MAX:
        scan.report("GOD001",
                    "line %d: type %s spans %d lines (max %d): too many "
                    "responsibilities, split it"
                    % (line_of(scan.source, frame["open"]), frame["name"] or "?",
                       span, STRUCT_LOC_MAX))


def scan_braces(source: str) -> list[tuple[str, str]]:
    scan = _Scan(source)
    header_start = 0
    for cursor, char in enumerate(source):
        if char not in "{};":
            continue
        if char == "{":
            _open_brace(scan, cursor, source[header_start:cursor])
        elif char == "}":
            _close_brace(scan, cursor)
        header_start = cursor + 1
    return scan.findings


# --- Line-oriented rules ------------------------------------------------------

def scan_lines(source: str, package_main: bool, is_test: bool) -> list[tuple[str, str]]:
    findings = []
    current_func = None
    named_results = False
    for number, line in enumerate(source.split("\n"), start=1):
        func_match = FUNC_RE.search(line)
        if func_match:
            current_func = func_match.group(1)
            named_results = has_named_results(line)
        in_must = bool(current_func and current_func.startswith("Must"))
        if PANIC_RE.search(line) and not is_test and not package_main and not in_must:
            findings.append((
                "GO001",
                "line %d: panic() in library code: return an error so the caller "
                "can decide" % number))
        if named_results and NAKED_RETURN_RE.match(line):
            findings.append((
                "WARN-GO001",
                "line %d: naked return in %s(): name what you return"
                % (number, current_func or "closure")))
    return findings


def analyze(path: str) -> list[tuple[str, str]]:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            raw = handle.read(MAX_SOURCE_BYTES + 1)
    except OSError:
        return []
    if len(raw) > MAX_SOURCE_BYTES:
        return []
    source = blank_literals(raw)
    package_main = bool(re.search(r"^\s*package\s+main\b", source, re.M))
    return scan_braces(source) + scan_lines(source, package_main, path.endswith("_test.go"))


def main() -> None:
    if len(sys.argv) < 2:
        return
    for rule, message in analyze(sys.argv[1]):
        print("%s|%s" % (rule, message))


if __name__ == "__main__":
    main()
