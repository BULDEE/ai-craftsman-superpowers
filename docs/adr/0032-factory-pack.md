# ADR-0032: The Factory Is a Pack, and Its Reviews Run in Subagents

## Status

Accepted

## Date

2026-11-25

## Context

`/craftsman:workflow` carries one feature through design, spec, plan, implement,
test, verify and commit with a human at every gate (ADR-0013). That is the
workshop. A second mode was asked for: a queue of issues turned into pull
requests without a human between the issue and the review, so that the human's
time goes to reading results and not to driving steps.

The idea is not new. "Software factory" pipelines for coding agents share a
shape: issues as the queue, a deterministic script that owns state and refuses
illegal moves, model agents for judgment in between, a pull request as the
exit. The concept was studied in a public reference implementation and
re-implemented here from the idea, with no code taken from it (its licence is
GPLv3, this plugin's is Apache-2.0).

Three questions had to be settled.

**Where does it live?** A companion plugin was the first answer. It fails on
access: the factory must call `ci/craftsman-ci.sh`, the language registry,
`metrics-query.py` and the session helpers, and a plugin knows only its own
root. In the core's `skills/` it would grow the six core agents and could not
be removed without surgery.

**Who merges?** The reference implementation lets an approver agent merge what
it is sure of. This plugin's promise is a human in the loop.

**Can a review run in a subagent?** ADR-0028 moved `/craftsman:challenge` into
the main session after measuring three failures of its fork: it returned
nothing one run in two, it could not see the conversation or its attachments,
and worktree isolation hid the uncommitted diff under review.

## Decision

1. **The factory is a pack**, `packs/factory/`, in the mould of `packs/ai-ml`:
   agents, one command, scripts, no validator. A pack may be a mode of
   execution and not only a language or a domain. It declares
   `stack: ["*"]` and holds no list of languages: it reads which pack owns a
   file from the other packs' manifests.

2. **A script is the brain, the session is a dispatcher.**
   `craftsman-factory step <job>` does every deterministic thing it can, then
   stops at the first thing only a model or a human can do and prints which:
   `SPAWN <agent> <model> <name> <prompt>`. The orchestrating session starts
   what it is told to start and runs `step` again when an agent returns. It
   decides nothing, reads no job file, and never sees issue text.
   `job.json` has one writer and a table of legal moves.

3. **The gate is the plugin's own.** `ci/craftsman-ci.sh --changed-only`, the
   repository's checks, the packs' `protected_configs`, and a new capability,
   `test_skip_markers`, declared per language in `pack.yml`. No verdict is not
   a clean verdict: a rules engine that did not answer, or no check
   configured, fails the gate. Two rounds failing with the same signature stop
   the job (the `no_progress` stop of `/craftsman:loop`).

4. **Nothing merges.** A job ends as a pull request marked ready, with a
   review-depth label (`review:skim`, `review:standard`, `review:deep`)
   computed by a script from the job's facts. A reviewer agent may lower the
   score; nothing raises it. Merging is the human's approval.

5. **Reviews run in subagents, and ADR-0028 still holds.** Its three causes do
   not apply here, each for a reason that is checked:
   - *returned nothing*: the reviewer's deliverable is a file with a
     `VERDICT:` line, not a reply. The script reads the file; an agent that
     returns without it is asked once more, then the job goes to a human;
   - *could not see what was reviewed*: the reviewer is given the spec, the
     build report and the gate report as files. There is no conversation to
     miss: the job never had one;
   - *worktree hid the diff*: the diff is committed and pushed before any
     reviewer starts, and the reviewer is handed the worktree's path. No agent
     of the factory declares `isolation: worktree`; the worktree is created by
     the script.
   ADR-0028's rule is about a skill that delivers a verdict *to the user*. The
   factory's reviewers deliver to a script.

6. **A subagent's finding in another worktree does not hold the dispatcher.**
   Measured in the spike: a subagent's hook state is filed under the parent's
   session id, so the end-of-turn gate (CR-259) held the orchestrator for a
   builder's finding and told it to fix code it must never touch.
   `post-write-check.sh` now records which subagent left a finding
   (`landed_agents`), and the gate skips one that a subagent left outside the
   session's own git checkout. The session's own agent is held wherever it
   wrote, and a subagent's finding in the session's checkout still holds the
   turn: `/craftsman:team` is unchanged.

7. **What humans do with the pull requests is recorded** in `metrics.db`
   (`factory_jobs`, `factory_feedback`): commits pushed after delivery,
   changes requested, feedback, closure without merge. When a review-depth
   level is corrected more often than its name promises, a threshold change is
   proposed. Nothing applies it but a human editing the config (ADR-0020).

## Consequences

### Positive

- One gate: a factory job is judged by the validators, the severity resolution
  and the checks a developer and the CI already meet.
- The orchestrating session's context stays small, so one session can run a
  whole queue, and a session that dies resumes from files.
- Issue text reaches a model only as quoted data in a file. The session that
  holds every tool never reads it.
- The confidence score is explainable line by line and calibrated against what
  humans actually did.

### Negative

- Claude Code only. The command needs background subagents and `SendMessage`;
  the copy shipped under `skills/` says so and stops on any other host.
- GitHub is the only forge. Linear is a queue, not a forge: the pull request
  is still opened with `gh`.
- A bug in the spine ships with the core's release, to every install, although
  the pack adds no hook handler and stays dormant until the command is typed.
- The cost figure is an estimate read from subagent transcripts, a format
  Claude Code documents as internal. A Claude Code update can break it; the
  reader is one function with its own test.
- The Linear adapter is tested against a local stand-in server, not against
  Linear itself.

### Neutral

- "Pack" no longer means "a language or a domain" only.
- The weights of the confidence score are arbitrary until outcomes exist to
  compare them with. They live in the config for that reason.

## Alternatives Considered

### Alternative 1: A companion plugin in its own repository

Rejected: a plugin cannot resolve another plugin's root, and the factory calls
five of the core's internals. It would also be a second version to keep in
step with the first, for one pipeline.

### Alternative 2: Per-agent session state

Proposed before the spike's numbers were read closely: name the state file
after `session_id` and `agent_id`. Rejected: a subagent's passing test run
would no longer verify its parent's session, and the parent would stop being
held for what its subagents left in its own checkout, both of which
`/craftsman:team` relies on. The narrower change in point 6 fixes what the
factory needs and nothing else.

### Alternative 3: Let an approver agent merge

Rejected: a label that tells a human how closely to read is a statement the
plugin can stand behind. A merge is not.

## References

- [ADR-0013: Flexible Workflow Orchestrator](./0013-workflow-orchestrator.md)
- [ADR-0020: Instinct Promotion Requires Human Review](./0020-instinct-promotion-human-review.md)
- [ADR-0023: Deterministic Verification Loop](./0023-deterministic-verification-loop.md)
- [ADR-0028: Review Runs in the Main Session](./0028-review-runs-in-the-main-session.md)
- [The factory guide](../guides/factory.md)
