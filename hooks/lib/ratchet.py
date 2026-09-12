#!/usr/bin/env python3
"""Structural ratchet (ADR-0025): per-file metrics and a one-way baseline.

Usage:
  ratchet.py measure <file>
  ratchet.py check <file> [--baseline FILE]
  ratchet.py update <file> [--baseline FILE]
  ratchet.py init [paths...] [--baseline FILE]

Debt can tighten (metrics improve) but never loosen: `check` exits 1 when a
touched file regresses against its committed high-water mark, and `update`
only ever writes lower values.

`complexity` counts decision points (branch keywords, boolean operators,
ternaries) inside the WORST function span of the file, so extracting a method
lowers the score. Raw indentation is deliberately not part of it: it reflects
the formatter, not the structure.

Zero dependency, single pass, no AST: this runs on every Write/Edit in the AI
loop and in CI from the same code path (zero drift).
"""
import json
import os
import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import lang_registry_read
except ImportError:
    lang_registry_read = None


# Reading a file costs roughly five times its size in memory once split into
# lines. A hostile repository can ship a 1 GB "source" file, and this runs on
# every write: anything past this size is not code worth measuring.
MAX_SOURCE_BYTES = 2 * 1024 * 1024
# The baseline is repo-supplied too, and it is parsed on every write.
MAX_BASELINE_BYTES = 8 * 1024 * 1024
BASELINE_NAME = ".craftsman-baseline.json"
RATCHETED_METRICS = ["complexity", "file_lines", "max_fn_lines", "fan_out", "ignores"]

CONTROL_WORDS = (
    "if|elif|elseif|else|for|foreach|while|switch|case|catch|do|try|return|match"
)

BRANCH_RE = re.compile(
    r"\b(?:if|elif|elseif|for|foreach|while|case|catch|when)\b|&&|\|\||\s\?\s"
)
IMPORT_RE = re.compile(
    r"^\s*(?:use\s+[A-Z][\w\\]+|import\s+.+?from\s+['\"][^'\"]+['\"]|"
    r"import\s+[\w.]+|from\s+[\w.]+\s+import|require\s+['\"][^'\"]+['\"]|"
    r"source\s+\S+)"
)
FN_RE = re.compile(
    r"^\s*(?:public\s+|private\s+|protected\s+|static\s+|async\s+|final\s+|abstract\s+)*"
    r"(?:function\s+\w+|def\s+\w+|const\s+\w+\s*=[^=]*=>|"
    r"(?!(?:" + CONTROL_WORDS + r")\b)\w+\s*\([^)]*\)\s*\{)"
)
IGNORE_RE = re.compile(r"craftsman-ignore:")

# Which comment and string syntax a file uses, by extension.
#
# `structural_metrics.clean()` already blanks literals, but only for the C-like
# family: it reads `#` as nothing and knows no triple quote, so Python would
# come through it with every comment intact. And blanking `#` to end of line in
# TypeScript would eat `this.#private`. So the dialect is chosen by extension,
# and a file whose extension is unknown is measured raw, which is what happened
# to every file before this existed.
_HASH = "hash"
_SLASH = "slash"
_BOTH = "both"

_TRIPLE_DOUBLE = '"' * 3
_TRIPLE_SINGLE = "'" * 3

_LITERAL_DIALECTS = {
    ".py": (_HASH, (_TRIPLE_DOUBLE, _TRIPLE_SINGLE), ("'", '"')),
    ".sh": (_HASH, (), ("'", '"')),
    ".bash": (_HASH, (), ("'", '"')),
    ".rb": (_HASH, (), ("'", '"')),
    ".php": (_BOTH, (), ("'", '"')),
    ".ts": (_SLASH, (), ("'", '"', "`")),
    ".tsx": (_SLASH, (), ("'", '"', "`")),
    ".js": (_SLASH, (), ("'", '"', "`")),
    ".jsx": (_SLASH, (), ("'", '"', "`")),
    ".go": (_SLASH, (), ('"', "`")),
    ".java": (_SLASH, (), ("'", '"')),
    ".rs": (_SLASH, (), ('"',)),
    ".c": (_SLASH, (), ("'", '"')),
    ".h": (_SLASH, (), ("'", '"')),
    ".cpp": (_SLASH, (), ("'", '"')),
}


def _blank_span(text):
    """Same length, same line breaks, no content: offsets and counts survive."""
    return "".join("\n" if char == "\n" else " " for char in text)


def _blank_comment_run(source, cursor, opener, closer):
    """Where a comment starting at `cursor` ends."""
    length = len(source)
    if closer is None:
        end = source.find("\n", cursor)
        return length if end == -1 else end
    end = source.find(closer, cursor + len(opener))
    return length if end == -1 else end + len(closer)


# A run that reaches end of line unterminated stops there. A broken literal
# must not swallow the rest of the file, which is how one stray quote could
# take every metric on it to zero.
def _blank_string_run(source, cursor, quote):
    length = len(source)
    end = cursor + 1
    while end < length:
        if source[end] == "\\":
            end += 2
            continue
        if source[end] == quote:
            return end + 1
        if source[end] == "\n":
            return end
        end += 1
    return length


# Where the literal or comment starting at `cursor` ends, or None for code,
# which is the only case the caller copies through untouched.
def _literal_run(source, cursor, dialect):
    comment_style, triples, quotes = dialect
    char = source[cursor]
    peek = source[cursor + 1] if cursor + 1 < len(source) else ""

    if comment_style in (_SLASH, _BOTH) and char == "/" and peek == "/":
        return _blank_comment_run(source, cursor, "//", None)
    if comment_style in (_SLASH, _BOTH) and char == "/" and peek == "*":
        return _blank_comment_run(source, cursor, "/*", "*/")
    if comment_style in (_HASH, _BOTH) and char == "#":
        return _blank_comment_run(source, cursor, "#", None)
    for triple in triples:
        if source.startswith(triple, cursor):
            return _blank_comment_run(source, cursor, triple, triple)
    if char in quotes:
        return _blank_string_run(source, cursor, char)
    return None


# Comments and string literals blanked, everything else untouched.
#
# The point is not tidiness. `BRANCH_RE` matched `for` anywhere on a line, so
# `logger.info("retrying if the lock is free")` carried two decision points and
# rewording a log message moved a file's complexity. RATCHET001 refuses a file
# whose complexity rose above its mark, so prose could fail a build. The other
# direction is worse: a reworded message could LOWER the number, `update` would
# write that as the new mark, and a real branch added later would fit under a
# budget nobody earned.
#
# Rust keeps its single quotes: `&'a str` is a lifetime, not a string, and
# blanking from it would swallow the rest of the line.
def _blank_literals(source, extension):
    dialect = _LITERAL_DIALECTS.get(extension.lower())
    if dialect is None:
        return source
    out = []
    cursor, length = 0, len(source)
    while cursor < length:
        end = _literal_run(source, cursor, dialect)
        if end is None:
            out.append(source[cursor])
            cursor += 1
            continue
        out.append(_blank_span(source[cursor:end]))
        cursor = end
    return "".join(out)

# Which files are ratcheted is the loaded packs' answer. The literal set this
# replaces named five extensions, so a project whose pack shipped a sixth got
# no regression guard at all while the doctrine advertised one. An empty set is
# the honest answer when no pack is loaded: ratcheting a file nobody claims
# would compare it against a baseline nothing else maintains.
#
# Placed below the regex constants on purpose. complexity is measured per
# function span, a span running from one def to the next, so a function
# inserted above CONTROL_WORDS takes the keyword alternation into its own span
# and scores 13 phantom decision points.
def supported_extensions() -> set:
    if lang_registry_read is None:
        return set()
    return lang_registry_read.known_extensions()


def _indent_of(line: str) -> int:
    return len(line) - len(line.lstrip())


def _body_end(lines, start: int, limit: int) -> int:
    """First line past the function body that opens at `start`.

    Spans used to run from one header to the next, which charged every line
    between them to the earlier function. In a sequential test script that is
    the whole file: run_file_changed in tests/core/test-hooks.sh is 7 lines and
    was measured at 600, and a function inserted above a block of regex
    constants took their keywords into its own complexity. Both numbers then
    look like debt, and refactoring in response to them is refactoring to
    flatter a broken instrument.

    Brace-delimited bodies close on balance. Indentation-delimited ones close
    on the first line indented no deeper than the header. Anything unresolved
    falls back to the old bound, so this can only narrow a span, never widen it.
    """
    header = lines[start]
    depth = header.count("{") - header.count("}")
    if depth > 0:
        return _brace_end(lines, start, limit, depth)
    return _indent_end(lines, start, limit)


def _brace_end(lines, start: int, limit: int, depth: int) -> int:
    for index in range(start + 1, limit):
        depth += lines[index].count("{") - lines[index].count("}")
        if depth <= 0:
            return index + 1
    return limit


def _indent_end(lines, start: int, limit: int) -> int:
    base = _indent_of(lines[start])
    for index in range(start + 1, limit):
        line = lines[index]
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if _indent_of(line) <= base:
            return index
    return limit


def _function_spans(lines) -> list:
    """Half-open [start, end) line ranges, one per function body."""
    starts = [index for index, line in enumerate(lines) if FN_RE.match(line)]
    if not starts:
        return [(0, len(lines))]
    bounds = starts + [len(lines)]
    return [
        (bounds[pos], _body_end(lines, bounds[pos], bounds[pos + 1]))
        for pos in range(len(starts))
    ]


def _decision_points(lines) -> int:
    return sum(len(BRANCH_RE.findall(line)) for line in lines)


def measure(path: Path) -> dict:
    """Structural fingerprint of one file: the five ratcheted metrics.

    Four of the five are measured on the source with comments and string
    literals blanked, so a rename or a reworded message cannot move them.
    `ignores` is measured on the RAW source, because a craftsman-ignore marker
    lives in a comment by definition: blanking it first would count zero, every
    time, on every file, and the ratchet would stop noticing suppressions
    piling up.
    """
    raw = path.read_text(errors="ignore")
    code = _blank_literals(raw, path.suffix)
    lines = code.split("\n")
    spans = _function_spans(lines)
    return {
        "path": str(path),
        "complexity": max(_decision_points(lines[start:end]) for start, end in spans),
        "file_lines": len(lines),
        "max_fn_lines": max(end - start for start, end in spans),
        "fan_out": sum(1 for line in lines if IMPORT_RE.match(line)),
        "ignores": sum(1 for line in raw.split("\n") if IGNORE_RE.search(line)),
    }


_PROJECT_ROOT = None


def set_project_root(path: Path) -> None:
    """Pin the anchor for the rest of this process.

    `--baseline path/to/file` names where the mark lives, so it also names what
    the keys inside it are relative to. Without this, a caller that passed an
    explicit baseline wrote keys against one root and read them back against
    another: `init` recorded `sub/deep/Deep.php`, the check looked up
    `deep/Deep.php`, and the ratchet reported nothing at all.
    """
    global _PROJECT_ROOT
    _PROJECT_ROOT = Path(path).resolve()


def _repository_of(start: Path):
    """The nearest `.git` at or above `start`, or None outside any repository."""
    for candidate in [start] + list(start.parents):
        if (candidate / ".git").exists():
            return candidate
    return None


def _nearest_baseline(start: Path, repository: Path):
    """The closest existing baseline between `start` and the repository root.

    Bounded by the repository on purpose. Searching for the baseline before
    finding the `.git` let a stray `.craftsman-baseline.json` in a workspace
    directory or in $HOME outrank the project: this repository's marks were
    written into another tree's file, keyed against an anchor outside it.
    """
    for candidate in [start] + list(start.parents):
        if (candidate / BASELINE_NAME).is_file():
            return candidate
        if candidate == repository:
            break
    return None


def project_root(start=None) -> Path:
    """The directory the baseline is anchored to.

    Not `Path.cwd()`. A pipeline that runs `cd packages/api && craftsman-ci src`,
    or a hook fired while the shell sat in a subdirectory, looked for the
    baseline in that subdirectory, found none, and reported every recorded
    violation as new: the exact failure this file exists to prevent, silently.

    A pinned anchor answers for everything; otherwise the walk starts where the
    caller says, which is the file's own directory when there is a file. An
    existing baseline wins over the repository root, so a package that marked
    its own state keeps it, and cwd is the last resort for a directory outside
    any repository.
    """
    if _PROJECT_ROOT is not None:
        return _PROJECT_ROOT
    override = os.environ.get("CRAFTSMAN_PROJECT_ROOT")
    if override and Path(override).is_dir():
        return Path(override)
    start = Path(start).resolve() if start is not None else Path.cwd().resolve()
    repository = _repository_of(start)
    if repository is None:
        return start
    return _nearest_baseline(start, repository) or repository


def _baseline_path(args) -> Path:
    if "--baseline" in args:
        explicit = Path(args[args.index("--baseline") + 1])
        set_project_root(explicit.resolve().parent)
        return explicit
    return project_root() / BASELINE_NAME


def _flag_value(args, flag: str) -> str:
    if flag in args:
        position = args.index(flag) + 1
        if position < len(args):
            return args[position]
    return ""


def _flag_operands(args, baseline_file: Path) -> list:
    """Positional arguments, with flag values removed."""
    consumed = set()
    for flag in ("--baseline", "--reason"):
        if flag in args:
            consumed.add(args.index(flag) + 1)
    return [
        arg for position, arg in enumerate(args)
        if not arg.startswith("--")
        and position not in consumed
        and arg != str(baseline_file)
    ]


def _is_measurement(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _is_usable(entry) -> bool:
    """A poisoned metric must never reach the comparison in `check`: a string
    there raises TypeError, the caller reads the resulting exit 1 as a
    regression, and because stdout is empty it prints nothing and skips the
    update branch. The ratchet then no-ops forever on that path, silently.

    A missing metric stays legitimate: older baselines predate later metrics
    and `check` already defaults them to the current value.
    """
    if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
        return False
    return all(_is_measurement(entry[name]) for name in RATCHETED_METRICS if name in entry)


def load_baseline(path: Path) -> dict:
    """Entries keyed by project-relative path, malformed ones dropped one by one.

    Dropping the whole file on a single bad entry is what makes this dangerous
    rather than merely wrong: every touched file then looks new, and the next
    save rewrites the baseline with that one entry, erasing every other
    high-water mark in the repository.

    A symlinked baseline is refused outright, see save_baseline.
    """
    if path.is_symlink() or not path.is_file():
        return {}
    try:
        if path.stat().st_size > MAX_BASELINE_BYTES:
            return {}
        entries = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return {}
    if not isinstance(entries, list):
        return {}
    return {entry["path"]: entry for entry in entries if _is_usable(entry)}


def save_baseline(path: Path, entries: dict) -> None:
    """One JSON object per line, sorted by path: diffs stay readable.

    Written to a sibling temp file and renamed over the target. A cloned
    repository can ship the baseline as a symlink, and `write_text` would
    follow it and overwrite whatever it points at (~/.claude/settings.json,
    .git/hooks/*, any file the developer can write) on the first edit after
    cloning. os.replace acts on the link itself, never on its target.
    """
    rendered = [
        json.dumps(entries[key], separators=(",", ":"), sort_keys=True)
        for key in sorted(entries)
    ]
    if path.is_symlink():
        print(f"ratchet: {path} is a symlink, replacing it with a regular file", file=sys.stderr)
    handle, temp_name = tempfile.mkstemp(dir=str(path.parent or Path(".")), prefix=".ratchet-")
    try:
        with os.fdopen(handle, "w") as stream:
            stream.write("[\n" + ",\n".join(rendered) + "\n]\n")
        os.replace(temp_name, path)
    except OSError:
        Path(temp_name).unlink(missing_ok=True)
        raise


def _relative(path: Path):
    """Project-relative path, or None when the file lives outside the project.

    Outside files are never recorded: an absolute path written into a committed
    baseline leaks local directory structure to everyone who clones the
    repository, and adds entries no teammate can act on.
    """
    try:
        return str(path.resolve().relative_to(project_root()))
    except ValueError:
        return None


def _current_entry(file_path: Path):
    """Measured entry keyed by project-relative path, or None when the file
    lives outside the project. Only the writing paths (check, update, init)
    consult this: `measure` stays a pure read with no project constraint."""
    relative = _relative(file_path)
    if relative is None:
        return None
    entry = measure(file_path)
    entry["path"] = relative
    return entry


# Dependency and build trees are not the project's code. `ci/craftsman-ci.sh`
# prunes exactly these, and the two halves of one baseline file disagreed: a
# `vendor/acme/lib/Junk.php` carried a structural mark and no rule mark, which
# is a row nobody can act on and a diff nobody can read.
_NOT_THE_PROJECT = frozenset(
    {"vendor", "node_modules", ".git", "dist", "build", "var"}
)


def _skipped(file_path: Path) -> bool:
    if _NOT_THE_PROJECT.intersection(file_path.parts):
        return True
    if not file_path.is_file() or file_path.suffix not in supported_extensions():
        return True
    # A size cap alone is not enough: os.path.getsize("/dev/zero") is 0, so a
    # symlink to a character device would sail past it and read forever. Only
    # regular, non-symlinked files are measured.
    if file_path.is_symlink():
        return True
    try:
        stat = file_path.stat()
    except OSError:
        return True
    from stat import S_ISREG
    return not S_ISREG(stat.st_mode) or stat.st_size > MAX_SOURCE_BYTES


def _cmd_measure(args) -> int:
    file_path = Path(args[0])
    if _skipped(file_path):
        return 0
    print(json.dumps(measure(file_path)))
    return 0


def _cmd_check(args) -> int:
    file_path = Path(args[0])
    if _skipped(file_path):
        return 0
    baseline_file = _baseline_path(args)
    entries = load_baseline(baseline_file)
    current = _current_entry(file_path)
    if current is None:
        return 0
    known = entries.get(current["path"])
    if known is None:
        entries[current["path"]] = current
        save_baseline(baseline_file, entries)
        return 0
    regressions = [
        (name, known[name], current[name])
        for name in RATCHETED_METRICS
        if current[name] > known.get(name, current[name])
    ]
    for name, mark, value in regressions:
        print(f"RATCHET001 {name} {mark} -> {value}")
    return 1 if regressions else 0


def _cmd_update(args) -> int:
    file_path = Path(args[0])
    if _skipped(file_path):
        return 0
    baseline_file = _baseline_path(args)
    entries = load_baseline(baseline_file)
    current = _current_entry(file_path)
    if current is None:
        return 0
    known = entries.get(current["path"], current)
    # Start from what the row already said, then tighten. Rebuilding from
    # scratch and copying back the keys this function happens to know about is
    # how `reason` was lost once, and how `rules` was lost the day it was
    # added: a row carries more than this command owns, and the next key added
    # by someone else must not need an edit here to survive.
    tightened = {key: value for key, value in known.items() if key != "path"}
    tightened["path"] = current["path"]
    for name in RATCHETED_METRICS:
        tightened[name] = min(known.get(name, current[name]), current[name])
    entries[current["path"]] = tightened
    save_baseline(baseline_file, entries)
    return 0


def _sources_under(root: str) -> list:
    base = Path(root)
    candidates = [base] if base.is_file() else base.rglob("*")
    return [item for item in candidates if not _skipped(item)]


def _iter_sources(roots):
    for root in roots or ["."]:
        yield from _sources_under(root)


# A scoped init is the only way to loosen a budget, and one loosened without a
# stated reason is how a ratchet becomes a rubber stamp: the entry stores
# numbers only, so a reviewer reading the diff sees a figure go up and nothing
# about why. Refuse rather than record it silently. A whole-tree init is the
# adoption path and the --repair rebuild, not a loosening, so it needs none.
def _refuse_silent_loosening(roots) -> None:
    print(
        f"ratchet: refusing to re-photograph {', '.join(roots)} without "
        "--reason.\n"
        "  A scoped init raises budgets, and the entry records numbers only.\n"
        '  Example: ratchet.py init path/to/file.sh --reason "..."',
        file=sys.stderr,
    )


# A whole-tree photograph replaces the baseline: that is the adoption path and
# the --repair rebuild. Explicit paths re-photograph only what was named and
# keep every other row, because scoping a command must narrow what it writes,
# never widen what it deletes.
def _photograph_into(entries: dict, roots: list, reason: str) -> int:
    """Overwrite the metrics of each row, keep everything else it carried.

    `init` re-measures on purpose: that is what taking a mark means. What it
    must not do is drop the keys it does not measure. `rules`, written by
    rule_baseline.py into the same row, was silently erased by a later `init`,
    and the only symptom was a gate that started refusing inherited debt again
    weeks after someone recorded it.
    """
    written = 0
    for source in _iter_sources(roots):
        entry = _current_entry(source)
        if entry is None:
            continue
        if reason:
            entry["reason"] = reason
        previous = entries.get(entry["path"])
        if isinstance(previous, dict):
            for key, value in previous.items():
                if key not in entry and key != "path":
                    entry[key] = value
        entries[entry["path"]] = entry
        written += 1
    return written


def _cmd_init(args) -> int:
    baseline_file = _baseline_path(args)
    roots = _flag_operands(args, baseline_file)
    reason = _flag_value(args, "--reason").strip()

    # Naming a file re-photographs that one budget, which is the loosening
    # path. Naming a directory photographs a tree, which is adoption or
    # --repair. Only the first needs a stated reason: gating on "any argument"
    # would refuse `init .`, `init src` and `init deep`, the form three test
    # suites already use.
    named_files = [root for root in roots if Path(root).is_file()]
    if named_files and not reason:
        _refuse_silent_loosening(named_files)
        return 2

    entries = {} if not roots else load_baseline(baseline_file)
    written = _photograph_into(entries, roots, reason)
    save_baseline(baseline_file, entries)
    print(f"baseline: {written} files -> {baseline_file} ({len(entries)} rows)")
    return 0


COMMANDS = {
    "measure": _cmd_measure,
    "check": _cmd_check,
    "update": _cmd_update,
    "init": _cmd_init,
}


def main() -> int:
    argv = sys.argv[1:]
    if not argv or argv[0] not in COMMANDS:
        print(__doc__, file=sys.stderr)
        return 2
    command, args = argv[0], argv[1:]
    if command != "init" and not args:
        print(__doc__, file=sys.stderr)
        return 2
    return COMMANDS[command](args)


if __name__ == "__main__":
    sys.exit(main())
