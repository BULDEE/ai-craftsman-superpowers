#!/usr/bin/env python3
"""The brace walk every brace-delimited language pack needs, written once (#38).

packs/go/hooks/go_structure.py and packs/rust/hooks/rust_structure.py each
scanned braces on their own, because hooks/lib/structural_metrics.py keys on
the word `function` and on control heads that open with a parenthesis, and
neither language writes either. Measured against each other, 134 of their
lines were identical, whole functions: the scan state, the control-depth
count behind NEST001, the span behind LOC001, the parameter count behind
PARAM001, the ignore filter, the line arithmetic. The next fix to the brace
stack would have been carried by hand three times, and one of the two copies
had already grown a different docstring on the same function.

The engine knows no language, so what carries one stays in the pack: a
profile names the function head, the control heads, an optional container
head (a Rust `impl`), how to split a parameter list, and two hooks for what
only that language measures (a Go `context.Context` out of first position, a
Rust type's impl blocks summed). Adding a third brace-delimited language means
writing a profile, not a scanner.

    profile = Profile(function_re=..., control_re=..., parameter_list=...)
    scan = walk_braces(source, profile)
    findings = drop_ignored(scan.findings, raw)

structural_metrics.py is deliberately not migrated here: its two dialects sit
under the regression tests PHP and TypeScript depend on, and it moves once
this module has proved itself on the two packs that had no such net.
"""

from __future__ import annotations

import re
from typing import Callable, Optional

NEST_MAX = 3
LOC_MAX = 50
PARAM_MAX = 3

# A source past this size is a generated file or a vendored one, and a scan
# that reads it in full costs a hook its latency budget for no finding anyone
# will act on.
MAX_SOURCE_BYTES = 512 * 1024


def line_of(source: str, position: int) -> int:
    return source.count("\n", 0, position) + 1


def read_source(path: str) -> Optional[str]:
    """The file's text, or None when it cannot be read or is too large."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            raw = handle.read(MAX_SOURCE_BYTES + 1)
    except OSError:
        return None
    if len(raw) > MAX_SOURCE_BYTES:
        return None
    return raw


def balanced_group(header: str, start: int) -> str:
    """Text inside the parentheses opening at `start`, or "" when unbalanced.

    Only parentheses count toward the depth. Counting `<` and `>` as well
    looks right until a parameter is `f: impl Fn(u32) -> u32`: the `>` of the
    arrow took the depth to zero without a `)`, the walk gave up, and the
    function was reported as having no parameters at all.
    """
    depth = 0
    for index in range(start, len(header)):
        depth += _paren_delta(header[index])
        if depth == 0 and header[index] == ")":
            return header[start + 1:index]
    return ""


def _paren_delta(char: str) -> int:
    if char == "(":
        return 1
    if char == ")":
        return -1
    return 0


def _angle_delta(inner: str, index: int, depth: int) -> int:
    """How `<` and `>` move the depth, for a language whose generics use them."""
    char = inner[index]
    previous = inner[index - 1] if index else ""
    if char == "<" and (previous.isalnum() or previous == "_"):
        return 1
    if char == ">" and previous != "-" and depth > 0:
        return -1
    return 0


def split_params(inner: str, angle_brackets: bool = False) -> list:
    """The top-level comma-separated parts of a parameter list.

    `angle_brackets` makes `<...>` nest too, for a language whose generics are
    written that way and whose `->` must not close one.
    """
    parts, depth, current = [], 0, ""
    for index, char in enumerate(inner):
        depth += _bracket_delta(inner, index, depth, angle_brackets)
        if char == "," and depth == 0:
            parts.append(current.strip())
            current = ""
            continue
        current += char
    parts.append(current.strip())
    return [part for part in parts if part]


def _bracket_delta(inner: str, index: int, depth: int, angle_brackets: bool) -> int:
    char = inner[index]
    if char in "([{":
        return 1
    if char in ")]}":
        return -1
    if angle_brackets:
        return _angle_delta(inner, index, depth)
    return 0


class Profile:
    """What carries a language: the heads, the parameter split, two hooks.

    function_re    group(1) is the function name, or None for a closure
    control_re     a head that opens a control block
    container_re   a head that opens a container measured as a whole
                   (a Rust impl); group(1) names it. Optional.
    parameter_list header -> list of parameters, the receiver excluded
    on_function    (scan, cursor, header, name) after the shared PARAM001
                   check, for what only this language measures on a head
    on_close       (scan, frame, span) after the shared LOC001 check, for a
                   frame the language accumulates
    function_word  the noun the messages use: "function"
    """

    def __init__(self, function_re: "re.Pattern", control_re: "re.Pattern",
                 parameter_list: Callable[[str], list], **options) -> None:
        self.function_re = function_re
        self.control_re = control_re
        self.parameter_list = parameter_list
        self.container_re = options.get("container_re")
        self.on_function = options.get("on_function")
        self.on_close = options.get("on_close")
        self.function_word = options.get("function_word", "function")
        self.nest_max = options.get("nest_max", NEST_MAX)
        self.loc_max = options.get("loc_max", LOC_MAX)
        self.param_max = options.get("param_max", PARAM_MAX)


class Scan:
    """Mutable state of one pass over a file, kept out of the argument lists.

    `state` is the pack's own scratch space, for what it accumulates across
    frames and judges at the end.
    """

    def __init__(self, source: str, profile: Profile) -> None:
        self.source = source
        self.profile = profile
        self.findings: list = []
        self.stack: list = []
        self.control_depth = 0
        self.seen_nest: set = set()
        self.state: dict = {}

    def report(self, rule: str, message: str) -> None:
        self.findings.append((rule, message))

    def line(self, position: int) -> int:
        return line_of(self.source, position)


def _open_function(scan: Scan, cursor: int, header: str, name: Optional[str]) -> None:
    profile = scan.profile
    params = profile.parameter_list(header)
    if len(params) > profile.param_max:
        scan.report("PARAM001",
                    "line %d: %s() has %d parameters (max %d): pass a struct"
                    % (scan.line(cursor), name or "closure", len(params), profile.param_max))
    if profile.on_function:
        profile.on_function(scan, cursor, header, name)


def _open_control(scan: Scan, cursor: int) -> None:
    scan.control_depth += 1
    if scan.control_depth < scan.profile.nest_max:
        return
    line_number = scan.line(cursor)
    if line_number in scan.seen_nest:
        return
    scan.seen_nest.add(line_number)
    scan.report("NEST001",
                "line %d: control flow nested %d levels deep: extract a %s "
                "or return early" % (line_number, scan.control_depth, scan.profile.function_word))


def _classify(profile: Profile, header: str) -> tuple:
    function_match = profile.function_re.search(header)
    if function_match:
        return "function", function_match.group(1)
    container_match = profile.container_re.search(header) if profile.container_re else None
    if container_match:
        return "container", container_match.group(1)
    if profile.control_re.search(header):
        return "control", None
    return "other", None


def _open_brace(scan: Scan, cursor: int, header: str) -> None:
    kind, name = _classify(scan.profile, header)
    if kind == "function":
        _open_function(scan, cursor, header, name)
    elif kind == "control":
        _open_control(scan, cursor)
    scan.stack.append({"kind": kind, "open": cursor, "name": name})


def _close_brace(scan: Scan, cursor: int) -> None:
    if not scan.stack:
        return
    frame = scan.stack.pop()
    span = scan.line(cursor) - scan.line(frame["open"])
    profile = scan.profile
    if frame["kind"] == "control":
        scan.control_depth = max(0, scan.control_depth - 1)
    elif frame["kind"] == "function" and span > profile.loc_max:
        scan.report("LOC001",
                    "line %d: %s() body is %d lines (max %d): extract a %s"
                    % (scan.line(frame["open"]), frame["name"] or "closure",
                       span, profile.loc_max, profile.function_word))
    if profile.on_close:
        profile.on_close(scan, frame, span)


def walk_braces(source: str, profile: Profile) -> Scan:
    """Walk the braces. Only `{` and `}` bound a header.

    `;` bounds one in the shared PHP and TypeScript extractor. In Go that hides
    the language's most common control statement: in `if err := check(); err
    != nil {` the keyword sits before the semicolon, so the header seen was
    ` err != nil ` and NEST001 never fired on idiomatic error handling. Rust's
    `if let Some(x) = f() {` and `while let` hide the same way.
    """
    scan = Scan(source, profile)
    header_start = 0
    for cursor, char in enumerate(source):
        if char not in "{}":
            continue
        _step(scan, cursor, char, source[header_start:cursor])
        header_start = cursor + 1
    return scan


def _step(scan: Scan, cursor: int, char: str, header: str) -> None:
    if char == "{":
        _open_brace(scan, cursor, header)
        return
    _close_brace(scan, cursor)


def drop_ignored(findings: list, raw: str, also_exempt: Optional[Callable] = None) -> list:
    """Remove any finding whose own line carries `craftsman-ignore: <RULE>`.

    The bash validators call line_has_ignore per rule; a scanner that reports
    line numbers can do it once, at the end, for every rule it emits.
    `also_exempt(rule, lines, index)` lets a language honour its own syntax
    too, a `#[allow(clippy::...)]` above the item for instance.
    """
    lines = raw.split("\n")
    return [(rule, message) for rule, message in findings
            if not _exempt(rule, message, lines, also_exempt)]


def _exempt(rule: str, message: str, lines: list, also_exempt: Optional[Callable]) -> bool:
    match = re.match(r"line (\d+):", message)
    index = int(match.group(1)) - 1 if match else -1
    if not 0 <= index < len(lines):
        return False
    if ("craftsman-ignore: %s" % rule) in lines[index]:
        return True
    return bool(also_exempt and also_exempt(rule, lines, index))
