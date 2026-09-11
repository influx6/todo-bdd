"""Composition root.

The factory takes its dependencies rather than constructing them. That single
decision is what lets a test start the identical application with a frozen
clock and an in-memory repository, and lets production start it with the real
clock and a database — with no test-only branches inside the app.
"""

from __future__ import annotations

import sqlite3

from flask import Flask

from ..adapters.memory_repo import InMemoryTodoRepository
from ..adapters.sqlite_repo import SqliteTodoRepository
from ..domain.model import RuleViolation
from ..domain.ports import Clock, SystemClock, TodoRepository
from ..service.todo_service import TodoService
from .api import api
from .ui import ui


def create_app(
    repository: TodoRepository | None = None,
    clock: Clock | None = None,
    secret_key: str = "dev-only-not-a-real-secret",
) -> Flask:
    app = Flask(__name__)
    app.secret_key = secret_key
    app.config["TODO_SERVICE"] = TodoService(
        repository=repository if repository is not None else InMemoryTodoRepository(),
        clock=clock if clock is not None else SystemClock(),
    )
    app.register_blueprint(api)
    app.register_blueprint(ui)

    # Blueprint-level handlers do not catch exceptions raised in other
    # blueprints, so the app-level one keeps the two interfaces consistent.
    app.register_error_handler(RuleViolation, _rule_violation)
    return app


def _rule_violation(error: RuleViolation):
    from flask import jsonify, request

    if request.path.startswith("/api"):
        return jsonify(error=str(error)), 422
    raise error


def create_production_app(database_path: str = "todos.db") -> Flask:
    connection = sqlite3.connect(database_path, check_same_thread=False)
    return create_app(repository=SqliteTodoRepository(connection), clock=SystemClock())
