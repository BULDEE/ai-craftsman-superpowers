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
import re
import sys
import xml.etree.ElementTree as ElementTree
from xml.sax.saxutils import quoteattr

# XML 1.0 forbids most C0 control characters outright: no escape represents
# them, so a document carrying one is not well-formed and no parser will read
# it. They reach here through static analysis, whose stdout is copied verbatim
# into the message and whose tools colour their output with ANSI escapes.
# quoteattr does not touch them, so the renderer used to exit 0 on a document
# Warnings NG could only refuse.
_ILLEGAL_XML = re.compile(
    r"[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD\U00010000-\U0010FFFF]")


def xml_safe(text: str) -> str:
    """The text with every character XML cannot carry replaced by a space."""
    return _ILLEGAL_XML.sub(" ", text)

# Warnings NG maps Checkstyle severity onto its own: `error` fails the quality
# gate, `warning` and `info` do not. The rules engine has already resolved
# severity per file, `.craft-rules.yml` included, so this is a translation and
# never a second decision.
#
# There is one array, not two. `output_json` puts warnings in `violations` with
# `severity: "warning"`, which is why a renderer that read a `warnings` key
# would have emitted an XML file with every advisory finding missing and no
# error to say so.
# `output_json` emits `critical` and `warning` and nothing else today, so the
# other two keys and the fallback below are a guard rather than a live path.
# They are kept because the fallback DIRECTION is what the three renderers must
# agree on: github.sh and gitlab.sh apply the same one, and
# tests/ci/test-adapters.sh fails when they diverge. Warnings NG would not drop
# an unknown value either (`Severity.guessFromString` falls back to WARNING_LOW),
# so this is about the verdict being the same everywhere, not about the plugin.
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
            # An unknown severity becomes an error rather than being dropped
            # or demoted. github.sh and gitlab.sh apply the same fallback, and
            # tests/ci/test-adapters.sh fails when the three disagree.
            "severity": CHECKSTYLE_SEVERITY.get(
                str(issue.get("severity", "")), "error"),
            "message": xml_safe(str(issue.get("message", ""))),
            "source": xml_safe(str(issue.get("rule", "unknown"))),
        })
    return by_file


def render(report: dict) -> str:
    by_file = _issues_by_file(report)
    out = ['<?xml version="1.0" encoding="UTF-8"?>', '<checkstyle version="8.0">']
    for path in sorted(by_file):
        out.append("  <file name=%s>" % quoteattr(xml_safe(path)))
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
    document = render(report)
    # The renderer builds a string, so it can build one no parser accepts. It
    # reads its own output back before claiming success: an exit code is the
    # only thing adapter_annotate has to go on before it publishes the file.
    try:
        ElementTree.fromstring(document)
    except ElementTree.ParseError as error:
        sys.stderr.write("checkstyle_report: produced a document no parser accepts: %s\n"
                         % error)
        return 1
    print(document)
    return 0


if __name__ == "__main__":
    sys.exit(main())
