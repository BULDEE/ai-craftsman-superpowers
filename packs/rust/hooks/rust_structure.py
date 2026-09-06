#!/usr/bin/env python3
"""Rust rules that need to see more than one line, plus the structure metrics.

Why this exists next to hooks/lib/structural_metrics.py rather than inside it:
that extractor keys on the word `function` and on control heads that open with
a parenthesis. Rust writes `fn` and `if a > 0 {`, so the shared scanner finds no
functions and no control blocks in a Rust file and reports it clean (measured:
`c-like` and `php-like` both return nothing on a file with four nested blocks
and a four-parameter function). Its parameter counter also reads the last
balanced group of a header, which in Rust is a `where` clause or a tuple type.

Emits one `RULE|message` line per finding:
  NEST001, LOC001, GOD001, PARAM001  core-owned structure rules
  RUST002                            panic!/todo!/unimplemented! in library code
  RUST003                            an unsafe block with no SAFETY comment
  RUST004                            a public item with no doc comment
  WARN-RUST001                       an #[allow] with no justification

GOD001 is claimed here, unlike in the Go pack: Rust's god object is an `impl`
block carrying forty methods, and an `impl` block is brace-delimited, so its
span is the measurement. Go's is a type with methods scattered across a file
and a five-line struct, which is why packs/go declares no GOD001.

Usage: rust_structure.py <file>
"""

from __future__ import annotations

import re
import sys

NEST_MAX = 3
LOC_MAX = 50
IMPL_LOC_MAX = 300
PARAM_MAX = 3

MAX_SOURCE_BYTES = 512 * 1024

FN_RE = re.compile(
    r"\bfn\s+(\w+)\s*(?:<[^>]*>\s*)?\(")
IMPL_RE = re.compile(r"\bimpl\b(?:\s*<[^>]*>)?\s+(?:[\w:<>, ]+\s+for\s+)?([\w:]+)")
CONTROL_RE = re.compile(r"(?:^|[^.\w])(if|for|while|loop|match)\b|\belse\b")
PANIC_RE = re.compile(r"\b(panic|unreachable|todo|unimplemented)\s*!\s*[\(\[]")
UNSAFE_RE = re.compile(r"(?:^|[^\w])unsafe\s*\{")
ALLOW_RE = re.compile(r"^\s*#\s*\[\s*allow\s*\(")
PUBLIC_ITEM_RE = re.compile(
    r"^\s*pub(?:\s*\([^)]*\))?\s+(?:async\s+|const\s+|unsafe\s+|extern\s+\"[^\"]*\"\s+)*"
    r"(fn|struct|enum|trait|type|mod|const|static|union)\s+(\w+)")
DOC_RE = re.compile(r"^\s*(///|//!|#\s*\[)")
TEST_ATTR_RE = re.compile(r"^\s*#\s*\[\s*(cfg\s*\(\s*test\s*\)|test|tokio::test)")


# --- Blanking out strings and comments ---------------------------------------
#
# Offsets and line breaks are preserved so every position computed on the
# blanked text still points at the right line of the original file.

def _char_literal_length(source: str, cursor: int) -> int:
    """Length of the char literal starting at `cursor`, or 0 for a lifetime.

    `'a` in `&'a str` is a lifetime, not an unterminated character literal.
    Treating it as one swallows the rest of the file, and with it every brace
    the scanner was counting. A char literal is `'x'`, `'\\n'`, `'\\u{1F600}'`:
    it always closes, and it closes within a bounded distance.
    """
    end = source.find("'", cursor + 1)
    if end == -1:
        return 0
    body = source[cursor + 1:end]
    if not body:
        return 0
    if body.startswith("\\"):
        return end - cursor + 1
    if len(body) == 1:
        return end - cursor + 1
    return 0


def _raw_string_length(source: str, cursor: int) -> int:
    """Length of a raw string `r"..."` or `r#"..."#` starting at `cursor`."""
    match = re.match(r'r(#*)"', source[cursor:])
    if not match:
        return 0
    hashes = match.group(1)
    terminator = '"' + hashes
    end = source.find(terminator, cursor + len(match.group(0)))
    if end == -1:
        return len(source) - cursor
    return end + len(terminator) - cursor


def _blanked(text: str) -> str:
    """Same length, same line breaks, no content."""
    return "".join("\n" if char == "\n" else " " for char in text)


def _blank_comment(source: str, cursor: int, out: list) -> int:
    """Blank a `//` or `/* */` comment. Returns the cursor, or -1 if neither."""
    length = len(source)
    peek = source[cursor + 1] if cursor + 1 < length else ""
    if source[cursor] != "/" or peek not in ("/", "*"):
        return -1
    if peek == "/":
        end = source.find("\n", cursor)
        end = length if end == -1 else end
    else:
        end = source.find("*/", cursor + 2)
        end = length if end == -1 else end + 2
    out.append(_blanked(source[cursor:end]))
    return end


def blank_literals(source: str) -> str:
    """Blank strings, chars and comments, keeping offsets and line breaks."""
    out: list[str] = []
    cursor, length = 0, len(source)
    while cursor < length:
        char = source[cursor]
        peek = source[cursor + 1] if cursor + 1 < length else ""
        moved = _blank_comment(source, cursor, out)
        if moved != -1:
            cursor = moved
            continue
        if char == "r" and peek in ('"', "#"):
            span = _raw_string_length(source, cursor)
            if span:
                out.append(_blanked(source[cursor:cursor + span]))
                cursor += span
                continue
        if char == '"':
            cursor = _blank_plain_string(source, cursor, out)
            continue
        if char == "'":
            span = _char_literal_length(source, cursor)
            if span:
                out.append(" " * span)
                cursor += span
                continue
        out.append(char)
        cursor += 1
    return "".join(out)


def _blank_plain_string(source: str, cursor: int, out: list) -> int:
    """Blank a `"..."` literal, honouring backslash escapes. Returns the cursor."""
    length = len(source)
    out.append(" ")
    cursor += 1
    while cursor < length:
        char = source[cursor]
        if char == "\\" and cursor + 1 < length:
            out.append("  ")
            cursor += 2
            continue
        if char == '"':
            out.append(" ")
            return cursor + 1
        out.append("\n" if char == "\n" else " ")
        cursor += 1
    return cursor


# --- Header parsing -----------------------------------------------------------

def line_of(source: str, position: int) -> int:
    return source.count("\n", 0, position) + 1


def _param_group(header: str, start: int) -> str:
    """Text inside the parameter parentheses, angle brackets counted along."""
    depth = 0
    for index in range(start, len(header)):
        if header[index] in "(<[":
            depth += 1
        elif header[index] in ")>]":
            depth -= 1
            if depth == 0 and header[index] == ")":
                return header[start + 1:index]
    return ""


def parameter_list(header: str) -> list[str]:
    """Parameters of the group that follows the function name, `self` excluded.

    A `where` clause or a tuple return type is a later balanced group on the
    same header, so reading the last one counts the wrong thing.
    """
    match = FN_RE.search(header)
    if not match:
        return []
    inner = _param_group(header, header.index("(", match.end() - 1)).strip()
    if not inner:
        return []
    parts, depth, current = [], 0, ""
    for char in inner:
        if char in "([{<":
            depth += 1
        elif char in ")]}>":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(current.strip())
            current = ""
            continue
        current += char
    parts.append(current.strip())
    # The receiver is not a parameter the caller passes.
    return [part for part in parts
            if part and not re.match(r"^(&\s*)?(mut\s+)?self\b", part)]


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


def _open_fn(scan: _Scan, cursor: int, header: str, name: str | None) -> None:
    params = parameter_list(header)
    if len(params) > PARAM_MAX:
        scan.report("PARAM001",
                    "line %d: %s() has %d parameters (max %d): pass a struct"
                    % (line_of(scan.source, cursor), name or "closure", len(params), PARAM_MAX))


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
    fn_match = FN_RE.search(header)
    impl_match = IMPL_RE.search(header)
    if fn_match:
        kind, name = "fn", fn_match.group(1)
        _open_fn(scan, cursor, header, name)
    elif impl_match:
        kind, name = "impl", impl_match.group(1)
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
    elif frame["kind"] == "fn" and span > LOC_MAX:
        scan.report("LOC001",
                    "line %d: %s() body is %d lines (max %d): extract a function"
                    % (line_of(scan.source, frame["open"]), frame["name"] or "closure",
                       span, LOC_MAX))
    elif frame["kind"] == "impl" and span > IMPL_LOC_MAX:
        scan.report("GOD001",
                    "line %d: impl %s spans %d lines (max %d): too many "
                    "responsibilities, split the trait"
                    % (line_of(scan.source, frame["open"]), frame["name"] or "?",
                       span, IMPL_LOC_MAX))


def scan_braces(source: str) -> list[tuple[str, str]]:
    """Walk the braces. Only `{` and `}` bound a header.

    `;` bounds one in the shared PHP and TypeScript extractor. In Rust that
    would hide `if let Some(x) = f() {` and `while let`, the same way it hid
    Go's `if err := f(); err != nil {`.
    """
    scan = _Scan(source)
    header_start = 0
    for cursor, char in enumerate(source):
        if char == "{":
            _open_brace(scan, cursor, source[header_start:cursor])
        elif char == "}":
            _close_brace(scan, cursor)
        else:
            continue
        header_start = cursor + 1
    return scan.findings


# --- Line-oriented rules ------------------------------------------------------

def _panic_and_unsafe(line, number, in_test, findings):
    if PANIC_RE.search(line) and not in_test:
        findings.append((
            "RUST002",
            "line %d: a panicking macro in library code: return a Result so the "
            "caller can decide" % number))


def _unsafe_without_reason(line, number, previous_raw, findings):
    """RUST003: an unsafe block must carry the invariant it relies on.

    This is the standard library's own convention and clippy's
    `undocumented_unsafe_blocks`: the comment is what a reviewer checks, so an
    unsafe block without one cannot be reviewed at all.
    """
    if not UNSAFE_RE.search(line):
        return
    if "SAFETY:" in line or "SAFETY:" in previous_raw:
        return
    findings.append((
        "RUST003",
        "line %d: unsafe block with no `// SAFETY:` comment stating the invariant"
        % number))


def _public_docs(line, number, previous_raw, findings):
    match = PUBLIC_ITEM_RE.match(line)
    if not match:
        return
    if DOC_RE.match(previous_raw):
        return
    findings.append((
        "RUST004",
        "line %d: public %s %s has no doc comment"
        % (number, match.group(1), match.group(2))))


def _allow_without_reason(line, number, previous_raw, findings):
    if not ALLOW_RE.match(line):
        return
    if "//" in previous_raw or "reason" in line:
        return
    findings.append((
        "WARN-RUST001",
        "line %d: #[allow] with no comment saying why the lint does not apply"
        % number))


def scan_lines(source: str, raw: str, is_test_file: bool) -> list[tuple[str, str]]:
    """Code is read from the blanked text, comments from the raw text.

    A doc comment is a comment, and `blank_literals` has replaced every comment
    with spaces by the time this runs.
    """
    findings: list[tuple[str, str]] = []
    raw_lines = raw.split("\n")
    previous_raw = ""
    in_test = is_test_file
    for number, line in enumerate(source.split("\n"), start=1):
        raw_line = raw_lines[number - 1] if number <= len(raw_lines) else ""
        if TEST_ATTR_RE.match(raw_line):
            in_test = True
        _panic_and_unsafe(line, number, in_test, findings)
        _unsafe_without_reason(line, number, previous_raw, findings)
        if not in_test:
            _public_docs(line, number, previous_raw, findings)
        _allow_without_reason(raw_line, number, previous_raw, findings)
        previous_raw = raw_line
    return findings


def drop_ignored(findings, raw: str):
    """Remove any finding whose own line carries `craftsman-ignore: <RULE>`."""
    lines = raw.split("\n")
    kept = []
    for rule, message in findings:
        match = re.match(r"line (\d+):", message)
        if match:
            index = int(match.group(1)) - 1
            if 0 <= index < len(lines) and ("craftsman-ignore: %s" % rule) in lines[index]:
                continue
        kept.append((rule, message))
    return kept


def analyze(path: str) -> list[tuple[str, str]]:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            raw = handle.read(MAX_SOURCE_BYTES + 1)
    except OSError:
        return []
    if len(raw) > MAX_SOURCE_BYTES:
        return []
    source = blank_literals(raw)
    is_test_file = path.endswith("_test.rs") or "/tests/" in path
    findings = scan_braces(source) + scan_lines(source, raw, is_test_file)
    return drop_ignored(findings, raw)


def main() -> None:
    if len(sys.argv) < 2:
        return
    for rule, message in analyze(sys.argv[1]):
        print("%s|%s" % (rule, message))


if __name__ == "__main__":
    main()
