# Beginner Guide

Welcome to your journey as an AI-Augmented Craftsman. This guide assumes basic programming knowledge but no experience with DDD, Clean Architecture, or AI tooling.

## What You'll Learn

- [x] Using core skills effectively
- [x] Understanding the craftsman workflow
- [x] Basic DDD concepts through practice
- [x] Writing better code with AI assistance

## Prerequisites

- AI Craftsman Superpowers installed ([Installation Guide](../getting-started/installation.md))
- A project to work on (any language)
- Basic git knowledge

---

## Lesson 1: The /craftsman:design Command

### What is Domain-Driven Design?

DDD is about **modeling your code after the business domain**. Instead of thinking in database tables, you think in business concepts.

**Before DDD:**
```
users table → UserRepository → UserService → UserController
(Data-centric, anemic)
```

**After DDD:**
```
User entity → User.register(email, password) → UserRegistered event
(Behavior-centric, rich domain)
```

### Your First Design Session

```bash
claude
```

```
> /craftsman:design

I'm building a simple blog system.
I need to represent a BlogPost that can be published or draft.
```

**What happens:**

1. **Phase 1 - Understand**: Claude asks about your domain
   - What makes a post "published"?
   - Can a published post go back to draft?
   - What happens when published?

2. **Phase 2 - Challenge**: Claude explores alternatives
   - Should "status" be an enum or state pattern?
   - Is BlogPost an Entity or Aggregate?
   - What about Author as a separate aggregate?

3. **Phase 3 - Recommend**: Claude proposes a design
   ```
   RECOMMENDATION: BlogPost as AggregateRoot
   - status: PostStatus (enum)
   - publish(): void (behavioral method)
   - emits: PostPublished event
   ```

4. **Phase 4 - Implement**: After your approval, Claude generates code

### Key Takeaways

- **Don't skip phases**: The questioning reveals requirements you missed
- **Behavioral methods > setters**: `post.publish()` not `post.setStatus('published')`
- **Events capture intent**: `PostPublished` tells *what happened*

### Further Reading

- [What is DDD?](https://martinfowler.com/bliki/DomainDrivenDesign.html) - Martin Fowler (5 min)
- [Entities vs Value Objects](https://enterprisecraftsmanship.com/posts/entity-vs-value-object-the-ultimate-list-of-differences/) - Vladimir Khorikov (10 min)

---

## Lesson 2: The /craftsman:debug Command

### Systematic Debugging

Most developers debug by:
1. Staring at code
2. Adding random console.log
3. Guessing and changing things

Craftsmen debug by:
1. **Forming hypotheses**
2. **Testing each systematically**
3. **Finding root cause before fixing**

### Your First Debug Session

```
> /craftsman:debug

Users can't log in. The login form submits but nothing happens.
No errors in browser console.
```

**Claude applies ReAct pattern:**

```
THOUGHT: No client-side error suggests server-side issue
ACTION: Check server logs
OBSERVATION: 500 error on POST /api/login

THOUGHT: 500 error, need stack trace
ACTION: Check full error log
OBSERVATION: "Column 'last_login' cannot be null"

THOUGHT: Database constraint failing
ACTION: Check User entity for last_login handling
OBSERVATION: last_login not set on new users

ROOT CAUSE: Migration added NOT NULL column without default
FIX: Add default value or make nullable
```

### Key Takeaways

- **Hypothesize before acting**: Don't change random code
- **One variable at a time**: Change one thing, observe, repeat
- **Find root cause**: Don't fix symptoms

### Further Reading

- [Debugging Guide](https://jvns.ca/blog/2019/06/23/a-few-debugging-tips/) - Julia Evans (10 min)
- [Systematic Debugging](https://www.debuggingbook.org/) - Free online book

---

## Lesson 3: The /craftsman:test Command

### Why Test?

Tests aren't just about catching bugs. They:
- **Document behavior**: Tests show how code should be used
- **Enable refactoring**: Change code confidently
- **Design feedback**: Hard-to-test code is poorly designed

### Your First Test Session

```
> /craftsman:test

I need tests for the BlogPost entity.
Focus on the publish behavior.
```

**Claude applies test methodology:**

```
TEST STRATEGY (AAA Pattern):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. test_can_publish_draft_post
   ARRANGE: Create draft post
   ACT: Call publish()
   ASSERT: Status is published, event emitted

2. test_cannot_publish_already_published_post
   ARRANGE: Create published post
   ACT: Call publish()
   ASSERT: Throws InvalidStateException

3. test_publish_sets_published_date
   ARRANGE: Create draft post
   ACT: Call publish()
   ASSERT: publishedAt is set to now
```

### The Test Pyramid

```
        /\
       /E2E\         Few, slow, expensive
      /------\
     /Integration\   Some, medium speed
    /-------------\
   /     Unit      \ Many, fast, cheap
  /-----------------\
```

Focus on unit tests (70%), then integration (20%), then E2E (10%).

### Key Takeaways

- **One concept per test**: Test one thing only
- **Test behavior, not implementation**: Test what, not how
- **Descriptive names**: `test_cannot_publish_without_title` > `testPublish3`

### Further Reading

- [Test Pyramid](https://martinfowler.com/bliki/TestPyramid.html) - Martin Fowler (5 min)
- [Unit Testing Best Practices](https://www.toptal.com/qa/how-to-write-testable-code-and-why-it-matters) - Toptal (15 min)

---

## Lesson 4: The Craftsman Workflow

### Putting It All Together

Real work combines skills in a natural flow:

```
1. UNDERSTAND THE REQUIREMENT
   > What do I need to build?

2. DESIGN THE SOLUTION
   > /craftsman:design - Model the domain

3. WRITE TESTS FIRST
   > /craftsman:test - Define expected behavior

4. IMPLEMENT
   > Write code to pass tests

5. DEBUG IF NEEDED
   > /craftsman:debug - Systematic investigation

6. REFACTOR
   > /craftsman:refactor - Improve without changing behavior

7. REVIEW
   > /craftsman:challenge - Validate decisions
```

### Example: Adding Comments to BlogPost

```
# 1. Design
> /craftsman:design
Add comment functionality to BlogPost.
Users can comment on published posts.

# 2. Test
> /craftsman:test
Tests for the new comment feature

# 3. Implement
[Write code to pass tests]

# 4. Review
> /craftsman:challenge
Review the comment implementation
```

---

## Practice Exercises

### Exercise 1: Design a Shopping Cart

```
> /craftsman:design
Create a shopping cart that:
- Can add/remove items
- Calculates total
- Has a maximum of 50 items
```

### Exercise 2: Debug a Calculation

```
> /craftsman:debug
The cart total is sometimes wrong.
It should include tax but sometimes doesn't.
```

### Exercise 3: Test Edge Cases

```
> /craftsman:test
Tests for the shopping cart.
Focus on edge cases: empty cart, max items, negative quantities.
```

---

## Next Steps

You're ready to move on when you can:

- [ ] Use /craftsman:design to create domain entities
- [ ] Follow all 4 phases without skipping
- [ ] Use /craftsman:debug systematically
- [ ] Write meaningful tests with /craftsman:test

Continue to: [Intermediate Guide](./intermediate.md)
