"""HTML pages. The second delivery mechanism over the same service.

Post/Redirect/Get with the message carried in the session, so the browser test
never has to reason about form resubmission.
"""

from __future__ import annotations

from flask import (
    Blueprint,
    current_app,
    redirect,
    render_template,
    request,
    session,
    url_for,
)

from ..domain.model import RuleViolation

ui = Blueprint("ui", __name__)


def _service():
    return current_app.config["TODO_SERVICE"]


@ui.get("/")
def index():
    return render_template(
        "index.html",
        todos=_service().list(),
        message=session.pop("message", None),
    )


@ui.post("/todos")
def add_todo():
    _attempt(lambda: _service().add(request.form.get("title", "")))
    return redirect(url_for("ui.index"))


@ui.post("/todos/<todo_id>")
def change_todo(todo_id: str):
    action = request.form.get("action")
    actions = {
        "complete": lambda: _service().complete(todo_id),
        "reopen": lambda: _service().reopen(todo_id),
        "delete": lambda: _service().delete(todo_id),
    }
    _attempt(actions[action])
    return redirect(url_for("ui.index"))


def _attempt(action) -> None:
    try:
        action()
    except RuleViolation as violation:
        session["message"] = str(violation)
