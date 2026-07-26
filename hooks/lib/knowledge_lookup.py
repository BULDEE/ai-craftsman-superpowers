#!/usr/bin/env python3
"""Deterministic lookup over the OKF knowledge bundle (ADR-0024).

Usage:
  knowledge_lookup.py <bundle_dir> by-rule <RULE_ID>
  knowledge_lookup.py <bundle_dir> by-tag <tag>
  knowledge_lookup.py <bundle_dir> list

Exact frontmatter matching only: no embeddings, no index, no fuzziness.
Prints one concept per line as '<concept-id>\ttitle'. Exit 0 with output,
exit 0 silent when nothing matches (callers degrade to no pointer).
"""
import sys
from pathlib import Path

RESERVED = {"index.md", "log.md"}


def _parse_frontmatter(text: str) -> dict:
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 4)
    if end == -1:
        return {}
    fields: dict = {}
    for line in text[4:end].split("\n"):
        if ":" not in line or line.startswith((" ", "\t")):
            continue
        key, _, value = line.partition(":")
        value = value.strip().strip('"')
        if value.startswith("[") and value.endswith("]"):
            fields[key.strip()] = [item.strip() for item in value[1:-1].split(",") if item.strip()]
        else:
            fields[key.strip()] = value
    return fields


def _concepts(bundle: Path):
    for path in sorted(bundle.rglob("*.md")):
        if path.name in RESERVED:
            continue
        fields = _parse_frontmatter(path.read_text(errors="ignore"))
        if fields:
            concept_id = str(path.relative_to(bundle))[:-3]
            yield concept_id, fields


def _emit(concept_id: str, fields: dict) -> None:
    print(f"{concept_id}\t{fields.get('title', concept_id)}")


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    bundle = Path(sys.argv[1])
    command = sys.argv[2]
    if not bundle.is_dir():
        sys.exit(0)

    if command == "list":
        for concept_id, fields in _concepts(bundle):
            _emit(concept_id, fields)
        return

    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    needle = sys.argv[3]
    key = {"by-rule": "rules", "by-tag": "tags"}.get(command)
    if key is None:
        print(f"unknown command: {command}", file=sys.stderr)
        sys.exit(1)
    for concept_id, fields in _concepts(bundle):
        values = fields.get(key, [])
        if isinstance(values, list) and needle in values:
            _emit(concept_id, fields)


if __name__ == "__main__":
    main()
