#!/usr/bin/env python3
"""AST checks for the Python pack, kept out of the shell validator.

Embedding these passes as heredocs inside python-validator.sh grew the file
past its structural budget and put the logic beyond the reach of ruff and of
the test suite. Here they are lintable, testable and callable from one line of
shell.

Usage: python_ast_checks.py <check> <file>
where <check> is one of: py006, py007
"""
from __future__ import annotations

import ast
import sys


def _parse(path: str) -> ast.Module | None:
    try:
        with open(path, encoding="utf-8") as handle:
            return ast.parse(handle.read())
    except (OSError, SyntaxError, UnicodeDecodeError):
        return None


def _handler_body(node: ast.ExceptHandler) -> list[ast.stmt]:
    body = node.body
    first = body[0] if body else None
    is_docstring = (
        isinstance(first, ast.Expr)
        and isinstance(first.value, ast.Constant)
        and isinstance(first.value.value, str)
    )
    return body[1:] if is_docstring else body


def check_py006(tree: ast.Module) -> list[str]:
    """An `except Exception` whose body only passes swallows the failure."""
    messages = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.ExceptHandler):
            continue
        if not (isinstance(node.type, ast.Name) and node.type.id == "Exception"):
            continue
        body = _handler_body(node)
        if len(body) == 1 and isinstance(body[0], ast.Pass):
            messages.append(
                f"line {node.lineno}: except Exception with an empty body - "
                "either handle it or let it propagate"
            )
    return messages


def check_py007(tree: ast.Module) -> list[str]:
    """A bare call at module level runs on import, before any caller decides to."""
    return [
        f"line {node.lineno}: module-level side effect on import - "
        'wrap in a function or an if __name__ == "__main__" guard'
        for node in tree.body
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Call)
    ]


CHECKS = {"py006": check_py006, "py007": check_py007}


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] not in CHECKS:
        print(f"usage: {argv[0]} <{'|'.join(CHECKS)}> <file>", file=sys.stderr)
        return 2
    tree = _parse(argv[2])
    if tree is None:
        return 0
    for message in CHECKS[argv[1]](tree):
        print(message)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
