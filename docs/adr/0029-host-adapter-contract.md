# ADR-0029: Host Adapter Contract

## Status

Accepted.

## Date

2026-08-26

## Context

The plugin has three front-ends over one core: `hooks/` for Claude Code,
`ci/craftsman-ci.sh` for pipelines, and `adapters/hermes/` for Nous Research's
Hermes runtime. CLAUDE.md already states the rule ("a fourth front-end is an
adapter, never a fork") and `tests/ci/test-craftsman-ci.sh` holds hooks and CI
to the same severity resolution. Nothing held the Hermes adapter to anything.

Three gaps followed, all found in review:

1. The Hermes adapter dropped every non-critical violation
   (`pre-verify.sh` filtered `severity == "critical"` and discarded the rest),
   so the "one engine, one verdict" claim was false on that host.
2. The gate did not protect its own configuration. A turn that wrote
   `.craft-rules.yml` next to a violating file switched the rule to `ignore`
   before the scan read it, and Hermes consent survives script edits (the
   allowlist keys on the command string, not a hash). The Dockerfile documented
   this refusal as the one containment measure living in this repository; it
   was not implemented.
3. No test compared the three front-ends on the same fixtures, so a fourth
   adapter could drift on day one without any suite noticing.

The multi-host precedent worth contrasting is ECC, which supports many hosts by
copying agents, rules and hooks into per-host directories and warns its own
users about the duplication. The premise here is the opposite: one engine,
adapters at the edge, parity enforced by tests.

An adversarial design panel reviewed the first draft of this contract. It cut
a `verify` verb (operational health belongs to each host's own doctor command),
cut a speculative event catalogue (the `violations`, `corrections` and
`instincts` tables are the model), and forced two clarifications recorded
below: a gate returns exactly `pass` or `block`, and the instinct projection is
a projection, never a second system of record.

## Decision

Every host adapter implements three verbs against the shared core:

| Verb | Responsibility |
|------|----------------|
| `gate` | Run the rules engine on the turn's scope and return exactly `pass` or `block`. A gate that cannot run returns `block` with the reason: no verdict is not a clean verdict. A turn whose scope touches the gate's own configuration (`.craft-rules.yml`, `.craft-config.yml`, the adapter's own files, `ci/craftsman-ci.sh`) is blocked, not flagged. Non-critical findings are surfaced with the verdict, never dropped: they ride along with a block, and on a host where advice costs a turn they surface once, on the first attempt. |
| `inject` | Put correction trends and approved instincts into the agent's context at session start. CI has no agent to inform and does not implement it. |
| `record` | Write violations and corrections into `metrics.db` with `source=<host>` and enough threading (session id, attempt) to tie a correction to the violation it fixed. |

Enforcement is `tests/adapters/test-parity.sh`: the same fixtures (a LAYER001
domain import, a TS001 `any`, an advisory TS002, a directory-level
`.craft-rules.yml` relaxation) run through every front-end, and the suite fails
when two front-ends disagree on a rule's blocking decision, and when a
directory under `adapters/` has no parity coverage at all.

`metrics.db` is the single system of record for violations, corrections and
instincts. On a host with no human at the keyboard, instinct candidates may be
exported as files in the repository so that a reviewed merge becomes the
approval gesture, but such an export is a projection: regenerated from the
database, never merged back by hand, and the merge lands in the database
through `instincts.py approve`. Codification stays human-gated on every host.

## Alternatives rejected

- **Per-host copies of rules and workflows (ECC's model).** Ships fast,
  drifts guaranteed, and contradicts the adapter rule this repository already
  enforces between hooks and CI.
- **A `verify` verb in the contract.** Adapter health is deployment, not
  architecture: `hermes hooks doctor` and `/craftsman:healthcheck` already own
  it per host.
- **A domain event catalogue.** Seven event types were drafted; two tables were
  in use. The tables are the contract.

## Consequences

- The Hermes adapter now blocks a turn that edits the gate's configuration and
  surfaces advisory findings once per turn cycle instead of dropping them.
  `tests/adapters/test-hermes-pre-verify.sh` covers both, red-first.
- A future host (a native Hermes Python plugin, Cursor, Codex) starts from this
  contract and from a parity entry, or the suite refuses it.
- The parity suite runs the real front-end entry points, not the engine
  directly, so an adapter that swallows the engine's verdict fails even when
  the engine was right.

## Re-evaluate if

- A host appears whose only integration surface cannot block anything, making
  `gate` unimplementable as specified.
- Instinct approval needs to synchronise across machines, which would reopen
  the projection-versus-record question that the panel closed here.
