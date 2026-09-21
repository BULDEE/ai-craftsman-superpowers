#!/usr/bin/env python3
"""Tokenize a shell command without treating quoted operators as syntax."""

from __future__ import annotations

import json
import shlex
import sys
from typing import TypedDict


class CommandGrammar(TypedDict):
    segments: list[str]
    separators: list[str]
    last: str
    has_or: bool
    has_pipe: bool


def _tokens(command: str) -> list[str]:
    lexer = shlex.shlex(command.replace("\n", ";"), posix=True, punctuation_chars=";&|")
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


def _segments(tokens: list[str]) -> tuple[list[str], list[str]]:
    segments: list[list[str]] = [[]]
    separators: list[str] = []
    for token in tokens:
        if token in {";", "&&", "||", "|", "&"}:
            separators.append(token)
            segments.append([])
            continue
        segments[-1].append(token)
    rendered = [" ".join(segment) for segment in segments]
    while rendered and not rendered[-1].strip():
        rendered.pop()
    return rendered, separators


def parse(command: str) -> CommandGrammar:
    rendered, separators = _segments(_tokens(command))
    return {
        "segments": rendered,
        "separators": separators,
        "last": rendered[-1] if rendered else "",
        "has_or": "||" in separators,
        "has_pipe": "|" in separators,
    }


def main() -> int:
    try:
        print(json.dumps(parse(sys.stdin.read()), ensure_ascii=False))
    except (ValueError, TypeError):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
