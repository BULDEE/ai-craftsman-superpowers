#!/usr/bin/env python3
"""Which git calls a terminal command makes, as the shell would run them.

The terminal gate used to split a command on spaced operators and look at the
first word of each piece. `echo ok;git push` and `env git push` went through
with exit 0 while `git push` was refused (review of main eb54d13, B6). This
reads the command the way a shell does: operators are punctuation even when
glued to a word, leading assignments and wrappers are stripped, and the text a
shell would run again (`sh -c`, `eval`, `$(...)`) is read as a command too.

What cannot be qualified is not let through: a git push or commit that this
reader can see but not place (`echo git push`, an alias that runs a shell) is
reported as `unknown`, and the gate refuses it.
"""
from __future__ import annotations

import os
import re
import shlex
import subprocess

GATED = ("push", "commit")
SEPARATORS = {";", "&&", "||", "|", "|&", "&"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "fish"}
# A wrapper runs the command that follows it. Options that take a value are
# listed so the value is not read as the command.
WRAPPERS = {
    "env": {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"},
    "command": set(), "builtin": set(), "exec": {"-a"}, "nohup": set(),
    "time": {"-f", "-o"}, "nice": {"-n"}, "ionice": {"-c", "-n", "-p"},
    "stdbuf": {"-i", "-o", "-e"}, "setsid": set(), "caffeinate": set(),
    "sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U"},
    "doas": {"-u", "-C"}, "timeout": {"-s", "-k", "--signal", "--kill-after"},
    "xargs": {"-I", "-n", "-P", "-L", "-s", "-d", "-E", "-a"},
}
# Wrappers whose first positional argument is not the command.
POSITIONAL = {"timeout": 1}
# Git subcommands that are not aliases: no config lookup for these.
BUILTINS = {"status", "log", "diff", "show", "add", "fetch", "pull", "branch", "checkout",
            "switch", "restore", "stash", "tag", "remote", "config", "rev-parse", "reset",
            "merge", "rebase", "clone", "init", "grep", "blame", "ls-files", "describe"}
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
SUBSTITUTION = re.compile(r"\$\(([^()]*)\)|`([^`]*)`")
MAX_DEPTH = 4


def _tokens(command: str) -> list[str]:
    lexer = shlex.shlex(command.replace("\n", ";"), posix=True, punctuation_chars=";&|<>")
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


def _segments(command: str) -> list[list[str]]:
    segments: list[list[str]] = [[]]
    for token in _tokens(command):
        if token in SEPARATORS:
            segments.append([])
            continue
        segments[-1].append(token)
    return [segment for segment in segments if segment]


def _strip_wrappers(segment: list[str]) -> list[str]:
    """The command a segment runs once assignments and wrappers are removed."""
    index = 0
    while index < len(segment):
        word = os.path.basename(segment[index])
        if ASSIGNMENT.match(segment[index]):
            index += 1
            continue
        if word not in WRAPPERS:
            return segment[index:]
        index = _after_wrapper(segment, index + 1, word)
    return []


def _after_wrapper(segment: list[str], index: int, word: str) -> int:
    """Index of the command a wrapper runs, past its options and positionals."""
    valued, positional = WRAPPERS[word], POSITIONAL.get(word, 0)
    while index < len(segment):
        token = segment[index]
        if token in valued:
            index += 2
            continue
        if token.startswith("-") or ASSIGNMENT.match(token):
            index += 1
            continue
        if not positional:
            return index
        positional -= 1
        index += 1
    return index


GIT_VALUED = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}


def _git_head(argv: list[str]) -> tuple[str, str, list[str]]:
    """(subcommand, -C directory, arguments after it) of a `git ...` argv.

    An inline `-c alias.x=...` defines what the subcommand means for this call
    only, which no config lookup can see: unknown.
    """
    directory, index = "", 1
    while index < len(argv):
        token = argv[index]
        if not token.startswith("-"):
            return token, directory, argv[index + 1:]
        value = argv[index + 1] if index + 1 < len(argv) else ""
        if token == "-c" and value.startswith("alias."):
            return "unknown", directory, []
        if token == "-C":
            directory = value
        index += 2 if token in GIT_VALUED else 1
    return "", directory, []


def _alias(workspace: str, verb: str) -> str:
    """What `git <verb>` really runs when <verb> is an alias, "" when it is not one."""
    if verb in BUILTINS or verb in GATED:
        return ""
    proc = subprocess.run(["git", "-C", workspace or ".", "config", "--get", "alias." + verb],
                          capture_output=True, text=True, check=False, timeout=10)
    return proc.stdout.strip() if proc.returncode == 0 else ""


def _resolve(verb: str, args: list[str], workspace: str) -> tuple[str, list[str]]:
    expansion = _alias(workspace, verb)
    if not expansion:
        return verb, args
    if expansion.startswith("!"):
        body = expansion[1:]
        return ("unknown", []) if any(word in body for word in GATED) else ("", [])
    words = expansion.split()
    return words[0], words[1:] + args


def _nested(argv: list[str]) -> str:
    """The text a shell would run again: `sh -c TEXT`, `eval WORDS`."""
    head = os.path.basename(argv[0])
    if head == "eval":
        return " ".join(argv[1:])
    if head in SHELLS and "-c" in argv[1:]:
        position = argv.index("-c")
        return argv[position + 1] if position + 1 < len(argv) else ""
    return ""


def _mentions_gated(argv: list[str]) -> bool:
    words = [os.path.basename(token) for token in argv]
    return "git" in words and any(verb in words for verb in GATED)


def calls(command: str, cwd: str, depth: int = 0) -> list[dict]:
    """Every gated git call the command makes: {"verb", "workspace", "args"}.

    verb is push, commit or unknown (a gated call this reader cannot place).
    """
    if depth > MAX_DEPTH:
        return [{"verb": "unknown", "workspace": cwd, "args": []}]
    found: list[dict] = []
    for match in SUBSTITUTION.finditer(command):
        found += calls(match.group(1) or match.group(2) or "", cwd, depth + 1)
    workspace = cwd
    for segment in _segments(SUBSTITUTION.sub(" ", command)):
        argv = _strip_wrappers(segment)
        if not argv:
            continue
        if os.path.basename(argv[0]) == "cd" and len(argv) > 1:
            workspace = os.path.join(workspace, argv[1]) if workspace else argv[1]
            continue
        found += _segment_calls(argv, workspace, depth)
    return found


def _segment_calls(argv: list[str], workspace: str, depth: int) -> list[dict]:
    nested = _nested(argv)
    if nested:
        return calls(nested, workspace, depth + 1)
    if os.path.basename(argv[0]) != "git":
        if _mentions_gated(argv):
            return [{"verb": "unknown", "workspace": workspace, "args": []}]
        return []
    verb, directory, args = _git_head(argv)
    where = directory if os.path.isabs(directory) else os.path.join(workspace, directory) if directory else workspace
    verb, args = _resolve(verb, args, where)
    if verb in GATED or verb == "unknown":
        return [{"verb": verb, "workspace": where, "args": args}]
    return []
