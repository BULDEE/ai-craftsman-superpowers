#!/usr/bin/env python3
# =============================================================================
# Hotspot analysis: churn x complexity ranking for a git repository.
#
# COMMAND-TIME ONLY. Never call this from a hook: it shells out to git over the
# whole history and is far too slow for the <50ms write-time budget. It backs
# `/craftsman:legacy audit` and `/craftsman:metrics --report`.
#
# This is the ZERO-DEPENDENCY FALLBACK for hotspots. When the team runs
# CodeScene / code-forensics / SonarQube, prefer that report via
# `/craftsman:legacy audit --from <report>`; this tool only computes from git +
# lines-of-code + structural findings when no external report is available.
# See knowledge/tooling-integration.md.
#
# Usage:
#   python3 hotspot_analysis.py [--since 12.month] [--top 30] [--json] [PATH]
#
# Output (default): a ranked table. With --json: a JSON array of
#   { file, churn, complexity, loc, findings, quadrant, risk }.
# =============================================================================
import json
import os
import subprocess
import sys

try:
    import structural_metrics  # reuse the same complexity signal as the gate
except ImportError:
    structural_metrics = None

LANG_BY_EXT = {
    ".php": "php", ".ts": "ts", ".tsx": "ts", ".js": "ts", ".jsx": "ts",
    ".py": "py", ".go": "go", ".rs": "rs", ".sh": "bash",
}


def parse_args(argv):
    since, top, as_json, path = "12.month", 30, False, "."
    positional = []
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--since" and index + 1 < len(argv):
            since = argv[index + 1]
            index += 2
        elif arg == "--top" and index + 1 < len(argv):
            top = int(argv[index + 1])
            index += 2
        elif arg == "--json":
            as_json = True
            index += 1
        else:
            positional.append(arg)
            index += 1
    if positional:
        path = positional[0]
    return since, top, as_json, path


def compute_churn(repo, since):
    """Count changes per file from git history. Read-only, never mutates."""
    try:
        out = subprocess.run(
            ["git", "-C", repo, "log", "--format=format:", "--name-only", f"--since={since}"],
            capture_output=True, text=True, check=True, timeout=60,
        ).stdout
    except (subprocess.SubprocessError, OSError):
        return {}
    churn = {}
    for line in out.splitlines():
        name = line.strip()
        if name:
            churn[name] = churn.get(name, 0) + 1
    return churn


def complexity_of(abspath):
    """LOC plus structural-finding count as a language-neutral complexity proxy."""
    try:
        with open(abspath, "r", encoding="utf-8", errors="replace") as handle:
            loc = sum(1 for _ in handle)
    except OSError:
        return 0, 0
    findings = 0
    ext = os.path.splitext(abspath)[1]
    lang = LANG_BY_EXT.get(ext)
    if structural_metrics is not None and lang in ("php", "ts"):
        try:
            findings = len(structural_metrics.analyze(abspath, lang))
        except Exception:
            findings = 0
    # LOC is the base proxy; each structural finding adds weight.
    return loc + findings * 25, findings


def median(values):
    if not values:
        return 0
    ordered = sorted(values)
    mid = len(ordered) // 2
    return ordered[mid] if len(ordered) % 2 else (ordered[mid - 1] + ordered[mid]) / 2


def classify(complexity, churn, c_med, ch_med):
    hi_c, hi_ch = complexity >= c_med, churn >= ch_med
    if hi_c and hi_ch:
        return "top-right", "HIGH"
    if hi_c and not hi_ch:
        return "top-left", "LOW"
    if not hi_c and hi_ch:
        return "bottom-right", "LOW"
    return "bottom-left", "NONE"


def analyze_repo(repo, since, top):
    churn = compute_churn(repo, since)
    rows = []
    for name, change_count in churn.items():
        ext = os.path.splitext(name)[1]
        if ext not in LANG_BY_EXT:
            continue
        abspath = os.path.join(repo, name)
        if not os.path.isfile(abspath):
            continue  # deleted/renamed file still in history
        complexity, findings = complexity_of(abspath)
        rows.append({"file": name, "churn": change_count, "complexity": complexity,
                     "loc": complexity - findings * 25, "findings": findings})
    complexity_median = median([row["complexity"] for row in rows])
    churn_median = median([row["churn"] for row in rows])
    for row in rows:
        row["quadrant"], row["risk"] = classify(
            row["complexity"], row["churn"], complexity_median, churn_median)
    # Rank: top-right first, then by churn*complexity.
    rows.sort(key=lambda row: (row["quadrant"] != "top-right",
                               -(row["churn"] * row["complexity"])))
    return rows[:top]


def main():
    since, top, as_json, path = parse_args(sys.argv[1:])
    rows = analyze_repo(path, since, top)
    if as_json:
        print(json.dumps(rows, indent=2))
        return
    if not rows:
        print("No hotspots found (no git history, or no supported files changed).")
        return
    print(f"{'File':<50} {'Cplx':>6} {'Churn':>6} {'Quadrant':>13} {'Risk':>5}")
    print("-" * 84)
    for row in rows:
        print(f"{row['file']:<50} {row['complexity']:>6} {row['churn']:>6} "
              f"{row['quadrant']:>13} {row['risk']:>5}")
    print("\nRefactor the top-right (complex AND churning) first. See "
          "knowledge/refactoring/refactoring-campaigns.md")


if __name__ == "__main__":
    main()
