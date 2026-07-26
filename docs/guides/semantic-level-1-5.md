# Level 1.5: LSP-Backed Semantic Validation

> v4.0.0 feature. Decision record: [ADR-0019](../adr/0019-established-tooling-first.md).

The quality gate has always had three levels: regex (Level 1, always on), static analysis (Level 2, PHPStan/ESLint when installed), architecture (Level 3, deptrac/dependency-cruiser when installed). v4 inserts **Level 1.5**: real-time code intelligence from a Language Server, giving Claude live diagnostics, type information, and reference navigation while it edits.

## How it activates

The plugin ships an `.lsp.json` configuration for PHP ([intelephense](https://intelephense.com/)). Claude Code starts the server automatically **only if the binary is already installed** on your machine. The plugin never installs, bundles, or updates a language server: your toolchain stays yours (see the [established-tooling-first policy](../adr/0019-established-tooling-first.md)).

| Stack | Server | How to get it |
|-------|--------|---------------|
| PHP | intelephense | `npm install -g intelephense` (plugin ships the `.lsp.json`) |
| TypeScript | typescript-language-server | Official LSP plugin from `claude-plugins-official` |
| Python | pyright | Official LSP plugin from `claude-plugins-official` |
| Rust | rust-analyzer | Official LSP plugin from `claude-plugins-official` |

For TypeScript, Python, and Rust, install Anthropic's official LSP plugins rather than duplicating them here: same capability, maintained upstream.

## What each level catches

| Level | Mechanism | Catches | Latency |
|-------|-----------|---------|---------|
| 1 | Regex hooks | strict_types, final, any, setters | <50ms |
| 1.5 | Language server | type errors, undefined symbols, dead references, signature mismatches | live |
| 2 | PHPStan / ESLint | rule-based static analysis | <2s |
| 3 | deptrac / dependency-cruiser | layer dependency violations | <2s |

## Checking your status

Run `/craftsman:healthcheck`: the `lsp` line reports which servers are detected and what installing one would unlock. No server installed means Level 1.5 is inactive; everything else keeps working (graceful degradation, as with Levels 2 and 3).
