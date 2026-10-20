#!/usr/bin/env python3
"""Name the git hook bypass a shell command performs, if any (CR-258).

Reads one shell command on stdin. Prints one line per bypass found, nothing
when there is none. A command the lexer cannot read prints nothing: the shell
would refuse it too.

A bypass switches the project's own git hooks off: `--no-verify` (and `-n` on
commit), `-c core.hooksPath=...`, `git config core.hooksPath <dir>`, the
skip variables of husky, pre-commit and lefthook, and a `git stash` run in
the same command as a commit, which hides from the hooks what the commit
leaves out.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from command_grammar import token_segments  # noqa: E402

# Short commit options whose value follows: `-nm "msg"` is -n then -m "msg",
# while in `-mn` the n is the message.
_COMMIT_VALUE_SHORT = set("mFCct")
_COMMIT_VALUE_LONG = {
    "--message", "--file", "--author", "--date", "--template", "--reuse-message",
    "--reedit-message", "--fixup", "--squash", "--cleanup", "--trailer",
    "--pathspec-from-file",
}
_GIT_VALUE_GLOBALS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
_SKIP_VARIABLES = {"HUSKY": "0", "HUSKY_SKIP_HOOKS": None, "SKIP": None, "LEFTHOOK": "0"}
_STASH_KEEPS = {"pop", "apply", "list", "show", "drop", "clear", "branch", "create", "store"}
_CONFIG_READS = {"--get", "--get-all", "--get-regexp", "--unset", "--unset-all", "--list", "-l", "get", "unset", "list"}


def _assignments(tokens: list[str]) -> tuple[dict[str, str], list[str]]:
    env: dict[str, str] = {}
    index = 0
    while index < len(tokens) and "=" in tokens[index] and not tokens[index].startswith("-") \
            and tokens[index].split("=", 1)[0].isidentifier():
        name, value = tokens[index].split("=", 1)
        env[name] = value
        index += 1
    return env, tokens[index:]


def _git_call(tokens: list[str]):
    """(global options, subcommand, arguments) of a git call, None otherwise."""
    if not tokens or os.path.basename(tokens[0]) != "git":
        return None
    globals_: list[tuple[str, str]] = []
    index = 1
    while index < len(tokens) and tokens[index].startswith("-"):
        option = tokens[index]
        name, _, attached = option.partition("=")
        if name in _GIT_VALUE_GLOBALS and not attached and index + 1 < len(tokens):
            globals_.append((name, tokens[index + 1]))
            index += 2
            continue
        globals_.append((name, attached))
        index += 1
    if index >= len(tokens):
        return globals_, "", []
    return globals_, tokens[index], tokens[index + 1:]


def _commit_skips_hooks(arguments: list[str]) -> str:
    skip_value = False
    for argument in arguments:
        if skip_value:
            skip_value = False
            continue
        if argument == "--":
            return ""
        if argument == "--no-verify":
            return "--no-verify"
        if argument.startswith("--"):
            skip_value = argument in _COMMIT_VALUE_LONG
            continue
        if not argument.startswith("-") or argument == "-":
            continue
        for position, flag in enumerate(argument[1:], start=1):
            if flag == "n":
                return "-n"
            if flag in _COMMIT_VALUE_SHORT:
                skip_value = position == len(argument) - 1
                break
    return ""


def _sets_hooks_path(arguments: list[str]) -> bool:
    lowered = [argument.lower() for argument in arguments]
    if "core.hookspath" not in lowered or any(argument in _CONFIG_READS for argument in lowered):
        return False
    position = lowered.index("core.hookspath")
    return position + 1 < len(arguments) and not arguments[position + 1].startswith("-")


def _segment_bypasses(env: dict[str, str], call) -> list[str]:
    globals_, subcommand, arguments = call
    found = [
        f"{name}={env[name]}" for name, value in _SKIP_VARIABLES.items()
        if name in env and (value is None or env[name] == value)
    ]
    for name, value in globals_:
        key = value.split("=", 1)[0].lower()
        if name in ("-c", "--config-env") and key == "core.hookspath":
            found.append(f"git {name} core.hooksPath")
    if "--no-verify" in arguments and subcommand != "commit":
        found.append(f"git {subcommand} --no-verify")
    if subcommand == "commit":
        flag = _commit_skips_hooks(arguments)
        if flag:
            found.append(f"git commit {flag}")
    if subcommand == "config" and _sets_hooks_path(arguments):
        found.append("git config core.hooksPath")
    return found


def bypasses(command: str) -> list[str]:
    try:
        segments = token_segments(command)
    except ValueError:
        return []
    found: list[str] = []
    stashes = commits = False
    for tokens in segments:
        env, rest = _assignments(tokens)
        call = _git_call(rest)
        if call is None:
            continue
        found.extend(_segment_bypasses(env, call))
        _, subcommand, arguments = call
        commits = commits or subcommand == "commit"
        stashes = stashes or (subcommand == "stash" and not (arguments and arguments[0] in _STASH_KEEPS))
    if stashes and commits:
        found.append("git stash in the same command as git commit")
    return found


def main() -> int:
    for bypass in bypasses(sys.stdin.read()):
        print(bypass)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
