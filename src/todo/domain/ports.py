"""Ports: the interfaces the application depends on but does not implement.

These exist so the service can be driven at speed in tests (in-memory repository,
frozen clock) and in earnest in production (SQLite, the real clock) without the
service knowing which it got.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Protocol

from .model import Todo


class TodoRepository(Protocol):
    def add(self, todo: Todo) -> None: ...

    def replace(self, todo: Todo) -> None: ...

    def remove(self, todo_id: str) -> None: ...

    def get(self, todo_id: str) -> Todo | None: ...

    def find_active_by_title(self, title: str) -> Todo | None: ...

    def all(self) -> list[Todo]: ...


class Clock(Protocol):
    def now(self) -> datetime: ...


class SystemClock:
    def now(self) -> datetime:
        return datetime.now(timezone.utc)


class FrozenClock:
    """A clock the tests control.

    Time is an input to the system like any other. Injecting it is what makes
    'a todo completed yesterday sorts below one completed today' a testable
    statement instead of a sleep().
    """

    def __init__(self, start: datetime) -> None:
        self._now = start

    def now(self) -> datetime:
        return self._now

    def advance(self, **delta) -> None:
        from datetime import timedelta

        self._now = self._now + timedelta(**delta)

    def set(self, moment: datetime) -> None:
        self._now = moment
