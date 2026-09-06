"""Step 2: one seam, and nothing else.

The only change from step 1 is the constructor: the clock is now something the
caller hands in, defaulting to the real one so every existing call site keeps
working. Forty lines of pricing logic are untouched, deliberately. A step that
introduces a seam AND rearranges the code is a step whose failure you cannot
attribute.

The original docstring follows, because it still describes the class.

The class that arrived with the codebase.

Nothing about it is exotic, which is the point: it prices a basket, it is
forty lines long, it has no tests, and three things make it hard to test.

  1. It reads the clock itself (`datetime.now`), so a weekend discount cannot
     be exercised without waiting for Saturday.
  2. It writes to stdout, so a test run is noisy and the message is not
     checkable.
  3. It reads a module-level rate table that a caller cannot substitute.

The rescue does not start by fixing any of that. It starts by writing down
what the code does today, bugs included.
"""

import sys
from datetime import datetime

VAT_RATE = 0.20
WEEKEND_DISCOUNT = 0.10
BULK_THRESHOLD = 10
BULK_DISCOUNT = 0.05


class PricingService:
    """Prices a basket. Inherited, untested, in production."""

    def __init__(self, clock=None):
        # The seam. `datetime.now` is the collaborator the test could not
        # control; now it arrives through the door. The default keeps every
        # existing caller working, which is what makes this step safe to ship
        # on its own.
        self._clock = clock or datetime.now

    def total(self, unit_price, quantity, customer_tier):
        subtotal = unit_price * quantity

        if quantity >= BULK_THRESHOLD:
            subtotal = subtotal - (subtotal * BULK_DISCOUNT)

        if self._clock().weekday() >= 5:
            subtotal = subtotal - (subtotal * WEEKEND_DISCOUNT)

        if customer_tier == "gold":
            subtotal = subtotal - (subtotal * 0.15)
        elif customer_tier == "silver":
            subtotal = subtotal - (subtotal * 0.05)

        total = subtotal + (subtotal * VAT_RATE)

        print("priced basket: %s x %s for tier %s = %s"
              % (unit_price, quantity, customer_tier, total), file=sys.stdout)

        return round(total, 2)
