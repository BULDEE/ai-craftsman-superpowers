---
name: craftsman-quality
description: How to write code that passes the craftsman gate, and how to answer it when it refuses a turn. Load when coding in a repository where the craftsman plugin is enabled.
version: 1.0.0
platforms: [macos, linux]
metadata:
  hermes:
    tags: [quality, architecture, ddd, craftsmanship]
    category: devops
    requires_toolsets: [terminal]
---

# Craftsman quality

## When to Use

Any coding turn in a workspace where the craftsman plugin is enabled. The gate
runs on `pre_verify`: it scans everything the turn produced (worktree, new
files, commits) and refuses the conclusion while critical violations remain.
Advisory findings arrive once, as a nudge, and never block.

## Procedure

1. Write code that respects the families the gate enforces:
   - **Layers**: Domain imports nothing from Infrastructure or Presentation.
     Application imports Domain. Dependencies point inward, always.
   - **PHP**: `declare(strict_types=1)` first line, `final` classes, private
     constructor plus a `static create()` factory, behaviour methods instead
     of setters, no empty `catch`.
   - **TypeScript**: no `any` (use precise types or `unknown`), named exports,
     `readonly` by default, no non-null assertion `!`.
   - **Security**: no hardcoded secret, no dynamic `eval`, no SQL built by
     string concatenation.
2. When the gate blocks, read the list it returns: one `file:line RULE`
   entry per finding. Fix every listed finding, then conclude again; the gate
   re-runs and releases the turn when the scan is clean.
3. Do not edit `.craft-rules.yml` or `.craft-config.yml` to silence a rule:
   the gate refuses any turn whose diff touches its own configuration. Rule
   changes go through a reviewed commit by a human.
4. Run `/craftsman` at any point for an on-demand verdict on the worktree,
   `/craftsman status` for the plugin's own state.

## Pitfalls

- A clean `git status` is not a clean turn: committed work is scanned too,
  back to the branch point.
- Writing through the terminal (`sed -i`, `tee`, redirects) does not evade
  the gate; scope comes from git, not from the tool name.
- Suppressing with `// craftsman-ignore: RULE` is recorded and counted; use
  it for a documented exception, not as an exit.
- If the gate reports it "could not run", that is a blocked turn, not a
  green one: say so instead of concluding.

## Verification

Before concluding any coding turn, state what you ran to prove the change
works (test command and its result). The gate checks structure; only your
test run checks behaviour. A turn that ends with "done" and no evidence is
not done.
