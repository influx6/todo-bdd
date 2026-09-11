"""SQLite repository. The production implementation of the same port."""

from __future__ import annotations

import sqlite3
from datetime import datetime

from ..domain.model import Todo
from ..domain.ports import TodoRepository

SCHEMA = """
CREATE TABLE IF NOT EXISTS todos (
    id           TEXT PRIMARY KEY,
    title        TEXT NOT NULL,
    created_at   TEXT NOT NULL,
    completed_at TEXT
);
CREATE INDEX IF NOT EXISTS todos_title ON todos (title);
"""


class SqliteTodoRepository(TodoRepository):
    def __init__(self, connection: sqlite3.Connection) -> None:
        self._connection = connection
        self._connection.row_factory = sqlite3.Row
        self._connection.executescript(SCHEMA)
        self._connection.commit()

    def add(self, todo: Todo) -> None:
        self._connection.execute(
            "INSERT INTO todos (id, title, created_at, completed_at) VALUES (?, ?, ?, ?)",
            (todo.id, todo.title, todo.created_at.isoformat(), _iso_or_none(todo.completed_at)),
        )
        self._connection.commit()

    def replace(self, todo: Todo) -> None:
        self._connection.execute(
            "UPDATE todos SET title = ?, created_at = ?, completed_at = ? WHERE id = ?",
            (todo.title, todo.created_at.isoformat(), _iso_or_none(todo.completed_at), todo.id),
        )
        self._connection.commit()

    def remove(self, todo_id: str) -> None:
        self._connection.execute("DELETE FROM todos WHERE id = ?", (todo_id,))
        self._connection.commit()

    def get(self, todo_id: str) -> Todo | None:
        row = self._connection.execute(
            "SELECT * FROM todos WHERE id = ?", (todo_id,)
        ).fetchone()
        return _to_todo(row) if row else None

    def find_active_by_title(self, title: str) -> Todo | None:
        row = self._connection.execute(
            "SELECT * FROM todos WHERE title = ? AND completed_at IS NULL", (title,)
        ).fetchone()
        return _to_todo(row) if row else None

    def all(self) -> list[Todo]:
        rows = self._connection.execute("SELECT * FROM todos").fetchall()
        return [_to_todo(row) for row in rows]


def _iso_or_none(moment: datetime | None) -> str | None:
    return moment.isoformat() if moment else None


def _to_todo(row: sqlite3.Row) -> Todo:
    return Todo(
        id=row["id"],
        title=row["title"],
        created_at=datetime.fromisoformat(row["created_at"]),
        completed_at=(
            datetime.fromisoformat(row["completed_at"]) if row["completed_at"] else None
        ),
    )
