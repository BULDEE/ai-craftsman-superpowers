# Level 1.5: LSP-Backed Semantic Validation

> v4.0.0 feature. Decision record: [ADR-0019](../adr/0019-established-tooling-first.md).

The quality gate has always had three levels: regex (Level 1, always on), static analysis (Level 2, PHPStan/ESLint when installed), architecture (Level 3, deptrac/dependency-cruiser when installed). v4 inserts **Level 1.5**: real-time code intelligence from a Language Server, giving Claude live diagnostics, type information, and reference navigation while it edits.

## How it activates

Level 1.5 is wired through Anthropic's official per-language LSP plugins (`claude-plugins-official`), never through this plugin. Install the LSP plugin for your stack from the `/plugin` Discover tab, plus its server binary. The plugin never installs, bundles, or declares a language server itself: your toolchain stays yours (see the [established-tooling-first policy](../adr/0019-established-tooling-first.md), amended 2026-07-29).

| Stack | Server | How to get it |
|-------|--------|---------------|
| PHP | intelephense | `php-lsp` official plugin + `npm install -g intelephense` |
| TypeScript | typescript-language-server | `typescript-lsp` official plugin |
| Python | pyright | `pyright-lsp` official plugin |
| Rust | rust-analyzer | `rust-analyzer-lsp` official plugin |

> Until 4.3.0 the plugin shipped its own `.lsp.json` for PHP, assuming Claude Code would skip the server when the binary was absent. It does not: Claude Code spawns the declared command unconditionally and reports `Command failed with ENOENT: intelephense --stdio` in the `/plugin` Errors tab on every machine without intelephense. 4.3.1 removed the file; the official `php-lsp` plugin covers the same capability as an explicit opt-in.

## What each level catches

| Level | Mechanism | Catches | Latency |
|-------|-----------|---------|---------|
| 1 | Regex hooks | strict_types, final, any, setters | <50ms |
| 1.5 | Language server | type errors, undefined symbols, dead references, signature mismatches | live |
| 2 | PHPStan / ESLint | rule-based static analysis | <2s |
| 3 | deptrac / dependency-cruiser | layer dependency violations | <2s |

## Checking your status

Run `/craftsman:healthcheck`: the `lsp` line reports which servers are detected and what installing one would unlock. No server installed means Level 1.5 is inactive; everything else keeps working (graceful degradation, as with Levels 2 and 3).
