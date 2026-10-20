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
- **The instrument is versioned, the history still is not.** Every mark
  carries `"instrument": N`, the version of the measurement that took it
  (`RATCHET_INSTRUMENT` in `ratchet.py`). The case that required it: the
  first instrument counted control keywords inside strings and comments, and
  a function whose docstring held `def example():` had its span cut short by
  FN_RE, so it measured complexity 0 and max_fn_lines 4. Instrument 2 blanks
  literals first and measures the same untouched file at 5 and 17. Compared
  blindly, `check` reported `RATCHET001 complexity 0 -> 5` on a file nobody
  had edited, and a plugin upgrade put CI in the red with no change in the
  code. A mark taken by an older instrument is therefore not a mark: `check`
  re-takes it on the next touch and says so on stderr, `update` replaces it
  rather than tightening against it (a `min()` between two rulers is a number
  neither measured), and a repository with a year of marks needs no manual
  step, since every file re-marks itself when next written. Bump the
  constant whenever a change to `measure()` can move a number on an
  unchanged file, in either direction.

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

## Amendment (2026-09-14): what shipped, against what was decided

The decision stands: one committed, per-file, one-way mark. Four details of
the design section describe a product that was not shipped, found by the
architecture review of 2026-09-13, and this is the record rather than a
rewrite of the decision.

- "Block in strict, warn in moderate, silent in relaxed": `RATCHET001` is
  declared `default_severity: warn` in `rules/core.yml` and resolves through
  the rules engine like any rule; no strictness wiring of its own exists.
- "Loosening is explicit: `craftsman-ignore: RATCHET`": the marker is not
  read by the ratchet. Loosening is `ratchet.py init <file> --reason`, which
  writes the new numbers into the mark where a reviewer sees them in the
  diff (instrument 2, #59).
- `ratchet init --repair`: never implemented; the mark is rebuilt by
  `init` on the named files.
- Duplication through jscpd or phpcpd: not implemented; the row carries no
  duplication metric.
- The row schema grew `reason`, `rules` (the rule baseline shares the row,
  ADR-0025 and `rule_baseline.py`) and `instrument`.

## Amendment (2026-10-20): the mark records function-level debt only (CR-288)

Measured on this repository the day of the review: `.craftsman-baseline.json`
held 87 KB for 277 files, 55% of it reasons concatenated row after row; 473
budget raises in 116 commits, 270 of them on `file_lines` alone and 15% on a
function-level metric of production code; 13 marks looser than their file,
one by 212 lines. The per-file, committed, one-way mark stands (ESLint's bulk
suppressions, 2025, settled on the same shape: a committed file of counts per
file, pruned to tighten). Three details change.

- **The mark records `complexity`, `max_fn_lines` and `ignores`.** A file that
  grows with a feature is not debt, and LOC001, the rule that owns file
  length, is advisory permanently. `file_lines` and `fan_out` are still
  measured by `ratchet.py measure`; no mark records them, and `update` or
  `init` drops them from an older row.
- **One reason per row.** A raise replaces the reason (`init <file> --reason`
  always did); the history is the commit that wrote it. Rows were rewritten
  with the reason of the newest commit that changed each one, read from git.
- **Tightening is deterministic in CI.** It happened only in the local hook,
  after a Write or Edit; a file improved any other way kept its old budget.
  `check --tight` also fails on a mark looser than the file (`slack`) and on a
  touched file with no committed row (`unmarked`), and the repository's own
  Structural Ratchet job runs it. `ci/craftsman-ci.sh` and the hooks keep
  plain `check`, so hook and pipeline still agree for every user project.

Two defects surfaced while making the change, both fixed with it.

- **Instrument 3.** The span finder looked for `{` on the header only, fell
  back to indentation, and closed a function on a brace that opens on its own
  line: every PSR-12 method measured complexity 0 over one line, so with
  `file_lines` gone the ratchet would have guarded nothing in PHP. The body now
  opens on the header, after a signature whose parentheses span several lines,
  or on the next line when it starts with `{`; an indentation-delimited body is
  scanned from the signature's last line. The ruler changed, so marks taken by
  instrument 2 are re-taken on the next touch.
- **A re-take keeps the row.** Re-taking a mark from an older instrument
  replaced the whole row with a fresh measure, dropping its reason and the
  rule baseline's `rules` counts: the bump would have made every inherited rule
  finding block again. Only the ratcheted numbers are re-taken now.

