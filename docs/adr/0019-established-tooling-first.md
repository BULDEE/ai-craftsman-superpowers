# ADR-0019: Established Tooling First - The Plugin Orchestrates, Never Substitutes

## Status

Accepted (amended 2026-07-29: LSP bullet revised, see Amendment)

## Date

2026-07-26

## Context

v4.0.0 introduces semantic code intelligence (LSP-backed "Level 1.5" validation between the regex gate and static analysis). This raised the question of whether the plugin should bundle or install language servers, formatters, or analyzers itself.

The plugin's existing quality-gate philosophy already answers this for Levels 2 and 3: PHPStan, ESLint, deptrac, and dependency-cruiser are detected if installed and skipped if not. Users own their toolchain; the plugin adapts to it. Bundling tools would create version conflicts with project-pinned versions, bloat the plugin, and put us in the business of maintaining tool distributions.

## Decision

The plugin relies on each stack's established tooling and never substitutes for it. Concretely:

- **LSP** (amended, see below): ship no LSP declaration at all. Documentation points users to the official per-language LSP plugins in `claude-plugins-official` (php-lsp, typescript-lsp, pyright-lsp, rust-analyzer-lsp); the user installs the plugin and the server binary as an explicit opt-in. The plugin never downloads, installs, or vendors a language server.
- **Static analysis and architecture tools**: unchanged Level 2/3 behavior - detect, use, degrade gracefully.
- **Formatters, test runners, package managers**: always the project's own (`vendor/bin/phpunit`, project ESLint config, etc.). The plugin invokes them; it never replaces or reconfigures them.
- **Selection rule**: when the plugin needs a capability, prefer in order: (1) the tool the project already uses, (2) the community-standard tool for the stack if the user opts in, (3) nothing - degrade the check rather than impose a dependency.

## Consequences

### Positive

- No version conflicts with project toolchains; no plugin-side tool maintenance.
- Zero-install baseline preserved: Level 1 regex still works with nothing installed.
- Respects team decisions: a project's PHPStan level, ESLint config, and language server are authoritative.

### Negative

- Out-of-the-box capability varies by machine: a user without a language server gets no Level 1.5 until they install one.
- Documentation must explain per-stack setup instead of "it just works".

### Neutral

- `/craftsman:healthcheck` reports which levels are active and what installing would unlock, making the degradation visible instead of silent.

## Alternatives Considered

### Alternative 1: Bundle language servers with the plugin

Rejected: licensing complexity (e.g. freemium servers), platform-specific binaries, version drift against project expectations, and plugin size.

### Alternative 2: Auto-install missing tools on first run

Rejected: mutating the user's environment without an explicit request violates the trust contract of a quality plugin, and package-manager side effects are hard to reverse.

## Amendment (2026-07-29)

The original LSP decision shipped an `.lsp.json` for PHP (intelephense) on the assumption that Claude Code activates a declared server only when its binary is already installed. That assumption is false: Claude Code spawns the declared `command` unconditionally (the plugins reference states it "must be in PATH", and no field makes a declaration optional), so every machine without intelephense showed `Command failed with ENOENT: intelephense --stdio` in the `/plugin` Errors tab. This broke the graceful-degradation contract the rest of this ADR defends.

Two facts settled the revision:

1. A missing binary is a surfaced plugin error, not a silent skip - there is no graceful path for a bundled `.lsp.json`.
2. `claude-plugins-official` now ships `php-lsp` with the exact same intelephense configuration, closing the gap that justified bundling one here.

Decision revised: the plugin ships no `.lsp.json` and declares no `lspServers` in its manifest. `tests/core/test-lsp-policy.sh` enforces this. Removed in 4.3.1.

## References

- ADR-0016 (v4 clean break)
- Quality gate levels: README "Real-Time Quality Gate" differentiator
- LSP plugins: https://code.claude.com/docs/en/plugins-reference#lsp-servers
