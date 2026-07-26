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
import re
import sys
from pathlib import Path

SUPPORTED_EXTS = {".php", ".ts", ".tsx", ".py", ".sh"}
# Reading a file costs roughly five times its size in memory once split into
# lines. A hostile repository can ship a 1 GB "source" file, and this runs on
# every write: anything past this size is not code worth measuring.
MAX_SOURCE_BYTES = 2 * 1024 * 1024
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


def _function_spans(lines) -> list:
    """Half-open [start, end) line ranges, one per function-looking header."""
    starts = [index for index, line in enumerate(lines) if FN_RE.match(line)]
    if not starts:
        return [(0, len(lines))]
    bounds = starts + [len(lines)]
    return [(bounds[pos], bounds[pos + 1]) for pos in range(len(starts))]


def _decision_points(lines) -> int:
    return sum(len(BRANCH_RE.findall(line)) for line in lines)


def measure(path: Path) -> dict:
    """Structural fingerprint of one file: the five ratcheted metrics."""
    lines = path.read_text(errors="ignore").split("\n")
    spans = _function_spans(lines)
    return {
        "path": str(path),
        "complexity": max(_decision_points(lines[start:end]) for start, end in spans),
        "file_lines": len(lines),
        "max_fn_lines": max(end - start for start, end in spans),
        "fan_out": sum(1 for line in lines if IMPORT_RE.match(line)),
        "ignores": sum(1 for line in lines if IGNORE_RE.search(line)),
    }


def _baseline_path(args) -> Path:
    if "--baseline" in args:
        return Path(args[args.index("--baseline") + 1])
    return Path(BASELINE_NAME)


def load_baseline(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        entries = json.loads(path.read_text())
        return {entry["path"]: entry for entry in entries}
    except (json.JSONDecodeError, KeyError, TypeError, OSError):
        return {}


def save_baseline(path: Path, entries: dict) -> None:
    """One JSON object per line, sorted by path: diffs stay readable."""
    rendered = [
        json.dumps(entries[key], separators=(",", ":"), sort_keys=True)
        for key in sorted(entries)
    ]
    path.write_text("[\n" + ",\n".join(rendered) + "\n]\n")


def _relative(path: Path):
    """Project-relative path, or None when the file lives outside the project.

    Outside files are never recorded: an absolute path written into a committed
    baseline leaks local directory structure to everyone who clones the
    repository, and adds entries no teammate can act on.
    """
    try:
        return str(path.resolve().relative_to(Path.cwd()))
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


def _skipped(file_path: Path) -> bool:
    if not file_path.is_file() or file_path.suffix not in SUPPORTED_EXTS:
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
    tightened = {"path": current["path"]}
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


def _cmd_init(args) -> int:
    baseline_file = _baseline_path(args)
    roots = [
        arg for arg in args
        if not arg.startswith("--") and arg != str(baseline_file)
    ]
    entries = {}
    for source in _iter_sources(roots):
        entry = _current_entry(source)
        if entry is None:
            continue
        entries[entry["path"]] = entry
    save_baseline(baseline_file, entries)
    print(f"baseline: {len(entries)} files -> {baseline_file}")
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
