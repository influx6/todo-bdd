"""The domain model. Knows nothing about Flask, HTTP, SQL or tests."""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import datetime

MAX_TITLE_LENGTH = 120


class RuleViolation(Exception):
    """A rule the user broke.

    The message is user-facing: it is shown in the UI, returned by the API and
    asserted on in the executable specification. Keeping one message per rule
    means every interface says the same thing, which is what lets a single
    specification run against all of them.
    """


@dataclass(frozen=True)
class Todo:
    id: str
    title: str
    created_at: datetime
    completed_at: datetime | None = None

    @property
    def is_done(self) -> bool:
        return self.completed_at is not None

    def completed(self, at: datetime) -> Todo:
        if self.is_done:
            raise RuleViolation(f"'{self.title}' is already done")
        return replace(self, completed_at=at)

    def reopened(self) -> Todo:
        if not self.is_done:
            raise RuleViolation(f"'{self.title}' is not done yet")
        return replace(self, completed_at=None)


def clean_title(raw: str) -> str:
    """Normalise and validate a title, or explain why it is not acceptable."""
    title = " ".join((raw or "").split())
    if not title:
        return _reject("A todo needs a title")
    if len(title) > MAX_TITLE_LENGTH:
        return _reject(f"Keep the title under {MAX_TITLE_LENGTH} characters")
    return title


def _reject(message: str) -> str:
    raise RuleViolation(message)
