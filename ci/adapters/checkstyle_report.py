#!/usr/bin/env python3
"""Turns a craftsman JSON report into a Checkstyle XML report on stdout.

The Warnings Next Generation plugin reads Checkstyle natively, and the schema
carries exactly what the rules engine already produces: a file, a line, a
severity, a message and a rule identifier. `source` holds the identifier, so a
LAYER001 in Jenkins is the same LAYER001 the hook prints locally.

This lives in its own file rather than inside jenkins.sh so it can be run
against a report by hand, and tested without a Jenkins.

Usage: checkstyle_report.py < craftsman-report.json
"""

from __future__ import annotations

import json
import sys
from xml.sax.saxutils import quoteattr

# Warnings NG maps Checkstyle severity onto its own: `error` fails the quality
# gate, `warning` and `info` do not. The rules engine has already resolved
# severity per file, `.craft-rules.yml` included, so this is a translation and
# never a second decision.
#
# There is one array, not two. `output_json` puts warnings in `violations` with
# `severity: "warning"`, which is why a renderer that read a `warnings` key
# would have emitted an XML file with every advisory finding missing and no
# error to say so.
CHECKSTYLE_SEVERITY = {
    "critical": "error",
    "error": "error",
    "warning": "warning",
    "info": "info",
}


def _issues_by_file(report: dict) -> dict:
    by_file: dict = {}
    for issue in report.get("violations", []) or []:
        path = str(issue.get("file", ""))
        # './' is what the walk emits whenever the scanned path is '.', and a
        # path Jenkins cannot resolve is a finding it drops on the floor.
        path = path[2:] if path.startswith("./") else path
        try:
            line = int(issue.get("line", 0))
        except (TypeError, ValueError):
            line = 0
        by_file.setdefault(path, []).append({
            "line": line if line >= 1 else 1,
            # An unknown severity becomes an error rather than being dropped:
            # a finding nobody can see is worse than one ranked too high.
            "severity": CHECKSTYLE_SEVERITY.get(
                str(issue.get("severity", "")), "error"),
            "message": str(issue.get("message", "")),
            "source": str(issue.get("rule", "unknown")),
        })
    return by_file


def render(report: dict) -> str:
    by_file = _issues_by_file(report)
    out = ['<?xml version="1.0" encoding="UTF-8"?>', '<checkstyle version="8.0">']
    for path in sorted(by_file):
        out.append("  <file name=%s>" % quoteattr(path))
        for issue in by_file[path]:
            out.append(
                '    <error line="%d" column="0" severity=%s message=%s source=%s/>'
                % (issue["line"], quoteattr(issue["severity"]),
                   quoteattr(issue["message"]), quoteattr(issue["source"])))
        out.append("  </file>")
    out.append("</checkstyle>")
    return "\n".join(out)


def main() -> int:
    try:
        report = json.load(sys.stdin)
    except ValueError as error:
        sys.stderr.write("checkstyle_report: %s\n" % error)
        return 1
    if not isinstance(report, dict):
        sys.stderr.write("checkstyle_report: the report is not an object\n")
        return 1
    print(render(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
