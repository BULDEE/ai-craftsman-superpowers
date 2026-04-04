"""Canonical Python Repository — abstract interface in domain, implementation in infrastructure."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Protocol
from uuid import UUID


@dataclass(frozen=True)
class UserId:
    """User identity value object."""

    value: UUID

    @classmethod
    def generate(cls) -> UserId:
        from uuid import uuid4
        return cls(value=uuid4())


class UserRepository(Protocol):
    """Domain contract for user persistence — no infrastructure details leak."""

    def find_by_id(self, user_id: UserId) -> User | None: ...

    def find_by_email(self, email: str) -> User | None: ...

    def save(self, user: User) -> None: ...

    def remove(self, user: User) -> None: ...


class InMemoryUserRepository:
    """Test double — deterministic, no I/O."""

    def __init__(self) -> None:
        self._storage: dict[UUID, User] = {}

    def find_by_id(self, user_id: UserId) -> User | None:
        return self._storage.get(user_id.value)

    def find_by_email(self, email: str) -> User | None:
        for user in self._storage.values():
            if user.email == email:
                return user
        return None

    def save(self, user: User) -> None:
        self._storage[user.user_id.value] = user

    def remove(self, user: User) -> None:
        self._storage.pop(user.user_id.value, None)
