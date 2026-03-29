"""
Canonical Python Use Case — Command/Handler pattern.
Demonstrates: type hints, dataclass, explicit error handling, no mutable defaults.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


class OrderRepository(Protocol):
    """Repository interface — domain boundary."""

    def find_by_id(self, order_id: str) -> Order | None: ...
    def save(self, order: Order) -> None: ...


@dataclass(frozen=True)
class CreateOrderCommand:
    """Immutable command — no setters, no mutation."""

    customer_id: str
    items: list[OrderItem]


class CreateOrderHandler:
    """Use case handler — single responsibility."""

    def __init__(self, repo: OrderRepository) -> None:
        self._repo = repo

    def handle(self, command: CreateOrderCommand) -> Order:
        if not command.items:
            raise ValueError("Order must have at least one item")

        order = Order.create(
            customer_id=command.customer_id,
            items=command.items,
        )
        self._repo.save(order)

        return order
