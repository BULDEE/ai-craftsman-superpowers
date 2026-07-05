"""Canonical example: SOLID principles in Python.

One idiomatic demonstration per principle. See knowledge/principles.md for the
theory and the cross-language mapping table.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from typing import Protocol


# =============================================================================
# S - Single Responsibility Principle
# One class, one reason to change. Keep computation, formatting, and storage apart.
# =============================================================================
@dataclass(frozen=True)
class TaxCalculator:
    """Only computes tax. It does not format or persist."""

    def calculate(self, amount_cents: int, rate_percent: int) -> int:
        return amount_cents * rate_percent // 100


# =============================================================================
# O - Open/Closed Principle
# Add a discount type without editing existing code: depend on an abstraction.
# =============================================================================
class DiscountPolicy(Protocol):
    def apply(self, subtotal_cents: int) -> int: ...


@dataclass(frozen=True)
class SeasonalDiscount:
    percent: int

    def apply(self, subtotal_cents: int) -> int:
        return subtotal_cents - subtotal_cents * self.percent // 100


def checkout(subtotal_cents: int, discount: DiscountPolicy) -> int:
    # A new discount is a new class; this function never changes.
    return discount.apply(subtotal_cents)


# =============================================================================
# L - Liskov Substitution Principle
# A subtype must be substitutable for its base without breaking callers.
# Model shapes as independent types rather than Square(Rectangle) that
# secretly couples width and height.
# =============================================================================
class Shape(ABC):
    @abstractmethod
    def area(self) -> float: ...


@dataclass(frozen=True)
class Rectangle(Shape):
    width: float
    height: float

    def area(self) -> float:
        return self.width * self.height


@dataclass(frozen=True)
class Square(Shape):
    side: float

    def area(self) -> float:
        return self.side**2


# =============================================================================
# I - Interface Segregation Principle
# Depend on narrow protocols, not one fat interface with unused methods.
# =============================================================================
class OrderReader(Protocol):
    def find(self, order_id: str) -> "Order | None": ...


class OrderWriter(Protocol):
    def save(self, order: "Order") -> None: ...


# A reporting service takes only OrderReader; it cannot and need not write.


# =============================================================================
# D - Dependency Inversion Principle
# High-level policy depends on an abstraction (Clock), never on the system clock.
# =============================================================================
class Clock(Protocol):
    def now(self) -> datetime: ...


@dataclass(frozen=True)
class PlaceOrder:
    clock: Clock  # injected abstraction; tests pass a FrozenClock

    def __call__(self, order_id: str) -> None:
        _created_at = self.clock.now()  # not datetime.now()
        # ... orchestrate the domain here


@dataclass(frozen=True)
class Order:
    id: str
    total_cents: int
