# First Steps

Welcome! This guide will walk you through your first interactions with AI Craftsman Superpowers.

## Your First Skill: /design

Let's design a simple domain entity.

### 1. Start Claude Code in your project

```bash
cd ~/your-project
claude
```

### 2. Invoke the design skill

```
> /design

I need to create a User entity for a registration system.
Users have email, password hash, and registration date.
```

### 3. Follow the process

The skill will guide you through **4 mandatory phases**:

```
Phase 1: UNDERSTAND
────────────────────
Claude asks clarifying questions:
- What are the business invariants?
- Should email be unique?
- What events should registration emit?

Phase 2: CHALLENGE
────────────────────
Claude proposes alternatives:
- Is this an Entity or Value Object?
- Should password be a separate VO?
- Alternative: UserCredentials aggregate?

Phase 3: RECOMMEND
────────────────────
RECOMMENDATION: Entity (AggregateRoot)
REASON: Has identity, lifecycle, invariants
TRADE-OFF: More complexity than VO

"Do you want me to proceed with this design?"

Phase 4: IMPLEMENT
────────────────────
Generates:
- src/Domain/User/User.php
- src/Domain/User/Event/UserRegistered.php
- tests/Unit/Domain/User/UserTest.php
```

## Your Second Skill: /debug

Something not working? Use systematic debugging.

```
> /debug

The user registration is throwing a 500 error.
The error log shows "Integrity constraint violation".
```

Claude will apply the **ReAct pattern**:

```
HYPOTHESIS 1: Duplicate email
ACTION: Search for unique constraint on users table
OBSERVATION: Constraint exists, but no check in code
CONCLUSION: Missing email uniqueness validation

RECOMMENDED FIX: Add email existence check in RegisterUserUseCase
```

## Your Third Skill: /test

Need to add tests?

```
> /test

I need tests for the User entity we just created.
Focus on the registration behavior.
```

Claude applies test methodology:

```
TEST STRATEGY:
- Unit tests for User.register() method
- Edge cases: invalid email, weak password
- Event emission verification

GENERATED:
- tests/Unit/Domain/User/UserTest.php
  - test_can_register_with_valid_data()
  - test_cannot_register_with_invalid_email()
  - test_emits_user_registered_event()
```

## Quick Reference: Core Skills

| Skill | Use When |
|-------|----------|
| `/design` | Creating new entities, VOs, aggregates |
| `/debug` | Investigating bugs or errors |
| `/test` | Adding or improving tests |
| `/refactor` | Improving existing code |
| `/plan` | Planning multi-step tasks |
| `/challenge` | Reviewing architecture decisions |
| `/spec` | Writing specifications |
| `/git` | Git operations |

## Pro Tips

### 1. Let Claude ask questions

Don't give all details upfront. Let the skill's process discover what's needed.

```
# Too much upfront
> /design Create a User entity with id (UUID), email (Email VO),
  passwordHash (string), createdAt (DateTimeImmutable),
  updatedAt (DateTimeImmutable), with UserRegistered event...

# Better - let the process work
> /design I need a User entity for registration
```

### 2. Use bias protection

If configured, Claude will catch your tendencies:

```
You: "Let's just quickly add a setter for the status"

Claude: "BIAS ALERT: acceleration detected.
Before adding a setter, let's consider:
- Why do we need to change status?
- Should this be a behavioral method instead?"
```

### 3. Chain skills naturally

```
> /design    # Design the entity
> /test      # Add tests for it
> /debug     # Fix any issues
> /refactor  # Clean up if needed
```

## Next Steps

- [Core Concepts](./concepts.md) - Understand the architecture
- [Beginner Guide](../guides/beginner.md) - More detailed walkthroughs
