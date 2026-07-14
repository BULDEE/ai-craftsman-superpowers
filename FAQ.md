# FAQ

**Does this replace Superpowers / other Claude Code plugins?**
No. Craftsman handles domain-specific quality enforcement (DDD rules, architecture validation, correction learning). Superpowers handles workflow orchestration (brainstorming, planning, TDD loops). They're designed to run together - see [Using with Superpowers Plugin](README.md#using-with-superpowers-plugin).

**Will this slow down every Write/Edit?**
Level 1 (regex) runs in <50ms and is always on. Level 2/3 (PHPStan, ESLint, deptrac) run only if the tools are installed, in <2s. Agent hooks (Haiku semantic analysis) are the only meaningfully-costed layer - see [API Cost Model](README.md#api-cost-model) - and are fully optional via `agent_hooks: false`, or per-session via `CRAFTSMAN_HOOK_PROFILE=minimal` (see [Hook Profiles](docs/reference/hooks.md#hook-profiles-v380)).

**Can I use this without PHP/Symfony or React?**
Yes. Core methodology commands (`design`, `debug`, `plan`, `challenge`, `verify`, `refactor`, `legacy`, `test`, `git`) are language-agnostic. Language-specific rule enforcement (Level 1 regex, scaffolders) only activates for the packs you enable.

**Do I need to run `/craftsman:verify` before pushing?**
The `pre-push-verify.sh` hook warns (does not block) `git push` when verification hasn't run in the session, encouraging evidence-based completion claims over "should work" assumptions. It's warning-only by design so it never blocks trivial changes (docs, config) - see [Troubleshooting](TROUBLESHOOTING.md).

**Does anything leave my machine?**
Only if you opt in. Edited file content goes to the Anthropic API only when `agent_hooks: true` (the default). Sentry lookups only happen if you configure `sentry_org`/`sentry_project`. Metrics and RAG embeddings are always local (SQLite, Ollama). Full breakdown in [SECURITY.md](SECURITY.md#data--network-transparency).

**How is this different from just writing a good CLAUDE.md?**
A CLAUDE.md is instructions Claude can choose to follow. This plugin's Level 1/2/3 validation hooks and blocking exit codes make certain violations impossible to skip, not just discouraged. See [Why Craftsman?](README.md#why-craftsman---6-core-differentiators).

**Can I customize which rules apply to legacy code?**
Yes - the rules engine supports 3-level inheritance (Global → Project → Directory), so you can relax rules for a legacy directory while keeping strict enforcement on new code. See the Custom Rule Engine section in [README.md](README.md).

**Upgrading and something broke - what do I do?**
Check [MIGRATION.md](MIGRATION.md) for known breaking changes between major versions, then [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common fixes.
