"""Canonical Python Value Object — immutable, validated, self-documenting."""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class Email:
    """Email address value object with built-in validation."""

    value: str

    def __post_init__(self) -> None:
        if not re.match(r'^[^@]+@[^@]+\.[^@]+$', self.value):
            raise ValueError(f'Invalid email address: {self.value}')

    def domain(self) -> str:
        return self.value.split('@')[1]

    def __str__(self) -> str:
        return self.value


@dataclass(frozen=True)
class Money:
    """Money value object — prevents primitive obsession for financial amounts."""

    amount: int  # Store in cents to avoid floating point
    currency: str = 'EUR'

    def __post_init__(self) -> None:
        if self.amount < 0:
            raise ValueError(f'Amount cannot be negative: {self.amount}')
        if len(self.currency) != 3:
            raise ValueError(f'Currency must be ISO 4217: {self.currency}')

    def add(self, other: Money) -> Money:
        if self.currency != other.currency:
            raise ValueError(f'Cannot add {self.currency} and {other.currency}')
        return Money(amount=self.amount + other.amount, currency=self.currency)

    def display(self) -> str:
        whole_part = self.amount // 100
        fractional_part = self.amount % 100
        return f'{whole_part}.{fractional_part:02d} {self.currency}'
