#!/usr/bin/env python3
"""
YAML parser for AI Craftsman Superpowers rules engine.

Replaces the 250+ line bash YAML parser with a robust Python implementation.
Supports two modes:
  - "config": Full .craft-config.yml parsing (strictness + rules)
  - "rules":  Directory .craft-rules.yml parsing (rules section only)

Outputs JSON to stdout. Graceful degradation: works without PyYAML.
"""

from __future__ import annotations

import json
import os
import re
import sys


def parse_with_pyyaml(file_path: str) -> dict:
    """Parse YAML using PyYAML (preferred)."""
    import yaml
    with open(file_path, "r") as f:
        return yaml.safe_load(f) or {}


def _flush_rule(
    rules: dict, current_rule: str | None, current_rule_props: dict,
) -> None:
    if current_rule and current_rule_props:
        rules[current_rule] = current_rule_props


def _parse_top_level_line(
    stripped: str, result: dict, rules: dict,
    current_rule: str | None, current_rule_props: dict,
) -> tuple[bool, str | None, dict]:
    _flush_rule(rules, current_rule, current_rule_props)
    current_rule = None
    current_rule_props = {}

    if stripped.startswith("rules:"):
        return True, current_rule, current_rule_props

    scalar_match = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):\s+(.+)$', stripped)
    if scalar_match:
        result[scalar_match.group(1)] = _unquote(scalar_match.group(2))
    return False, current_rule, current_rule_props


def _parse_rule_property(stripped: str, current_rule_props: dict) -> None:
    m_prop = re.match(r'^([a-z_]+):\s+(.+)$', stripped)
    if not m_prop:
        return

    key = m_prop.group(1)
    val = m_prop.group(2)

    if key in ("languages", "paths"):
        current_rule_props[key] = _parse_inline_array(val)
    elif key in ("pattern", "message"):
        current_rule_props[key] = _unescape_yaml_string(_unquote(val))
    else:
        current_rule_props[key] = _unquote(val)


def _parse_rule_definition(
    stripped: str, rules: dict,
    current_rule: str | None, current_rule_props: dict,
) -> tuple[str | None, dict]:
    m_short = re.match(
        r'^([A-Za-z_][A-Za-z0-9_]*):\s+(block|warn|ignore)\s*$', stripped,
    )
    m_long = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):\s*$', stripped)

    if m_short:
        _flush_rule(rules, current_rule, current_rule_props)
        rules[m_short.group(1)] = m_short.group(2)
        return None, {}
    if m_long:
        _flush_rule(rules, current_rule, current_rule_props)
        return m_long.group(1), {}

    return current_rule, current_rule_props


def _dispatch_yaml_line(
    stripped: str, indent: int, in_rules: bool,
    result: dict, rules: dict,
    current_rule: str | None, current_rule_props: dict,
) -> tuple[bool, str | None, dict]:
    """Route a single YAML line to the appropriate handler."""
    if indent == 0:
        return _parse_top_level_line(
            stripped, result, rules, current_rule, current_rule_props,
        )
    if not in_rules:
        return in_rules, current_rule, current_rule_props
    if current_rule and indent >= 4:
        _parse_rule_property(stripped, current_rule_props)
        return in_rules, current_rule, current_rule_props
    new_rule, new_props = _parse_rule_definition(
        stripped, rules, current_rule, current_rule_props,
    )
    return in_rules, new_rule, new_props


def parse_line_by_line(file_path: str) -> dict:
    """Fallback line-by-line parser when PyYAML is not available."""
    result: dict = {}
    rules: dict = {}
    in_rules = False
    current_rule: str | None = None
    current_rule_props: dict = {}

    with open(file_path, "r") as f:
        for raw_line in f:
            line = raw_line.rstrip("\n\r")
            stripped = line.lstrip()
            if not stripped or stripped.startswith("#"):
                continue
            indent = len(line) - len(stripped)
            in_rules, current_rule, current_rule_props = _dispatch_yaml_line(
                stripped, indent, in_rules, result, rules,
                current_rule, current_rule_props,
            )

    _flush_rule(rules, current_rule, current_rule_props)
    if rules:
        result["rules"] = rules
    return result


def _unquote(val: str) -> str:
    """Strip surrounding quotes from a YAML value."""
    val = val.strip()
    if len(val) >= 2:
        if (val[0] == '"' and val[-1] == '"') or (
            val[0] == "'" and val[-1] == "'"
        ):
            return val[1:-1]
    return val


def _unescape_yaml_string(val: str) -> str:
    r"""Un-escape YAML double-quote sequences: \\ -> \, \n -> newline, etc."""
    # Only unescape double-backslash to single-backslash
    return val.replace("\\\\", "\\")


def _parse_inline_array(val: str) -> list[str]:
    """Parse YAML inline array: [php, typescript] -> ['php', 'typescript']."""
    val = val.strip()
    if val.startswith("[") and val.endswith("]"):
        inner = val[1:-1]
        if not inner.strip():
            return []
        items = []
        for item in inner.split(","):
            items.append(_unquote(item.strip()))
        return items
    return [_unquote(val)]


def _format_rule_entry(rule_id: str, value: str | dict) -> dict | None:
    if isinstance(value, str):
        return {"severity": value}
    if not isinstance(value, dict):
        return None

    entry: dict = {}
    for key in ("severity", "pattern", "message", "languages", "paths"):
        if key in value:
            entry[key] = value[key]
    return entry


def format_config(raw: dict) -> dict:
    """Format parsed YAML into config mode output."""
    output: dict = {}

    if "strictness" in raw:
        output["strictness"] = raw["strictness"]

    rules = raw.get("rules", {})
    formatted_rules: dict = {}

    for rule_id, value in rules.items():
        entry = _format_rule_entry(rule_id, value)
        if entry is not None:
            formatted_rules[rule_id] = entry

    if formatted_rules:
        output["rules"] = formatted_rules

    return output


def format_rules(raw: dict) -> dict:
    """Format parsed YAML into rules mode output (directory overrides)."""
    rules = raw.get("rules", {})
    formatted = {}

    for rule_id, value in rules.items():
        if isinstance(value, str):
            formatted[rule_id] = value
        elif isinstance(value, dict) and "severity" in value:
            formatted[rule_id] = value["severity"]

    return {"rules": formatted} if formatted else {}


def parse_yaml(file_path: str) -> dict:
    """Parse YAML file, trying PyYAML first, falling back to line parser."""
    try:
        return parse_with_pyyaml(file_path)
    except ImportError:
        return parse_line_by_line(file_path)
    except Exception as e:
        # PyYAML parse error — try fallback
        print(
            f"[yaml-parser] WARNING: PyYAML failed: {e}, trying fallback",
            file=sys.stderr,
        )
        try:
            return parse_line_by_line(file_path)
        except Exception as e2:
            print(
                f"[yaml-parser] WARNING: Fallback also failed: {e2}",
                file=sys.stderr,
            )
            return {}


def _parse_and_format(file_path: str, mode: str) -> dict | None:
    try:
        raw = parse_yaml(file_path)
    except Exception as e:
        print(f"[yaml-parser] WARNING: {e}", file=sys.stderr)
        return None

    if mode == "config":
        return format_config(raw)
    if mode == "rules":
        return format_rules(raw)

    print(f"[yaml-parser] WARNING: Unknown mode '{mode}'", file=sys.stderr)
    return None


def main() -> None:
    if len(sys.argv) < 3:
        print(
            "Usage: yaml-parser.py <file_path> <mode:config|rules>",
            file=sys.stderr,
        )
        print("{}")
        sys.exit(0)

    file_path = sys.argv[1]
    mode = sys.argv[2]

    if not os.path.isfile(file_path):
        print("{}")
        sys.exit(0)

    output = _parse_and_format(file_path, mode)
    print(json.dumps(output if output is not None else {}))


if __name__ == "__main__":
    main()
