#!/usr/bin/env python3
"""
YAML parser for AI Craftsman Superpowers rules engine.

Replaces the 250+ line bash YAML parser with a robust Python implementation.
Supports two modes:
  - "config": Full .craft-config.yml parsing (strictness + rules)
  - "rules":  Directory .craft-rules.yml parsing (rules section only)

Outputs JSON to stdout. Graceful degradation: works without PyYAML.
"""

import json
import os
import re
import sys


def parse_with_pyyaml(file_path):
    """Parse YAML using PyYAML (preferred)."""
    import yaml
    with open(file_path, "r") as f:
        return yaml.safe_load(f) or {}


def parse_line_by_line(file_path):
    """Fallback line-by-line parser when PyYAML is not available.

    Handles:
    - Top-level scalar keys (strictness, version, stack)
    - rules section with short-form (PHP001: block) and long-form entries
    - Quoted strings, backslash escapes
    - Inline arrays [php, typescript]
    - Comments and blank lines
    """
    result = {}
    rules = {}
    in_rules = False
    current_rule = None
    current_rule_props = {}

    with open(file_path, "r") as f:
        for raw_line in f:
            line = raw_line.rstrip("\n\r")

            # Skip empty lines and comments
            stripped = line.lstrip()
            if not stripped or stripped.startswith("#"):
                continue

            indent = len(line) - len(stripped)

            # Top-level key (no indentation)
            if indent == 0:
                # Flush current rule if any
                if current_rule and current_rule_props:
                    rules[current_rule] = current_rule_props
                    current_rule = None
                    current_rule_props = {}

                if stripped.startswith("rules:"):
                    in_rules = True
                    continue

                in_rules = False
                m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):\s+(.+)$', stripped)
                if m:
                    result[m.group(1)] = _unquote(m.group(2))
                continue

            if not in_rules:
                continue

            # Inside rules section
            # Sub-property of current long-form rule (indent >= 4, checked first)
            if current_rule and indent >= 4:
                m_prop = re.match(r'^([a-z_]+):\s+(.+)$', stripped)
                if m_prop:
                    key = m_prop.group(1)
                    val = m_prop.group(2)

                    if key == "languages":
                        current_rule_props[key] = _parse_inline_array(val)
                    elif key in ("pattern", "message"):
                        current_rule_props[key] = _unescape_yaml_string(
                            _unquote(val)
                        )
                    elif key == "severity":
                        current_rule_props[key] = _unquote(val)
                    elif key == "paths":
                        current_rule_props[key] = _parse_inline_array(val)
                    else:
                        current_rule_props[key] = _unquote(val)
                continue

            # Rule entry (indent 2 — new rule definition)
            m_short = re.match(
                r'^([A-Za-z_][A-Za-z0-9_]*):\s+(block|warn|ignore)\s*$',
                stripped,
            )
            m_long = re.match(
                r'^([A-Za-z_][A-Za-z0-9_]*):\s*$',
                stripped,
            )

            if m_short:
                # Flush previous rule
                if current_rule and current_rule_props:
                    rules[current_rule] = current_rule_props
                current_rule = None
                current_rule_props = {}
                rules[m_short.group(1)] = m_short.group(2)
            elif m_long:
                # Flush previous rule
                if current_rule and current_rule_props:
                    rules[current_rule] = current_rule_props
                current_rule = m_long.group(1)
                current_rule_props = {}

    # Flush last rule
    if current_rule and current_rule_props:
        rules[current_rule] = current_rule_props

    if rules:
        result["rules"] = rules

    return result


def _unquote(val):
    """Strip surrounding quotes from a YAML value."""
    val = val.strip()
    if len(val) >= 2:
        if (val[0] == '"' and val[-1] == '"') or (
            val[0] == "'" and val[-1] == "'"
        ):
            return val[1:-1]
    return val


def _unescape_yaml_string(val):
    r"""Un-escape YAML double-quote sequences: \\ -> \, \n -> newline, etc."""
    # Only unescape double-backslash to single-backslash
    return val.replace("\\\\", "\\")


def _parse_inline_array(val):
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


def format_config(raw):
    """Format parsed YAML into config mode output."""
    output = {}

    if "strictness" in raw:
        output["strictness"] = raw["strictness"]

    rules = raw.get("rules", {})
    formatted_rules = {}

    for rule_id, value in rules.items():
        if isinstance(value, str):
            # Short form: "PHP001: block"
            formatted_rules[rule_id] = {"severity": value}
        elif isinstance(value, dict):
            # Long form: custom rule with pattern, message, etc.
            entry = {}
            if "severity" in value:
                entry["severity"] = value["severity"]
            if "pattern" in value:
                entry["pattern"] = value["pattern"]
            if "message" in value:
                entry["message"] = value["message"]
            if "languages" in value:
                entry["languages"] = value["languages"]
            if "paths" in value:
                entry["paths"] = value["paths"]
            formatted_rules[rule_id] = entry

    if formatted_rules:
        output["rules"] = formatted_rules

    return output


def format_rules(raw):
    """Format parsed YAML into rules mode output (directory overrides)."""
    rules = raw.get("rules", {})
    formatted = {}

    for rule_id, value in rules.items():
        if isinstance(value, str):
            formatted[rule_id] = value
        elif isinstance(value, dict) and "severity" in value:
            formatted[rule_id] = value["severity"]

    return {"rules": formatted} if formatted else {}


def parse_yaml(file_path):
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


def main():
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

    try:
        raw = parse_yaml(file_path)
    except Exception as e:
        print(f"[yaml-parser] WARNING: {e}", file=sys.stderr)
        print("{}")
        sys.exit(0)

    if mode == "config":
        output = format_config(raw)
    elif mode == "rules":
        output = format_rules(raw)
    else:
        print(
            f"[yaml-parser] WARNING: Unknown mode '{mode}'", file=sys.stderr
        )
        print("{}")
        sys.exit(0)

    print(json.dumps(output))


if __name__ == "__main__":
    main()
