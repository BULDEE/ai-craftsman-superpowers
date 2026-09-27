# Example: Red Test Burndown

## Prompt

```
/craftsman:loop
Goal: fix failing tests for the payment refund feature. Verify: vendor/bin/phpunit tests/Feature/RefundPaymentTest.php. Max: 5 iterations. When we run out of iterations or tests pass, what's the open gap?
```

## Expected Behavior

### Step 1: Card

The loop card is built from the brief and shown before any iteration runs. The
verify command comes from the user; the skill never invents one.

```markdown
## Loop Card

| Field | Value |
|-------|-------|
| goal | Every test in RefundPaymentTest passes |
| verify | vendor/bin/phpunit tests/Feature/RefundPaymentTest.php |
| max_iterations | 5 |
| stop_on | green, no_progress, budget |
| escalate | If the loop stops red: does the remaining assertion describe the refund rule we want, or is the test wrong? |
```

### Step 2: Baseline

Verify runs once. The baseline is red, so the loop has something to fix.

```markdown
## Baseline

vendor/bin/phpunit tests/Feature/RefundPaymentTest.php

Verdict: red
Failure set (4):
- test_refund_reduces_customer_balance
- test_refund_emits_payment_refunded_event
- test_refund_fails_if_transaction_not_found
- test_refund_logs_audit_entry
```

### Step 3: Iterate

One atomic change, one full verify, one ledger line per iteration, in the
format the skill fixes: `iteration N: <verdict> - <what changed> - <delta vs previous>`.

```markdown
## Ledger

iteration 1: red - RefundPaymentHandler debits the refund amount from the customer balance - 1 fixed (test_refund_reduces_customer_balance), 3 remaining
iteration 2: red - handler records a PaymentRefunded domain event - 1 fixed (test_refund_emits_payment_refunded_event), 2 remaining
iteration 3: red - handler throws TransactionNotFound when the repository returns null - 1 fixed (test_refund_fails_if_transaction_not_found), 1 remaining
iteration 4: green - handler passes the refund to the injected AuditLog port - 1 fixed (test_refund_logs_audit_entry), 0 remaining

Note for the next /craftsman:plan: refunds and chargebacks duplicate the balance
adjustment; not addressed here, the loop optimizes one verdict.
```

No test was edited and no assertion was relaxed: the verify command stays the
only judge.

### Step 4: Stop

Iteration 4 turned verify green, the first stop condition to fire. Neither
no_progress (two consecutive identical failure sets) nor budget (5 iterations)
was reached.

### Step 5: Deliver

```markdown
## Verdict: green

Final verify output:
  OK (4 tests, 9 assertions)

Iterations used: 4 of 5
Ledger: the four lines above, one diff each
Remaining gap: none
```

The escalation question is not asked: the skill delivers it only when the loop
stops short of green. Had iterations 3 and 4 both ended on the same failing
`test_refund_logs_audit_entry`, the verdict would have been no_progress, with
that test named as the remaining gap and the card's escalate question put to
the user.

## Key Points

- The loop card is shown before the baseline runs; `goal`, `verify` and
  `escalate` are required, `max_iterations` defaults to 5
- A green baseline stops the loop immediately: there is nothing to fix
- One iteration is the smallest change that could flip the verdict, followed by
  a full verify; batching edits between verifies is refused
- The loop ends with one of three verdicts: green, no_progress or budget spent,
  and always shows the final verify output and the full ledger
- Discoveries become ledger notes for the next `/craftsman:plan`, never a new
  goal mid-loop
- For cadence across turns (waiting on a CI run or a deploy), the skill builds
  the card and hands off: paste it as the prompt of the native `/loop`
