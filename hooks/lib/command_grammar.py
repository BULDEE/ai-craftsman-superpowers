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
    background: bool


# `<` and `>` are punctuation so a redirection lexes as one operator token
# (`2>&1` is `2`, `>&`, `1`; `&>` stays `&>`) instead of leaking its `&` as a
# separator. Only the tokens below end a command.
_SEPARATORS = {";", "&&", "||", "|", "|&", "&"}
_PIPES = {"|", "|&"}


def _tokens(command: str) -> list[str]:
    lexer = shlex.shlex(command.replace("\n", ";"), posix=True, punctuation_chars=";&|<>")
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


def _segments(tokens: list[str]) -> tuple[list[str], list[str]]:
    segments: list[list[str]] = [[]]
    separators: list[str] = []
    for token in tokens:
        if token in _SEPARATORS:
            separators.append(token)
            segments.append([])
            continue
        segments[-1].append(token)
    rendered = [" ".join(segment) for segment in segments]
    while rendered and not rendered[-1].strip():
        rendered.pop()
    return rendered, separators


def parse(command: str) -> CommandGrammar:
    tokens = _tokens(command)
    rendered, separators = _segments(tokens)
    return {
        "segments": rendered,
        "separators": separators,
        "last": rendered[-1] if rendered else "",
        "has_or": "||" in separators,
        "has_pipe": any(separator in _PIPES for separator in separators),
        "background": bool(tokens) and tokens[-1] == "&",
    }


def main() -> int:
    try:
        print(json.dumps(parse(sys.stdin.read()), ensure_ascii=False))
    except (ValueError, TypeError):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
