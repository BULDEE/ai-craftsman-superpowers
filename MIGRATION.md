# Major Version Migration Guide

Breaking changes only. Minor/patch upgrades never require manual action - see [CHANGELOG.md](CHANGELOG.md) for the full history.

## 3.x → 4.0.0

**What changes:** v4 is a clean break to a native-first architecture, with security hardening against untrusted repositories. Full rationale in ADRs 0016-0027. No backward compatibility with 3.x config or older Claude Code versions.

**Requirements:**
- Claude Code **>= 2.1.218** (`claude --version` to check). Older versions must stay on the 3.9.x line, which remains available and frozen.

**Breaking changes:**
- `commands/*.md` are removed; every workflow is now a skill (`skills/<name>/SKILL.md`). User-facing invocations are unchanged: `/craftsman:design`, `/craftsman:challenge`, and the rest keep working. Anything referencing plugin command file paths must point at the skill paths instead.
- `output-styles/` is removed; the plugin activates its main-thread agent via plugin `settings.json`.
- The bash agent-hook wrappers are replaced by headless Haiku verification. If you disabled them with `agent_hooks: false`, that still works and now costs nothing when off.
- **Level 2 static analysis (PHPStan, ESLint, deptrac, dependency-cruiser) no longer runs by default.** It executes the tools a project ships and the configs they auto-discover, which is running the repository's code. To re-enable it for every project on your machine, add `trust_project_tools: true` to your own `~/.claude/.craft-config.yml`. A project file cannot grant it. Levels 1, 1.5 and 3, the rules engine, the security rules, and the ratchet are unaffected.
- **External packs are declared in your global config only.** `packs.external[].path` in a project `.craft-config.yml` is ignored, because those packs are sourced as shell code. Move any declaration to `~/.claude/.craft-config.yml`.
- The `knowledge-rag` MCP server and `/craftsman:knowledge` are removed. Indexed documents under `~/.claude/ai-craftsman-superpowers/knowledge/` are untouched plain files; point your own memory tooling at them.
- `.craft-config.yml` gains a `v: 4` marker plus `context_budget`, `hooks.disabled`, `guided`, and `trust_project_tools`, validated by a JSON schema. Run `/craftsman:setup` after upgrading: it migrates a 3.x config in place and shows what it inferred.
- The metrics database moves to `${CLAUDE_PLUGIN_DATA}`. Migration is automatic on first run (the old file is copied, never deleted).

**Optional after upgrading:**
- The structural ratchet is inert until you opt in. Run `/craftsman:setup`, or `python3 "${CLAUDE_PLUGIN_ROOT}/hooks/lib/ratchet.py" init src --baseline .craftsman-baseline.json`, then commit `.craftsman-baseline.json` so CI and teammates measure against the same reference. `RATCHET001` ships advisory; set it to `block` to enforce.

## 2.x / 3.x → 3.7.0

No breaking changes since 3.0.0. Safe to upgrade directly.

## 2.x → 3.0.0

**What changed:** the plugin shifted from passive (you invoke commands) to proactive (a routing table is injected at session start and Claude proposes the right `/craftsman:*` command when context matches).

**Action required:**
- If your project config used the `ai` pack key, rename it to `ai-ml` (matches the pack directory name). The setup template migrated automatically for new installs; existing `.craft-config.yml` files with `packs: "ai,..."` must be edited manually to `packs: "ai-ml,..."`.
- The knowledge-rag SQLite schema auto-migrates on first run (adds `file_hash`/`file_size` columns to the `sources` table) - no manual action needed.
- New commands available post-upgrade: `/craftsman:healthcheck`, `/craftsman:knowledge`.

## 1.x → 2.0.0

**What changed:** introduction of the Teams system (`/craftsman:team`), CI export (`/craftsman:ci`), and pre-push verification enforcement (`pre-push-verify.sh` blocks `git push` until `/craftsman:verify` has run).

**Action required:**
- If your workflow relies on pushing without running `/craftsman:verify` first, expect `git push` to block after upgrading. Run `/craftsman:verify` before pushing, or disable the hook if it doesn't fit your workflow (see [Troubleshooting](TROUBLESHOOTING.md)).
- No config migration needed - Teams and CI export are additive, opt-in features.

## Reporting a broken upgrade

If an upgrade breaks your setup in a way not covered here, please open an issue with your previous version, target version, and `.craft-config.yml` contents (redact secrets).
