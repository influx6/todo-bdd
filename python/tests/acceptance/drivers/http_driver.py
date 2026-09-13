"""Driver that goes through the JSON API. Milliseconds per test.

Adds routing, request parsing, serialisation and error mapping to what the
domain driver covered. It uses Flask's test client, which runs the real WSGI
stack without a socket. Swapping in `requests` against a base URL would let the
identical specification run against a deployed environment — that substitution
is the whole point of the layer.

Its token is the id the API returns on creation.
"""

from __future__ import annotations

from flask.testing import FlaskClient

from . import Token, TodoRow


class HttpDriver:
    def __init__(self, client: FlaskClient) -> None:
        self._client = client
        self._message: str | None = None

    def add(self, title: str) -> Token | None:
        response = self._client.post("/api/todos", json={"title": title})
        self._record(response)
        return response.get_json()["id"] if response.status_code == 201 else None

    def complete(self, token: Token) -> None:
        self._record(self._client.post(f"/api/todos/{token}/completion"))

    def reopen(self, token: Token) -> None:
        self._record(self._client.delete(f"/api/todos/{token}/completion"))

    def delete(self, token: Token) -> None:
        self._record(self._client.delete(f"/api/todos/{token}"))

    def visible_todos(self) -> list[TodoRow]:
        response = self._client.get("/api/todos")
        assert response.status_code == 200, f"Listing failed: {response.status_code}"
        return [
            TodoRow(token=t["id"], title=t["title"], is_done=t["done"])
            for t in response.get_json()["todos"]
        ]

    def last_message(self) -> str | None:
        return self._message

    def _record(self, response) -> None:
        self._message = (
            response.get_json().get("error") if response.status_code == 422 else None
        )
