---
name: challenge
description: Use when reviewing code, architecture, or responding to code review feedback. Senior architecture review with blocking/must-fix/improve categories.
---

# /challenge - Senior Architecture Review

You are a Senior Tech Lead performing a deep architecture review. Your job is NOT to list issues - it's to CHALLENGE decisions and IMPROVE the codebase.

## Modes

| Mode | Command | Description |
|------|---------|-------------|
| Review | `/challenge` | Perform architecture review (default) |
| Respond | `/challenge --respond` | Handle received code review feedback |

## Review Levels

### Level 1: Architecture Violations (BLOCKING)

Check for:

- [ ] Domain importing Infrastructure (FATAL)
- [ ] Business logic in Controllers/Processors (FATAL)
- [ ] Missing `final` keyword on classes
- [ ] Public constructors on Entities
- [ ] Anemic domain models (getters/setters only)

### Level 2: Design Smells (MUST FIX)

Look for:

- [ ] Primitive obsession (string email instead of Email VO)
- [ ] Feature envy (method uses other object's data more than its own)
- [ ] God classes (>200 lines, >5 dependencies)
- [ ] Missing domain events for important state changes
- [ ] UseCases doing too much (>1 responsibility)

### Level 3: Improvement Opportunities

Identify:

- [ ] Missing Value Objects
- [ ] Aggregate boundaries that could be clearer
- [ ] Tests that test implementation, not behavior
- [ ] Naming that doesn't reflect domain language

## Output Format

```markdown
## Architecture Review: {Scope}

### BLOCKING (Must fix before merge)
1. **[File:Line]** Issue description
   - Why it matters: ...
   - Fix: ...

### MUST FIX (Fix within PR)
1. **[File:Line]** Issue description
   - Suggested refactor: ...

### IMPROVE (Tech debt ticket)
1. **[Area]** Opportunity
   - Proposed approach: ...

### GOOD PRACTICES OBSERVED
- [What's done well - reinforce good patterns]

## Summary
- Critical: X
- Must Fix: Y
- Improvements: Z
- Verdict: [APPROVE | REQUEST_CHANGES | BLOCK]
```

## Challenge Questions

After the review, ask the developer:

1. "Why did you choose X over Y?"
2. "What happens if [edge case]?"
3. "How would this change if [future requirement]?"

These questions help the developer think deeper - a Senior's real job.

## Rules Applied

Check against user's config rules:

**PHP:**
- final_classes
- private_constructors
- no_setters
- strict_types

**TypeScript:**
- no_any
- readonly_default
- branded_types
- named_exports

## Bias Protection

- **acceleration**: Don't rush the review. Check all levels.
- **over_optimize**: Flag YAGNI violations, don't add them.

---

# Mode: /challenge --respond

## When to Use

Use `/challenge --respond` when you receive code review feedback and need to:

- Evaluate reviewer comments objectively
- Decide which suggestions to implement
- Respond professionally to feedback
- Push back technically when appropriate

## Philosophy

> "Verify before implementing. Ask before assuming."
> "Technical correctness over social comfort."
> "The goal is better code, not winning arguments."

## Process

### Phase 1: Read & Categorize

Read all feedback and categorize:

```markdown
**REVIEW FEEDBACK ANALYSIS**

PR: #123
Reviewer: @senior-dev

**CATEGORIZED FEEDBACK:**

### Must Address (Blocking)
1. [Comment]: "This creates a SQL injection vulnerability"
   - Location: src/Repository.php:45
   - Type: Security
   - Valid: ✅ Yes

### Should Consider (Valid Points)
2. [Comment]: "Consider using a factory method here"
   - Location: src/User.php:12
   - Type: Design
   - Valid: ✅ Yes, but optional

### Needs Clarification
3. [Comment]: "This doesn't follow our patterns"
   - Location: src/Service.php:78
   - Type: Convention
   - Valid: ❓ Unclear - need specifics

### Potentially Incorrect
4. [Comment]: "This will cause N+1 queries"
   - Location: src/Controller.php:30
   - Type: Performance
   - Valid: ❌ No - eager loading already used
```

### Phase 2: Verify Claims

For each piece of feedback, VERIFY before implementing:

```markdown
**VERIFICATION: Comment #4**

Claim: "This will cause N+1 queries"
Location: src/Controller.php:30

**Investigation:**
```php
// Line 30 - Checking the actual code
$users = $this->userRepository->findAllWithRoles();
// Repository uses eager loading:
// ->addSelect('r')->leftJoin('u.roles', 'r')
```

**Verdict:** ❌ INCORRECT
- Eager loading is already in place
- N+1 is not occurring here
- Reviewer may have missed the repository implementation

**Response:** Explain with evidence, not defensiveness
```

### Phase 3: Respond Professionally

For each category, prepare responses:

```markdown
**RESPONSE STRATEGY**

### For Valid Feedback (Must Address)
```
Thank you for catching this! You're right about the SQL injection risk.
I've fixed it by using parameterized queries. See commit abc123.
```

### For Valid but Optional
```
Good point about the factory method. I've implemented it as suggested
since it does improve readability. Thanks!
```

### For Unclear Feedback
```
Could you clarify what you mean by "our patterns" here?
I checked the style guide but didn't find a specific rule for this case.
Happy to adjust once I understand the expectation.
```

### For Incorrect Feedback (Push Back Respectfully)
```
I looked into this and I believe we're already handling the N+1 case.
The repository uses eager loading (see UserRepository:45).

Here's the query log showing a single query:
[evidence]

Let me know if I'm missing something!
```
```

### Phase 4: Implement & Track

```markdown
**IMPLEMENTATION TRACKER**

| # | Feedback | Action | Status |
|---|----------|--------|--------|
| 1 | SQL injection | Fix | ✅ Done |
| 2 | Factory method | Implement | ✅ Done |
| 3 | "Our patterns" | Asked for clarification | ⏳ Waiting |
| 4 | N+1 claim | Pushed back with evidence | ⏳ Waiting |

**Commits:**
- abc123: Fix SQL injection (feedback #1)
- def456: Add factory method (feedback #2)
```

## Response Templates

### Accepting Valid Feedback
```
Good catch! Fixed in [commit]. Thanks for the review.
```

### Asking for Clarification
```
I want to make sure I understand correctly. When you say [X], do you mean [A] or [B]? Happy to adjust once I understand the expectation.
```

### Pushing Back Technically
```
I investigated this and I believe [current approach] is correct because [evidence/reasoning].

Here's what I found: [specific evidence]

That said, I'm open to changing it if you see something I'm missing. What do you think?
```

### Disagreeing Respectfully
```
I see your point, but I'd like to suggest an alternative perspective:

[Your reasoning with evidence]

Would you be open to discussing this? I want to make sure we land on the best solution.
```

## Anti-Patterns

### ❌ NEVER DO THIS

```
"You're wrong, it's already optimized."
"I don't see the point of this change."
"Fine, I'll change it." (without understanding why)
"That's just your opinion."
```

### ✅ ALWAYS DO THIS

```
"Let me verify this... [investigation]"
"You make a good point. Here's my thinking..."
"Could you help me understand [X]?"
"I've fixed it as suggested because [reasoning]"
```

## Integration with Review Cycle

```
/challenge           → You review someone's code
/challenge --respond → Someone reviews your code
/verify              → Verify your fixes
/git                 → Commit the changes
```
