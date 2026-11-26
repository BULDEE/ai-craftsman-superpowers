# Example: Drain the Queue

## Prompt

```
/craftsman:factory run
```

Two issues carry the `factory` label: #12 "Reject an order whose total is
negative" and #14 "Make checkout faster". `concurrency` is 1.

## Expected Behavior

### Step 1: The queue

The dispatcher asks the script what to do. It judges no issue itself.

```bash
craftsman-factory queue
```

```
new   12  -  -  run `create 12`: Reject an order whose total is negative
hold  14  -  -  no free slot: Make checkout faster
```

### Step 2: Intake

```bash
craftsman-factory create 12      # prints 001-reject-an-order-whose-total
craftsman-factory step 001-reject-an-order-whose-total
```

```
SPAWN  001-reject-an-order-whose-total  craftsman:factory-intake  -  intake-001-reject-an-order-whose-total  Job: 001-... Issue: 12. Decide whether this issue is worth building and at what scope.
```

The prompt carries paths and a mission. The issue's text is in `issue.md`,
quoted, and never in the prompt. The dispatcher starts the agent in the
background and ends its turn:

```
001 #12: intake running.
```

### Step 3: Each return advances the job

When the intake returns, the dispatcher runs the script again, naming the agent:

```bash
craftsman-factory step 001-reject-an-order-whose-total --returned intake-001-reject-an-order-whose-total
```

```
STATE  001-...  design  accepted, medium risk
SPAWN  001-...  craftsman:factory-spec-writer  -  spec-writer-001-...-design  Job: 001-... Mode: design. ...
```

The intake rated the `domain` surface, so the change is modelled before it is
specified. The same loop carries the job through spec and build. The report
stays one line per transition:

```
001 #12: accepted, medium risk -> design
001 #12: design written -> spec
001 #12: spec ready -> build round 1
001 #12: round 1 built and pushed -> gate
```

### Step 4: The gate decides whether a reviewer runs

The builder returned `STATUS: READY`. The script pushes the branch, opens the
draft pull request, and runs the gate. Here it fails:

```
STATE  001-...  build  gate FAIL, build round 2
SPAWN  001-...  craftsman:factory-builder  -  builder-001-...  Job: 001-... Build round 2. The gate failed: read round-1/checks.md and checks.log, and fix what it names.
```

No reviewer was started on a failing build. The dispatcher continues the same
builder with `SendMessage`, so it keeps its context. Round 2 passes:

```
STATE  001-...  review  gate PASS, reviewers: symfony, architecture
SPAWN  001-...  craftsman:factory-reviewer  sonnet  reviewer-001-...-symfony       ... Lens: <plugin>/agents/symfony-reviewer.md. ...
SPAWN  001-...  craftsman:factory-reviewer  sonnet  reviewer-001-...-architecture  ... Lens: <plugin>/agents/architect.md. ...
```

Both reviewers start in one message and run in parallel.

### Step 5: Ready, with a review depth

```
STATE  001-...  ready  ready for review, confidence 55 (standard)
WAIT   001-...  ready  pull request https://github.com/acme/shop/pull/31 awaits your review (review:standard)
```

The pull request carries the label and a comment that lists every deduction:

```
Confidence 55/100, review depth: standard
- -15: medium risk
- -10: touches the domain surface
- -15: the spec of a domain change was written by the factory
- -10: 1 extra build round(s)
```

### Step 6: The next issue

A slot is free. The dispatcher runs `queue` again and starts #14. Its intake
answers `NEEDS-INFO`: "faster" names no page and no target.

```
STATE  002-make-checkout-faster  needs-info  questions posted on the issue
```

### Step 7: Summary

```
job                               issue  stage       rounds  confidence   cost    pull request
001-reject-an-order-whose-total   12     ready       2       55 standard  ~$1.84  https://github.com/acme/shop/pull/31
002-make-checkout-faster          14     needs-info  0       -            ~$0.21  -

Waiting on you:
- #12: pull request 31, review:standard. Read the whole diff once, with the spec beside it.
- #14: two questions on the issue, for its author.
Nothing was merged: merging pull request 31 is your approval.
Page: craftsman-factory page --open
```

## What the dispatcher did not do

- It did not read the issues, the spec, the diff or the reviews.
- It did not decide that #14 was too vague: the intake did, in a file.
- It did not fix the failing build "to save a round".
- It did not merge.
