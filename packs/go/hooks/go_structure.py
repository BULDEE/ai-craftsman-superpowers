#!/usr/bin/env python3
"""Go rules that need to see more than one line, plus the structure metrics.

Why this exists next to hooks/lib/structural_metrics.py rather than inside it:
that extractor keys on the word `function` and on control heads that open with
a parenthesis. Go writes `func` and `if err != nil {`, so the shared scanner
finds no functions and no control blocks in a Go file and reports it clean
(measured: four nested blocks and a four-parameter function produce no output
at all). Its parameter counter also reads the last balanced group of a header,
which in Go is the return tuple.

Emits one `RULE|message` line per finding:
  NEST001, LOC001, PARAM001  core-owned structure rules
  GO001                      panic outside main / outside Must*
  GO002                      context.Context not the first parameter
  GO003                      exported symbol without a doc comment naming it
  GO004                      an error dropped into the blank identifier
  GO006                      an error return ignored outright
  WARN-GO001                 naked return with named results

No GOD001. Go's god object is a type with forty methods spread across a file,
not a long declaration: a `type God struct` listing its fields is a handful of
lines however many responsibilities it carries. Measuring the declaration would
report every Go file clean, which is the same defect as declaring a metrics
dialect that cannot read the language.

Usage: go_structure.py <file>
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
    sys.stderr.write("craftsman: go_structure.py cannot load the engine's brace walk "
                     "(hooks/lib/brace_scanner.py not under CLAUDE_PLUGIN_ROOT=%r nor beside this pack); "
                     "set CLAUDE_PLUGIN_ROOT to the plugin root\n" % os.environ.get("CLAUDE_PLUGIN_ROOT"))
    sys.exit(2)


sys.path.insert(0, _engine_lib())
from brace_scanner import (  # noqa: E402
    Profile, balanced_group, drop_ignored, line_of, read_source, split_params, walk_braces,
)

# `(?:\[[^\]]*\]\s*)?` is the type parameter list: without it a generic
# function is invisible, which cost PARAM001 and GO002 their findings and, on
# `func MustParse[T any]`, produced a GO001 false positive on a blocking rule.
FUNC_RE = re.compile(r"\bfunc\b\s*(?:\(\s*[^)]*\)\s*)?(\w+)?\s*(?:\[[^\]]*\]\s*)?\(")
CONTROL_RE = re.compile(r"(?:^|[^.\w])(if|for|switch|select)\b|\belse\b")
PANIC_RE = re.compile(r"(?:^|[^.\w])panic\s*\(")
NAKED_RETURN_RE = re.compile(r"^\s*return\s*$")

EXPORTED_DECL_RE = re.compile(r"^(func|type|var|const)\s+([A-Z]\w*)")
EXPORTED_METHOD_RE = re.compile(r"^func\s+\([^)]*\)\s+([A-Z]\w*)")
GROUP_OPEN_RE = re.compile(r"^(var|const|type)\s*\($")
GROUP_MEMBER_RE = re.compile(r"^\s+([A-Z]\w*)\b")

# The comma-ok forms. In every one of them the discarded second value is a
# bool or a slice element, never an error, so flagging them is a false positive
# by construction rather than by accident. Measured on idiomatic Go: without
# these exclusions GO004 fired four times out of four on code with no defect.
COMMA_OK_RE = re.compile(
    r":?=\s*(?:<-\s*\w|[\w.\[\]]+\s*\[[^\]]*\]\s*$|[\w.()]+\.\(\s*[\w.*\[\]]+\s*\))"
)
RANGE_RE = re.compile(r"\brange\b")

# Level 1 cannot resolve a call's signature, so an errcheck-equivalent is out of
# reach in general. What is in reach is the set of standard-library calls that
# every Go programmer knows return an error, used as a statement with the result
# thrown away. errcheck supersedes this list when it is installed, see pack.yml.
IGNORED_ERROR_CALL_RE = re.compile(
    r"^\s*(?:defer\s+)?(?:[\w.]*\.)?"
    r"(Write|WriteString|WriteTo|Close|Flush|Sync|Remove|RemoveAll|Rename|"
    r"Mkdir|MkdirAll|Chmod|Chdir|Truncate|Fprintf|Fprintln|Fprint|Unmarshal|"
    r"Encode|Decode|Scan|Exec|Wait|Shutdown|Serve|ListenAndServe)\s*\("
)


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

def parameter_list(header: str) -> list[str]:
    """Parameters of the group that follows the function name.

    Go's return tuple is a second balanced group on the same header, so reading
    the last group would count return values instead of parameters.
    """
    match = FUNC_RE.search(header)
    if not match:
        return []
    inner = balanced_group(header, header.index("(", match.end() - 1)).strip()
    return split_params(inner) if inner else []


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
#
# Only what Go measures on a function head beyond the shared PARAM001: a
# context.Context that is not the first parameter.

def _context_first(scan, cursor: int, header: str, name: str | None, params: list) -> None:
    positions = [i for i, param in enumerate(params)
                 if re.search(r"\bcontext\.Context\b", param)]
    if positions and positions[0] != 0:
        scan.report("GO002",
                    "line %d: %s() takes context.Context as parameter %d: it goes first"
                    % (line_of(scan.source, cursor), name or "closure", positions[0] + 1))


PROFILE = Profile(function_re=FUNC_RE, control_re=CONTROL_RE,
                  parameter_list=parameter_list, on_function=_context_first)


def scan_braces(source: str) -> list[tuple[str, str]]:
    return walk_braces(source, PROFILE).findings


# --- Line-oriented rules ------------------------------------------------------

def _panic_and_naked_return(line, number, state, package_main, is_test, findings):
    in_must = bool(state["func"] and state["func"].startswith("Must"))
    if PANIC_RE.search(line) and not is_test and not package_main and not in_must:
        findings.append((
            "GO001",
            "line %d: panic() in library code: return an error so the caller "
            "can decide" % number))
    if state["named_results"] and NAKED_RETURN_RE.match(line):
        findings.append((
            "WARN-GO001",
            "line %d: naked return in %s(): name what you return"
            % (number, state["func"] or "closure")))


def _discarded_errors(line, number, findings):
    stripped = line.strip()
    if re.search(r",\s*_\s*:?=", line) or re.match(r"^\s*_\s*=\s*[\w.]+\s*\(", line):
        if not (COMMA_OK_RE.search(line) or RANGE_RE.search(line)):
            findings.append((
                "GO004",
                "line %d: result dropped into _ - handle the error or let it travel"
                % number))
        return
    if IGNORED_ERROR_CALL_RE.match(stripped) and "=" not in stripped.split("(")[0]:
        findings.append((
            "GO006",
            "line %d: the error returned here is ignored outright - assign it and "
            "handle it" % number))


def _report_doc(symbol, number, previous, findings):
    """The doc comment must name the symbol: that is what the rule text
    promises, and what `go doc` renders. A comment naming nothing was passing."""
    if not previous.strip().startswith("//"):
        findings.append(("GO003",
                         "line %d: exported %s has no doc comment" % (number, symbol)))
    elif symbol not in previous:
        findings.append(("GO003",
                         "line %d: the doc comment above %s does not name it"
                         % (number, symbol)))


def _exported_docs(line, number, previous, group, findings):
    """GO003, including the grouped forms `var (`, `const (` and `type (`.

    Returns whether the next line is still inside a grouped declaration. The
    grouped forms are how Go declares exported sentinel errors and constants,
    and a pattern anchored on the keyword at the start of a line saw none of
    them.
    """
    stripped = line.strip()
    if GROUP_OPEN_RE.match(stripped):
        return True
    if group:
        if stripped == ")":
            return False
        member = GROUP_MEMBER_RE.match(line)
        if member:
            _report_doc(member.group(1), number, previous, findings)
        return True
    match = EXPORTED_METHOD_RE.match(stripped) or EXPORTED_DECL_RE.match(stripped)
    if match:
        _report_doc(match.group(match.lastindex), number, previous, findings)
    return False


def scan_lines(source: str, raw: str, package_main: bool,
               is_test: bool) -> list[tuple[str, str]]:
    """Code is read from the blanked text, comments from the raw text.

    GO003 asks what the line above said, and `blank_literals` has replaced every
    comment with spaces by then: reading the blanked text made every documented
    symbol look undocumented, including the pack's own canonical example.
    """
    findings: list[tuple[str, str]] = []
    state = {"func": None, "named_results": False}
    previous_raw = ""
    group = False
    raw_lines = raw.split("\n")
    for number, line in enumerate(source.split("\n"), start=1):
        func_match = FUNC_RE.search(line)
        # Only a NAMED function changes the enclosing context. `go func() {`
        # used to reset it, so every panic after a closure lost the Must
        # exemption and a blocking rule fired on exempt code.
        if func_match and func_match.group(1):
            state["func"] = func_match.group(1)
            state["named_results"] = has_named_results(line)
        _panic_and_naked_return(line, number, state, package_main, is_test, findings)
        _discarded_errors(line, number, findings)
        if not is_test:
            group = _exported_docs(line, number, previous_raw, group, findings)
        previous_raw = raw_lines[number - 1] if number <= len(raw_lines) else ""
    return findings


def analyze(path: str) -> list[tuple[str, str]]:
    raw = read_source(path)
    if raw is None:
        return []
    source = blank_literals(raw)
    package_main = bool(re.search(r"^\s*package\s+main\b", source, re.M))
    findings = scan_braces(source) + scan_lines(
        source, raw, package_main, path.endswith("_test.go"))
    return drop_ignored(findings, raw)


def main() -> None:
    if len(sys.argv) < 2:
        return
    for rule, message in analyze(sys.argv[1]):
        print("%s|%s" % (rule, message))


if __name__ == "__main__":
    main()
