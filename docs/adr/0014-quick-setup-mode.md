# ADR-0014: Quick Setup Mode

## Status

Accepted

## Date

2026-04-05

## Context

Competitor analysis showed that zero-config onboarding is a significant adoption advantage. Claude Buddy v5 installs in 3 commands with no questions asked. Our `/craftsman:setup` wizard has 7 interactive steps (name, DISC, biases, packs, versions, config, summary), creating friction for first-time users.

The full setup remains valuable for customization, but we need a fast path.

## Decision

Add `--quick` flag to `/craftsman:setup` that:

1. Auto-detects stack from `composer.json` / `package.json`
2. Extracts user name from `git config user.name`
3. Applies smart defaults (strict mode, all biases, standard DDD paths)
4. Generates `.craft-config.yml` without any `AskUserQuestion` calls
5. Protects existing config (requires `--force` to overwrite)

### Why Modify Existing Command?

- Single command, two modes (consistent UX)
- Avoids command proliferation
- `--quick` is a standard CLI convention

### Why These Defaults?

- **strict mode:** Better to start strict and relax than start loose and tighten
- **All biases ON:** The bias detector is non-blocking (warnings only), so enabling all has no downside
- **Empty DISC:** DISC is personal — better to skip than guess
- **Standard DDD paths:** `src/Domain`, `src/Application`, etc. — the most common convention

## Consequences

### Positive
- 30-second onboarding (install plugin, run `/craftsman:setup --quick`, done)
- Competitive with zero-config plugins
- Full setup still available for power users

### Negative
- DISC profile empty until user runs full setup (acceptable — it's optional)
- ai-ml pack not auto-enabled (requires explicit opt-in)

## References

- Competitor analysis: Claude Buddy v5 zero-config approach
- [ADR-0012: Progressive Disclosure](0012-progressive-disclosure.md)
