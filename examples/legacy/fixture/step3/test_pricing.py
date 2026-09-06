"""Step 2: the same assertions, through the seam instead of through mock.patch.

Every number below is unchanged from step 1. That is the assertion that
matters: the seam moved the clock out of the class without moving the
behaviour. What changed is how the clock is held still, from reaching into the
module to passing an argument, so the test no longer breaks when an import
moves.

The original note follows, because it still applies.

Step 1: what the code does today. Not what it should do.

Written before a single line of pricing.py changes. Three of the assertions
record behaviour a reviewer would call wrong, and they are recorded anyway: a
net that only pins the parts you approve of has a hole exactly where you are
about to put your foot.

The clock is now injected, so mock.patch is gone.
"""

import io
import unittest
from contextlib import redirect_stdout
from datetime import datetime

from pricing import PricingService

TUESDAY = datetime(2026, 9, 1, 10, 0, 0)
SATURDAY = datetime(2026, 9, 5, 10, 0, 0)


class CharacterizationTest(unittest.TestCase):
    """Every number here was READ OFF the running code, never computed by hand."""

    def price(self, *args, today=TUESDAY):
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            total = PricingService(clock=lambda: today).total(*args)
        return total, buffer.getvalue()

    def test_a_plain_basket_on_a_weekday(self):
        total, _ = self.price(10.0, 3, "standard")
        self.assertEqual(36.0, total)

    def test_the_same_basket_is_cheaper_on_a_saturday(self):
        total, _ = self.price(10.0, 3, "standard", today=SATURDAY)
        self.assertEqual(32.4, total)

    def test_bulk_crosses_at_ten_not_at_eleven(self):
        nine, _ = self.price(10.0, 9, "standard")
        ten, _ = self.price(10.0, 10, "standard")
        self.assertEqual(108.0, nine)
        self.assertEqual(114.0, ten)

    def test_discounts_compound_instead_of_adding(self):
        # A reviewer would call this a bug: a gold customer buying in bulk gets
        # 5% off, then 15% off the discounted price, not 20% off. It is what
        # the code does, so it is what the net records. Fixing it is a separate
        # decision, taken deliberately, once the refactor has landed.
        total, _ = self.price(10.0, 10, "gold")
        self.assertEqual(96.9, total)

    def test_an_unknown_tier_is_charged_full_price_silently(self):
        # Another one. `platinum` is one typo away from `gold`, costs the
        # customer 15%, and raises nothing anywhere.
        total, _ = self.price(10.0, 1, "platinum")
        self.assertEqual(12.0, total)

    def test_it_writes_a_line_to_stdout(self):
        _, printed = self.price(10.0, 3, "standard")
        self.assertEqual(
            "priced basket: 10.0 x 3 tier standard = 36.0\n", printed)


if __name__ == "__main__":
    unittest.main()
