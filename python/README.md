# todo-bdd — Python

A small Flask todo application built to demonstrate one idea in full:

> You do not write a separate executable specification for the unit, integration
> and UI layers. You write **one** specification and swap what it drives.

Fifteen behaviours live in `tests/acceptance/test_todo_specification.py`. That
file mentions no HTTP, no SQL, no selectors and no ids. It runs unchanged against
the domain service, against the JSON API, and against a real browser — because it
never names any of them.

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

This README explains the whole thing: the architecture, how a single
specification is kept honest across three protocols, how the testing layers fit
together, and the design decisions (and trade-offs) behind each choice.

---

## 1. The architecture: rules in one place, everything else at the edges

The code is layered so that the *behaviour worth specifying* has exactly one
home, and everything else is a thin shell around it. This is ports-and-adapters
(hexagonal) with a classic DDD split.

```
src/todo/
  domain/       the rules, knowing nothing about machinery
    model.py      Todo entity, clean_title, RuleViolation
    ports.py      TodoRepository, Clock  (interfaces the app depends on)
  service/
    todo_service.py   the application service — the real system under test
  adapters/     the ports, implemented
    memory_repo.py    fast, disposable (used in tests)
    sqlite_repo.py    production persistence
  web/          delivery: two thin interfaces over one service
    app.py        composition root (create_app takes its dependencies)
    api.py        JSON API — parse, delegate, serialise
    ui.py         HTML pages — Post/Redirect/Get
    templates/, static/
```

**Domain (`model.py`).** Pure rules. A `Todo` is immutable; `completed()` and
`reopened()` return new todos or raise `RuleViolation`. `clean_title()`
normalises and validates. Nothing here imports Flask, SQL, or a test.

**Ports (`ports.py`).** The interfaces the application *depends on but does not
implement*: `TodoRepository` (persistence) and `Clock` (time). They exist so the
service can be driven at speed in tests (in-memory repo, frozen clock) and in
earnest in production (SQLite, the wall clock), without the service knowing which
it got. This is dependency inversion: the core owns the interface, the edges
implement it.

**Application service (`todo_service.py`).** This is *the real system under
test.* Every business rule lives here, once: title uniqueness, completion,
reopening, deletion, and the list ordering (outstanding oldest-first, then done
newest-first). Because all behaviour is here, the fastest acceptance driver can
talk straight to it and still be exercising the same system as the browser.

**Adapters (`adapters/`).** Two implementations of `TodoRepository`. The
in-memory one ships in `src/`, not `tests/`, on purpose — it is a real
implementation that happens to be fast, and it is held to the same contract test
as SQLite. A fake that is never verified is just a second bug farm.

**Delivery (`web/`).** Two ways in — JSON and HTML — each deliberately thin:
parse the request, delegate to the service, serialise the result. If a rule ever
creeps into `api.py` or `ui.py`, the domain driver stops testing the same system
as the HTTP driver and the whole arrangement quietly rots. The **composition
root** is `create_app()`, which *takes* its repository and clock rather than
constructing them — the single decision that lets a test start the identical
application with a frozen clock and an in-memory repository, and production start
it with the real clock and a database, with no test-only branches inside the app.

---

## 2. The singular specification: how one file drives three protocols

The specification is written in a **business vocabulary**, not a technical one:

```python
def test_finishing_something_frees_its_title_to_be_used_again(self, dsl):
    mondays_milk = dsl.a_todo_is_added("Buy milk")
    dsl.the_todo_is_completed(mondays_milk)

    thursdays_milk = dsl.a_todo_is_added("Buy milk")

    dsl.no_message_is_shown()
    dsl.the_list_reads(thursdays_milk, done(mondays_milk))
```

Three collaborating pieces keep that file protocol-free:

### The DSL (`tests/acceptance/dsl.py`)

The vocabulary the specification is written in. It has four jobs and no others:

1. **Business language.** Methods are named for what a person does
   (`a_todo_is_added`), never for what the code does (`post_json`).
2. **Named references.** `a_todo_is_added` returns a `TodoRef` the spec can name
   — `mondays_milk`, `thursdays_milk`. The DSL keeps the mapping from that name
   to whatever opaque token the driver issued. The spec holds the name; the
   driver holds the mechanics; neither knows the other.
3. **Test-data isolation.** The spec says "Buy milk"; the system sees
   "Buy milk [7f3a]". Two runs against one environment cannot see each other, so
   the suite is safe to parallelise and safe to point at a shared environment.
   Crucially, the suffix must *not* distinguish two todos the spec deliberately
   gave the same title — that is the token's job, not the title's.
4. **Synchronisation.** Every observation retries until it matches or a budget
   runs out (`_eventually`). Against the domain driver that costs nothing;
   against a browser it is the difference between a suite people trust and a suite
   people re-run until it goes green. This is the auto-retrying "web-first
   assertion" pattern, factored into the DSL so all three drivers share it. See
   [`../docs/04-browser-synchronisation.md`](../docs/04-browser-synchronisation.md)
   for how this relates to Playwright's auto-waiting and `waitUntil` options.

What the DSL must never contain is **logic**. A step may only drive the system
and report what is observable. The moment it computes an answer rather than
asking for one, the test becomes a mirror and can never fail for a real reason.

### The driver interface (`tests/acceptance/drivers/__init__.py`)

A tiny `Protocol` — `add`, `complete`, `reopen`, `delete`, `visible_todos`,
`last_message` — implemented once per way into the system. The specification
never learns which one it holds.

**Tokens are opaque.** `add` returns a token and every later action quotes it.
What a token *is* stays each driver's private business (the domain and HTTP
drivers use the todo's id; the browser reads it from the form `action` already in
the markup). This is what lets two todos share a title without the tests going
blind: addressing rows by title cannot tell Monday's finished milk from
Thursday's outstanding milk.

### The parametrised fixture (`tests/acceptance/conftest.py`)

One pytest fixture, `dsl`, parametrised over the layers. The same `app`,
`repository` and `clock` fixtures build the system; `SPEC_LAYERS` selects which
drivers run. The UI layer gets a **real HTTP server** running the *same*
`create_app` factory as production — not a special test build — with only the
repository and clock substituted at the composition root.

---

## 3. Consistent testing: the same behaviour, three costs, plus a pyramid under it

The three acceptance drivers trade fidelity for speed:

| driver  | goes through                     | cost      | run it… |
|---------|----------------------------------|-----------|---------|
| domain  | the service, in-process          | microseconds | on every keystroke |
| http    | the JSON API via Flask's test client (no socket) | milliseconds | on every commit |
| browser | Playwright against a live server | seconds   | before deploy |

`SPEC_LAYERS=domain` is the inner loop; `SPEC_LAYERS=domain,http` is every
commit; the full run adds the browser. Same fifteen behaviours every time.

Underneath the acceptance layer sit two more kinds of test that the acceptance
spec deliberately does **not** duplicate:

- **Unit tests** (`tests/unit/test_todo_service.py`) — *how the unit behaves*,
  including edges no user story would mention (ids, exception types, the clock).
  Rule of thumb: if it would bore a product owner, it is a unit test.
- **The repository contract** (`tests/contract/test_repository_contract.py`) —
  one contract, run against *every* implementation of the port. This is what
  earns you the right to use the fast in-memory repository everywhere else;
  without it, "all green" only means the fake agrees with itself.

This is the division of labour: the **specification** covers what was agreed with
the user; the **unit tests** hold the invariants in the place you decided they
belong. A unit test caught a real bug this way — `reopen` checked for a title
clash before checking the todo was actually finished, so an outstanding todo
collided with itself and was told it was "already back on your list". The
specification never could have found it: you cannot reach that state through any
interface.

---

## 4. Key design decisions (and their trade-offs)

- **Time is an input, injected.** A `FrozenClock` makes "finished yesterday sorts
  below finished today" a testable statement instead of a `sleep()`. The service
  reads `clock.now()`; the DSL advances it with `time_passes(hours=1)`.
- **Ordering is business behaviour, so it lives in the service**, not the
  database. `TodoService.list()` sorts; the spec asserts on the order. The
  repository contract says nothing about `all()`'s order — deliberately.
- **One message per rule.** `RuleViolation` carries a single user-facing string,
  shown in the UI, returned by the API, and asserted on in the spec. That single
  message is what lets one specification assert against all three interfaces.
- **Handles, not strings, for identity.** `mondays_milk` versus `thursdays_milk`
  is a distinction the user was already drawing out loud ("the one I finished on
  Monday"). Encoding it as a named reference — resolved to a token by the driver
  — is what makes "delete *that* one" expressible and verifiable. The trade-off,
  discussed in `../docs/03-open-questions.md`, is a small loss of browser
  fidelity (the driver acts on a row by id, which a human could not unambiguously
  pick) accepted in exchange for a stable reference.
- **Flash via session + Post/Redirect/Get.** The UI carries the message across a
  redirect in the session, so the browser test never reasons about form
  resubmission.
- **The fake ships in `src/` and is contract-tested.** See §3.

---

## 5. How this simplifies things

- **One specification instead of three.** The behaviours are written once. A
  change of intent is one edit, not three; a divergence between layers becomes
  impossible to express.
- **Adding a way in is one file.** A CLI, a queue consumer, a deployed
  environment: write one more driver implementing the six-method interface and
  change no tests at all.
- **Swapping the frontend is one file.** Rebuild the UI in React tomorrow and
  only `drivers/ui_driver.py` changes — not one line of the specification moves.
- **The rules cannot drift.** Because delivery layers are thin and every rule
  lives in the service, the domain driver and the HTTP driver are provably
  exercising the same behaviour.

---

## 6. Running it

```bash
pip install flask pytest
export PYTHONPATH=src

pytest tests/unit tests/contract              # 51 unit + contract, ~50ms
SPEC_LAYERS=domain pytest tests/acceptance     # the inner loop
SPEC_LAYERS=domain,http pytest                 # every commit
pytest                                         # everything, browser included

python run.py                                  # the app on :5000, SQLite on disk
```

The browser layer needs Playwright and Chromium:

```bash
pip install playwright && playwright install chromium
```

Watch the browser drive the page:

```bash
HEADED=1 SLOWMO=450 SPEC_LAYERS=ui pytest tests/acceptance
```

Without a browser, the UI layer skips rather than fails; the other two run
regardless.

**Status:** 51 unit and contract tests, and the 15 specifications across all
three drivers — 96 test runs, the two in-process layers in well under a second.

See `../docs/` for the longer design essays, and `../haskell/` for the same
design ported to a completely different stack.
