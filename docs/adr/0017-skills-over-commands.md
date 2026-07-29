# ADR-0017: Skills Over Commands (Supersedes ADR-0007)

## Status

Accepted - Supersedes [ADR-0007](0007-commands-over-skills.md)

## Date

2026-07-26

## Context

ADR-0007 (2025-02) moved workflows from `skills/` to `commands/` because, at the time, skills were invisible in `/help`, auto-triggered unexpectedly, and could not be invoked explicitly.

Every one of those constraints has since been removed. Custom commands have been merged into skills: a skill is user-invocable with `/name`, appears in the skill listing, and its invocation behavior is controlled by frontmatter. Skills additionally provide capabilities that flat command files never had:

- `context: fork` + `agent:` - run a workflow in a dedicated subagent, keeping review output out of the main context. `background: false` (>= 2.1.218) makes the fork synchronous when the result is needed in-turn.
- Dynamic context injection - `` !`git diff HEAD` `` lines execute before the model reads the skill, so review skills receive real data instead of instructions to go fetch it.
- `allowed-tools` with `${CLAUDE_SKILL_DIR}` substitution - bundled scripts run without permission prompts.
- Invocation control - `disable-model-invocation: true` for user-triggered workflows, `user-invocable: false` for background knowledge.
- Supporting files in the skill directory (progressive disclosure) and per-skill `hooks`.

ADR-0007 also removed `model:` and `allowed-tools:` from frontmatter as "SKILL.md-specific". Both fields are supported and load-bearing today; dropping them cost us the model tiering defined in ADR-0010.

## Decision

Migrate all workflows from `commands/*.md` to `skills/<name>/SKILL.md` in v4.0.0. The `commands/` directory is deleted (clean break per ADR-0016). Skill names keep the `/craftsman:<name>` namespace, so user-facing invocations do not change.

Frontmatter policy per workflow class:

| Class | Examples | Frontmatter |
|-------|----------|-------------|
| Heavy review | challenge, legacy, team | `context: fork`, `agent:` bound to the matching plugin agent, dynamic context (diff, codemap), `background: false` when the verdict gates the turn |
| Deliberate workflow | design, spec, plan, workflow, refactor, git | `disable-model-invocation: true`, `allowed-tools` for bundled scripts |
| Diagnostics | healthcheck, metrics, verify | `disable-model-invocation: true`, `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/* *)` |
| Background knowledge | knowledge/ content, learned instincts (ADR-0020) | `user-invocable: false` |

Descriptions follow the discovery contract: key use case first, `when_to_use` for trigger phrases, combined text under the 1,536-character cap.

## Amendment - 2026-07-29

The table above put `team` and `legacy` under "Heavy review". Neither belongs
there, and treating the table as normative produced two live defects.

`team` is not a review. It asks the user which template to use, then calls
`TeamCreate` to spawn teammates into the session. `context: fork` would strand
both: the questions reach nobody and the teammates die with the fork. It is
its own class, **interactive orchestration**: no fork, no
`disable-model-invocation`, model-invocable so an orchestrator can offer it.
`legacy` is a "Deliberate workflow", not a heavy review.

The second defect was structural. `disable-model-invocation: true` means the
skill starts only when the user types the slash command as the first thing in a
prompt; the Skill tool refuses it. Sixteen of twenty-two skills carry the flag,
yet `skills/workflow/SKILL.md` announced "Invoking /craftsman:design..." and
five agents listed locked skills in `skills:` frontmatter. Every one of those
references was unreachable.

Two invariants follow, both enforced by `tests/core/test-invocation-policy.sh`:

1. An agent's `skills:` frontmatter may only list model-invocable skills, and
   may not list a skill whose `agent:` binding points back at that same agent
   (it would fork the agent into itself).
2. A skill body may only write `**Invokes:** /craftsman:x` when `x` is
   model-invocable. For a locked skill, say `**Hands off to:**` and print the
   command for the user to run.

## Consequences

### Positive

- Review workflows stop polluting the main context; verdicts come back from a fork.
- Review skills receive live data (diff, metrics, codemap) through dynamic context instead of hoping the model fetches it.
- Model tiering (ADR-0010) is enforceable again via the `model:` field.
- Bundled validation scripts run without permission friction.
- `knowledge/` moves to progressive disclosure: loaded when relevant, not injected wholesale.

### Negative

- One-shot migration cost across 21 workflows, their tests, and all documentation.
- Skill content persists in context once invoked; bodies must be kept lean, with reference material in supporting files.

### Neutral

- Template validation rules (Mission/Context Files sections) move from command files to SKILL.md bodies.

## Alternatives Considered

### Alternative 1: Keep commands, add a few skills

Rejected: maintains two formats and two test suites for one concept, and command files can never gain fork, dynamic context, or tool pre-approval.

### Alternative 2: Symlink commands to skills during a transition

Rejected by ADR-0016: no dual-architecture period.

## References

- ADR-0007 (superseded), ADR-0010 (model tiering restored), ADR-0016 (clean break)
- Skills documentation: https://code.claude.com/docs/en/skills
