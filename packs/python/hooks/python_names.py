#!/usr/bin/env python3
"""PY001: report one and two character names bound by an assignment or a loop.

Usage: python_names.py <file>

Tokenised rather than grepped. The regex this replaces read raw lines, so the
second line of a docstring beginning with an English article matched
`^\\s+[a-z]{1,2}\\s`, and the rule blocked writes on prose. Documentation is
exactly what the doctrine asks people to write, so a rule that taxes it is
worse than no rule. tokenize knows a string from a name, and needs no
exception list to do it.
"""
import io
import keyword
import sys
import token as token_types
import tokenize
from pathlib import Path

ALLOWED = {
    "i", "j", "k", "n", "x", "y", "z", "f", "e", "ok", "id", "db", "fd",
    "df", "ax", "fp", "kv", "ns", "op", "pk", "rc", "sh", "ts", "tz", "up",
    "_",
}


def _binds_a_name(previous, current, following) -> bool:
    """A NAME is bound when an assignment follows it, or when a `for` precedes
    it. Comparison and keyword arguments bind nothing."""
    if current.type != token_types.NAME or keyword.iskeyword(current.string):
        return False
    if previous is not None and previous.string == "for":
        return True
    return following is not None and following.type == token_types.OP and following.string in ("=", ":=")


def short_names(source: str):
    stream = list(tokenize.generate_tokens(io.StringIO(source).readline))
    for index, current in enumerate(stream):
        previous = stream[index - 1] if index else None
        following = stream[index + 1] if index + 1 < len(stream) else None
        if not _binds_a_name(previous, current, following):
            continue
        if len(current.string) <= 2 and current.string not in ALLOWED:
            yield current.start[0], current.string


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: python_names.py <file>", file=sys.stderr)
        return 1
    try:
        source = Path(sys.argv[1]).read_text(errors="ignore")
        findings = list(short_names(source))
    except (OSError, tokenize.TokenError, IndentationError, SyntaxError):
        # An unparseable file is not a clean one, but it is not this rule's
        # finding either. Stay silent rather than guess from raw text, which
        # is the mistake that produced the docstring false positives.
        return 0
    for line_number, name in findings:
        print(f"line {line_number}: name '{name}' is one or two characters - use a descriptive name")
    return 0


if __name__ == "__main__":
    sys.exit(main())
