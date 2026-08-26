# Hermes Quickstart

Craftsman for [Hermes](https://hermes-agent.nousresearch.com) agents in five
minutes. For the Claude Code install, see the [main README](../../README.md#install);
for the full Hermes design and threat model, see
[adapters/hermes/README.md](../../adapters/hermes/README.md).

## What you get

An autonomous coding agent that cannot conclude a turn while critical
violations remain in what it wrote, learns from every fix it makes, and knows
which craftsman method to apply to which situation. In ADR-0029 terms:

| Verb | What it means for your agent |
|------|------------------------------|
| gate | `pre_verify` refuses the conclusion while LAYER/TS/PHP/SEC criticals remain; advisory findings surface once, without blocking |
| inject | each session's first turn receives the machine's correction history: what keeps getting fixed here |
| record | every violation and every fix lands in the local metrics database, `source=hermes` |
| skills | 7 skills selectable by situation: `craftsman-quality`, `-refactor`, `-legacy`, `-debug`, `-test`, `-spec`, `-design` |

## Install

Prerequisites: a Hermes install, plus `python3`, `bash` and `git` (all present
in the stock image and on any developer machine).

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers ~/.hermes/plugins/craftsman
hermes plugins enable craftsman
```

That is the whole install. No Docker, no config-file editing, no extra
binaries.

## Verify it works

```bash
hermes plugins            # craftsman listed and enabled
```

Then, inside a Hermes session:

```
/craftsman status         # plugin version, gate path, metrics database
/craftsman                # on-demand verdict on the current worktree
```

Or prove the refusal end to end without an agent:
run [examples/hermes-agent/demo.sh](../../examples/hermes-agent/demo.sh) and
watch a layer violation get blocked, fixed, released and recorded.

## Recommended agent profile

```yaml
# ~/.hermes/config.yaml
agent:
  max_verify_nudges: 6        # default 3; a real refactor under the gate needs room
skills:
  write_approval: true        # agent-authored skills wait for human review
auxiliary:
  background_review:
    enabled: false            # the correction loop already learns from verdicts
plugins:
  entries:
    craftsman:
      gate_seconds: 45        # gate budget per run
      inject_trends: "on"     # correction history on each session's first turn
```

## Running on a server (VPS or PaaS)

On any host with a persistent volume (a VPS, a PaaS service), clone onto
that volume so the plugin and its metrics survive redeploys, and keep the clone read-only for the agent user where the platform
allows it:

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers /opt/data/hermes/plugins/craftsman
```

Point `~/.hermes` at the volume (or symlink `~/.hermes/plugins/craftsman` to
the clone), then `hermes plugins enable craftsman`. Updating is `git pull` in
the clone: a reviewable, versioned change, which is the point.

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `hermes plugins` does not list craftsman | The clone is not at `~/.hermes/plugins/craftsman`, or `plugin.yaml` is missing from its root. Re-clone; do not copy a subdirectory. |
| Every turn ends with "The craftsman gate could not run" | The gate fails closed by design. Read the reason in the message: usually `git` missing from PATH or an unreadable workspace. |
| No trends injected on the first turn | Normal on a fresh machine: the database fills as the agent works. Check `/craftsman status`. |
| The agent loops on the same refusal | It is not applying the fix. Check `agent.max_verify_nudges` is at least 6 and that the `craftsman-refactor` skill is listed by the skill selector. |
| A rule blocks something your project allows | Change the rule through a reviewed commit: `.craft-rules.yml` next to the code (`rules: {TS001: warn}`). The gate refuses turns where the agent edits that file itself. |
