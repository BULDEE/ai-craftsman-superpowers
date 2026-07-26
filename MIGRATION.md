# Major Version Migration Guide

Breaking changes only. Minor/patch upgrades never require manual action - see [CHANGELOG.md](CHANGELOG.md) for the full history.

## 4.1.x → 4.2.0

**What changes:** the optional knowledge-rag MCP server (Ollama + local vector store) is removed ([ADR-0024](docs/adr/0024-okf-knowledge-bundle.md)). The plugin's knowledge is now an [OKF v0.2](https://github.com/GoogleCloudPlatform/knowledge-catalog) bundle with a deterministic rule-to-concept lookup.

**Action required:**
- If you used `/craftsman:knowledge` and the RAG server: they no longer exist. Your indexed documents in `~/.claude/ai-craftsman-superpowers/knowledge/` are untouched plain files; point your own memory tooling (Obsidian, claude-mem, any MCP knowledge source) at them. The 4.1.x line retains the server.
- Everyone else: nothing. Installations get faster (no Node MCP process, no 115 MB install) and `/craftsman:healthcheck` no longer reports Ollama.

## 3.x → 4.0.0

**What changes:** v4 is a clean break to a native-first architecture (full rationale in [docs/v4-roadmap.md](docs/v4-roadmap.md) and ADRs 0016-0023). No backward compatibility with 3.x config or older Claude Code versions.

**Requirements:**
- Claude Code **>= 2.1.218** (`claude --version` to check). Older versions must stay on the 3.9.x line, which remains available and frozen.

**Breaking changes:**
- `commands/*.md` are removed; every workflow is now a skill (`skills/<name>/SKILL.md`). User-facing invocations are unchanged: `/craftsman:design`, `/craftsman:challenge`, etc. keep working. Anything that referenced plugin command file paths directly must point at the skill paths instead.
- `output-styles/` is removed; the plugin activates its main-thread agent via plugin `settings.json`.
- The bash agent-hook wrappers (`agent-ddd-verifier.sh`, `agent-sentry-context.sh`, `agent-final-review.sh`, `subagent-quality-gate.sh`) are replaced by native `agent`/`prompt` hooks. If you disabled them via `agent_hooks: false`, that option still works and now costs nothing when off.
- `.craft-config.yml` gains a `v: 4` marker plus new `context_budget` and `hooks.disabled` keys, validated by a JSON schema. Run `/craftsman:setup` after upgrading: it migrates a 3.x config in place and shows you what it inferred. A 3.x config without `v: 4` is reported by `/craftsman:healthcheck` but not silently interpreted.
- The metrics database moves from `~/.claude/plugins/data/craftsman/` to `${CLAUDE_PLUGIN_DATA}`. Migration is automatic on first run (the old file is copied, never deleted).

**New after upgrade:** LSP-backed Level 1.5 validation (activates only if your language server is already installed), learned-skill promotion with human review in `/craftsman:metrics`, setup by observation (generated project-conventions skill and codemap), `asyncRewake` test-failure wake-ups, and a `TaskCompleted` evidence gate following your `strictness` setting.

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
