#!/usr/bin/env python3
"""The `terminal` half of the Hermes write gate: a push waits for the conclusion.

Between two conclusions an agent can `git commit` and `git push` through the
`terminal` tool, which no craftsman hook saw: a violation the conclusion gate
would have refused was already on the remote. This reads the terminal command
off the pre_tool_call wire, and when it is a push (or a commit, under strict)
compares the tree it would publish with the tree the conclusion gate last
judged. A pass on one tree does not authorise pushing another, and no verdict
is not a clean verdict (ADR-0029).

Usage:
    terminal_gate.py inspect            stdin: the pre_tool_call payload
                                        stdout: "<push|commit|none> <workspace>"
    terminal_gate.py judge <workspace> <push|commit> <strictness>
                                        exit 0: allowed; exit 2: refused, reason on stdout

The verdict file is written by pre-verify.sh (see record_verdict) into the
repository's own git directory: `<git-dir>/craftsman-verdict`, one line,
"<pass|fail> <tree> <session> <utc timestamp>".
"""
from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
import tempfile

VERDICT_NAME = "craftsman-verdict"
GATED_VERBS = ("push", "commit")
SEGMENT_TOKENS = ("&&", "||", ";", "|", "\n")


def _git(workspace: str, *args: str, env: dict | None = None) -> str:
    proc = subprocess.run(
        ["git", "-C", workspace, *args],
        capture_output=True, text=True, check=False, timeout=15, env=env,
    )
    return proc.stdout.strip() if proc.returncode == 0 else ""


def _segments(command: str) -> list[list[str]]:
    """The command split on shell operators, each segment tokenised."""
    try:
        tokens = shlex.split(command, posix=True)
    except ValueError:
        tokens = command.split()
    segments: list[list[str]] = [[]]
    for token in tokens:
        if token in SEGMENT_TOKENS or token.endswith(";"):
            if token.endswith(";") and token not in SEGMENT_TOKENS:
                segments[-1].append(token[:-1])
            segments.append([])
            continue
        segments[-1].append(token)
    return [segment for segment in segments if segment]


def _git_verb(segment: list[str]) -> tuple[str, str]:
    """(subcommand, -C directory) of a `git ...` segment, ("", "") otherwise."""
    if not segment or os.path.basename(segment[0]) != "git":
        return "", ""
    directory = ""
    index = 1
    while index < len(segment):
        token = segment[index]
        if token == "-C" and index + 1 < len(segment):
            directory = segment[index + 1]
            index += 2
        elif token in ("-c", "--git-dir", "--work-tree", "--namespace") and index + 1 < len(segment):
            index += 2
        elif token.startswith("-"):
            index += 1
        else:
            return token, directory
    return "", directory


def _workspace_of(payload: dict, segments: list[list[str]], gated_index: int, git_dir_flag: str) -> str:
    """Where the gated git command runs: -C, else the last `cd`, else the wire's cwd."""
    if git_dir_flag:
        return git_dir_flag
    cwd = str(payload.get("cwd") or "")
    for segment in segments[:gated_index]:
        if segment[0] == "cd" and len(segment) > 1:
            cwd = os.path.join(cwd, segment[1]) if cwd else segment[1]
    return cwd


def inspect(payload: dict) -> str:
    """"<push|commit|none> <workspace>" for a terminal call."""
    arguments = payload.get("tool_input")
    if not isinstance(arguments, dict):
        arguments = payload.get("args")
    command = str((arguments or {}).get("command") or "")
    segments = _segments(command)
    for index, segment in enumerate(segments):
        verb, directory = _git_verb(segment)
        if verb in GATED_VERBS:
            return "%s %s" % (verb, _workspace_of(payload, segments, index, directory))
    return "none "


def worktree_tree(workspace: str) -> str:
    """The tree id of the working copy as a commit of everything would record it."""
    with tempfile.NamedTemporaryFile(prefix="craftsman-index.", delete=False) as handle:
        index_path = handle.name
    env = dict(os.environ, GIT_INDEX_FILE=index_path)
    try:
        if _git(workspace, "rev-parse", "--verify", "HEAD"):
            _git(workspace, "read-tree", "HEAD", env=env)
        _git(workspace, "add", "-A", env=env)
        return _git(workspace, "write-tree", env=env)
    finally:
        try:
            os.unlink(index_path)
        except OSError:
            pass


def verdict_path(workspace: str) -> str:
    git_dir = _git(workspace, "rev-parse", "--git-dir")
    if not git_dir:
        return ""
    if not os.path.isabs(git_dir):
        git_dir = os.path.join(workspace, git_dir)
    return os.path.join(git_dir, VERDICT_NAME)


def record_verdict(workspace: str, verdict: str, session: str) -> None:
    """Called by pre-verify.sh through `record`: one line, replaced on every conclusion."""
    path = verdict_path(workspace)
    if not path:
        return
    stamp = subprocess.run(["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"], capture_output=True, text=True).stdout.strip()
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("%s %s %s %s\n" % (verdict, worktree_tree(workspace), session, stamp))


def read_verdict(workspace: str) -> tuple[str, str]:
    """(verdict, tree) last recorded, ("", "") when the conclusion never ran here."""
    path = verdict_path(workspace)
    try:
        fields = open(path, encoding="utf-8").read().split()
    except (OSError, TypeError):
        return "", ""
    return (fields[0], fields[1]) if len(fields) >= 2 else ("", "")


def _published_tree(workspace: str, verb: str) -> str:
    if verb == "push":
        return _git(workspace, "rev-parse", "HEAD^{tree}")
    return worktree_tree(workspace)


def judge(workspace: str, verb: str, strictness: str) -> int:
    """Exit 0 to allow, 2 to refuse with the reason on stdout."""
    if verb == "commit" and strictness != "strict":
        return 0
    if not _git(workspace, "rev-parse", "--git-dir"):
        print("craftsman refused `git %s`: %s is not inside a git repository this gate can read. "
              "Run it with `git -C <repository> %s` so the conclusion gate's verdict can be found." % (verb, workspace or "the working directory", verb))
        return 2
    verdict, judged = read_verdict(workspace)
    if verdict != "pass":
        state = "refused the last turn" if verdict == "fail" else "has not judged this work yet"
        print("craftsman refused `git %s`: the conclusion gate %s. Finish the turn so the gate "
              "runs (it judges what would be published), fix what it reports, then %s." % (verb, state, verb))
        return 2
    if judged != _published_tree(workspace, verb):
        print("craftsman refused `git %s`: the conclusion gate passed a different tree than the one this "
              "would publish. Conclude again so the gate judges the current work, then %s." % (verb, verb))
        return 2
    return 0


def main(argv: list[str]) -> int:
    if len(argv) >= 1 and argv[0] == "inspect":
        try:
            payload = json.load(sys.stdin)
        except (ValueError, TypeError):
            payload = {}
        print(inspect(payload if isinstance(payload, dict) else {}))
        return 0
    if len(argv) >= 4 and argv[0] == "judge":
        return judge(argv[1], argv[2], argv[3])
    if len(argv) >= 4 and argv[0] == "record":
        record_verdict(argv[1], argv[2], argv[3])
        return 0
    sys.stderr.write(__doc__ or "")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
