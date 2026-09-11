"""Driver that calls the service in-process. Microseconds per test.

This is the driver you run on every keystroke. It exercises every business rule
and none of the plumbing, which is exactly the trade you want hundreds of times
a day.

Its token is the todo's id, which it has in hand the moment `add` returns.
"""

from __future__ import annotations

from todo.domain.model import RuleViolation
from todo.service.todo_service import TodoService

from . import Token, TodoRow


class DomainDriver:
    def __init__(self, service: TodoService) -> None:
        self._service = service
        self._message: str | None = None

    def add(self, title: str) -> Token | None:
        created = self._attempt(lambda: self._service.add(title))
        return created.id if created else None

    def complete(self, token: Token) -> None:
        self._attempt(lambda: self._service.complete(token))

    def reopen(self, token: Token) -> None:
        self._attempt(lambda: self._service.reopen(token))

    def delete(self, token: Token) -> None:
        self._attempt(lambda: self._service.delete(token))

    def visible_todos(self) -> list[TodoRow]:
        return [
            TodoRow(token=t.id, title=t.title, is_done=t.is_done)
            for t in self._service.list()
        ]

    def last_message(self) -> str | None:
        return self._message

    def _attempt(self, action):
        self._message = None
        try:
            return action()
        except RuleViolation as violation:
            self._message = str(violation)
            return None
