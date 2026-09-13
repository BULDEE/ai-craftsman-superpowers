---
description: A stack trace pasted with no instruction. /craftsman:debug owns this.
tags: [routing]
max_turns: 6
allowed_tools: [Skill]
expected_outcome: craftsman:debug fires and the answer states a hypothesis to check before proposing a fix.
---

Our checkout is throwing this on about one order in twenty and I cannot reproduce it locally:

```
TypeError: Cannot read properties of undefined (reading 'total')
    at applyDiscount (src/Checkout/Discount.ts:42:19)
    at processOrder (src/Checkout/Order.ts:118:24)
```

What do I do with this?
