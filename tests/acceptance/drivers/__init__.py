"""Protocol drivers: one per way of reaching the system.

Every driver implements the same small interface, so the specification never
learns which one it is talking to. Adding a fourth way in (a CLI, a queue
consumer, a deployed environment) means writing one more class here and
changing no tests at all.

**Tokens.** `add` hands back an opaque token, and every later action quotes it.
What a token *is* stays each driver's private business — the domain and HTTP
drivers use the todo's id; the browser driver reads it out of the form action
that already has to be in the markup for the page to work at all. The
specification never sees one. It holds a named reference ("Monday's milk") and
the DSL keeps the mapping.

This is what lets two todos share a title without the tests going blind.
Addressing rows by title cannot tell Monday's finished milk from Thursday's
outstanding milk, and forces that ambiguity up into the specification's
vocabulary, where it does not belong.

Drivers hold no assertions and no business rules. They act, and they report
what is observable. Deciding whether that is correct is the specification's
job.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

Token = str


@dataclass(frozen=True)
class TodoRow:
    """One line of what the user can currently see."""

    token: Token
    title: str
    is_done: bool


class TodoDriver(Protocol):
    def add(self, title: str) -> Token | None:
        """Returns the new todo's token, or None if the system refused it."""

    def complete(self, token: Token) -> None: ...

    def reopen(self, token: Token) -> None: ...

    def delete(self, token: Token) -> None: ...

    def visible_todos(self) -> list[TodoRow]: ...

    def last_message(self) -> str | None: ...
