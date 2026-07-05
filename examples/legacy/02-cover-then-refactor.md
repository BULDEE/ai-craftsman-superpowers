# Example: Net Untested Code, Then Refactor Safely

## Prompt

```
/craftsman:legacy cover
I need to refactor calculateShipping() in OrderService but there are no tests
and it prints to stdout. I'm scared to touch it.
```

## Expected Behavior

Claude builds a characterization net first (records current behavior, bugs and all), proves the net catches change, and only then is a refactor safe.

### 1. Handle the side effect (seam)

```
calculateShipping() prints to stdout, which is untestable. First extract that
into a seam so I can silence it in the test (Subclass & Override):
  - extract the print into a protected log() method
  - subclass OrderService as TestableOrderService, override log() to do nothing
```

### 2. Characterize current behavior

```php
// Golden master: run across representative orders, capture the output.
public function test_shipping_is_unchanged(): void
{
    $outputs = [];
    foreach ([domestic(), international(), oversized(), freeShipping()] as $order) {
        $outputs[] = (new TestableOrderService())->calculateShipping($order);
    }
    $this->approvals->verify(implode("\n", $outputs)); // first run writes .approved
}
```

### 3. Prove the net catches change

```
Introduce an obvious mistake (return 0 from a helper) -> a test MUST go red.
It did. The net works. Reverting the deliberate break.
Coverage of calculateShipping(): 91% of the branches you will touch.
```

### 4. Now refactor is safe

```
Net is green. Handing off to /craftsman:refactor:
  - Extract the tax step, the zone lookup, the surcharge rule (one green commit each)
  - Rerun the golden master after every step; it stays green = behavior preserved.
Bugs found in the current behavior are FROZEN for now; fix them deliberately later.
```

## Key Points

- No behavior change while netting: the golden master records what the code *does*, not what it *should*.
- The seam (Subclass & Override) makes untestable stdout code testable without a rewrite.
- Proving the net catches a deliberate mistake is non-negotiable; a net that never fails protects nothing.
- Only after the net is green does `/craftsman:refactor` proceed (its Step 0 gate enforces this).
