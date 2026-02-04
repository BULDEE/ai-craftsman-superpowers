# Example: Safe Git Commit Workflow

## Prompt

```
/craftsman:git
I want to commit my changes for the new User entity
```

## Expected Behavior

### Step 1: Analyze Changes

Claude runs:
```bash
git status
git diff --staged
git diff
```

### Step 2: Suggest Atomic Commits

```markdown
## Proposed Commits

Based on your changes, I recommend **3 atomic commits**:

### Commit 1: Value Object
```
feat(user): add Email value object

Files:
- src/Domain/ValueObject/Email.php
- tests/Unit/Domain/ValueObject/EmailTest.php
```

### Commit 2: Entity
```
feat(user): add User entity with factory pattern

Files:
- src/Domain/Entity/User.php
- tests/Unit/Domain/Entity/UserTest.php
```

### Commit 3: Domain Event
```
feat(user): add UserRegistered domain event

Files:
- src/Domain/Event/UserRegisteredEvent.php
```

---

### Alternative: Single Commit
```
feat(user): implement User domain model

Adds User entity with:
- Email value object
- Factory pattern
- UserRegistered event
- Unit tests

Files: [all 5 files]
```

**Which approach do you prefer?**
- [ ] 3 atomic commits (recommended for better history)
- [ ] 1 combined commit (simpler)
```

### Step 3: Execute (after choice)

If user chooses atomic:

```bash
# Commit 1
git add src/Domain/ValueObject/Email.php tests/Unit/Domain/ValueObject/EmailTest.php
git commit -m "feat(user): add Email value object"

# Commit 2
git add src/Domain/Entity/User.php tests/Unit/Domain/Entity/UserTest.php
git commit -m "feat(user): add User entity with factory pattern"

# Commit 3
git add src/Domain/Event/UserRegisteredEvent.php
git commit -m "feat(user): add UserRegistered domain event"
```

## Destructive Command Protection

If user asks:
```
git reset --hard HEAD~3
```

Claude MUST respond:

```markdown
## DESTRUCTIVE COMMAND DETECTED

**Command:** `git reset --hard HEAD~3`

**What this will do:**
- Permanently delete the last 3 commits
- Discard ALL uncommitted changes
- This action is IRREVERSIBLE

**Safer alternatives:**
1. `git revert HEAD~3..HEAD` - Undo with new commits (reversible)
2. `git stash` - Save uncommitted changes first
3. `git reset --soft HEAD~3` - Undo commits, keep changes staged

**To proceed anyway:** Type exactly:
"I understand the risks, proceed with reset --hard"
```

## Test This Example

1. Make some changes in a test repository
2. Run `/craftsman:git`
3. Verify Claude suggests atomic commits
4. Test destructive command protection with `git reset --hard`
