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
                                        stdout: "<push|commit|unknown|none> <workspace>"
    terminal_gate.py judge <workspace> <push|commit|unknown> <strictness>
                                        stdin (optional): the same payload, so a
                                        push is judged on the refs it publishes
                                        exit 0: allowed; exit 2: refused, reason on stdout

The verdict file is written by pre-verify.sh (see record_verdict) into the
repository's own git directory: `<git-dir>/craftsman-verdict`, one line,
"<pass|fail> <tree> <session> <utc timestamp>".
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile

VERDICT_NAME = "craftsman-verdict"
PUSH_VALUED = {"--repo", "--receive-pack", "--exec", "-o", "--push-option"}
UNENUMERABLE = ("--all", "--mirror", "--tags", "--branches")
UNKNOWN_FORM = ("craftsman refused this terminal command: it runs git push or commit in a form this gate "
                "cannot place (a shell string, an alias that runs a shell, or git named as data). "
                "Run the git command directly so the conclusion gate's verdict can be checked.")


def _git_command():
    """The sibling module that reads a command the way a shell runs it.

    Loaded by path on first use: Hermes runs this file as a script from its
    own working directory, and the tests load it by path too.
    """
    import importlib.util

    location = os.path.join(os.path.dirname(os.path.abspath(__file__)), "git_command.py")
    spec = importlib.util.spec_from_file_location("craftsman_git_command", location)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _git(workspace: str, *args: str, env: dict | None = None) -> str:
    proc = subprocess.run(
        ["git", "-C", workspace, *args],
        capture_output=True, text=True, check=False, timeout=15, env=env,
    )
    return proc.stdout.strip() if proc.returncode == 0 else ""


def _command(payload: dict) -> str:
    arguments = payload.get("tool_input")
    if not isinstance(arguments, dict):
        arguments = payload.get("args")
    return str((arguments or {}).get("command") or "")


def _gated_call(payload: dict) -> dict:
    """The first gated git call of a terminal command, {} when there is none."""
    found = _git_command().calls(_command(payload), str(payload.get("cwd") or ""))
    return found[0] if found else {}


def inspect(payload: dict) -> str:
    """"<push|commit|unknown|none> <workspace>" for a terminal call."""
    call = _gated_call(payload)
    return "%s %s" % (call["verb"], call["workspace"]) if call else "none "


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


def _positionals(args: list[str]) -> list[str]:
    positionals, index = [], 0
    while index < len(args):
        token = args[index]
        if token in PUSH_VALUED:
            index += 2
            continue
        if not token.startswith("-"):
            positionals.append(token)
        index += 1
    return positionals


def _refspecs(args: list[str]) -> list[str]:
    """The refspecs after the repository argument."""
    return _positionals(args)[1:]


def _unqualified_push(workspace: str, args: list[str]) -> str:
    """Why a push cannot be judged on the refs it names, "" when it can.

    After a pass on HEAD, `git push origin unsafe` published another branch's
    tree (review of main eb54d13, B7): what is published is the refspec's
    source, and a form whose sources this gate cannot list is refused.
    """
    if any(flag in args for flag in UNENUMERABLE):
        return "it publishes refs this gate cannot enumerate (--all, --mirror or --tags); push them one at a time"
    refspecs = _refspecs(args)
    if any("*" in spec for spec in refspecs):
        return "a glob refspec publishes refs this gate cannot enumerate; name each branch"
    if refspecs:
        return ""
    if _git(workspace, "config", "--get", "push.default") == "matching":
        return "push.default=matching publishes every matching branch; name the branch"
    remote = (_positionals(args) or ["origin"])[0]
    if _git(workspace, "config", "--get-all", "remote.%s.push" % remote):
        return "remote.%s.push decides what is published; name the refspec" % remote
    return ""


def _published_sources(args: list[str]) -> list[str]:
    """The source of every ref the push publishes: HEAD when none is named.

    A deletion (`:branch`, `--delete`) publishes no content, so it has no source.
    """
    if "-d" in args or "--delete" in args:
        return []
    refspecs = _refspecs(args)
    if not refspecs:
        return ["HEAD"]
    sources = [spec.lstrip("+").split(":", 1)[0] for spec in refspecs]
    return [source for source in sources if source]


def _tree_mismatch(request: dict, judged: str) -> str:
    """The first published source whose tree is not the judged one, "" when all match."""
    workspace = request["workspace"]
    if request["verb"] == "commit":
        return "" if worktree_tree(workspace) == judged else "the working tree"
    for source in _published_sources(request["args"]):
        if _git(workspace, "rev-parse", "--verify", "--quiet", source + "^{tree}") != judged:
            return source
    return ""


def _publication_refusal(request: dict, judged: str) -> str:
    verb = request["verb"]
    why = _unqualified_push(request["workspace"], request["args"]) if verb == "push" else ""
    if why:
        return "craftsman refused `git push`: %s." % why
    mismatch = _tree_mismatch(request, judged)
    if mismatch:
        return ("craftsman refused `git %s`: the conclusion gate passed a different tree than the one %s "
                "would publish. Conclude again on that work, then %s." % (verb, mismatch, verb))
    return ""


def _refusal(request: dict) -> str:
    """The reason to refuse the call, "" to allow it."""
    verb, workspace = request["verb"], request["workspace"]
    if verb == "unknown":
        return UNKNOWN_FORM
    if not _git(workspace, "rev-parse", "--git-dir"):
        return ("craftsman refused `git %s`: %s is not inside a git repository this gate can read. "
                "Run it with `git -C <repository> %s` so the conclusion gate's verdict can be found."
                % (verb, workspace or "the working directory", verb))
    verdict, judged = read_verdict(workspace)
    if verdict != "pass":
        state = "refused the last turn" if verdict == "fail" else "has not judged this work yet"
        return ("craftsman refused `git %s`: the conclusion gate %s. Finish the turn so the gate "
                "runs (it judges what would be published), fix what it reports, then %s." % (verb, state, verb))
    return _publication_refusal(request, judged)


def judge(request: dict) -> int:
    """Exit 0 to allow, 2 to refuse with the reason on stdout.

    request: {"workspace", "verb", "strictness", "args"}.
    """
    if request["verb"] == "commit" and request["strictness"] != "strict":
        return 0
    reason = _refusal(request)
    if not reason:
        return 0
    print(reason)
    return 2


def _read_payload(text: str) -> dict:
    try:
        payload = json.loads(text)
    except (ValueError, TypeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def main(argv: list[str]) -> int:
    if len(argv) >= 1 and argv[0] == "inspect":
        print(inspect(_read_payload(sys.stdin.read())))
        return 0
    if len(argv) >= 4 and argv[0] == "judge":
        payload = {} if sys.stdin.isatty() else _read_payload(sys.stdin.read())
        args = _gated_call(payload).get("args", []) if payload else []
        return judge({"workspace": argv[1], "verb": argv[2], "strictness": argv[3], "args": args})
    if len(argv) >= 4 and argv[0] == "record":
        record_verdict(argv[1], argv[2], argv[3])
        return 0
    sys.stderr.write(__doc__ or "")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
