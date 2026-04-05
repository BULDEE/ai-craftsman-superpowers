# Example: Workflow Starting from Implement

## Prompt

```
/craftsman:workflow --from implement
I already designed and spec'd the caching layer. Ready to code.
```

## Context

- Design and spec phases already completed in a previous session
- User wants to jump straight to implementation

## Expected Behavior

### Pipeline Initialization (Skipped Steps Shown)

```
Starting Development Pipeline (from: implement)...

Pipeline Progress:
  [~] design    — Skipped (--from)
  [~] spec      — Skipped (--from)
  [~] plan      — Skipped (--from)
  [ ] implement — Write code
  [ ] test      — Run tests
  [ ] verify    — Evidence check
  [ ] commit    — Version control
```

### Step 4: Implement

```
Step 4/7: IMPLEMENT — Write the code. Craftsman hooks validate in real-time.
Go ahead and implement. Tell me when you're done.
```

Proceeds normally from here through test → verify → commit.

## When to Use

- Design/spec done in a previous session
- Resuming after a break
- Bug fix where you already know the root cause
- Refactoring with clear scope
