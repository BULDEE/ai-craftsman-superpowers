#!/usr/bin/env python3
"""Quality tooling detector: report what the project already declares, per language.

Usage: tooling_detect.py <repo_root> [--json]

The plugin is the action layer, not another analysis tool: when a project
already declares a quality or churn tool, the audit must consume its output
instead of computing a worse second opinion. When nothing is declared, the
report suggests the community-standard tool for the detected stack so the
user can opt in (never installed automatically).
"""
import json
import sys
from pathlib import Path

# language -> (manifest, [(dependency substring, tool label, report command)])
DECLARED = {
    "php": ("composer.json", [
        ("phpstan", "PHPStan", "vendor/bin/phpstan analyse --error-format=json"),
        ("psalm", "Psalm", "vendor/bin/psalm --output-format=json"),
        ("phpmetrics", "PhpMetrics", "vendor/bin/phpmetrics --report-json=phpmetrics.json ."),
        ("deptrac", "Deptrac", "vendor/bin/deptrac analyse --formatter=json"),
        ("phpunit", "PHPUnit", "vendor/bin/phpunit --coverage-text"),
    ]),
    "javascript": ("package.json", [
        ("eslint", "ESLint", "npx eslint . --format json"),
        ("dependency-cruiser", "dependency-cruiser", "npx depcruise src --output-type json"),
        ("vitest", "Vitest", "npx vitest run --coverage"),
        ("jest", "Jest", "npx jest --coverage --json"),
        ("typescript", "tsc", "npx tsc --noEmit"),
    ]),
    "python": ("pyproject.toml", [
        ("ruff", "Ruff", "ruff check --output-format json ."),
        ("radon", "Radon", "radon cc -j ."),
        ("mypy", "mypy", "mypy --json-report mypy-report ."),
        ("pytest", "pytest", "pytest --cov"),
    ]),
    "rust": ("Cargo.toml", [
        ("clippy", "Clippy", "cargo clippy --message-format json"),
        ("tarpaulin", "Tarpaulin", "cargo tarpaulin --out Json"),
    ]),
    "go": ("go.mod", [
        ("golangci-lint", "golangci-lint", "golangci-lint run --out-format json"),
    ]),
}

# Suggestions when a language is present but declares no quality tool.
SUGGEST = {
    "php": [("PHPStan", "composer require --dev phpstan/phpstan"),
            ("PhpMetrics (complexity for hotspots)", "composer require --dev phpmetrics/phpmetrics")],
    "javascript": [("ESLint", "npm install --save-dev eslint"),
                   ("dependency-cruiser (layer boundaries)", "npm install --save-dev dependency-cruiser")],
    "python": [("Ruff", "pip install ruff"), ("Radon (complexity)", "pip install radon")],
    "rust": [("Clippy", "rustup component add clippy")],
    "go": [("golangci-lint", "https://golangci-lint.run/usage/install/")],
}

CHURN_TOOLS = [
    ("code-maat", "Churn/coupling analysis (Adam Tornhill): https://github.com/adamtornhill/code-maat"),
    ("git-of-theseus", "Long-range churn: pip install git-of-theseus"),
]


def _manifest_text(root: Path, manifest: str) -> str:
    path = root / manifest
    if not path.is_file():
        return ""
    try:
        return path.read_text(errors="ignore").lower()
    except OSError:
        return ""


def detect(root: Path) -> dict:
    result: dict = {"languages": {}, "churn": [], "suggestions": {}}
    for lang, (manifest, tools) in DECLARED.items():
        text = _manifest_text(root, manifest)
        if not text:
            continue
        found = [
            {"tool": label, "report_command": command}
            for needle, label, command in tools if needle in text
        ]
        result["languages"][lang] = {"manifest": manifest, "declared": found}
        if not found:
            result["suggestions"][lang] = [
                {"tool": label, "install": how} for label, how in SUGGEST.get(lang, [])
            ]
    result["churn"] = [
        {"tool": label, "how": how} for label, how in CHURN_TOOLS
    ]
    return result


def _render_language(lang: str, info: dict) -> list[str]:
    lines = [f"### {lang} ({info['manifest']})"]
    if info["declared"]:
        for entry in info["declared"]:
            lines.append(f"- {entry['tool']}: `{entry['report_command']}`")
    else:
        lines.append("- no quality tool declared")
    return lines


def render(result: dict) -> str:
    lines = ["## Declared tooling"]
    if not result["languages"]:
        lines.append("- no supported manifest found (built-in churn ranking is the fallback)")
    for lang, info in result["languages"].items():
        lines.extend(_render_language(lang, info))
    if result["suggestions"]:
        lines.append("")
        lines.append("## Suggested (not installed - your call)")
        for lang, entries in result["suggestions"].items():
            for entry in entries:
                lines.append(f"- {lang}: {entry['tool']} -> `{entry['install']}`")
    lines.append("")
    lines.append("## Churn (always available from git; dedicated tools optional)")
    for entry in result["churn"]:
        lines.append(f"- {entry['tool']}: {entry['how']}")
    return "\n".join(lines)


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    root = Path(sys.argv[1]).resolve()
    result = detect(root)
    if "--json" in sys.argv:
        json.dump(result, sys.stdout, indent=2)
        print()
        return
    print(render(result))


if __name__ == "__main__":
    main()
