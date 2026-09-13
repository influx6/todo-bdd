"""One contract, every implementation of the port.

This is the test that earns you the right to use a fast in-memory repository
everywhere else. Without it, "all green" only means the fake agrees with
itself, and the first thing you learn in production is that SQLite compares
strings differently or forgot the timezone.

Add an implementation, add one line to the fixture params. Nothing else moves.
"""

from __future__ import annotations

import sqlite3
from datetime import datetime, timezone

import pytest

from todo.adapters.memory_repo import InMemoryTodoRepository
from todo.adapters.sqlite_repo import SqliteTodoRepository
from todo.domain.model import Todo

NOON = datetime(2026, 3, 1, 12, 0, tzinfo=timezone.utc)


@pytest.fixture(params=["memory", "sqlite"])
def repository(request):
    if request.param == "memory":
        return InMemoryTodoRepository()
    return SqliteTodoRepository(sqlite3.connect(":memory:"))


def a_todo(id="t1", title="Buy milk", created_at=NOON, completed_at=None) -> Todo:
    return Todo(id=id, title=title, created_at=created_at, completed_at=completed_at)


class TestStoringAndFetching:
    def test_a_stored_todo_comes_back_unchanged(self, repository):
        todo = a_todo()

        repository.add(todo)

        assert repository.get(todo.id) == todo

    def test_timezone_survives_the_round_trip(self, repository):
        repository.add(a_todo(created_at=NOON))

        assert repository.get("t1").created_at.tzinfo is not None

    def test_a_completion_time_survives_the_round_trip(self, repository):
        repository.add(a_todo(completed_at=NOON))

        assert repository.get("t1").completed_at == NOON

    def test_an_unknown_id_is_absent_rather_than_an_error(self, repository):
        assert repository.get("never-stored") is None

    def test_all_returns_everything_that_was_added(self, repository):
        repository.add(a_todo(id="t1", title="Buy milk"))
        repository.add(a_todo(id="t2", title="Call the dentist"))

        assert {t.id for t in repository.all()} == {"t1", "t2"}

    def test_all_is_empty_before_anything_is_added(self, repository):
        assert repository.all() == []


class TestReplacing:
    def test_replace_overwrites_the_stored_state(self, repository):
        repository.add(a_todo())

        repository.replace(a_todo(completed_at=NOON))

        assert repository.get("t1").completed_at == NOON

    def test_replace_does_not_create_a_duplicate(self, repository):
        repository.add(a_todo())

        repository.replace(a_todo(title="Buy oat milk"))

        assert len(repository.all()) == 1


class TestRemoving:
    def test_a_removed_todo_is_gone(self, repository):
        repository.add(a_todo())

        repository.remove("t1")

        assert repository.get("t1") is None

    def test_removing_something_absent_is_quietly_accepted(self, repository):
        repository.remove("never-stored")  # must not raise


class TestFindingActiveWorkByTitle:
    def test_finds_an_outstanding_todo(self, repository):
        repository.add(a_todo())

        assert repository.find_active_by_title("Buy milk").id == "t1"

    def test_ignores_finished_work(self, repository):
        repository.add(a_todo(completed_at=NOON))

        assert repository.find_active_by_title("Buy milk") is None

    def test_matches_the_whole_title_exactly(self, repository):
        repository.add(a_todo(title="Buy milk"))

        assert repository.find_active_by_title("Buy") is None

    def test_is_case_sensitive(self, repository):
        repository.add(a_todo(title="Buy milk"))

        assert repository.find_active_by_title("buy milk") is None

    def test_finds_the_outstanding_one_when_a_title_is_reused(self, repository):
        repository.add(a_todo(id="done", completed_at=NOON))
        repository.add(a_todo(id="active"))

        assert repository.find_active_by_title("Buy milk").id == "active"
