"""The DSL layer: the vocabulary the specification is written in.

Four jobs live here and nowhere else.

  1. **Business language.** Methods are named for what a person does, not for
     what the code does. `a_todo_is_added("Buy milk")`, never `post_json(...)`.

  2. **Named references.** `a_todo_is_added` hands back a `TodoRef` the
     specification can name — `mondays_milk`, `thursdays_milk`. The DSL keeps
     the mapping from that reference to whatever opaque token the driver
     issued. The specification holds the name; the driver holds the mechanics;
     neither knows about the other.

     The names are not test machinery. They are the distinction the person in
     the conversation was already making out loud: *"the one I finished on
     Monday."*

  3. **Test data isolation.** The specification says "Buy milk". The system
     sees "Buy milk [7f3a]". Two runs of the same test against the same
     environment therefore cannot see each other, which makes the suite safe to
     run in parallel and safe to point at a shared environment.

     Note what the suffix must *not* do: distinguish two todos that the
     specification deliberately gave the same title. The rule under test is
     that finishing something frees its title for reuse — if the DSL quietly
     made those two titles different, the test would stop testing the rule.
     Telling them apart is the token's job, not the title's.

  4. **Synchronisation.** Every observation retries until it matches or the
     budget runs out. Against the domain driver that costs nothing; against a
     browser it is the difference between a suite people trust and a suite
     people re-run until it goes green.

What the DSL must never contain is logic. A step method may only delegate to
the running system and report what is observable. The moment it computes an
answer rather than asking for one, the test has become a mirror and can never
fail for a real reason.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass

from .drivers import Token, TodoDriver


@dataclass(frozen=True)
class TodoRef:
    """A specification's name for one particular todo.

    Deliberately not an id. The specification is naming an occasion — "the milk
    I added on Monday" — and the DSL knows which token that turned into.
    """

    name: str

    def __repr__(self) -> str:  # failure output only
        return self.name


@dataclass(frozen=True)
class Entry:
    """An expected line of the list."""

    ref: TodoRef
    is_done: bool = False

    def __repr__(self) -> str:  # failure output only
        return f"{self.ref}{' (done)' if self.is_done else ''}"


def done(ref: TodoRef) -> Entry:
    """Read as: this todo, completed. `dsl.the_list_reads(done(mondays_milk))`."""
    return Entry(ref, is_done=True)


class TodoListDsl:
    def __init__(self, driver: TodoDriver, clock, timeout: float = 2.0) -> None:
        self._driver = driver
        self._clock = clock
        self._timeout = timeout
        self._suffix = f" [{uuid.uuid4().hex[:6]}]"
        self._tokens: dict[Token, TodoRef] = {}

    # --- things a person does -------------------------------------------

    def a_todo_is_added(self, name: str) -> TodoRef:
        return self._remember(name, self._driver.add(self._isolated(name)))

    def a_todo_is_added_with_untidy_spacing(self, name: str) -> TodoRef:
        sloppy = f"   {self._isolated(name).replace(' ', '   ')}  "
        return self._remember(name, self._driver.add(sloppy))

    def a_todo_is_added_with_no_title(self) -> None:
        self._driver.add("   ")

    def a_todo_is_added_expecting_refusal(self, name: str) -> None:
        """For cases where the point is that the system says no.

        `a_todo_is_added` asserts the todo was created, because a specification
        that silently carried on from a failed setup step would assert on the
        wrong list. When refusal *is* the behaviour, say so.
        """
        token = self._driver.add(self._isolated(name))
        assert token is None, f"Expected {name!r} to be refused, but it was added"

    def a_todo_is_added_with_an_overlong_title(self) -> None:
        self._driver.add("x" * 200)

    def the_todo_is_completed(self, ref: TodoRef) -> None:
        self._driver.complete(self._token_for(ref))

    def the_todo_is_reopened(self, ref: TodoRef) -> None:
        self._driver.reopen(self._token_for(ref))

    def the_todo_is_deleted(self, ref: TodoRef) -> None:
        self._driver.delete(self._token_for(ref))

    def time_passes(self, **delta) -> None:
        self._clock.advance(**delta)

    # --- things a person sees -------------------------------------------

    def the_list_reads(self, *expected: TodoRef | Entry) -> None:
        """Assert the whole visible list, in order. Order is behaviour."""
        wanted = [e if isinstance(e, Entry) else Entry(e) for e in expected]
        self._eventually(self._our_entries, wanted, f"Expected the list to read {wanted}")

    def the_list_is_empty(self) -> None:
        self.the_list_reads()

    def the_message_shown_is(self, expected: str) -> None:
        self._eventually(
            lambda: (self._driver.last_message() or "").replace(self._suffix, ""),
            expected,
            f"Expected the message {expected!r}",
        )

    def no_message_is_shown(self) -> None:
        self._eventually(lambda: self._driver.last_message(), None, "Expected no message")

    # --- bookkeeping ------------------------------------------------------

    def _isolated(self, name: str) -> str:
        return f"{name}{self._suffix}"

    def _remember(self, name: str, token: Token | None) -> TodoRef:
        assert token is not None, f"The system refused to add {name!r}"
        ref = TodoRef(self._unique_name(name))
        self._tokens[token] = ref
        return ref

    def _unique_name(self, name: str) -> str:
        """Two todos may share a title, so the second gets a distinguishable
        name in failure output. The system never sees this."""
        taken = sum(1 for ref in self._tokens.values() if ref.name.startswith(name))
        return name if not taken else f"{name} #{taken + 1}"

    def _token_for(self, ref: TodoRef) -> Token:
        for token, known in self._tokens.items():
            if known == ref:
                return token
        raise AssertionError(f"No todo known as {ref} in this test")

    def _our_entries(self) -> list[Entry]:
        return [
            Entry(self._tokens[row.token], row.is_done)
            for row in self._driver.visible_todos()
            if row.token in self._tokens  # ignore anything this test did not create
        ]

    def _eventually(self, probe, expected, description: str) -> None:
        deadline = time.monotonic() + self._timeout
        while True:
            actual = probe()
            if actual == expected:
                return
            if time.monotonic() >= deadline:
                raise AssertionError(
                    f"{description}, but after {self._timeout:g}s it was {actual!r}"
                )
            time.sleep(0.05)
