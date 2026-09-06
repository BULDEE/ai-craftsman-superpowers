# Example: one untested class, from arrival to safety

The other two examples in this directory show what `/craftsman:legacy` says.
This one shows what happens when you do it, on a fixture you can run.

```bash
bash examples/legacy/demo.sh
```

Requirements: `python3`, `bash`, `git`. The three the plugin itself needs.
Nothing to install, no test framework, no network. Every block of output below
was copied from a real run, and the demo prints the command before each one so
you can replay any step on its own.

## The class that arrived

`examples/legacy/fixture/step1/pricing.py`. It prices a basket, it is 48 lines,
it has no tests, and it is in production. Three things make it hard to test:

- it reads the clock itself (`datetime.now`), so the weekend discount cannot be
  exercised without waiting for Saturday;
- it writes to stdout, so a test run is noisy and the message is not checkable;
- its rates are module-level constants a caller cannot substitute.

```
$ python3 hooks/lib/ratchet.py measure pricing.py
{"path": "pricing.py", "complexity": 5, "file_lines": 48, "max_fn_lines": 21, "fan_out": 2, "ignores": 0}
```

Those two numbers, `complexity 5` and `max_fn_lines 21`, are the before. Keep
them; step 4 is the after.

## Step 1: a net, before anything is touched

`step1/test_pricing.py`. Six assertions, every number **read off the running
code** rather than computed by hand. That is what makes it a characterization
test rather than a specification: you do not yet know what the code is supposed
to do, only what it does.

Three of the six record behaviour a reviewer would call wrong:

```python
def test_discounts_compound_instead_of_adding(self):
    # A gold customer buying in bulk gets 5% off, then 15% off the discounted
    # price, not 20% off.
    total, _ = self.price(10.0, 10, "gold")
    self.assertEqual(96.9, total)

def test_an_unknown_tier_is_charged_full_price_silently(self):
    # `platinum` is one typo away from `gold`, costs the customer 15%, and
    # raises nothing anywhere.
    total, _ = self.price(10.0, 1, "platinum")
    self.assertEqual(12.0, total)
```

They are recorded on purpose. A net that pins only the parts you approve of has
a hole exactly where you are about to put your foot. The bugs are **frozen**,
not blessed: fixing them is a separate decision, taken deliberately, once there
is a net that will show what changes when you do.

The clock is held still with `mock.patch`, which is **not** a seam: it reaches
into the module and replaces a name, so it breaks the moment an import moves.
It is here because the net has to exist before the code can be touched, and
this is the cheapest thing that makes today's behaviour reproducible.

```
$ python3 -m unittest test_pricing
......
Ran 6 tests in 0.001s

OK
```

## Step 1b: a net nobody has seen fail protects nothing

Six green tests prove nothing until one of them has been red for a reason you
chose. The demo changes `BULK_THRESHOLD` from 10 to 11, the exact off-by-one a
refactor introduces, and the net has to notice.

```
$ python3 -m unittest test_pricing
..FF..
FAIL: test_bulk_crosses_at_ten_not_at_eleven
AssertionError: 114.0 != 120.0

FAIL: test_discounts_compound_instead_of_adding
AssertionError: 96.9 != 102.0

Ran 6 tests in 0.001s

FAILED (failures=2)
```

Then reverted. Only now is the code safe to change.

> **The instrument had to be validated first.** The first version of this demo
> printed `OK` here. `BULK_THRESHOLD = 10` and `= 11` are the same number of
> bytes, and the edit landed in the same second as the copy before it: Python
> validates a cached `.pyc` against `(mtime, size)`, both matched, and the
> "broken" run executed the old bytecode. The demo would have taught the
> opposite of its own lesson. `PYTHONDONTWRITEBYTECODE=1` fixes it, and the
> point generalises: a red you never saw is not evidence, and neither is a
> green whose instrument you never checked.

## Step 2: one seam, and nothing else

A seam is a place where you can change behaviour without editing there. The
clock arrives through the constructor, defaulting to the real one so every
existing call site keeps working:

```diff
+    def __init__(self, clock=None):
+        self._clock = clock or datetime.now
+
     def total(self, unit_price, quantity, customer_tier):
@@
-        if datetime.now().weekday() >= 5:
+        if self._clock().weekday() >= 5:
```

Forty lines of pricing logic are untouched, deliberately. A step that
introduces a seam **and** rearranges the code is a step whose failure you
cannot attribute.

The test's assertions do not change; only the way the clock is held still does.
`mock.patch` is gone.

```
$ python3 -m unittest test_pricing
......
Ran 6 tests in 0.000s

OK
```

This commit is shippable on its own. That matters: a rescue made of shippable
steps can be paused at any point, and a rescue that cannot be paused will be
abandoned halfway.

## Step 3: one refactor, under the net

The if/elif chain of discounts becomes a table the method walks, and the
forty-line method becomes four small ones. The net is copied from step 2 **byte
for byte** and never edited:

```
$ diff -q step2/test_pricing.py step3/test_pricing.py
$ python3 -m unittest test_pricing
......
Ran 6 tests in 0.000s

OK
```

The empty `diff` output is the assertion. A net you have to edit to make the
refactor pass is a net that just told you the refactor changed behaviour.

The two recorded defects survive the refactor intact, which is correct: this
step preserves behaviour. What it does change is that `TIER_DISCOUNT.get(tier,
0.0)` puts the silent-full-price bug in one visible place, where fixing it is a
one-line decision rather than an archaeology expedition.

## Step 4: the mark the ratchet records

```
$ python3 hooks/lib/ratchet.py measure pricing.py
{"path": "pricing.py", "complexity": 1, "file_lines": 68, "max_fn_lines": 10, "fan_out": 2, "ignores": 0}
```

`complexity 5 → 1`, worst function `21 → 10` lines. The rescue is not a matter
of opinion: it is two numbers that moved. The file grew by 20 lines, and the
ratchet does not care, because `file_lines` is not a budget it enforces on its
own.

```
$ python3 hooks/lib/ratchet.py init pricing.py \
    --reason "legacy rescue: clock seam and discount table, under a characterization net"
baseline: 1 files -> .craftsman-baseline.json (1 rows)
```

The reason is required. A budget raised or lowered without one is a number
nobody can argue with six months later.

## What happens on the next touch

Six months on, someone puts the discounts back inline, in a hurry. The
behaviour is identical, so the net stays green:

```
$ python3 -m unittest test_pricing
......
Ran 6 tests in 0.000s

OK
```

The tests cannot see the difference, because there is no behavioural difference
to see. That is not a gap in the tests; it is what tests are for. The ratchet
can:

```
$ python3 hooks/lib/ratchet.py check pricing.py
RATCHET001 complexity 1 -> 5
RATCHET001 max_fn_lines 10 -> 21
```

Exit code 1. The file loosened a budget it had already earned. Raising it on
purpose stays possible, with `ratchet.py init --reason`, where a reviewer sees
the new numbers and the justification in the same diff.

That is the whole point of the mark: the rescue you paid for stops being
something the next person has to know about, and becomes something the pipeline
remembers.

## What this example deliberately does not show

- **Fixing the two recorded bugs.** They are frozen, and unfreezing them is a
  separate change with its own test edits, which is exactly why they are not
  mixed into a refactor.
- **A hotspot analysis.** The class to rescue is given here. Choosing it out of
  a real codebase is Phase 2 of
  [docs/guides/legacy-rescue.md](../../docs/guides/legacy-rescue.md), and
  `/craftsman:legacy audit` does it against churn and complexity together.
- **Strangler fig.** One class is not a subsystem. See
  [knowledge/legacy/strangler-fig.md](../../knowledge/legacy/strangler-fig.md).

## Related

- [docs/guides/legacy-rescue.md](../../docs/guides/legacy-rescue.md), the six phases.
- [knowledge/legacy/characterization-testing.md](../../knowledge/legacy/characterization-testing.md).
- [01-audit-inherited-codebase.md](01-audit-inherited-codebase.md) and
  [02-cover-then-refactor.md](02-cover-then-refactor.md), the same path as a
  conversation rather than a fixture.
