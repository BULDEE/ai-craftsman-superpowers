"""Codification (ADR-0020): an approved instinct becomes a skill on disk.

Split from instincts.py, which extracts and lists candidates: everything here
writes a file a host loads into the model's context, so every input is treated
as untrusted, every destination is validated, and Approve and the review
preview share one builder (ADR-0031).
"""
from __future__ import annotations

import os
import re
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path


def _slugify(rule: str) -> str:
    return "".join(char.lower() if char.isalnum() else "-" for char in rule).strip("-")


# A generated skill is loaded into the model's context as background knowledge,
# so every field interpolated into it is an instruction channel. Two of them are
# not plugin-controlled: pattern_summary comes from a correction's context, and
# the evidence lines carry file_pattern, which is a path out of the audited
# repository. A newline in either one closes the markdown body and lets the rest
# of the string read as fresh instructions - or, at the top of the file, as more
# YAML frontmatter. Collapse to a single line, drop the characters that would
# terminate the inline-code fence, and cap the length.
_UNTRUSTED_MAX = 200


def _untrusted(text: str, limit: int = _UNTRUSTED_MAX) -> str:
    collapsed = " ".join(str(text or "").split())
    stripped = "".join(char for char in collapsed if char.isprintable() and char != "`")
    if len(stripped) > limit:
        stripped = stripped[:limit] + "..."
    return stripped


# metrics-db.sh validates a rule id before it writes one, but this module is a
# second front door: it reads rows a previous version wrote, and rows written by
# anything else pointed at the same database. Validating here keeps the
# guarantee local instead of borrowing it from a caller three files away.
_RULE_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{1,39}$")


def _safe_rule(rule: str) -> str:
    if not _RULE_RE.match(str(rule or "")):
        print(f"error: refusing to generate a skill for malformed rule id: {rule!r}",
              file=sys.stderr)
        sys.exit(1)
    return rule


# skills_dir is raw argv. _slugify already prevents the rule from walking out of
# it, but nothing stopped the directory itself from pointing anywhere writable.
# A generated skill only means something inside the project or the user's own
# Claude configuration; anywhere else is a write primitive, not a feature.
# The directories a host reads project and user skills from, and from nowhere
# deeper. Claude Code: .claude/skills/<name>/SKILL.md and ~/.claude/skills/,
# measured with `claude -p --debug` (two project skills on disk, one at that
# depth and one under .claude/skills/craftsman-learned/, loaded as
# `project: 1`; four releases of approvals went to the second place). Codex:
# .agents/skills/<name>/SKILL.md and ~/.agents/skills/, documented at
# learn.chatgpt.com/docs/build-skills and listed by `codex debug prompt-input`
# on 0.154.0; an approval into .claude/skills on a Codex machine was a file
# Codex never loaded (audit CR-117, C5). A destination the consumer will never
# read is refused, not written.
HOST_SKILL_PARENTS = (".claude", ".agents")


def _resolve_skills_dir(skills_dir: str) -> Path:
    target = Path(skills_dir).expanduser().resolve()
    roots = (Path.cwd().resolve(), Path.home().resolve())
    allowed = [root / parent / "skills" for root in roots for parent in HOST_SKILL_PARENTS]
    # Exactly these four directories, not "anything named .claude/skills": a
    # nested project/x/.agents/skills passed the name test and is a place no
    # host reads (review of ff99dd5, F4).
    if target not in allowed:
        print("error: a host loads a skill from .claude/skills/<name>/SKILL.md (Claude Code) "
              "or .agents/skills/<name>/SKILL.md (Codex), at the project root or under $HOME, "
              f"never from {target}: approve into \"$PWD/.claude/skills\" or \"$PWD/.agents/skills\"",
              file=sys.stderr)
        sys.exit(1)
    return target


def _own_skill_dir(skills_dir: Path, name: str) -> Path:
    """The skill's directory, created, and neither it nor its SKILL.md a
    symlink: the directory under the validated root could be a link placed
    there beforehand, and the write followed it out of the project
    (independent verification, 2026-09-15)."""
    skill_dir = skills_dir / name
    skill_dir.mkdir(parents=True, exist_ok=True)
    target = skill_dir / "SKILL.md"
    if skill_dir.is_symlink() or target.is_symlink() or skill_dir.resolve() != skill_dir:
        print(f"error: {skill_dir} is a symlink; refusing to write a skill through it", file=sys.stderr)
        sys.exit(1)
    return skill_dir


SKILL_TEMPLATE = """---
name: learned-{slug}
description: Learned instinct for rule {rule}. This project corrected {rule} {occurrences} times across {distinct_files} files; apply the fix pattern proactively when writing matching code.
user-invocable: false
---

# Learned Instinct: {rule}

This project repeatedly corrects **{rule}**. Apply the correction proactively instead of waiting for the quality gate to flag it.

## Pattern

{pattern}

## Evidence

{evidence}

## Provenance

- Source: {occurrences} recorded corrections across {distinct_files} files (confidence {confidence})
- Approved by human review on {today} via /craftsman:metrics
- Delete this file or run /craftsman:metrics to retire the instinct
"""


def _render_skill(rule: str, summary: str, occurrences: int, distinct_files: int,
                  confidence: float, contexts: list[tuple]) -> str:
    rule = _safe_rule(rule)
    evidence = "\n".join(
        f"- `{_untrusted(fp, 120)}`: {_untrusted(ctx, 120)}" if ctx
        else f"- `{_untrusted(fp, 120)}`"
        for ctx, fp in contexts
    ) or "- (contexts not recorded)"
    return SKILL_TEMPLATE.format(
        rule=rule,
        slug=_slugify(rule),
        occurrences=occurrences,
        distinct_files=distinct_files,
        confidence=confidence,
        pattern=_untrusted(summary) or f"See the {rule} rule definition in the active pack validators.",
        evidence=evidence,
        today=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
    )


def _load_candidate(conn: sqlite3.Connection, instinct_id: int) -> tuple:
    row = conn.execute(
        "SELECT project_hash, rule, pattern_summary, occurrences, distinct_files, confidence"
        " FROM instincts WHERE id = ? AND status = 'candidate'",
        (instinct_id,),
    ).fetchone()
    if row is None:
        print(f"error: no candidate instinct with id {instinct_id}", file=sys.stderr)
        sys.exit(1)
    return row


def _evidence_contexts(conn: sqlite3.Connection, project_hash: str, rule: str) -> list[tuple]:
    return conn.execute(
        "SELECT DISTINCT COALESCE(context, ''), file_pattern FROM corrections"
        " WHERE project_hash = ? AND rule = ? AND action = 'fixed'"
        " ORDER BY timestamp DESC LIMIT 3",
        (project_hash, rule),
    ).fetchall()


def approve(conn: sqlite3.Connection, instinct_id: int, skills_dir: str) -> None:
    project_hash, rule, summary, occurrences, distinct_files, confidence = _load_candidate(
        conn, instinct_id
    )
    skill_dir = _own_skill_dir(_resolve_skills_dir(skills_dir), f"learned-{_slugify(rule)}")
    content = _skill_for(conn, project_hash, (rule, summary, occurrences, distinct_files, confidence))
    (skill_dir / "SKILL.md").write_text(content)
    conn.execute(
        "UPDATE instincts SET status = 'approved', reviewed_at = datetime('now') WHERE id = ?",
        (instinct_id,),
    )
    conn.commit()
    print(f"approved: {skill_dir / 'SKILL.md'}")


GLOBAL_TEMPLATE = """---
name: learned-global-{slug}
description: Cross-project learned instinct for rule {rule}. Confirmed in {project_count} independent projects; apply the fix pattern proactively when writing matching code.
user-invocable: false
---

# Global Learned Instinct: {rule}

This correction was approved independently in **{project_count} projects**, so it reflects how you work rather than one codebase's quirk. Apply it proactively.

## Pattern

{pattern}

## Provenance

- Confirmed in {project_count} projects ({occurrences} corrections total)
- Promoted from project scope by human review on {today} via /craftsman:metrics
- Delete this file to retire the instinct globally
"""


def global_candidates(conn: sqlite3.Connection) -> list[tuple]:
    """Rules approved in 2+ distinct projects and not yet promoted globally."""
    return conn.execute(
        "SELECT rule, COUNT(DISTINCT project_hash) AS projects, SUM(occurrences),"
        " MAX(COALESCE(pattern_summary, ''))"
        " FROM instincts WHERE status = 'approved'"
        " GROUP BY rule HAVING projects >= 2"
    ).fetchall()


def promote(conn: sqlite3.Connection, rule: str, skills_dir: str) -> None:
    """Promote a rule to global scope. Human-invoked only, never automatic."""
    match = [row for row in global_candidates(conn) if row[0] == rule]
    if not match:
        print(f"error: {rule} is not approved in 2+ projects", file=sys.stderr)
        sys.exit(1)
    _rule, projects, occurrences, summary = match[0]
    rule = _safe_rule(rule)
    skill_dir = _own_skill_dir(_resolve_skills_dir(skills_dir), f"learned-global-{_slugify(rule)}")
    (skill_dir / "SKILL.md").write_text(GLOBAL_TEMPLATE.format(
        rule=rule,
        slug=_slugify(rule),
        project_count=projects,
        occurrences=occurrences,
        pattern=_untrusted(summary) or f"See the {rule} rule definition in the active pack validators.",
        today=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
    ))
    print(f"promoted: {skill_dir / 'SKILL.md'}")


# The rule's wording, owner and default severity, from the registry the hooks
# compile out of the pack manifests (CRAFTSMAN_RULE_REGISTRY, exported by
# rule_registry_init). Absent, the fields are empty: the queue still answers.
# An external pack writes these columns, so they are filtered like any text
# out of a repository.
_NO_RULE_INFO = {"rule_text": "", "rule_group": "", "rule_owner": "", "default_severity": ""}


def _rule_info(rule: str) -> dict:
    registry = os.environ.get("CRAFTSMAN_RULE_REGISTRY", "")
    try:
        rows = Path(registry).read_text().splitlines() if registry else []
    except OSError:
        rows = []
    for row in rows:
        columns = row.split("\t")
        if len(columns) >= 5 and columns[0] == rule:
            return {"rule_text": _untrusted(columns[4]), "rule_group": _untrusted(columns[1], 40),
                    "rule_owner": _untrusted(columns[3], 40), "default_severity": _untrusted(columns[2], 10)}
    return dict(_NO_RULE_INFO)


# One builder for the skill Approve writes and the preview the review shows,
# so the pane can promise what lands on disk. With no correction context
# recorded, the rule's own wording is the pattern: "see the rule definition"
# taught the model nothing.
def _skill_for(conn: sqlite3.Connection, project_hash: str, candidate: tuple) -> str:
    rule, summary, occurrences, distinct_files, confidence = candidate
    wording = _rule_info(rule)["rule_text"]
    pattern = summary or (f"{rule}: {wording}." if wording else "")
    contexts = _evidence_contexts(conn, project_hash, rule)
    return _render_skill(rule, pattern, occurrences, distinct_files, confidence, contexts)
