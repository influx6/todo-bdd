"""Driver that goes through a real browser. Seconds per test.

Everything the browser knows about the application is confined to this file:
selectors, form submission, page loads. Rebuild the frontend in React tomorrow
and this is the only file that changes; not one line of the specification
moves.

**Where its token comes from.** Each row's form must post to
`/todos/<id>` for the page to function, so the id is already in the markup —
no test-only attribute was added to make this work. The driver reads it back
out of the form's action.

Note what this file does *not* do: no sleeps, and no assertions. Playwright's
locators retry on their own, and the DSL retries the whole observation, so the
driver stays a plain translation of intent into clicks.
"""

from __future__ import annotations

from playwright.sync_api import Page

from . import Token, TodoRow


class UiDriver:
    def __init__(self, page: Page, base_url: str) -> None:
        self._page = page
        self._base_url = base_url
        self._page.goto(self._base_url)

    def add(self, title: str) -> Token | None:
        before = {row.token for row in self.visible_todos()}
        self._page.get_by_test_id("new-todo").fill(title)
        self._submit(self._page.get_by_test_id("add"))
        new = {row.token for row in self.visible_todos()} - before
        return new.pop() if new else None

    def complete(self, token: Token) -> None:
        self._submit(self._row(token).get_by_test_id("complete"))

    def reopen(self, token: Token) -> None:
        self._submit(self._row(token).get_by_test_id("reopen"))

    def delete(self, token: Token) -> None:
        self._submit(self._row(token).get_by_test_id("delete"))

    def visible_todos(self) -> list[TodoRow]:
        return [
            TodoRow(
                token=self._token_of(row),
                title=row.get_attribute("data-title"),
                is_done=row.get_attribute("data-done") == "true",
            )
            for row in self._page.get_by_test_id("todo").all()
        ]

    def last_message(self) -> str | None:
        banner = self._page.get_by_test_id("message")
        return banner.inner_text().strip() if banner.count() else None

    def _submit(self, control) -> None:
        """Every action is a form post, so every action is a navigation.

        Waiting for it here means the DSL's retry loop is a safety net rather
        than the primary mechanism — retries should cover genuine asynchrony,
        not a page load we knew was coming.
        """
        with self._page.expect_navigation():
            control.click()

    def _row(self, token: Token):
        return self._page.locator(f'[data-testid="todo"]:has(form[action$="/{token}"])')

    @staticmethod
    def _token_of(row) -> Token:
        return row.locator("form").get_attribute("action").rstrip("/").split("/")[-1]
