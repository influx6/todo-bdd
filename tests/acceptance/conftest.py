"""Wiring. The specification is parametrised over every way into the system.

Choosing which layers run:

    pytest tests/acceptance                      # all available layers
    SPEC_LAYERS=domain pytest tests/acceptance   # inner loop, milliseconds
    SPEC_LAYERS=domain,http pytest tests/acceptance
    SPEC_LAYERS=domain,http,ui pytest            # what CI runs before deploy

Note that the same application object is used for every layer. The UI driver
does not get a special test build — it gets a real HTTP server running the same
factory as production, with two dependencies substituted at the composition
root.
"""

from __future__ import annotations

import os
import socket
import threading
from datetime import datetime, timezone

import pytest
from werkzeug.serving import make_server

from todo.adapters.memory_repo import InMemoryTodoRepository
from todo.domain.ports import FrozenClock
from todo.service.todo_service import TodoService
from todo.web import create_app

from .drivers.domain_driver import DomainDriver
from .drivers.http_driver import HttpDriver
from .dsl import TodoListDsl

START_OF_TIME = datetime(2026, 3, 1, 9, 0, tzinfo=timezone.utc)

ALL_LAYERS = ("domain", "http", "ui")


def _requested_layers() -> list[str]:
    raw = os.environ.get("SPEC_LAYERS")
    if not raw:
        return list(ALL_LAYERS)
    chosen = [name.strip() for name in raw.split(",") if name.strip()]
    unknown = set(chosen) - set(ALL_LAYERS)
    if unknown:
        raise pytest.UsageError(f"Unknown SPEC_LAYERS: {', '.join(sorted(unknown))}")
    return chosen


@pytest.fixture
def clock() -> FrozenClock:
    return FrozenClock(START_OF_TIME)


@pytest.fixture
def repository() -> InMemoryTodoRepository:
    """Swap for SqliteTodoRepository to run the same spec against the database."""
    return InMemoryTodoRepository()


@pytest.fixture
def app(repository, clock):
    return create_app(repository=repository, clock=clock)


@pytest.fixture(params=_requested_layers())
def dsl(request, app, repository, clock) -> TodoListDsl:
    layer = request.param
    request.node.add_marker(pytest.mark.layer(layer))
    builder = {
        "domain": _domain_dsl,
        "http": _http_dsl,
        "ui": _ui_dsl,
    }[layer]
    yield from builder(request, app, repository, clock)


def _domain_dsl(request, app, repository, clock):
    service = TodoService(repository=repository, clock=clock)
    yield TodoListDsl(DomainDriver(service), clock)


def _http_dsl(request, app, repository, clock):
    with app.test_client() as client:
        yield TodoListDsl(HttpDriver(client), clock)


def _ui_dsl(request, app, repository, clock):
    playwright = pytest.importorskip(
        "playwright.sync_api", reason="playwright is not installed"
    )
    server = _LiveServer(app)
    server.start()
    try:
        with playwright.sync_playwright() as p:
            try:
                browser = p.chromium.launch()
            except Exception as exc:  # no browser binary on this machine
                pytest.skip(f"No chromium available: {exc}")
            page = browser.new_page()
            from .drivers.ui_driver import UiDriver

            try:
                yield TodoListDsl(UiDriver(page, server.base_url), clock, timeout=5.0)
            finally:
                browser.close()
    finally:
        server.stop()


class _LiveServer:
    """The production WSGI app on a real port, in a background thread.

    Same process as the test, which is what lets the browser and the test share
    one frozen clock. In a fully out-of-process setup you would expose time
    control through a test-only endpoint instead.
    """

    def __init__(self, app) -> None:
        self._port = _free_port()
        self._server = make_server("127.0.0.1", self._port, app, threaded=True)
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self._port}"

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._server.shutdown()
        self._thread.join(timeout=5)


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]
