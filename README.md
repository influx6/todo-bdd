# A todo list, specified once and tested three ways

A small Flask application built to demonstrate one idea: **you do not write a
separate executable specification for the unit, integration and UI layers. You
write one specification and swap what it drives.**

Fifteen behaviours are described in `tests/acceptance/test_todo_specification.py`.
That file mentions no HTTP, no SQL, no selectors and no ids. It runs unchanged
against the domain service, against the JSON API, and against a real browser.

```
Specification        what the product does
      |
     DSL             vocabulary, test-data isolation, waiting
      |
   +--+--+--------------+
   |     |              |
 domain  http        browser        three drivers, one interface
   |     |              |
   +-----+--------------+
      |
Application service     every rule lives here, once
```

## Read in this order

1. **`docs/01-the-conversation.md`** — where the behaviours came from, and the
   plain-language version of DDD and BDD that the rest depends on.
2. **`docs/02-the-specification.md`** — how the specification, the DSL and the
   drivers were derived, and a line-by-line reading of the parametrised
   `dsl` fixture that makes one spec run three ways.
3. **`docs/03-open-questions.md`** — the design argument we had not finished,
   left open rather than papered over.
4. Then the code, starting at `src/todo/service/todo_service.py`.

## Running it

```bash
pip install flask pytest
export PYTHONPATH=src

pytest tests/unit tests/contract          # 51 tests, ~50ms
SPEC_LAYERS=domain pytest tests/acceptance # the inner loop
SPEC_LAYERS=domain,http pytest             # every commit
pytest                                     # everything, browser included

python run.py                              # the app on :5000, SQLite on disk
```

The browser layer needs Playwright and a Chromium binary:

```bash
pip install playwright && playwright install chromium
```

Without them, that layer skips rather than fails. The other two run regardless.

## Status

Verified: 51 unit and contract tests, and the 15 specifications across the
domain and HTTP drivers — 81 test runs, passing in under half a second.

The specification uses named references (`mondays_milk`, `thursdays_milk`)
rather than bare titles. `docs/03-open-questions.md` explains why, including
the version that shipped first and what was wrong with it.

The browser driver is written but was never executed: the sandbox this was
built in could not download Chromium. Treat `tests/acceptance/drivers/ui_driver.py`
as unproven code. It is short, and the point it illustrates does not depend on
it having run.

## One thing worth knowing before you read the code

Writing this caught a real bug. `TodoService.reopen` checked for a title clash
before checking that the todo was actually finished, so an outstanding todo
collided with itself and was told it was "already back on your list". A unit
test found it in 80 milliseconds. The specification never would have — you
cannot reach that state through any interface. That is the division of labour
in one example: the specification covers what was agreed, the unit tests hold
the invariants in the place you decided they belong.
