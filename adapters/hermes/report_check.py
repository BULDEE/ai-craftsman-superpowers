#!/usr/bin/env python3
"""Whether a craftsman-ci report can be read as a verdict at all.

pre-verify.sh read a report it could not parse as "no finding" and recorded a
pass, and so did a zero-file report that exited 2 (review of main eb54d13,
B8). A report is a verdict only when it parses, carries its summary, agrees
with the exit status it came with, and covers the source files the turn
changed. craftsman-ci exits 0 when clean, 1 on warnings only, and 2 on a
blocking finding or when it found no source file to scan.

Usage: report_check.py <exit status> <plugin root> <changed path>...   stdin: the report
stdout: nothing when the report is a verdict, the reason when it is not.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys


def known_extensions(plugin_root: str) -> set:
    """Every extension an installed pack declares, from the same compiler the hooks use."""
    packs = os.path.join(plugin_root, "packs")
    manifests = sorted(os.path.join(packs, name, "pack.yml") for name in os.listdir(packs)
                       if os.path.isfile(os.path.join(packs, name, "pack.yml")))
    compiled = subprocess.run([sys.executable, os.path.join(plugin_root, "hooks", "lib", "lang_registry.py"), *manifests],
                              capture_output=True, text=True, check=False, timeout=30)
    rows = (line.split("\t") for line in compiled.stdout.splitlines())
    return {row[2] for row in rows if len(row) >= 3 and row[1] == "extensions"}


def _summary(report: object) -> dict | None:
    if not isinstance(report, dict) or not isinstance(report.get("violations"), list):
        return None
    summary = report.get("summary")
    if not isinstance(summary, dict):
        return None
    fields = ("files_scanned", "violations", "warnings")
    return summary if all(isinstance(summary.get(field), int) for field in fields) else None


def problem(text: str, status: int, judgeable: int) -> str:
    """The reason the report is not a verdict, "" when it is one."""
    try:
        report = json.loads(text)
    except (ValueError, TypeError):
        return "the gate's report does not parse"
    summary = _summary(report)
    if summary is None:
        return "the gate's report carries no summary"
    if status not in (0, 1, 2):
        return "the gate exited %d" % status
    blocking = [finding for finding in report["violations"]
                if isinstance(finding, dict) and finding.get("severity") == "critical"]
    if judgeable and summary["files_scanned"] == 0:
        return "the gate's report covers none of the %d changed source file(s)" % judgeable
    if status == 2 and not blocking and judgeable:
        return "the gate exited 2 without a blocking finding"
    return ""


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        sys.stderr.write(__doc__ or "")
        return 2
    extensions = known_extensions(argv[1])
    judgeable = sum(1 for path in argv[2:] if os.path.splitext(path)[1].lstrip(".") in extensions)
    reason = problem(sys.stdin.read(), int(argv[0]), judgeable)
    if reason:
        print(reason)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
