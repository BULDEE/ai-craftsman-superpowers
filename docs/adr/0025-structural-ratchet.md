# ADR-0025: Structural Ratchet - Per-File One-Way Baseline

## Status

Accepted

## Date

2026-07-26

## Context

The plugin's rules engine blocks known-bad patterns (e.g., missing `declare(strict_types=1)`, public setters, use of `any`). But nothing prevents structural debt from accumulating gradually: a function growing by 5 lines per session, import fan-out creeping upward, craftsman-ignore suppressions multiplying. Each write passes the gate alone; the sum is technical debt. Boy-scout principle says "leave code better than you found it," but without a ratchet that tightens on improvement and resists regression, cleanup competes against velocity and loses.

The plugin runs on every write (real-time feedback) and in CI (pipeline enforcement). Metrics must be identical in both places, with zero drift. Commits move forward only; a baseline must support fast merges without conflicts.

## Decision

Implement a structural ratchet as a committed `.craftsman-baseline.json` that acts as a high-water mark:

1. **Baseline format**: one sorted JSON line per file (merge-friendly). Per file: path, complexity (worst-case function branch count), file_lines, max_fn_lines (longest function), fan_out (distinct imports), ignores (craftsman-ignore count).
2. **Metrics and computation**: zero-dependency, single-pass measurement. Complexity counts decision points (if/elif/else, for/foreach/while, case/catch, try, boolean operators, ternaries) in the worst function span; indentation is excluded (formatter noise, not structure). Duplication percentage only when jscpd or phpcpd is declared by the project; null otherwise, never blocks when null.
3. **Policy on touched files**:
   - Post-write-check calls `ratchet check` on each modified file. Regression against baseline: block in strict mode, warn in moderate, silent in relaxed.
   - New file (absent from baseline): baseline entry created from first accepted state. Born clean, stays clean.
   - Untouched files: never evaluated, never block. Directories relaxed via `.craft-rules.yml`: exempt from enforcement.
   - **Automatic tightening**: when a green pass improves a metric, `ratchet update` lowers the high-water mark. Metrics only tighten, never widen.
   - **Loosening is explicit**: requires an inline `craftsman-ignore: RATCHET` comment with a reason. Those ignores are themselves counted, ratcheted, and surfaced in `/craftsman:metrics` and the dashboard, feeding the correction-learning instinct pipeline.
4. **CI parity**: `craftsman-ci` runs the same `ratchet check` on files changed in the PR diff, using the same library code. No CI-side writes to the baseline; enforcement only.
5. **Legacy interplay**: Project init (ADR-0027) asks whether the repository is greenfield or existing. Greenfield: strict from first file. Existing: `ratchet init` photographs the current state as baseline; boy-scout applies from there forward.
6. **Implementation detail**: Both hook and CI call sites capture ratchet check status via explicit `|| VAR=$?` branching because a non-zero status inside a command substitution in bash 3.2 (POSIX sh) triggers the fail-open ERR trap, blocking all writes if not handled.

## Consequences

### Positive

- Debt does not accumulate on any touched file. Improvements are locked in; regressions are caught at write time, not discovered in review.
- New files start debt-free, removing the bootstrap penalty of cleaning up inherited patterns.
- Boy-scout policy applies per file touched: legacy code never blocks modern code unless that file is edited.
- Baseline merges cleanly (one JSON line per file, sorted) in the most common case (non-overlapping file edits).
- Automatic tightening removes the human burden of deciding when metrics are "good enough": if the gate passed, the mark tightens.
- Ratchet ignores are countable and ratchet themselves, surfacing which suppressions accumulate and where, feeding the correction-learning loop.

### Negative

- Regressions are now blocking at write time (instead of review time or not at all). False positives in the metric core erode trust; dogfooding on this repo in warn mode for 2 weeks before flip to block-by-default mitigates this.
- Merge conflicts on `.craftsman-baseline.json` can occur when multiple developers edit the same file in parallel. Conflicts resolve per-line; `ratchet init --repair` rebuilds from the working tree if corruption occurs. This is acceptable at typical development frequencies.
- The ratchet measures approximate cyclomatic complexity without a full AST, so edge cases (macros, DSLs, string-based dispatch) may evade the metric. Measured acceptable: PHP, TypeScript, Python, and Bash v1 languages do not heavily use such patterns.

### Neutral

- ADR-0019 (established tooling first) holds: duplication metrics depend on jscpd or phpcpd being declared, not bundled. When those tools are absent, duplication remains null and does not block.
- Baseline history is not tracked in this ADR; versioning or rollback lives in CHANGELOG and release notes only.

## Alternatives Considered

### Alternative 1: Global repo-wide ratchet

One high-water mark per metric, across the whole repo. Rejected: punishes whoever touches legacy code first, blocks legitimate refactors, and violates the boy-scout principle (you clean your file, not the whole codebase).

### Alternative 2: CI-only enforcement

Measure and block only in CI, after code is pushed. Rejected: feedback arrives too late; the developer has already committed. Real-time feedback on every write is faster and cheaper.

### Alternative 3: Net budget per session

Set a "debt budget" per day/week and allow developers to trade improvements in one file for regressions elsewhere. Rejected: encourages cosmetic cleanup elsewhere to "pay for" structural debt, and metrics become games rather than signals.

### Alternative 4: Model-scored qualitative metrics inside the gate

Use the Claude API or a local model to assess code quality; ratchet on the score. Rejected: a ratchet that moves with model mood is not a ratchet. Metrics must be deterministic and reproducible offline.

## References

- ADR-0019 (established tooling first): tooling detection and optional metrics
- ADR-0022 (project conventions): legacy signal detection for baseline mode
- ADR-0027 (situational onboarding): baseline mode decision based on project age
- ADR-0023 (verification loop): quality gate and severity model for rules
- hooks/lib/ratchet.py: metric computation and baseline management
- hooks/post-write-check.sh: ratchet integration in write-time validation
- ci/craftsman-ci.sh: ratchet integration in CI enforcement
