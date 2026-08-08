#!/usr/bin/env python3
"""Codemap generator (ADR-0022): compact structural map of a repository.

Usage: codemap.py <repo_root>

Prints a markdown map (directories, file counts by language, entry points,
test location). Callers handle caching; this script only observes.
"""
import os
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import lang_registry_read
except ImportError:
    lang_registry_read = None

SKIP_DIRS = {".git", "node_modules", "vendor", "dist", "build", ".idea",
             ".vscode", "__pycache__", ".ruff_cache", "coverage", ".next"}
CODE_EXTS = {".php", ".ts", ".tsx", ".js", ".py", ".sh", ".go", ".rs", ".java", ".md", ".yml", ".yaml", ".json"}
# Project markers come from the loaded packs, plus Make, which belongs to no
# language. A literal table here meant a project whose pack declared its own
# marker was reported as having no recognisable entry point.
def _entry_markers() -> dict:
    markers = {"Makefile": "Make"}
    if lang_registry_read is None:
        return markers
    for marker, language in lang_registry_read.entry_markers().items():
        markers.setdefault(marker, "%s (%s)" % (language, marker))
    return markers
MAX_DIRS = 20


def _scan(root: Path) -> tuple[Counter, Counter]:
    by_dir: Counter = Counter()
    by_ext: Counter = Counter()
    for path in root.rglob("*"):
        rel = path.relative_to(root)
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        if path.is_symlink():
            continue
        if path.is_file() and path.suffix in CODE_EXTS:
            by_ext[path.suffix] += 1
            if len(rel.parts) >= 3:
                group = "/".join(rel.parts[:2])
            elif len(rel.parts) == 2:
                group = rel.parts[0]
            else:
                group = "."
            by_dir[group] += 1
    return by_dir, by_ext


def _safe_label(text: str, max_len: int = 60) -> str:
    """Render an attacker-controlled directory name as one inert line.

    This output is spliced into a skill's own context by dynamic-context
    substitution, not returned as a tool result, so a name carrying newlines
    could forge headings or instructions that read as the skill's own text.
    Newlines are escaped and the label is length-capped.
    """
    flattened = text.replace("\r", "").replace("\n", "\\n")
    if len(flattened) > max_len:
        return flattened[:max_len] + "..."
    return flattened


def _entry_points(root: Path) -> list[str]:
    return [label for marker, label in _entry_markers().items() if (root / marker).exists()]


def render(root: Path) -> str:
    by_dir, by_ext = _scan(root)
    langs = ", ".join(f"{ext[1:]}({n})" for ext, n in by_ext.most_common(8))
    dirs = "\n".join(
        f"- {_safe_label(name)}/ ({count} files)"
        for name, count in by_dir.most_common(MAX_DIRS)
    )
    entries = ", ".join(_entry_points(root)) or "none detected"
    tests = ", ".join(
        str(entry.name) + "/" for entry in root.iterdir()
        if entry.is_dir() and entry.name.lower() in {"tests", "test", "spec", "__tests__"}
    ) or "none detected"
    return (
        f"## Codemap\n\nEntry points: {entries}\nLanguages: {langs}\n"
        f"Test roots: {tests}\n\nTop directories:\n{dirs}\n"
    )


def main() -> None:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    root = Path(sys.argv[1]).resolve()
    if not root.is_dir():
        print(f"error: not a directory: {root}", file=sys.stderr)
        sys.exit(1)
    print(render(root))


if __name__ == "__main__":
    main()
