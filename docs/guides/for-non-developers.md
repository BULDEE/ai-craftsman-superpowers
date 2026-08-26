# Craftsman For Non-Developers

You do not write code, but code gets written for you: by your developers, and
increasingly by AI agents. This page explains what this plugin does in plain
language, and what to look for.

## The problem it solves

AI writes code fast. Speed is not the risk; silence is. Badly structured code
works on day one, then every change gets slower and riskier, until a feature
that took days starts taking months. By the time anyone notices, the expensive
part already happened.

You can tell an AI "write clean code" in its instructions. It follows them the
way a driver follows speed limits with no radar anywhere: mostly, at first,
less and less as the trip gets long. Instructions are advice. Nothing checks.

## What Craftsman does

It puts the radar in the loop. Every time the AI tries to save code, an
automatic inspector checks it against your team's architecture rules. If the
code breaks a serious rule, **the save is refused before it lands**, and the
AI is told exactly what to fix, file and line. It fixes and retries. You never
see the bad version: it never existed on disk.

Three things make it more than a blocker:

1. **The same rules everywhere.** The inspector that refuses a save on a
   laptop is the same one that fails the team's pipeline. No gap between "it
   worked for me" and what the team accepts.
2. **It learns.** Every fixed mistake is recorded. Mistakes that keep coming
   back are surfaced to a human, who can promote them into a permanent
   instinct. The system gets stricter about *your* project's real failure
   modes, not a generic checklist.
3. **"Done" needs proof.** A task cannot be declared finished without
   evidence that the checks ran. "It should work" does not count.

## What it looks like

When the AI writes a file that breaks the architecture, this is the whole
event, in seconds:

```
🚫 BLOCKED by AI Craftsman - 2 violation(s) detected before write:
  ✗ LAYER001: Domain imports Infrastructure - DDD layer violation
  ✗ PHP001: Missing declare(strict_types=1) in class file
```

The AI reads the same two lines, corrects the code, and saves a clean
version. That refusal is the product working, not failing.

## The two places it runs

- **Claude Code**: the assistant your developers use in their editor and
  terminal. Craftsman installs as a plugin there.
- **Hermes agents**: autonomous AI workers that code without a human watching
  each step. There, Craftsman refuses to let the agent declare a task
  finished while serious problems remain, and teaches it the right repair
  method (refactoring, testing, debugging) for each situation. An unwatched
  agent is exactly where a radar matters most.

## Questions worth asking your team

- "Is the gate on in the pipeline, not just on laptops?" (One yes: the same
  rules run in both, by design.)
- "What are our most-violated rules this month?" (`/craftsman:metrics` shows
  the trend; recurring violations are a signal about pressure, not about
  people.)
- "When the gate refuses something, do we relax the rule or fix the code?"
  (Relaxing is sometimes right, and it is always a reviewed, visible
  decision: the plugin refuses to let the AI relax rules for itself.)

## What it does not do

It does not judge whether the product idea is good, whether the feature is
useful, or whether the tests assert the right business behaviour. It enforces
structure, the part that silently decays. Humans keep the judgment calls; the
plugin makes sure nobody has to spend their judgment on `strict_types`.
