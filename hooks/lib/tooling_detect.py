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
        ("roave/security-advisories", "Roave Security Advisories", "composer audit --format=json"),
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

# Security is never "already covered": these are suggested for every detected
# language, declared or not, as (tool, command, what it catches). ADR-0019: the
# detector suggests, the human decides, nothing is ever installed.
SECURITY_SUGGEST = {
    "php": [
        ("composer audit", "composer audit",
         "known CVEs in declared dependencies, ships with Composer 2.4+"),
        ("gitleaks", "brew install gitleaks", "committed secrets, history included"),
        ("Psalm taint analysis", "composer require --dev vimeo/psalm",
         "injection paths from input to sink, run with --taint-analysis"),
    ],
    "javascript": [
        ("npm audit", "npm audit", "known CVEs in the dependency tree, ships with npm"),
        ("gitleaks", "brew install gitleaks", "committed secrets, history included"),
        ("semgrep", "brew install semgrep", "SAST rules for injection, eval, unsafe sinks"),
    ],
    "python": [
        ("pip-audit", "pip install pip-audit", "known CVEs in installed packages"),
        ("bandit", "pip install bandit", "eval/exec, subprocess shell, weak crypto"),
        ("gitleaks", "brew install gitleaks", "committed secrets, history included"),
    ],
    "rust": [
        ("cargo-audit", "cargo install cargo-audit", "RustSec advisories for the lockfile"),
        ("gitleaks", "brew install gitleaks", "committed secrets, history included"),
    ],
    "go": [
        ("govulncheck", "go install golang.org/x/vuln/cmd/govulncheck@latest",
         "vulnerabilities reachable from your call graph"),
        ("gitleaks", "brew install gitleaks", "committed secrets, history included"),
    ],
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


def _security_for(languages: dict) -> dict:
    security: dict = {}
    for lang in languages:
        entries = SECURITY_SUGGEST.get(lang, [])
        security[lang] = [
            {"tool": tool, "command": command, "catches": catches}
            for tool, command, catches in entries
        ]
    return security


def detect(root: Path) -> dict:
    result: dict = {"languages": {}, "churn": [], "suggestions": {}, "security": {}}
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
    result["security"] = _security_for(result["languages"])
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


def _render_security(security: dict) -> list[str]:
    if not security:
        return []
    lines = ["", "## Security (verify these run in CI)"]
    for lang, entries in security.items():
        for entry in entries:
            lines.append(
                f"- {lang}: {entry['tool']} -> `{entry['command']}` ({entry['catches']})"
            )
    lines.append("- doctrine: knowledge/security/secure-by-design.md (SEC001-SEC003)")
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
    lines.extend(_render_security(result.get("security", {})))
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
