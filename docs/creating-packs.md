# Creating Packs for AI Craftsman Superpowers

This guide explains how to create a language or framework pack for the AI Craftsman Superpowers plugin.

## What is a Pack?

A pack extends the core craftsman methodology with language-specific rules, validators, agents, templates, and knowledge. The core provides DDD, Clean Architecture, and TDD methodology. Packs provide the concrete implementation patterns for your stack.

## Quick Start

```bash
/craftsman:scaffold pack my-pack-name
```

This generates the full pack directory structure. Edit `pack.yml` to configure it.

## Pack Structure

```
packs/<name>/
├── pack.yml                    # Pack manifest (required)
├── hooks/
│   └── <name>-validator.sh     # Regex validator for the pack-loader
├── static-analysis/
│   └── <tool>.sh               # Static analysis tool integration
├── commands/
│   └── scaffold-types/         # Scaffold templates
├── agents/
│   └── <name>-craftsman.md     # Pack-specific agents
├── knowledge/
│   └── canonical/              # Canonical code examples (Iron Law)
├── templates/                  # Code generation templates
└── tests/
    └── test-<name>.sh          # Pack test suite
```

## pack.yml Reference

```yaml
name: my-pack                          # Unique pack name (lowercase, no spaces)
version: "1.0.0"                       # Semver
description: "Short description"       # One-line description
compatibility:
  core: ">=2.6.0"                      # Minimum core version required
  stack: ["my-stack"]                  # Compatible stacks, or ["*"] for universal

languages:                             # REQUIRED for a language pack
  - id: my-lang                        # registry key
    extensions: [ml, mli]              # no leading dot
    entry_markers: [my-lang.toml]      # files that say "this project is my-lang"
    protected_configs: [".mylint.yml"] # files that exist only to configure a gate
    validators: ["hooks/my-validator.sh"]
    test_commands: ["my-lang test"]
    lsp: "my-lang-langserver"
    metrics_dialect: c-like            # OPTIONAL, and only c-like or php-like

rules:
  owned:                               # id, wording and default severity
    - id: MYPACK001
      group: MyLang
      text: "what the rule asks for, in one line"
      default_severity: block          # block | warn
  builtin: ["MYPACK001", "MYPACK002"]  # every rule this pack detects
  static_analysis: ["MYSA001"]         # SA rule IDs

hooks:
  validators: ["hooks/my-validator.sh"] # Validator scripts to source

static_analysis:
  tools: ["static-analysis/my-tool.sh"] # SA tool scripts

commands:
  scaffold_types: ["my-type"]          # Scaffold types this pack provides

agents: ["agents/my-agent.md"]         # Agent definitions

knowledge: ["knowledge/"]             # Knowledge directories to include

templates: ["templates/"]             # Template directories
```

## Writing a Validator

Validators are bash scripts that define a `pack_validate_<lang>()` function. The pack-loader sources your script and calls this function for each file of the matching language.

### Available Helper Functions

Your validator receives these functions from the orchestrator:

| Function | Purpose |
|----------|---------|
| `add_violation "RULE_ID" "message"` | Report a blocking violation |
| `add_warning "RULE_ID" "message"` | Report a non-blocking warning |
| `line_has_ignore "$line" "ignore-tag"` | Check if a line has `craftsman-ignore: <tag>` |
| `metrics_record_violation ...` | Record in metrics DB (optional) |

### Naming Conventions for Rule IDs

Use a unique prefix to avoid collisions with other packs:

| Pack | Prefix | Example |
|------|--------|---------|
| symfony | PHP, LAYER, PHPSTAN, DEPTRAC | PHP001, LAYER001 |
| react | TS, ESLINT | TS001, ESLINT001 |
| go | GO | GO001 |
| rust | RUST | RUST001 |
| python | PY | PY001 |

Warnings use the `WARN-` prefix: `WARN-GO001`, `WARN-PY001`.

### Validator Template

```bash
#!/usr/bin/env bash
pack_validate_<lang>() {
    local file="$1"

    # MYPACK001: Description
    if grep -q "bad_pattern" "$file" 2>/dev/null; then
        add_violation "MYPACK001" "Descriptive error message"
    fi

    # WARN-MYPACK001: Soft rule
    if grep -q "questionable_pattern" "$file" 2>/dev/null; then
        add_warning "WARN-MYPACK001" "Consider improving this pattern"
    fi
}
```

### Rules

- **Never use `exit 1`** - validators must use `exit 0` (pass) or `exit 2` (block)
- Always redirect stderr: `2>/dev/null` on grep/sed calls
- Use `line_has_ignore` to respect `craftsman-ignore` comments
- Keep validators fast (<50ms per file) - regex only, no external tool calls
- Static analysis tools (eslint, phpstan, clippy) go in `static-analysis/`, not validators

## Writing Agents

Pack agents are Markdown files with YAML frontmatter:

```markdown
---
name: my-craftsman
model: sonnet
allowedTools: [Read, Glob, Grep, Bash, Agent]
---

# My Pack Craftsman

You are a senior {language} craftsman...
```

**Required:** Always define `allowedTools` to restrict agent permissions.

## External Packs

Users can load packs from outside the plugin directory via `.craft-config.yml`:

```yaml
packs:
  external:
    - path: "~/.claude/packs/go"
    - path: "/absolute/path/to/my-pack"
```

## Validation

Before distributing, validate your pack:

```bash
bash scripts/validate-pack.sh packs/my-pack/

# Check for rule ID collisions with existing packs:
bash scripts/validate-pack.sh packs/my-pack/ --check-collisions packs/
```

## Testing

Every pack should have a test suite at `tests/test-<name>.sh` following this pattern:

```bash
#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(dirname "$SCRIPT_DIR")"
TESTS_PASSED=0; TESTS_FAILED=0

log_pass() { echo "  ✓ $1"; ((TESTS_PASSED++)); }
log_fail() { echo "  ✗ $1 - $2"; ((TESTS_FAILED++)); }

# Source your validator
source "$PACK_DIR/hooks/my-validator.sh"

# Provide mock helpers
VIOLATIONS=""
add_violation() { VIOLATIONS="${VIOLATIONS}$1:$2\n"; }
add_warning() { VIOLATIONS="${VIOLATIONS}WARN:$1:$2\n"; }
line_has_ignore() { return 1; }
metrics_record_violation() { true; }

# Write your tests...

echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
```

## The `languages:` block is not optional

The engine holds no list of languages. `hooks/lib/lang-registry.sh` compiles
every loaded `pack.yml` into the registry that the hooks and `craftsman-ci.sh`
both read, so a pack without a `languages:` entry declaring its extensions is
loaded, sourced, and never called: no file ever dispatches to its validator.
That is the single most common reason a new pack appears to do nothing.

### On `metrics_dialect`

Declaring it gives you NEST001, LOC001, GOD001 and PARAM001 for free, from
`hooks/lib/structural_metrics.py`. It accepts `c-like` and `php-like` and
nothing else, and both mean brace-delimited with `function` as the keyword and
parenthesised control heads.

Check before you declare. Go and Rust are brace-delimited yet match neither:
they write `func`/`fn` and `if x > 0 {`, so the extractor finds no function and
no control block and reports every file clean. A dialect that silently measures
nothing is worse than none, because the structural ratchet then guards a signal
that is absent. Declare none and emit the four rules from your own detector
instead: `packs/go/hooks/go_structure.py` and `packs/python` both do this.

## Examples

`packs/go/` is the smallest complete pack: one manifest, two validators, a
Python structure scanner, a canonical example and a test file covering one
passing and one failing fixture per rule. Copy that.

`packs/symfony/` is the most complete, with agents, templates and static
analysis wired in.

`examples/pack-skeleton-rust/` is the last remaining skeleton, for a language
with no shipped pack yet. The rule is simple and applies to every skeleton: a
skeleton exists to be promoted, and it is deleted when its pack ships. Keeping
both means maintaining a second manifest that nothing loads, which is how the
Go and Python skeletons came to teach a `pack.yml` with no `languages:` block
months after the engine stopped dispatching without one.
