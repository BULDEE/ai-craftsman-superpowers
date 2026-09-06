"""Step 3: one refactor, under the net.

The net from step 2 is copied here byte for byte and never touched. That is the
point of the exercise: if the tests had to be edited to make the refactor pass,
the refactor changed behaviour and the net was the thing that noticed.

The change is a single move: the four discount rules were an if/elif chain
inside a forty-line method, and they are now a table the method walks. Nothing
about what the code computes changes, including the two defects the
characterization tests recorded. Fixing those is the next decision, taken on
purpose, with a net that already proves what changes when they are fixed.
"""

import sys
from datetime import datetime

VAT_RATE = 0.20
WEEKEND_DISCOUNT = 0.10
BULK_THRESHOLD = 10
BULK_DISCOUNT = 0.05

# The if/elif chain, as data. An unknown tier finds no row and pays full price,
# which is the behaviour the net recorded rather than the behaviour anyone
# would design. Moving it here does not fix it; it makes it visible, in one
# place, where fixing it is a one-line decision instead of an archaeology
# expedition.
TIER_DISCOUNT = {
    "gold": 0.15,
    "silver": 0.05,
}


class PricingService:
    """Prices a basket. Inherited, now under test."""

    def __init__(self, clock=None):
        self._clock = clock or datetime.now

    def total(self, unit_price, quantity, customer_tier):
        subtotal = unit_price * quantity
        subtotal = self._apply_bulk(subtotal, quantity)
        subtotal = self._apply_weekend(subtotal)
        subtotal = self._apply_tier(subtotal, customer_tier)

        total = subtotal + (subtotal * VAT_RATE)
        self._log(unit_price, quantity, customer_tier, total)
        return round(total, 2)

    def _apply_bulk(self, subtotal, quantity):
        if quantity < BULK_THRESHOLD:
            return subtotal
        return subtotal - (subtotal * BULK_DISCOUNT)

    def _apply_weekend(self, subtotal):
        if self._clock().weekday() < 5:
            return subtotal
        return subtotal - (subtotal * WEEKEND_DISCOUNT)

    def _apply_tier(self, subtotal, customer_tier):
        # The compounding the net recorded is preserved exactly: this discount
        # applies to a subtotal the earlier ones already reduced.
        rate = TIER_DISCOUNT.get(customer_tier, 0.0)
        return subtotal - (subtotal * rate)

    def _log(self, unit_price, quantity, customer_tier, total):
        print("priced basket: %s x %s for tier %s = %s"
              % (unit_price, quantity, customer_tier, total), file=sys.stdout)
