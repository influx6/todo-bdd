"""JSON API. Thin by design: parse, delegate, serialise.

There is no business logic here. If a rule ever creeps into this file, the
domain driver stops testing the same system as the HTTP driver and the whole
arrangement quietly rots.
"""

from __future__ import annotations

from flask import Blueprint, current_app, jsonify, request

from ..domain.model import RuleViolation

api = Blueprint("api", __name__, url_prefix="/api")


def _service():
    return current_app.config["TODO_SERVICE"]


@api.errorhandler(RuleViolation)
def _handle_rule_violation(error: RuleViolation):
    return jsonify(error=str(error)), 422


@api.get("/todos")
def list_todos():
    return jsonify(todos=[_json(t) for t in _service().list()])


@api.post("/todos")
def add_todo():
    payload = request.get_json(silent=True) or {}
    todo = _service().add(payload.get("title", ""))
    return jsonify(_json(todo)), 201


@api.post("/todos/<todo_id>/completion")
def complete_todo(todo_id: str):
    return jsonify(_json(_service().complete(todo_id)))


@api.delete("/todos/<todo_id>/completion")
def reopen_todo(todo_id: str):
    return jsonify(_json(_service().reopen(todo_id)))


@api.delete("/todos/<todo_id>")
def delete_todo(todo_id: str):
    _service().delete(todo_id)
    return "", 204


def _json(todo) -> dict:
    return {"id": todo.id, "title": todo.title, "done": todo.is_done}
