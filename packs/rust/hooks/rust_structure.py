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
  RUST001                            .unwrap() outside tests
  RUST002                            panic!/todo!/unimplemented! in library code
  RUST003                            an unsafe block with no SAFETY comment
  RUST004                            a public item with no doc comment
  RUST005                            .expect() outside tests
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

# `(?:[^<>]|->)*` rather than `[^>]*`: a bound like `<F: Fn(u32) -> u32>`
# carries a `>` that is not the end of the list, and stopping there left the
# function unrecognised, which cost it PARAM001 and LOC001 both.
FN_RE = re.compile(
    r"\bfn\s+(\w+)\s*(?:<(?:[^<>]|->)*>\s*)?\(")
IMPL_RE = re.compile(r"\bimpl\b(?:\s*<[^>]*>)?\s+(?:[\w:<>, ]+\s+for\s+)?([\w:]+)")
CONTROL_RE = re.compile(r"(?:^|[^.\w])(if|for|while|loop|match)\b|\belse\b")
PANIC_RE = re.compile(r"\b(panic|unreachable|todo|unimplemented)\s*!\s*[\(\[]")
UNSAFE_RE = re.compile(r"(?:^|[^\w])unsafe\s*\{")
ALLOW_RE = re.compile(r"^\s*#\s*\[\s*allow\s*\(")
PUBLIC_ITEM_RE = re.compile(
    r"^\s*pub(?:\s*\([^)]*\))?\s+(?:async\s+|const\s+|unsafe\s+|extern\s+\"[^\"]*\"\s+)*"
    r"(fn|struct|enum|trait|type|mod|const|static|union)\s+(\w+)")
# An attribute is not documentation. Accepting `#[` here meant a single
# `#[derive(Debug)]` above an item satisfied the rule, and `#[derive]`,
# `#[inline]` and `#[serde(...)]` are everywhere, so the rule went quiet on
# most real code. `/** */` is accepted by rustdoc and was refused.
DOC_RE = re.compile(r"^\s*(///|//!|/\*\*)")
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
    # `find` on the closing quote is wrong for `'\''`: it stops on the escaped
    # quote, leaves the real one behind, and that residue pairs with the next
    # quote in the file. One stray `'\''` in a const then blanked everything
    # after it and the file came back clean.
    if cursor + 1 >= len(source):
        return 0
    if source[cursor + 1] == "\\":
        index = cursor + 2
        if index < len(source) and source[index] == "u" and source[index + 1:index + 2] == "{":
            index = source.find("}", index)
            if index == -1:
                return 0
            index += 1
        else:
            index += 1
        return index - cursor + 1 if source[index:index + 1] == "'" else 0
    if source[cursor + 2:cursor + 3] == "'":
        return 3
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
        # Rust nests block comments, unlike C. Stopping on the first `*/`
        # handed the rest of a commented-out block back as live code, and
        # rules fired on lines rustc never compiles.
        depth, index = 0, cursor
        while index < length - 1:
            if source[index:index + 2] == "/*":
                depth += 1
                index += 2
                continue
            if source[index:index + 2] == "*/":
                depth -= 1
                index += 2
                if depth == 0:
                    break
                continue
            index += 1
        end = index if depth == 0 else length
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
            # A backslash before a newline is a line continuation. Replacing
            # both with spaces removes the newline, and every line number after
            # it is then one too low: findings point at the wrong line, and
            # drop_ignored reads the wrong line for its marker.
            out.append(" \n" if source[cursor + 1] == "\n" else "  ")
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
    """Text inside the parameter parentheses.

    Only parentheses count toward the depth. Counting `<` and `>` as well looks
    right until a parameter is `f: impl Fn(u32) -> u32`: the `>` of the arrow
    took the depth to zero without a `)`, the walk gave up, and the function
    was reported as having no parameters at all. `[u8; 1 << 4]` did the same.
    """
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
    for index, char in enumerate(inner):
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "<" and index and (inner[index - 1].isalnum() or inner[index - 1] == "_"):
            depth += 1
        elif char == ">" and index and inner[index - 1] != "-" and depth > 0:
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
        # A Rust type spreads its methods over several impl blocks: the
        # inherent one, then one per trait. Measuring a single block is the
        # defect packs/go documented when it refused GOD001 outright, so the
        # spans are summed per type and judged once, at the end.
        self.impl_span: dict = {}
        self.impl_first_line: dict = {}

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
    elif frame["kind"] == "impl":
        name = frame["name"] or "?"
        scan.impl_span[name] = scan.impl_span.get(name, 0) + span
        scan.impl_first_line.setdefault(name, line_of(scan.source, frame["open"]))


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
    for name, span in scan.impl_span.items():
        if span > IMPL_LOC_MAX:
            scan.report("GOD001",
                        "line %d: the impl blocks of %s span %d lines in total "
                        "(max %d): too many responsibilities, split the type"
                        % (scan.impl_first_line[name], name, span, IMPL_LOC_MAX))
    return scan.findings


# --- Line-oriented rules ------------------------------------------------------

UNWRAP_RE = re.compile(r"\.unwrap\s*\(\s*\)")
EXPECT_RE = re.compile(r"\.expect\s*\(")


def _unwrap_and_expect(line, number, in_test, findings):
    """RUST001 refuses, RUST005 reports, and the difference is the message.

    `.expect("the schema is embedded")` carries the invariant a reviewer
    checks; `.unwrap()` carries nothing at all. Both are exempt in test code,
    where a panic is how a failure is reported.
    """
    if in_test:
        return
    if UNWRAP_RE.search(line):
        findings.append((
            "RUST001",
            "line %d: .unwrap() - propagate with ? or handle the error" % number))
    elif EXPECT_RE.search(line):
        findings.append((
            "RUST005",
            "line %d: .expect() - the message documents the panic, it does not "
            "prevent it" % number))


def _panic_and_unsafe(line, number, in_test, findings):
    if PANIC_RE.search(line) and not in_test:
        findings.append((
            "RUST002",
            "line %d: a panicking macro in library code: return a Result so the "
            "caller can decide" % number))


def _preamble(raw_lines, index):
    """The contiguous run of comments and attributes above line `index`.

    Reading a single line above an item is wrong in both directions. A SAFETY
    note runs to two or three lines, which is the convention in the standard
    library and what clippy's `undocumented_unsafe_blocks` expects; and a doc
    comment is routinely separated from its item by `#[derive(...)]`, which
    rustfmt happily spreads over four lines.
    """
    collected = []
    cursor = index - 1
    inside_attribute = False
    inside_block_comment = False
    while cursor >= 0:
        stripped = raw_lines[cursor].strip()
        if not stripped and not inside_block_comment:
            break
        if inside_block_comment:
            # A `/** ... */` doc comment: the middle lines are prose and match
            # nothing, so the walk stopped on them and the doc was never seen.
            collected.append(raw_lines[cursor])
            if stripped.startswith("/*"):
                inside_block_comment = False
            cursor -= 1
            continue
        if stripped.endswith("*/") and not stripped.startswith("/*"):
            inside_block_comment = True
            collected.append(raw_lines[cursor])
            cursor -= 1
            continue
        if inside_attribute:
            # Everything between `#[derive(` and its `)]` belongs to the
            # attribute, and rustfmt puts one item per line in there.
            collected.append(raw_lines[cursor])
            if stripped.startswith("#["):
                inside_attribute = False
            cursor -= 1
            continue
        if stripped.endswith(")]") and not stripped.startswith("#["):
            inside_attribute = True
            collected.append(raw_lines[cursor])
            cursor -= 1
            continue
        if (stripped.startswith("//") or stripped.startswith("#[")
                or stripped.startswith("*") or stripped.startswith("/*")):
            collected.append(raw_lines[cursor])
            cursor -= 1
            continue
        break
    return "\n".join(reversed(collected))


def _unsafe_without_reason(line, number, preamble, findings):
    """RUST003: an unsafe block must carry the invariant it relies on.

    This is the standard library's own convention and clippy's
    `undocumented_unsafe_blocks`: the comment is what a reviewer checks, so an
    unsafe block without one cannot be reviewed at all.
    """
    if not UNSAFE_RE.search(line):
        return
    if "SAFETY:" in line or "SAFETY:" in preamble:
        return
    findings.append((
        "RUST003",
        "line %d: unsafe block with no `// SAFETY:` comment stating the invariant"
        % number))


def _public_docs(line, number, preamble, findings):
    match = PUBLIC_ITEM_RE.match(line)
    if not match:
        return
    if any(DOC_RE.match(candidate) for candidate in preamble.split("\n")):
        return
    findings.append((
        "RUST004",
        "line %d: public %s %s has no doc comment"
        % (number, match.group(1), match.group(2))))


def _allow_without_reason(line, number, preamble, findings):
    """WARN-RUST001: an #[allow] says why, or it says nothing.

    The trailing comment is where the reason naturally goes, and a `///` above
    the item documents the item rather than the suppression. Measuring "are
    there two slashes above" got both backwards.
    """
    if not ALLOW_RE.match(line):
        return
    if "reason" in line:
        return
    if re.search(r"//(?!/)", line):
        return
    for candidate in preamble.split("\n"):
        stripped = candidate.strip()
        if stripped.startswith("//") and not stripped.startswith(("///", "//!")):
            return
    findings.append((
        "WARN-RUST001",
        "line %d: #[allow] with no comment saying why the lint does not apply"
        % number))


def _matching_close(source: str, open_index: int) -> int:
    """Index of the `}` closing the `{` at `open_index`, or the end of file."""
    depth = 0
    for index in range(open_index, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return len(source) - 1


def test_line_range(source: str, raw: str) -> set:
    """Line numbers inside a `#[cfg(test)]` module or a `#[test]` function.

    A flag that flips to "we are in tests" on the first attribute and never
    flips back stops validating the file from there on. `#[cfg(test)] mod
    tests` conventionally sits at the bottom, so the damage is usually
    invisible; put anything after it, or a single `#[test]` in the middle, and
    every rule below goes quiet. The block's own braces are what bounds it.
    """
    inside: set = set()
    raw_lines = raw.split("\n")
    offsets, position = [], 0
    for line in source.split("\n"):
        offsets.append(position)
        position += len(line) + 1
    for index, raw_line in enumerate(raw_lines):
        if not TEST_ATTR_RE.match(raw_line):
            continue
        if index >= len(offsets):
            continue
        opening = source.find("{", offsets[index])
        if opening == -1:
            continue
        closing = _matching_close(source, opening)
        first = source.count("\n", 0, offsets[index]) + 1
        last = source.count("\n", 0, closing) + 1
        inside.update(range(first, last + 1))
    return inside


def scan_lines(source: str, raw: str, is_test_file: bool) -> list[tuple[str, str]]:
    """Code is read from the blanked text, comments from the raw text.

    A doc comment is a comment, and `blank_literals` has replaced every comment
    with spaces by the time this runs.
    """
    findings: list[tuple[str, str]] = []
    raw_lines = raw.split("\n")
    test_lines = set() if is_test_file else test_line_range(source, raw)
    for number, line in enumerate(source.split("\n"), start=1):
        raw_line = raw_lines[number - 1] if number <= len(raw_lines) else ""
        preamble = _preamble(raw_lines, number - 1)
        in_test = is_test_file or number in test_lines
        _unwrap_and_expect(line, number, in_test, findings)
        _panic_and_unsafe(line, number, in_test, findings)
        _unsafe_without_reason(line, number, preamble, findings)
        if not in_test:
            _public_docs(line, number, preamble, findings)
        _allow_without_reason(raw_line, number, preamble, findings)
    return findings


# A clippy lint that says the same thing as one of our rules. Honouring it
# means a developer writes the exemption once, in the language's own syntax,
# instead of twice.
CLIPPY_EQUIVALENT = {
    "PARAM001": "too_many_arguments",
    "RUST001": "unwrap_used",
    "RUST005": "expect_used",
    "RUST004": "missing_docs_in_private_items",
}


def drop_ignored(findings, raw: str):
    """Remove a finding its own line, or its preamble, already exempts.

    Two syntaxes are honoured: `craftsman-ignore: <RULE>` on the line, and the
    `#[allow(clippy::...)]` attribute above the item when clippy has a lint
    that means the same thing.
    """
    lines = raw.split("\n")
    kept = []
    for rule, message in findings:
        match = re.match(r"line (\d+):", message)
        if not match:
            kept.append((rule, message))
            continue
        index = int(match.group(1)) - 1
        if not 0 <= index < len(lines):
            kept.append((rule, message))
            continue
        if ("craftsman-ignore: %s" % rule) in lines[index]:
            continue
        lint = CLIPPY_EQUIVALENT.get(rule)
        if lint and lint in _preamble(lines, index):
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
    # The pipeline scans relative paths, so `/tests/` alone missed
    # `tests/integration.rs` and every one of its unwraps was refused. The
    # fixture that was supposed to cover this wrote an absolute path, which is
    # why it passed: a fixture whose shape is not the consumer's proves nothing.
    normalised = "/" + path.lstrip("./")
    is_test_file = (path.endswith("_test.rs")
                    or "/tests/" in normalised or "/benches/" in normalised)
    findings = scan_braces(source) + scan_lines(source, raw, is_test_file)
    return drop_ignored(findings, raw)


def main() -> None:
    if len(sys.argv) < 2:
        return
    for rule, message in analyze(sys.argv[1]):
        print("%s|%s" % (rule, message))


if __name__ == "__main__":
    main()
