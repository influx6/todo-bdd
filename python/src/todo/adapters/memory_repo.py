"""In-memory repository.

This ships in `src/`, not in `tests/`, on purpose. It is a real implementation
of the port that happens to be fast and disposable, and it is verified by the
same contract test as the SQLite one. A fake that is never verified is just a
second bug farm.
"""

from __future__ import annotations

from ..domain.model import Todo
from ..domain.ports import TodoRepository


class InMemoryTodoRepository(TodoRepository):
    def __init__(self) -> None:
        self._todos: dict[str, Todo] = {}

    def add(self, todo: Todo) -> None:
        self._todos[todo.id] = todo

    def replace(self, todo: Todo) -> None:
        self._todos[todo.id] = todo

    def remove(self, todo_id: str) -> None:
        self._todos.pop(todo_id, None)

    def get(self, todo_id: str) -> Todo | None:
        return self._todos.get(todo_id)

    def find_active_by_title(self, title: str) -> Todo | None:
        for todo in self._todos.values():
            if todo.title == title and not todo.is_done:
                return todo
        return None

    def all(self) -> list[Todo]:
        return list(self._todos.values())
