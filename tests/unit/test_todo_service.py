"""Unit tests: the TDD inner loop.

These are not smaller copies of the specification. The specification says *what
the product does*; these say *how this unit behaves*, including the edges no
user story would ever mention. They are allowed to know about ids, exception
types and the repository port, because they are written by and for the person
changing this class.

Rule of thumb for what belongs here rather than in the specification: if it
would bore a product owner, it is a unit test.
"""

from __future__ import annotations

from datetime import datetime, timezone

import pytest

from todo.adapters.memory_repo import InMemoryTodoRepository
from todo.domain.model import MAX_TITLE_LENGTH, RuleViolation
from todo.domain.ports import FrozenClock
from todo.service.todo_service import TodoService

NOON = datetime(2026, 3, 1, 12, 0, tzinfo=timezone.utc)


@pytest.fixture
def clock() -> FrozenClock:
    return FrozenClock(NOON)


@pytest.fixture
def repository() -> InMemoryTodoRepository:
    return InMemoryTodoRepository()


@pytest.fixture
def service(repository, clock) -> TodoService:
    return TodoService(repository=repository, clock=clock)


class TestAdding:
    def test_assigns_an_identity(self, service):
        first = service.add("Buy milk")
        second = service.add("Call the dentist")

        assert first.id != second.id

    def test_stamps_the_creation_time_from_the_clock(self, service, repository):
        created = service.add("Buy milk")

        assert repository.get(created.id).created_at == NOON

    def test_collapses_runs_of_whitespace(self, service):
        assert service.add("  Buy   milk  ").title == "Buy milk"

    @pytest.mark.parametrize("blank", ["", "   ", "\t\n", None])
    def test_rejects_a_title_that_says_nothing(self, service, blank):
        with pytest.raises(RuleViolation, match="needs a title"):
            service.add(blank)

    def test_accepts_a_title_at_the_limit(self, service):
        title = "x" * MAX_TITLE_LENGTH

        assert service.add(title).title == title

    def test_rejects_a_title_one_character_past_the_limit(self, service):
        with pytest.raises(RuleViolation, match="under 120 characters"):
            service.add("x" * (MAX_TITLE_LENGTH + 1))

    def test_treats_differently_spaced_titles_as_the_same_thing(self, service):
        service.add("Buy milk")

        with pytest.raises(RuleViolation, match="already on your list"):
            service.add("Buy    milk")


class TestCompleting:
    def test_stamps_the_completion_time_from_the_clock(self, service, repository, clock):
        todo = service.add("Buy milk")
        clock.advance(hours=3)

        service.complete(todo.id)

        assert repository.get(todo.id).completed_at == NOON.replace(hour=15)

    def test_refuses_to_complete_something_twice(self, service):
        todo = service.add("Buy milk")
        service.complete(todo.id)

        with pytest.raises(RuleViolation, match="already done"):
            service.complete(todo.id)

    def test_refuses_to_reopen_something_that_was_never_finished(self, service):
        todo = service.add("Buy milk")

        with pytest.raises(RuleViolation, match="not done yet"):
            service.reopen(todo.id)

    def test_reopening_clears_the_completion_time(self, service, repository):
        todo = service.add("Buy milk")
        service.complete(todo.id)

        service.reopen(todo.id)

        assert repository.get(todo.id).completed_at is None

    def test_preserves_the_original_creation_time_through_a_round_trip(
        self, service, repository, clock
    ):
        todo = service.add("Buy milk")
        clock.advance(days=2)
        service.complete(todo.id)
        service.reopen(todo.id)

        assert repository.get(todo.id).created_at == NOON


class TestMissingTodos:
    @pytest.mark.parametrize("operation", ["complete", "reopen", "delete"])
    def test_every_operation_says_the_same_thing_about_a_vanished_todo(
        self, service, operation
    ):
        with pytest.raises(RuleViolation, match="no longer on your list"):
            getattr(service, operation)("a-id-that-was-never-issued")


class TestOrdering:
    def test_puts_outstanding_work_before_finished_work(self, service, clock):
        first = service.add("Buy milk")
        clock.advance(minutes=1)
        service.add("Call the dentist")
        service.complete(first.id)

        assert [t.title for t in service.list()] == ["Call the dentist", "Buy milk"]

    def test_breaks_ties_among_finished_work_by_most_recently_finished(
        self, service, clock
    ):
        first = service.add("Buy milk")
        second = service.add("Call the dentist")
        service.complete(first.id)
        clock.advance(minutes=1)
        service.complete(second.id)

        assert [t.title for t in service.list()] == ["Call the dentist", "Buy milk"]

    def test_an_empty_list_is_not_a_special_case(self, service):
        assert service.list() == []
