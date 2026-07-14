# Major Version Migration Guide

Breaking changes only. Minor/patch upgrades never require manual action - see [CHANGELOG.md](CHANGELOG.md) for the full history.

## 2.x / 3.x → 3.7.0 (current)

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
