# Example: Full Workflow for a New Feature

## Prompt

```
/craftsman:workflow
I need to add a "forgot password" feature with email verification.
```

## Expected Behavior

### Pipeline Initialization

```
Starting Development Pipeline...

Pipeline Progress:
  [ ] design    — Domain modeling
  [ ] spec      — Test specifications
  [ ] plan      — Task breakdown
  [ ] implement — Write code
  [ ] test      — Run tests
  [ ] verify    — Evidence check
  [ ] commit    — Version control
```

### Step 1: Design

```
Step 1/7: DESIGN — Domain modeling and business understanding.
Invoking /craftsman:design...
```

Claude runs the full DDD design process:
- Phase 1: Understand (business problem, invariants, events)
- Phase 2: Challenge (alternatives)
- Phase 3: Recommend

```
Design complete. Continue to SPEC? [Y/skip/stop]
> Y
```

### Step 2: Spec

```
Step 2/7: SPEC — Write tests before code (TDD/BDD).
Invoking /craftsman:spec...
```

Claude writes failing tests for the password reset flow.

```
Spec complete. Continue to PLAN? [Y/skip/stop]
> Y
```

### Step 3: Plan

```
Step 3/7: PLAN — Break implementation into atomic tasks.
Invoking /craftsman:plan...
```

Claude creates a task breakdown (PasswordResetToken VO, ResetPasswordUseCase, etc.)

```
Plan complete. Continue to IMPLEMENT? [Y/skip/stop]
> Y
```

### Step 4: Implement

```
Step 4/7: IMPLEMENT — Write the code. Craftsman hooks validate in real-time.
Go ahead and implement. Tell me when you're done.
```

User codes. Hooks fire on every Write/Edit. Bias detector monitors prompts.

```
> Done implementing.
Implementation done. Continue to TEST? [Y/skip/stop]
> Y
```

### Step 5: Test

```
Step 5/7: TEST — Verify all tests pass.
Invoking /craftsman:test...
```

```
Tests complete. Continue to VERIFY? [Y/skip/stop]
> Y
```

### Step 6: Verify

```
Step 6/7: VERIFY — Evidence-based verification. No claims without proof.
Invoking /craftsman:verify...
```

```
Verification complete. Continue to COMMIT? [Y/skip/stop]
> Y
```

### Step 7: Commit

```
Step 7/7: COMMIT — Create a clean conventional commit.
Invoking /craftsman:git...
```

```
Workflow complete! All steps executed successfully.

Pipeline Progress:
  [x] design    — Domain modeling
  [x] spec      — Test specifications
  [x] plan      — Task breakdown
  [x] implement — Write code
  [x] test      — Run tests
  [x] verify    — Evidence check
  [x] commit    — Version control
```
