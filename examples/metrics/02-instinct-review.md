# Example: Instinct Review (v4)

Reviewing and approving a learned instinct with `/craftsman:metrics`.

## Context

Session start showed: `Instincts: 1 candidate(s) pending review - run /craftsman:metrics`. The project has corrected `PHP001` (missing `strict_types`) repeatedly.

## Invocation

```
/craftsman:metrics
```

## What happens (Step 9: Instinct Review)

Claude lists the pending candidates:

```bash
bash ~/.claude/craftsman-instincts.sh candidates
```

```
#1 PHP001 [candidate] confidence=0.74 corrections=3 files=3 context=added strict_types
```

Claude presents the evidence and asks for a decision:

> Candidate instinct **PHP001**, confidence 0.74: `declare(strict_types=1)` was added by hand 3 times across 3 files (`src/A/`, `src/B/`, `src/C/`). Approve to codify as a project skill, or reject?

## On approval

```bash
bash ~/.claude/craftsman-instincts.sh approve 1 "$PWD/.claude/skills/craftsman-learned"
```

```
approved: .claude/skills/craftsman-learned/learned-php001/SKILL.md
```

The generated skill is `user-invocable: false` (background knowledge), records its provenance (source corrections, approval date), is shareable with the team via git, and can be retired anytime by deleting the directory.

## On rejection

```bash
bash ~/.claude/craftsman-instincts.sh reject 1
```

The candidate is not re-proposed unless significant new evidence accumulates (3+ new corrections). Promotion is never automatic ([ADR-0020](../../docs/adr/0020-instinct-promotion-human-review.md)).
