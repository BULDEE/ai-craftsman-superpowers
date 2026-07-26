#!/usr/bin/env python3
"""Codemap generator (ADR-0022): compact structural map of a repository.

Usage: codemap.py <repo_root>

Prints a markdown map (directories, file counts by language, entry points,
test location). Callers handle caching; this script only observes.
"""
import sys
from collections import Counter
from pathlib import Path

SKIP_DIRS = {".git", "node_modules", "vendor", "dist", "build", ".idea",
             ".vscode", "__pycache__", ".ruff_cache", "coverage", ".next"}
CODE_EXTS = {".php", ".ts", ".tsx", ".js", ".py", ".sh", ".go", ".rs", ".java", ".md", ".yml", ".yaml", ".json"}
ENTRY_MARKERS = {
    "composer.json": "PHP (composer)",
    "package.json": "Node (package.json)",
    "pyproject.toml": "Python (pyproject)",
    "Cargo.toml": "Rust (cargo)",
    "go.mod": "Go (modules)",
    "Makefile": "Make",
}
MAX_DIRS = 20


def _scan(root: Path) -> tuple[Counter, Counter]:
    by_dir: Counter = Counter()
    by_ext: Counter = Counter()
    for path in root.rglob("*"):
        rel = path.relative_to(root)
        if any(part in SKIP_DIRS for part in rel.parts):
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


def _entry_points(root: Path) -> list[str]:
    return [label for marker, label in ENTRY_MARKERS.items() if (root / marker).exists()]


def render(root: Path) -> str:
    by_dir, by_ext = _scan(root)
    langs = ", ".join(f"{ext[1:]}({n})" for ext, n in by_ext.most_common(8))
    dirs = "\n".join(f"- {d}/ ({n} files)" for d, n in by_dir.most_common(MAX_DIRS))
    entries = ", ".join(_entry_points(root)) or "none detected"
    tests = ", ".join(
        str(p.name) + "/" for p in root.iterdir()
        if p.is_dir() and p.name.lower() in {"tests", "test", "spec", "__tests__"}
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
