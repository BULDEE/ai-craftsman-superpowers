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

import os
import re
import sys

# The brace walk, the parameter split, the ignore filter and the line
# arithmetic are the engine's (#38): this file keeps what carries the language.
#
# The engine is found where it actually is, not where a variable says it is:
# the three front-ends export CLAUDE_PLUGIN_ROOT, but the bash side only trusts
# it when the directory exists (pack-loader.sh) and craftsman-ci.sh keeps a
# pre-existing value while sourcing its own libraries, so a root that loads the
# pack fine in bash can point the import at a tree without the module. The
# relative path is the plugin's own layout; the variable serves a pack that
# lives outside it. Neither holding the module is loud, and not a clean
# verdict: the validator reads stdout for findings, so a traceback on stderr
# and an empty stdout used to read as "nothing found" on an unread file.
def _engine_lib() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    for root in (os.environ.get("CLAUDE_PLUGIN_ROOT"),
                 os.path.dirname(os.path.dirname(os.path.dirname(here)))):
        if root and os.path.isfile(os.path.join(root, "hooks", "lib", "brace_scanner.py")):
            return os.path.join(root, "hooks", "lib")
    sys.stderr.write("craftsman: rust_structure.py cannot load the engine's brace walk "
                     "(hooks/lib/brace_scanner.py not under CLAUDE_PLUGIN_ROOT=%r nor beside this pack); "
                     "set CLAUDE_PLUGIN_ROOT to the plugin root\n" % os.environ.get("CLAUDE_PLUGIN_ROOT"))
    sys.exit(2)


sys.path.insert(0, _engine_lib())
from brace_scanner import (  # noqa: E402
    Profile, balanced_group, drop_ignored, line_of, read_source, split_params, walk_braces,
)

IMPL_LOC_MAX = 300

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

def parameter_list(header: str) -> list[str]:
    """Parameters of the group that follows the function name, `self` excluded.

    A `where` clause or a tuple return type is a later balanced group on the
    same header, so reading the last one counts the wrong thing. Generics nest
    with `<` and `>`, and a `->` must not close one.
    """
    match = FN_RE.search(header)
    if not match:
        return []
    inner = balanced_group(header, header.index("(", match.end() - 1)).strip()
    if not inner:
        return []
    # The receiver is not a parameter the caller passes.
    return [part for part in split_params(inner, angle_brackets=True)
            if not re.match(r"^(&\s*)?(mut\s+)?self\b", part)]


# --- Brace scan ---------------------------------------------------------------
#
# What Rust measures beyond the shared walk: a type spreads its methods over
# several impl blocks, the inherent one then one per trait. Measuring a single
# block is the defect packs/go documented when it refused GOD001 outright, so
# the spans are summed per type across frames and judged once, at the end.

def _sum_impl_span(scan, frame: dict, span: int) -> None:
    if frame["kind"] != "container":
        return
    name = frame["name"] or "?"
    spans = scan.state.setdefault("impl_span", {})
    spans[name] = spans.get(name, 0) + span
    scan.state.setdefault("impl_first_line", {}).setdefault(
        name, line_of(scan.source, frame["open"]))


PROFILE = Profile(function_re=FN_RE, control_re=CONTROL_RE, container_re=IMPL_RE,
                  parameter_list=parameter_list, on_close=_sum_impl_span,
                  param_remedy="pass a struct")


def scan_braces(source: str) -> list[tuple[str, str]]:
    scan = walk_braces(source, PROFILE)
    first_line = scan.state.get("impl_first_line", {})
    for name, span in scan.state.get("impl_span", {}).items():
        if span > IMPL_LOC_MAX:
            scan.report("GOD001",
                        "line %d: the impl blocks of %s span %d lines in total "
                        "(max %d): too many responsibilities, split the type"
                        % (first_line[name], name, span, IMPL_LOC_MAX))
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


def _allowed_by_clippy(rule: str, lines: list, index: int) -> bool:
    """A `#[allow(clippy::...)]` above the item, when clippy has a lint that
    means the same thing as the rule."""
    lint = CLIPPY_EQUIVALENT.get(rule)
    return bool(lint and lint in _preamble(lines, index))


def analyze(path: str) -> list[tuple[str, str]]:
    raw = read_source(path)
    if raw is None:
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
    return drop_ignored(findings, raw, also_exempt=_allowed_by_clippy)


def main() -> None:
    if len(sys.argv) < 2:
        return
    for rule, message in analyze(sys.argv[1]):
        print("%s|%s" % (rule, message))


if __name__ == "__main__":
    main()
