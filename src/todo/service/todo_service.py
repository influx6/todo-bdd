"""The application service. This is the real system under test.

Everything above it (JSON API, HTML pages) is delivery mechanism. Everything
below it (SQLite, the clock) is infrastructure. All the behaviour worth
specifying lives here, which is why the fastest acceptance driver can talk
straight to it and still be testing the same system as the browser.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from ..domain.model import RuleViolation, Todo, clean_title
from ..domain.ports import Clock, TodoRepository


@dataclass(frozen=True)
class TodoView:
    """What a caller is allowed to see. Deliberately smaller than the entity."""

    id: str
    title: str
    is_done: bool


class TodoService:
    def __init__(self, repository: TodoRepository, clock: Clock) -> None:
        self._repository = repository
        self._clock = clock

    def add(self, raw_title: str) -> TodoView:
        title = clean_title(raw_title)
        if self._repository.find_active_by_title(title) is not None:
            raise RuleViolation(f"'{title}' is already on your list")
        todo = Todo(id=uuid.uuid4().hex, title=title, created_at=self._clock.now())
        self._repository.add(todo)
        return _view(todo)

    def complete(self, todo_id: str) -> TodoView:
        todo = self._require(todo_id)
        done = todo.completed(at=self._clock.now())
        self._repository.replace(done)
        return _view(done)

    def reopen(self, todo_id: str) -> TodoView:
        todo = self._require(todo_id)
        # Check this todo's own state first. Otherwise an outstanding todo
        # collides with itself in the title check below and gets told it is
        # already back on the list.
        active = todo.reopened()
        if self._repository.find_active_by_title(todo.title) is not None:
            raise RuleViolation(f"'{todo.title}' is already back on your list")
        self._repository.replace(active)
        return _view(active)

    def delete(self, todo_id: str) -> None:
        self._require(todo_id)
        self._repository.remove(todo_id)

    def list(self) -> list[TodoView]:
        """Outstanding work first, oldest first; then what is done, newest first.

        The order is part of the behaviour — it is what the user sees — so it
        belongs in the service and gets specified, not left to the database.
        """
        todos = self._repository.all()
        active = sorted((t for t in todos if not t.is_done), key=lambda t: t.created_at)
        done = sorted(
            (t for t in todos if t.is_done),
            key=lambda t: t.completed_at,
            reverse=True,
        )
        return [_view(t) for t in active + done]

    def _require(self, todo_id: str) -> Todo:
        todo = self._repository.get(todo_id)
        if todo is None:
            raise RuleViolation("That todo is no longer on your list")
        return todo


def _view(todo: Todo) -> TodoView:
    return TodoView(id=todo.id, title=todo.title, is_done=todo.is_done)
