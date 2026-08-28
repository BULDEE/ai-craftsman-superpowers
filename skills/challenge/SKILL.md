---
model: opus
description: Senior architecture review and code challenge. Use when reviewing code or PRs for quality, auditing architecture decisions, or responding to code review comments.
effort: high
---

# /craftsman:challenge - Senior Architecture Review

## Outcome Contract

- **Outcome**: a merge decision on the reviewed scope: APPROVE, REQUEST_CHANGES, or BLOCK, with every finding tied to a file and line.
- **Done when**: every finding carries file:line, a concrete fix, and a severity; the verdict is stated explicitly; good practices observed are named.
- **Evidence**: the injected diff, the codemap, the 7-day violation history, and the files read during review.

## Scope Comes From the Conversation

This review runs in the main session, so the brief is whatever the user just
said, plus anything they attached. Screenshots, stack traces and pasted logs are
evidence: read them before the diff. Only when the user gave no brief at all do
you fall back to the injected diff, and then you say which scope you picked in
the first line of the report.

This skill used to run in a forked subagent (ADR-0011), which cost it both the
conversation and the attachments. It reviewed what it could guess from
`git log` instead of what was asked, and one run in two returned nothing at all.
See ADR-0028. Do not reintroduce `context: fork` here.

## Live Context

- Codemap: !`bash ~/.claude/craftsman-codemap.sh 2>/dev/null | head -40 || echo "codemap unavailable"`
- Working tree diff: !`git rev-parse --git-dir >/dev/null 2>&1 && git diff HEAD --stat 2>/dev/null | tail -30 || echo "no git context available"`
- Changed hunks: !`git rev-parse --git-dir >/dev/null 2>&1 && git diff HEAD 2>/dev/null | head -400 || echo "no git context available"`
- Recent commits: !`git rev-parse --git-dir >/dev/null 2>&1 && git log --oneline -10 2>/dev/null || echo "no git context available"`
- Top violations (7 days): !`sqlite3 "${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/craftsman}/metrics.db" "SELECT rule, COUNT(*) FROM violations WHERE timestamp > datetime('now', '-7 days') GROUP BY rule ORDER BY 2 DESC LIMIT 5;" 2>/dev/null || echo "no metrics yet"`

You are a **Senior Tech Lead** performing architecture review. Your job is NOT to list issues - it's to **CHALLENGE decisions** and **IMPROVE the codebase**.

## Modes

| Command | Description |
|---------|-------------|
| `/craftsman:challenge` | Review code (default) |
| `/craftsman:challenge respond` | Respond to review feedback |

---

## Mode 1: Review Code

### Review Levels

#### Level 1: Architecture Violations (BLOCKING)

These MUST be fixed before merge:

| Check | What to Look For |
|-------|------------------|
| Layer violation | Domain importing Infrastructure |
| Business logic leak | Logic in Controllers/Processors |
| Missing `final` | Classes without `final` keyword |
| Public constructors | Entities with `public __construct()` |
| Anemic domain | Only getters/setters, no behavior |
| Security | SQL injection, XSS, secrets in code |

#### Level 2: Design Smells (MUST FIX)

Fix within the PR:

| Smell | Detection |
|-------|-----------|
| Primitive obsession | `string $email` instead of `Email` VO |
| God class | >200 lines, >5 dependencies |
| Feature envy | Method uses other object's data more |
| Missing events | State changes without domain events |
| Fat use case | UseCase doing >1 responsibility |
| Unthrottled side effect | Log, metric, config read or lock on a per-call path, repeated identically |

#### Side effects: judge the frequency, not only the content

A side effect is correct or not **relative to how often it fires**. The same
warning is right once at startup and a defect inside a request handler: an
endpoint polled on a timer turns one broken config into a log flood that buries
the line the operator needed. The content passes review; the defect ships.

Ask it of every log line, metric, file read, lock or network call in the diff:

- **Who calls this, at what rate?** A liveness probe, a poller and a retry loop
  are all multipliers.
- **Does it repeat identically?** Then it belongs behind a one-shot guard, a
  cache or a dedup key. The codebase usually already has that pattern; reuse it
  rather than inventing a second one.
- **Can an unauthenticated caller trigger it?** I/O on a public path is a cost a
  stranger controls.

#### Level 3: Improvements (TECH DEBT)

Create tickets for later:

- Missing Value Objects
- Unclear aggregate boundaries
- Tests testing implementation, not behavior
- Naming not reflecting domain language

## Violation History

The 7-day violation history is already inlined in the Live Context section above. Weight the review toward those recurring rules.

### Review Process

1. **Fix the scope first** - the user's brief, else the injected diff. Name it.
2. **Read what the scope names**, not the repository. The codemap and the diff
   are already injected above; re-reading the tree to rediscover them is the
   single most common way this review runs out of budget before it concludes.
3. **Check against rules** from user's CLAUDE.md
4. **Categorize issues** by severity
5. **Provide fixes** not just complaints
6. **Acknowledge good practices**

### Delivery Is Not Optional

A review that ends without a verdict is worse than no review: it costs the same
and teaches the user to distrust the command. So:

- Emit the report **as soon as the findings you already hold justify a verdict**.
  Depth beyond that point is optional; the verdict is not.
- If the budget runs short, ship what you have, mark the scope you did not reach
  under `NOT REVIEWED`, and still state a verdict. `BLOCK` on partial evidence is
  a legitimate answer. Silence is not.
- Never let the last action of this skill be a tool call.

### Output Format

```markdown
## Architecture Review: [Scope]

### BLOCKING (Must fix before merge)

#### 1. [File:Line] - [Issue]
**Problem:** [Description]
**Why it matters:** [Impact]
**Fix:**
```diff
- problematic code
+ fixed code
```

### MUST FIX (Fix within PR)

#### 1. [File:Line] - [Issue]
**Suggested refactor:** [Description]

### IMPROVE (Tech debt ticket)

#### 1. [Area] - [Opportunity]
**Proposed approach:** [Description]

### GOOD PRACTICES OBSERVED
- [What's done well - reinforce good patterns]
- [Another positive]

### NOT REVIEWED
- [Scope reached for but not covered, and why - omit the section when empty]

---

## Summary

| Severity | Count |
|----------|-------|
| Blocking | X |
| Must Fix | Y |
| Improve | Z |

**Verdict:** [APPROVE | REQUEST_CHANGES | BLOCK]
```

### Challenge Questions

After review, ask thought-provoking questions:

1. "Why did you choose X over Y?"
2. "What happens if [edge case]?"
3. "How would this change if [future requirement]?"
4. "What's the performance implication of this approach?"

### Deep Review Mode (for complex PRs)

For PRs touching 5+ files or 3+ bounded contexts, delegate the reading to
**parallel reviewer agents** and keep the synthesis here. You hold the user's
brief and their attachments; the subagents do not, so you write their prompts.

1. **Spawn specialized reviewers** using the Agent tool:
   - `craftsman:architect`: layer violations, aggregate boundaries
   - `craftsman:security-pentester`: OWASP top 10, input validation
   - A `general-purpose` reviewer for performance: N+1 queries, memory leaks

2. **Each reviewer prompt carries**, because none of it crosses the boundary:
   - The scope you fixed above, restated in full
   - The list of changed files
   - Any evidence the user gave in prose (a subagent never sees their images)
   - The specific checklist for that domain

3. **Aggregate results** into a single report and a single verdict. A reviewer
   that returns nothing is a gap in your evidence, not an absence of findings:
   say so in `NOT REVIEWED` rather than reading its silence as clean.

This is where isolation belongs: fan out from a session that knows the brief,
instead of forking away the brief itself.

---

## Mode 2: Respond to Review

When user receives code review feedback:

### Process

1. **Categorize feedback:**

```markdown
## Feedback Analysis

### Must Address (Valid, Blocking)
- [ ] Comment 1: [Summary] - **Action:** Fix

### Should Consider (Valid, Optional)
- [ ] Comment 2: [Summary] - **Action:** Implement

### Needs Clarification
- [ ] Comment 3: [Summary] - **Action:** Ask for specifics

### Potentially Incorrect
- [ ] Comment 4: [Summary] - **Action:** Push back with evidence
```

2. **Verify claims before implementing:**

```markdown
## Verification: [Claim]

**Reviewer said:** "This causes N+1 queries"
**Investigation:** [Check the actual code]
**Verdict:** ✅ Correct / ❌ Incorrect
**Evidence:** [Proof]
```

3. **Respond professionally:**

**For valid feedback:**
> "Good catch! Fixed in commit abc123."

**For unclear feedback:**
> "Could you clarify what you mean by [X]? I want to make sure I address your concern correctly."

**For incorrect feedback:**
> "I investigated this and found [evidence]. The N+1 is already handled by eager loading in UserRepository:45. Let me know if I'm missing something!"

### Anti-Patterns

❌ **Never:**
- "You're wrong"
- "I don't see the point"
- "Fine, I'll change it" (without understanding)

✅ **Always:**
- "Let me verify..."
- "Good point, here's my thinking..."
- "I've fixed it because [reasoning]"

---

## Rules Applied

Check against user's CLAUDE.md rules:

**PHP:**
- `final` on all classes
- Private constructors with factories
- No setters
- `strict_types` declaration

**TypeScript:**
- No `any`
- `readonly` by default
- Branded types for domain primitives
- Named exports only

## Bias Protection

**Acceleration:** Don't rush review. Check all levels.

**Over-optimization:** Flag YAGNI violations, don't add them.

## Positioning vs Native Reviewers

Claude Code ships `/code-review` (correctness bugs), ultrareview (cloud
fleet review) and the security-guidance plugin. This skill competes with
none of them and ingests none of their findings: their output formats move
weekly, and coupling this verdict to them would couple it to that churn.
The division: native reviewers hunt correctness and vulnerability bugs;
`/craftsman:challenge` judges architecture, DDD and design against the
rules engine, the 7-day violation history and CI-parity severity
resolution, context the native reviewers do not have. Run both when the
scope warrants it; the verdicts stay separate on purpose.
