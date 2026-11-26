# The Factory: From an Issue Queue to Reviewed Pull Requests

`/craftsman:workflow` is the workshop: you drive one feature through each step.
`/craftsman:factory` is the factory: you label issues, it builds them, and your
time goes to reading pull requests. It never merges.

Claude Code only. GitHub is the forge; the queue is GitHub Issues or Linear.

## The pipeline

```
issue labelled `factory`
   -> intake        ACCEPT | NEEDS-INFO | REJECT | ESCALATE; risk, surfaces
   -> design        only when the domain model changes
   -> spec          skipped when the issue carries its own
   -> build         test-first, in the job's own worktree
   -> gate          a script: rules engine, your checks, protected paths
   -> review        one reviewer per language of the diff, one per surface
   -> ready         pull request marked ready, with a review-depth label
you   -> merge it (that is the approval), or give feedback, or reject
```

A script, `craftsman-factory`, owns every transition. The session that runs
`/craftsman:factory` only starts the agents the script names. State is files
under `.craftsman-factory/` in your repository, kept out of git through
`.git/info/exclude`: a session that dies resumes where it stopped.

## Set up

```
/craftsman:factory init            GitHub Issues as the queue
/craftsman:factory init linear     Linear as the queue
```

It needs `gh`, authenticated, with the right to push and to manage labels.
It writes `.craftsman-factory/config.json`. Read two keys before the first run:

| Key | What it is | If it is wrong |
|-----|------------|----------------|
| `checks` | The commands that prove a branch works, run in the job's worktree | Empty: the gate fails every job. No verdict is not a clean verdict |
| `setup` | What a fresh checkout needs (installing dependencies) | The builder's first test run fails for reasons that are not its own |

`init` proposes one test command per language it finds, taken from the packs'
manifests. It cannot know your install step: fill `setup` yourself.

Other keys, with their defaults:

| Key | Default | Meaning |
|-----|---------|---------|
| `concurrency` | 1 | Jobs running at once. Start at 1 |
| `max_rounds` | 3 | Build rounds before a human is asked |
| `protected_paths` | `[]` | Extra paths no job may modify, as glob patterns. Tool configurations the packs declare are always protected |
| `reviewer_models` | haiku / sonnet / opus | Reviewer model for low / medium / high risk |
| `confidence.thresholds` | skim 80, standard 55 | Score needed for each review depth |
| `allow_no_checks` | false | Let the gate pass with no check configured. Do not |

## Run

Label an issue `factory`, then:

```
/craftsman:factory run          every labelled issue, and whatever a dead session left
/craftsman:factory run 12       one issue
/craftsman:factory status       where every job stands
/craftsman:factory page         the page of what waits on you
```

The page is one file, rewritten after every factory command, and it reloads
itself: every 15 seconds while a job runs, every minute otherwise, and when
you come back to its tab. Open it once and leave it open. It holds still while
you have a file unfolded or text selected. It shows what the script last
knew: a pull request you merged appears as merged at the next `run`.

## What the gate refuses, and what it records

The gate fails a branch that modifies a tool configuration the packs declare
protected, that adds or edits a `.craft-rules.yml` or `.craft-config.yml` (the
rules it is judged by), that leaves a blocking finding of the rules engine, or
whose checks fail. A green run that executed no test fails too.

It records, without failing, what only a reader can judge: a test skip marker
the branch added, a test file it deleted, a rule ignore marker it added. Each
is listed for the reviewer, lowers the confidence score, and rules out
`review:skim`.

The label is the trust boundary: an issue without it is refused. Issue text
reaches the agents as quoted data in a file and is never part of a prompt.

## What comes back to you

**A question on the issue.** The request needs a decision only its author can
make. The issue gets a comment and the `factory:needs-info` label. Answer on
the issue, or with `/craftsman:factory answer <job>: <text>`. The next run
picks it up.

**A pull request with a review-depth label.**

| Label | Read it like this |
|-------|-------------------|
| `review:skim` | The summary and the acceptance evidence; open the diff where something surprises you |
| `review:standard` | The whole diff once, with the spec beside it |
| `review:deep` | Line by line, run it, and check every reason listed |

The label comes from a score that starts at 100 and loses points for each
reason to look closer: risk, surfaces touched, a spec the factory wrote for a
domain change, extra rounds, a large diff, a test skipped or deleted, warnings
left in the diff. Every deduction is listed in a comment on the pull request.
A reviewer agent can lower the score. Nothing can raise it, and a change that
touches security or skips a test is never a skim.

Merge it to approve. To change it:
`/craftsman:factory feedback <job>: <what to change>`. To take over by hand,
`cd` into the job's worktree and run `/craftsman:workflow --from implement`:
the spec is already written.

**An escalation.** The issue is labelled `factory:needs-human` and the reason
is on the pull request or the issue: the build rounds are spent, two rounds
failed the same way, the builder is blocked, or the intake found code with no
tests under the change. Legacy code is characterised before it is changed
(`/craftsman:legacy`); the factory does not build on it blind.

## Linear

Issues come from Linear, pull requests still go to GitHub. The pull request
body carries `Fixes LIN-123`.

- With `LINEAR_API_KEY` in the environment, the script calls Linear's API.
- Without it, `init` selects the `mcp` transport: a small agent,
  `factory-fetch`, reads Linear through your connected Linear MCP server and
  writes what it finds to files. The session that dispatches never reads issue
  text either way.

Create the three labels (`factory`, `factory:needs-info`,
`factory:needs-human`) in the Linear workspace first. On GitHub anyone with
triage rights can label an issue; in Linear any workspace member can, so the
trust boundary is your workspace.

## What the factory learns

Every run, the script looks at what you did with the pull requests it
delivered: commits you pushed after delivery, changes you requested, feedback
you gave, pull requests you closed without merging. It is written to the
plugin's `metrics.db`.

```
/craftsman:factory learn
```

prints, per review depth, how many pull requests were closed or merged and how
many you corrected. When `review:skim` pull requests are corrected more often
than one in five, over at least five, it proposes raising the threshold. It
never applies the change: edit `confidence.thresholds` in the config to accept.

`learn --classify` additionally sorts your review remarks into `missing-rule`,
`spec-gap`, `missed-by-review` and `style-preference` with one headless Haiku
call. A class seen on two jobs or more is listed as recurring: a candidate for
a rule in `.craft-rules.yml`, a line in an agent, or a knowledge note. That
decision stays yours too.

The page shows all of it, with the count behind every rate. With a handful of
pull requests the rates mean little; the page says how many.

## Cost

Each job's cost is estimated from the tokens its agents used, read from Claude
Code's subagent transcripts and priced with `prices_usd_per_mtok` in the
config. It is an estimate, on purpose called one: Claude Code computes cost
client-side, and on a subscription it shows where the spend goes, not what you
are billed. The orchestrating session's own tokens are not attributed to a job.

## Limits, stated

- Claude Code only; GitHub is the only forge.
- The Linear adapter is tested against a stand-in server, not against Linear.
- A job is one small pull request. An issue that needs more is cut down at
  intake, and what was left out is said on the issue.
- The rules engine judges the files a branch changes. Debt those files already
  carried can block a job: record it with `craftsman-ci baseline` first.
- The cost reader depends on a transcript format Claude Code calls internal.

See [ADR-0032](../adr/0032-factory-pack.md) for why it is built this way.
