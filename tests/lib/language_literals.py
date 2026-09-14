"""Language names and extensions written into the core, outside comments.

Read by tests/core/test-no-language-literals.sh. Dialect names (`php-like`,
`c-like`) are not languages and are allowed; the test-path convention names
directories, not languages, and never matches here. Python docstrings are
comments for this purpose and are skipped.
"""
import os
import re
import sys

PATTERN = re.compile(
    r"[\"'](php|typescript|python|golang|rust|tsx?|py|go|rs)[\"']"
    r"|(?<=[\"'\s\[(|*])\.(php|tsx?|py|go|rs|sh)(?=[\"'\s\]\)|]|$)"
    r"|composer\.json|package\.json|go\.mod|Cargo\.toml|pyproject\.toml",
    re.IGNORECASE,
)

# What is allowed to stay, and why. Every entry is a debt with a backlog line,
# not an exemption: the day the line goes, the entry goes.
ALLOWED = {
    # A language-to-tooling table the healthcheck reads to suggest analysers.
    # It belongs to the packs (CR-113): each pack should declare the tools it
    # knows how to install, and the healthcheck should ask the registry.
    "hooks/lib/tooling_detect.py": "CR-113",
    # The PHP001 auto-fix inserts declare(strict_types=1) through updatedInput.
    # A fixer is a pack capability the manifest does not declare yet (CR-114).
    "hooks/pre-write-check.sh": "CR-114",
}


def _targets(root):
    for folder in ("hooks", "ci"):
        for dirpath, _, names in os.walk(os.path.join(root, folder)):
            if "__pycache__" in dirpath or "bias-patterns" in dirpath:
                continue
            for name in names:
                if name.endswith((".sh", ".py", ".json")):
                    yield os.path.join(dirpath, name)


def _code_lines(lines, ext):
    """Each line with its comment removed; an empty string for a comment line."""
    in_docstring = False
    for line in lines:
        if ext == ".py":
            stripped = line.strip()
            quotes = stripped.count('"""') + stripped.count("'''")
            if in_docstring:
                if quotes:
                    in_docstring = False
                yield ""
                continue
            if quotes == 1:
                in_docstring = True
                yield ""
                continue
            if quotes >= 2:
                yield ""
                continue
        if ext == ".json":
            yield line
            continue
        marker = line.find("#")
        yield line[:marker] if marker >= 0 else line


def main(root):
    for path in sorted(_targets(root)):
        rel = os.path.relpath(path, root)
        if rel in ALLOWED:
            continue
        ext = os.path.splitext(path)[1]
        try:
            lines = open(path, encoding="utf-8").read().splitlines()
        except (OSError, UnicodeDecodeError):
            continue
        for number, code in enumerate(_code_lines(lines, ext), 1):
            if code.strip() and PATTERN.search(code):
                print("%s:%d: %s" % (rel, number, code.strip()[:100]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
