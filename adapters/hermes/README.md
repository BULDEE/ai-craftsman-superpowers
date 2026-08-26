# Hermes host adapter

Runs the craftsman gate inside [Hermes](https://hermes-agent.nousresearch.com),
Nous Research's agent runtime. Two independent paths, usable together.

Every environment claim below was measured on a running
`nousresearch/hermes-agent` container, not read from documentation.

## Path 1: native Hermes hook

`pre-verify.sh` answers Hermes' `pre_verify` event, which fires once per turn
when the agent has edited code and is about to conclude.

```yaml
# ~/.hermes/config.yaml
hooks:
  pre_verify:
    - command: "/opt/craftsman/adapters/hermes/pre-verify.sh"
      timeout: 60
```

Headless deployments need `HERMES_ACCEPT_HOOKS=1` or `hooks_auto_accept: true`:
Hermes asks for a one-shot approval per `(event, command)` pair, stored in
`shell-hooks-allowlist.json`. **A hook is arbitrary shell in a container that
holds your credentials. Auto-accepting is a security decision, not a
deployment detail.**

### Why the conclusion and not the write

Hermes exposes `pre_tool_call`, which can veto a write. This adapter uses
`pre_verify` instead. Blocking a write assumes somebody can break the loop it
creates, and an autonomous agent has nobody: with a human present, this plugin
records 530 suppressed violations against 436 fixed. Refusing a conclusion
traps nothing, and Hermes bounds the retries itself through
`agent.max_verify_nudges`.

### Scope comes from git, not from the payload

Hermes builds `changed_paths` from the tool name. `agent/tool_dispatch_helpers.py`
returns `[]` for anything outside `FILE_MUTATING_TOOL_NAMES`, and only
`write_file` and `patch` are in it, so a write through `terminal` (`sed -i`,
`python -c`, `tee`, a redirect, `git apply`) never appears. The adapter derives
scope from `git diff` plus untracked files and treats the payload as a hint.

A dirty worktree is therefore unverified work, and all of it is scanned.

### One verdict, two channels

Critical violations block the conclusion, and carry the advisory findings
along so they are read in the same turn. A turn with only advisory findings
gets them once, as a `continue` directive on the first attempt, and silence on
every later one: repeated, advice would burn `agent.max_verify_nudges`;
dropped, it would break verdict parity with the hook and CI front-ends
(ADR-0029, `tests/adapters/test-parity.sh`).

### The gate refuses its own reconfiguration

A turn whose diff touches `.craft-rules.yml`, `.craft-config.yml`,
`adapters/hermes/` or `ci/craftsman-ci.sh` is blocked outright, whatever else
it contains. Hermes consent survives script edits (the allowlist keys on the
command string, not a hash), so this is the one containment measure that
lives in this repository rather than in infrastructure.

## Path 2: Claude Code inside the container

Hermes ships `skills/autonomous-ai-agents/claude-code/SKILL.md`, which tells
the agent to run the Claude Code CLI. **The binary is absent from the image**,
so that skill currently fails with `command not found`.

Installing it is the cheapest way to get the whole plugin into an autonomous
loop: every existing hook runs unchanged, with no second implementation of the
gate to keep in sync. `claude-craftsman.sh` wraps the invocation.

### Credential precedence

Claude Code resolves credentials in a fixed order, and two of its documented
behaviours decide how this wrapper invokes it.

`--bare` skips auto-discovery of hooks, skills, plugins, MCP servers and
CLAUDE.md, so it loads none of this plugin, and it does not read
`CLAUDE_CODE_OAUTH_TOKEN`. The Claude Code docs state that `--bare` "will
become the default for `-p` in a future release", so the wrapper refuses the
flag with exit 64 rather than run ungated, and a test asserts on the arguments
`claude` actually receives that it never passes it.

`ANTHROPIC_API_KEY` outranks `CLAUDE_CODE_OAUTH_TOKEN` in that order, and the
Hermes image already carries one. When both are present the wrapper drops the
key for its own process so the credential it was given is the effective one,
and says so on stderr. With neither, it exits 78 rather than half-run.

## Container

`Dockerfile.craftsman` adds what the stock image lacks: `sqlite3` (absent, so
metrics and the learning loop are dead without it), `jq` (absent, and every
craftsman hook parses its stdin with it), and the Claude Code CLI.

The plugin is baked into the image rather than dropped on `/opt/data`. That
volume is outside version control, so a gate living there could be changed
with no diff, no review and no history. What enforces the rules ships with the
image; only session state belongs on the volume.

## What this does not protect against

Stated plainly, because a control that does not control is worse than none.

**The gated party configures the gate, and the refusal above only covers the
turn.** A `.craft-rules.yml` that was already in the repository when it was
cloned, or one edited outside a gated turn, still switches its rule to
`ignore` with no refusal. `trust_project_tools` in `~/.claude/.craft-config.yml`
turns a config toggle into execution of a cloned repository's own binaries.
Both reproduced before the in-turn guard existed, and both remain live outside
it.

The stock image runs as uid 0, so file permissions contain nobody. Containment
needs one of:

- the agent running as a non-root uid that does not own `/opt/craftsman`
- `/opt/craftsman` mounted read-only at the container level
- CODEOWNERS and required review on those paths server-side, which needs the
  configuration to be in git in the first place

Before enabling clone plus worktree plus PR plus auto-merge, also settle:

1. **Credentials out of the LLM process.** The agent reads an untrusted repo's
   README, issues and comments, and runs its test suite, in a process holding a
   repo-write token. Have it produce a patch; let a separate minimal publisher
   hold the token.
2. **No `workflows` scope on any token.** Write access to
   `.github/workflows/**` rewrites the required check, and every control above
   collapses to that one permission bit.
3. **No auto-merge on agent-authored PRs.** It removes the second party that
   branch protection exists to place between authorship and `main`.
