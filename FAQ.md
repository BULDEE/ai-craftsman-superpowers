# FAQ

**Does this replace Superpowers / other Claude Code plugins?**
No. Craftsman handles domain-specific quality enforcement (DDD rules, architecture validation, correction learning). Superpowers handles workflow orchestration (brainstorming, planning, TDD loops). They're designed to run together - see [Using with Superpowers Plugin](README.md#using-with-superpowers-plugin).

**Will this slow down every Write/Edit?**
Level 1 (regex) is always on; its cost is measured, not asserted: `bash tests/perf/test-hook-latency.sh --report` prints the median per hook (hundreds of milliseconds per write on a laptop, most of it process spawn). Level 2/3 (PHPStan, ESLint, deptrac) run only if the tools are installed and trusted, under a budget of 15s per file and 30s per project (`CRAFTSMAN_SA_BUDGET_FILE`, `CRAFTSMAN_SA_BUDGET_PROJECT`). Headless Haiku verification is the only meaningfully-costed layer - see [Cost and Privacy](README.md#cost-and-privacy) - and is optional via `agent_hooks: false` (from 4.10.0; before that the option never reached the hooks), or per-session via `CRAFTSMAN_HOOK_PROFILE=minimal` (see [Hook Profiles](docs/reference/hooks.md#hook-profiles-v380)).

**Can I use this without PHP/Symfony or React?**
Yes. Every shipped pack that owns a language judges its own files on every project, whatever the `stack` setting says: PHP, TypeScript and JavaScript, Python, Go, Rust and Bash. There is no shipped pack to switch on. The methodology commands (`design`, `debug`, `plan`, `challenge`, `verify`, `refactor`, `legacy`, `test`, `git`) are language-agnostic.

**I write PHP without Symfony (Slim, Laravel, plain PHP). Does it push Symfony patterns on me?**
Not in the rules that block. The PHP craft rules are not framework rules: `declare(strict_types=1)`, `final` classes, no public setters, an injected clock instead of `new DateTime()`, no empty `catch`. They apply the same way on Slim, Laravel or plain PHP. The layer rules (LAYER001 to LAYER004) read your root namespace from the psr-4 map of your `composer.json`, not a hardcoded `App\`, and they only fire on code that lives in a Domain or Application layer, by path or by namespace. The PHP pack still carries the name `symfony` for historical reasons, and part of it is Symfony-specific: the knowledge, the `backend-craftsman`, `symfony-reviewer` and `api-craftsman` agents, and the scaffold templates. Two rule behaviours know Doctrine. An entity carrying the `ORM\Entity` attribute or annotation is exempt from `final`, because the ORM subclasses it. The controller-persistence check (CTRL001, a warning) recognises Doctrine calls only (`EntityManagerInterface`, `persist`, `flush`, `getRepository`), so it stays silent on Eloquent, and its message suggests an Application use case. The `stack` setting labels the setup and the exported doctrine; it switches no shipped pack's rule on or off. A third-party pack that declares its own stack list is still filtered by it.

**Do I need to run `/craftsman:verify` before pushing?**
The `pre-push-verify.sh` hook warns (does not block) `git push` when verification hasn't run in the session, encouraging evidence-based completion claims over "should work" assumptions. It's warning-only by design so it never blocks trivial changes (docs, config) - see [Troubleshooting](TROUBLESHOOTING.md).

**Does anything leave my machine?**
Only if you opt in. Edited file content goes to the Anthropic API only when `agent_hooks: true` (the default). Sentry lookups only happen if you configure `sentry_org`/`sentry_project`. Metrics are always local (SQLite). Full breakdown in [SECURITY.md](SECURITY.md#data--network-transparency).

**How is this different from just writing a good CLAUDE.md?**
A CLAUDE.md is instructions Claude can choose to follow. This plugin's Level 1/2/3 validation hooks and blocking exit codes make certain violations impossible to skip, not just discouraged. See [Why Craftsman?](README.md#why-craftsman---6-core-differentiators).

**Can I customize which rules apply to legacy code?**
Yes - the rules engine supports 3-level inheritance (Global → Project → Directory), so you can relax rules for a legacy directory while keeping strict enforcement on new code. See the Custom Rule Engine section in [README.md](README.md).

**Can I use this with Hermes agents instead of Claude Code?**
Yes, the repository is itself a native Hermes plugin: `git clone https://github.com/BULDEE/ai-craftsman-superpowers ~/.hermes/plugins/craftsman && hermes plugins enable craftsman`. The agent gets the same gate, the learning loop and seven craftsman skills. See the [Hermes quickstart](docs/guides/hermes-quickstart.md).

**I'm not a developer - what does this actually buy my team?**
An automatic inspector that refuses badly structured AI-written code before it lands, with the same rules on laptops and in the pipeline, and a learning loop that adapts to your project's real failure modes. Plain-language explanation: [For non-developers](docs/guides/for-non-developers.md).

**Upgrading and something broke - what do I do?**
Check [MIGRATION.md](MIGRATION.md) for known breaking changes between major versions, then [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common fixes.
