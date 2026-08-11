# ADR-0028: Review Runs in the Main Session

## Status

Accepted. Supersedes the `challenge` row of [ADR-0011](./0011-context-fork-strategy.md).

## Date

2026-08-10

## Context

`/craftsman:challenge` ran with `context: fork`, `agent: craftsman:architect`,
`background: false`. ADR-0011 justified the fork on three grounds: a cleaner
main context, a full context budget for the review, and an unbiased analysis
free of prior conversation.

Three months of recorded runs contradict all three.

### 1. It returned nothing, one run in two

38 recorded runs of `craftsman:architect`. 15 delivered a report. 23 did not.

Every truncated subagent transcript on the machine (17 of 164) was this agent,
every one stopped at exactly 20 model turns with `stop_reason: tool_use`, and no
other agent type ever did. `agents/architect.md` declared `maxTurns: 20`. When
the cap lands on a tool call, the agent loop stops there and returns no text.

Claude Code's forked-command handler then substitutes a default string for the
missing result and returns `shouldQuery: false`:

```js
let $ = yCr(D, "Command completed");
return { messages: [M, YO(`<local-command-stdout>${z1e($)}</local-command-stdout>`), ...],
         shouldQuery: W.requestQuery, ... }
```

The session prints `Command completed` and the turn ends. No error, no partial,
no retry path. The user typed `continue` to get anything at all.

### 2. The fork could not see what was being reviewed

A forked skill receives the rendered `SKILL.md` as a plain string prompt. Text
arguments are appended as `ARGUMENTS: <value>`; **attachments are not carried**.
A review invoked with seven screenshots received seven `[Image #14]` tokens and
zero images. It also has no conversation history, so a review asked to look at
what the user had just been discussing derived its scope from `git log` instead
and reviewed a different subsystem.

An independent reviewer with no brief does not produce an unbiased review of the
right thing. It produces a confident review of the wrong thing.

### 3. Worktree isolation hid the diff under review

`craftsman:architect` also declared `isolation: worktree`. A worktree is a clean
checkout of a commit: `git status --porcelain` inside one is empty while the
repository it came from is dirty. An agent whose injected context is
`git diff HEAD` would, when isolation applies, review a tree in which that diff
does not exist. The agent declares no `Write` or `Edit`, so the isolation
protected nothing in exchange.

### The shape is already on file

`.claude/agent-memory/craftsman-architect/project_silent_verdict_loss.md`
records this repository losing a verdict at a front-end boundary four times: the
deptrac formatter that never existed, the CI scanner exit code that was
discarded, the annotation `curl` whose status was dropped, the workflow job that
bypassed the rules engine. The fork boundary is the fifth instance and the only
one that faces the user directly.

## Decision

1. `/craftsman:challenge` runs in the main session. Its frontmatter declares
   `model` and `effort` only.
2. Isolation moves down one level: for a large scope the skill fans out to
   reviewer subagents from a session that holds the brief, and writes their
   prompts. The orchestrator keeps the user's intent and attachments; the
   subagents get an explicit scope instead of guessing one.
3. Every agent declaring `maxTurns` carries a `## Turn Budget` contract: emit
   the deliverable as soon as the evidence justifies it, reserve the last third
   of the budget for writing, name what was not covered under `NOT REVIEWED`,
   and never end on a tool call.
4. `craftsman:architect` moves to `maxTurns: 60` and drops `isolation: worktree`.
   The cap alone was never the defect (an agent that keeps no budget for writing
   fails at any cap) so the contract, not the number, is what is enforced.
5. `tests/core/test-turn-budget.sh` enforces 3 and 4, and refuses any future
   `context: fork` into an agent without the delivery contract. Both checks
   carry fixtures that prove they can fail.

## Consequences

### Positive

- The review always ends with a verdict, including a partial one.
- Screenshots, pasted logs and the preceding conversation are evidence again.
- The skill can ask a clarifying question, which a `background: false` fork
  could not.
- One less boundary at which a verdict disappears without an error.

### Negative

- The rendered `SKILL.md` and the injected diff stay in the main context for the
  session, roughly 5k to 8k tokens per invocation. Accepted: the command is
  invoked deliberately, and Deep Review Mode moves the bulk reading back out to
  subagents when the scope is large.
- The review is no longer blind to the conversation. That was never a benefit;
  it is what produced the wrong-scope reviews.

### Neutral

- ADR-0011 still stands for `debug`, `refactor`, `plan` and `mlops`, none of
  which is the delivery path for a user-facing verdict. Any future fork must
  clear the `test-turn-budget.sh` check.

## Addendum (2026-08-11): the fork premise, re-verified

Section 2 states a forked skill "has no conversation history" and that
attachments are not carried. On the current harness that premise is half
stale: the Agent tool now documents `subagent_type: "fork"` as inheriting
the full conversation context. Attachment delivery through a fork remains
unverified. The decision does not move, because it rests on the delivery
contract (a user-facing verdict must end in the user's session, never on a
tool call) and on sections 1 and 3, which are fork-agnostic. What changes is
the justification's shelf life: a future proposal to fork a verdict-delivering
skill must re-test inheritance against the harness of the day instead of
citing section 2, and still clears `tests/core/test-turn-budget.sh`.

## References

- [ADR-0011: Context Fork Strategy](./0011-context-fork-strategy.md)
- [ADR-0017: Skills over Commands](./0017-skills-over-commands.md)
- [Claude Code: run skills in a subagent](https://code.claude.com/docs/en/skills#run-skills-in-a-subagent)
