# Todo BDD — complete project bundle

Every file of the `todo-bdd` project in one document, each under its real path
so it can be reconstructed exactly. Generated from `todo-bdd.zip`.

**What this project demonstrates:** one executable specification, parametrised
over three protocol drivers, running unchanged against the domain service, the
JSON API and a real browser. Fifteen behaviours; 81 test runs; under half a
second for the two layers that could be executed in the build sandbox.

Empty `__init__.py` package markers are omitted; every other file is included
verbatim. The full list of paths is at the end.

---


# Orientation

## `README.md`

````markdown
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
````

# The conversation and the design argument

## `docs/01-the-conversation.md`

````markdown
# The conversation

Before any code. This is where the behaviours came from and why the code is
shaped the way it is.

---

## Part one: the short version of BDD

Five things. If these are in your head, everything else follows.

**1. BDD is a conversation technique. The tests are a receipt.**

The valuable output is three people agreeing on what "done" means before anyone
writes code. If you have that agreement, writing it down as an executable test
is a small extra step. If you do not, no tooling saves you. Cucumber's failure
was making people believe the file format *was* the practice.

**2. A behaviour is something a person can observe, and would complain about if
it stopped.**

"Completing a todo moves it below the outstanding ones" — observable, someone
would complain. "The service calls the repository twice" — not observable,
nobody cares. Only the first kind belongs in a specification.

**3. Argue with examples, not rules.**

Rules sound agreed when they are not. "Titles must be unique" — everyone nods.
Then: "I finished *Buy milk* on Monday. It is Thursday. Can I add it again?"
and the nodding stops. Examples flush out the disagreement that rules hide.
This is why Given/When/Then is phrased as a story about one specific occasion
rather than as policy.

**4. Given / When / Then is just: the world was like this, one thing happened,
now it is like this.**

That is the whole of it. One *When* per example. Two *Whens* means two
behaviours squashed together.

**5. Use the words the person asking used.**

If your test says "persist entity" and the person who wanted the feature says
"save it", the test is wrong even if it passes. This is the hinge into DDD.

---

## Part two: the short version of DDD

Three ideas matter here. The rest of the book can wait.

**Everyone uses the same words, including the code.**

If the people who want the product say "complete a todo", then there is a
method called `complete` on a thing called `Todo`. Not `finish`, not
`markDone`, not `updateStatus`. One word per concept, from the conversation,
down through the code, back out into the UI labels and the error messages.
Where the code and the conversation drift apart, every handover after that
costs a translation — and translations are where bugs live.

**Split the code into the part that is about todos and the part that is about
computers.**

The rules — a todo needs a title, finishing something frees its title — are
about todos. HTTP, SQL, HTML and the system clock are about computers. Keep
them apart, with the todo-part in the middle, knowing nothing about the
computer-part.

**The middle says what it needs; the outside supplies it.**

The rules need somewhere to keep todos and a way to know what time it is. So
the middle declares two things it wants — a shelf and a clock — and does not
care what shows up. In tests: a dict and a frozen clock. In production: SQLite
and the real clock.

Four names you will hear, one line each, in todo terms:

| Term | In this project |
|---|---|
| Entity | A thing with identity. Two todos both called "Buy milk" are different todos. `domain/model.py` |
| Repository | The shelf. Named in domain words (`find_active_by_title`), never database words. `domain/ports.py` |
| Application service | Carries out a whole request end to end: `add`, `complete`, `list`. Where the rules coordinate. `service/todo_service.py` |
| Port / adapter | The shelf's *shape* is the port; the dict version and the SQLite version are adapters. `adapters/` |

**Why any of this matters for testing, which is the only reason it is here:**
if the rules live in the middle and the middle has no machinery attached, every
rule can run without a server, a browser or a database. That is the entire
source of the speed. It is not a testing trick — it is an architecture
consequence.

---

## Part three: how the two connect

Take one sentence from the conversation:

> When I complete a todo, it moves below the outstanding ones.

DDD reads that sentence and takes the vocabulary: `Todo`, `complete`,
outstanding versus done. Those become the names in the code.

But notice something else: it mentions no machinery. No page, no endpoint, no
table. So the rule it describes must be able to live somewhere that has no
machinery either.

**The conversation forces the architecture.** These are not two disciplines
bolted together — the second falls out of taking the first literally.

---

## Part four: the actual conversation

Someone asks "what does a todo list do?" and you write down answers in plain
language until you stop finding surprises.

### The behaviours

- A new todo appears on the list
- A todo with no title is refused, and says why
- A title too long to read at a glance is refused
- Sloppy spacing gets tidied up
- The same outstanding thing cannot be added twice
- Completing something marks it done, and it sinks below outstanding work
- The most recently finished thing sits at the top of the done pile
- Finished work can be picked back up
- Anything can be thrown away

Two of those exist only because someone asked an awkward question.

> "Can I add *Buy milk* twice?"
> — No.
> "I bought milk on Monday. It is Thursday. Can I add *Buy milk* again?"

And now you have to decide. We said yes: **finishing something frees its title
to be used again.** Nobody writes that rule down from a wireframe. It comes out
of the conversation, and if you skip the conversation you find it in
production.

### What is deliberately not in the list

"Rejects a title of exactly 121 characters" is absent. The specification says
*too long to read at a glance*; where exactly the boundary sits is a
developer's problem.

> **Rule of thumb: if it would bore a product owner, it is a unit test, not a
> specification.**

### What is also absent, and this is load-bearing

No mention of HTTP, forms, tables or clicking. Not tidiness — the reason the
same specification can later run against three different interfaces.

---

## Part five: the invariant question

The behaviour list above answers *what happens when I do this?* There is a
second question to ask in the same conversation, and it is easy to skip:

> **What is always true of a todo that has been completed?**

- It has a completion time.
- It cannot be completed again.
- Its title is free for reuse.

These are **invariants** — true at every moment of a todo's life, regardless of
who is asking or through which door. They are not edge cases and they are not
minor. They do not get tested into existence; they get *located*.

"Cannot be completed twice" belongs on the entity, because the entity is the
only thing that can defend it:

```python
def completed(self, at: datetime) -> Todo:
    if self.is_done:
        raise RuleViolation(f"'{self.title}' is already done")
    return replace(self, completed_at=at)
```

Once the rule lives there, there is no path to a doubly-completed todo, because
the object will not produce one.

The unit test covering it is not hunting for a missed behaviour. It is
**documenting where the invariant lives**, so that the next person who
refactors and moves the check somewhere weaker gets told immediately.

### Three questions, not two

| Question | Where the answer comes from | Where it lands | Tested by |
|---|---|---|---|
| What should the product do? | Conversation, examples, disagreement | The specification | Acceptance, all layers |
| What must always be true of this concept? | Modelling the domain | Entity or service | Unit tests |
| Did I type it correctly? | Nowhere — it is craft | The implementation | Unit tests |

If you find a *first-column* question during TDD, the conversation was bad. Go
back and have it again.

The `reopen` bug in this project was a third-column failure: the behaviour was
agreed and specified, and the guard clauses were simply in the wrong order. The
analysis was complete. The typing was not.

### One honest caveat

You will not get every invariant first time. Modelling raises questions the
original conversation did not provoke — *if reopening restores the old creation
time, does it keep its old position in the list?* When that happens, the right
move is not to decide it quietly in code. Go back and ask.

The discipline is not "know everything up front." It is **"when you find
something you do not know, do not invent the answer alone."**
````

## `docs/02-the-specification.md`

````markdown
# The specification, the DSL, and the fixture that runs it three ways

How the four layers were derived — each one produced by asking "what should not
be in here?" and moving it down.

---

## 1. The first honest attempt

We have the sentence from the conversation:

> When I complete a todo, it moves below the outstanding ones.

We want it to run. The obvious first go:

```python
def test_finished_work_sinks_below_outstanding_work():
    service = TodoService(InMemoryTodoRepository(), FrozenClock(NOON))
    milk = service.add("Buy milk")
    service.add("Call the dentist")
    service.complete(milk.id)
    assert [t.title for t in service.list()] == ["Call the dentist", "Buy milk"]
```

It works. It is also not the sentence we agreed. Three things went wrong:

**It is full of things nobody discussed.** Constructing a repository, a clock, a
list comprehension. The agreement was four lines long; this is noise around a
nugget.

**It holds an id.** No user has ever held an id. A person looks at their list,
sees *Buy milk*, and clicks it. The test is addressing todos in a way no human
does.

**It is welded to `TodoService`.** There is no version of this test that could
run against a browser without being rewritten.

---

## 2. Push the noise down: the DSL appears

Anything in that test which is not part of the agreed sentence has to go
somewhere else. What is left:

```python
def test_finished_work_sinks_below_outstanding_work(self, dsl):
    milk = dsl.a_todo_is_added("Buy milk")
    dentist = dsl.a_todo_is_added("Call the dentist")

    dsl.the_todo_is_completed(milk)

    dsl.the_list_reads(dentist, done(milk))
```

The place the noise went is the DSL.

> **The DSL is not a design. It is a residue.** It is defined by subtraction:
> whatever the specification should not say, but someone has to.

Two things happened here that were not planned, and both are worth noticing.

The setup vanished, so the DSL owns it now. Fine.

And `milk` stopped being an id and became a *name*. Not `milk.id`, not a
string the DSL has to look up — a reference to an occasion. **Making the test
readable forced a better interface.** That was not cleverness; it was a side
effect of refusing to write a sentence a product owner could not read.

The names matter more than they look. When the same title is used twice, the
specification says `mondays_milk` and `thursdays_milk` — which is exactly the
distinction the person in the conversation was already making out loud.

### What the DSL owns

Three jobs, and nothing else. See `tests/acceptance/dsl.py`.

**Business vocabulary.** Methods named for what a person does.

**Named references.** `a_todo_is_added` hands back a `TodoRef`. The DSL keeps
the mapping from that name to whatever opaque token the driver issued. The
specification holds the name; the driver holds the mechanics; neither knows
about the other.

**Test data isolation.** The specification says "Buy milk". The system sees
`Buy milk [7f3a]`. Two runs against the same environment cannot see each other,
which is what makes the suite safe to parallelise and safe to point at shared
staging.

Note what the suffix must *not* do: distinguish two todos the specification
deliberately gave the same title. The rule under test is that finishing
something frees its title for reuse — if the DSL quietly made those titles
different, the test would stop testing the rule. Telling them apart is the
token's job, not the title's.

**Synchronisation.** Every observation retries until it matches or the budget
runs out:

```python
def _eventually(self, probe, expected, description):
    deadline = time.monotonic() + self._timeout
    while True:
        actual = probe()
        if actual == expected:
            return
        if time.monotonic() >= deadline:
            raise AssertionError(f"{description}, but it was {actual!r}")
        time.sleep(0.05)
```

Against the domain driver that costs nothing. Against a browser it is the
difference between a suite people trust and a suite people re-run until it goes
green. Written once, it covers every assertion in every test.

### What the DSL must never own

**Logic.** Not one line. A step method may only delegate to the running system
and report what is observable. The moment it computes an answer instead of
asking for one, the test has become a mirror and can never fail for a real
reason.

---

## 3. Push it down again: the drivers appear

The DSL still calls `service.complete(...)` directly, so it is welded to one
way in. Split on the same principle: the DSL keeps *the words*, and the
mechanics of reaching the system move behind a small interface.

```python
class TodoDriver(Protocol):
    def add(self, title: str) -> Token | None: ...
    def complete(self, token: Token) -> None: ...
    def visible_todos(self) -> list[TodoRow]: ...
    def last_message(self) -> str | None: ...
```

> **The rule for what is allowed in this interface: only things every way in
> can do.**

`add` hands back an opaque token and every later action quotes it. What a token
*is* stays each driver's private business. The specification never sees one.

Three implementations of the same intent:

```python
# domain — microseconds
def complete(self, token):
    self._service.complete(token)

# http — milliseconds
def complete(self, token):
    self._client.post(f"/api/todos/{token}/completion")

# browser — seconds
def complete(self, token):
    self._submit(self._row(token).get_by_test_id("complete"))
```

The browser's token is read out of the form's `action`, which must already be
`/todos/<id>` for the page to function — **no test-only attribute was added to
make this work.** That is the bar to hold: a driver may use anything the page
genuinely exposes, and must not require the product to grow a field for the
tests' benefit.

Rebuild the frontend in React tomorrow: `ui_driver.py` changes, and not one
line of the specification moves.

Drivers hold no assertions and no rules. They act, and they report what is
observable. Deciding whether that is correct is the specification's job.

---

## 4. The fixture that makes it run three ways

This is the piece that ties it together. From `tests/acceptance/conftest.py`:

```python
@pytest.fixture(params=_requested_layers())     # ("domain", "http", "ui")
def dsl(request, app, repository, clock) -> TodoListDsl:
    layer = request.param
    request.node.add_marker(pytest.mark.layer(layer))
    builder = {
        "domain": _domain_dsl,
        "http": _http_dsl,
        "ui": _ui_dsl,
    }[layer]
    yield from builder(request, app, repository, clock)
```

### Line by line

**`params=...`** is the whole mechanism. When a fixture declares params, pytest
runs *every test that depends on it* once per param. Fifteen specifications
with three params become forty-five test runs. Nothing in the specification
knows this is happening — the test ids just come out as
`test_a_new_todo_appears_on_the_list[domain]`, `[http]`, `[ui]`.

**`request.param`** is how the fixture body learns which run it is in. It is
the only place in the entire acceptance suite where the name of a layer
appears.

**`_requested_layers()`** reads `SPEC_LAYERS` from the environment and defaults
to all three. This is what gives you one suite with three costs:

```bash
SPEC_LAYERS=domain      pytest tests/acceptance   # every save, ~10ms
SPEC_LAYERS=domain,http pytest tests/acceptance   # every commit, ~100ms
                        pytest tests/acceptance   # before deploy, seconds
```

Because it is evaluated at collection time, the unselected layers are never
even collected — not run and skipped, simply absent.

**`app`, `repository`, `clock`** are ordinary fixtures, requested here so that
every layer gets *the same ones*. This matters more than it looks:

```python
@pytest.fixture
def app(repository, clock):
    return create_app(repository=repository, clock=clock)
```

The browser driver does not get a special test build. It gets a real HTTP
server running the same factory as production, with two dependencies
substituted at the composition root. And because that server runs in the same
process as the test, the browser and the specification share one frozen clock —
which is what lets `dsl.time_passes(hours=1)` work through a browser at all.

**`yield from builder(...)`** delegates to a generator so each layer can do its
own setup and teardown. The HTTP layer needs a client context manager; the UI
layer needs a live server and a browser, both of which must be torn down:

```python
def _http_dsl(request, app, repository, clock):
    with app.test_client() as client:
        yield TodoListDsl(HttpDriver(client), clock)
```

**`add_marker`** tags each run with its layer so you can filter and report on
them after the fact.

### What this buys

| Layer | Runs | Cost | What it proves |
|---|---|---|---|
| domain | Every save | ~10ms | Every business rule |
| http | Every commit | ~100ms | Routing, serialisation, error mapping |
| browser | Before deploy | Seconds | The wiring, across the whole spec |

You avoid the end-to-end tax not by writing fewer browser tests, but by making
the expensive layer prove only *the trip through HTML*, while the cheap layer
proves the behaviour hundreds of times a day. The browser suite stays small
because it is not carrying the burden of testing logic — logic was already
tested three layers down, in the same words.

Adding a fourth way in — a CLI, a queue consumer, a deployed staging
environment — means writing one more driver class and adding one string to
`ALL_LAYERS`. No test changes.

---

## 5. What the delivery layers must not contain

All of this collapses if a rule leaks upward. If title validation happens in a
Flask route, the domain driver and the browser driver are testing *different
systems*, and the arrangement is a lie.

So the routes parse, delegate, serialise, and do nothing else:

```python
@api.post("/todos")
def add_todo():
    payload = request.get_json(silent=True) or {}
    return jsonify(_json(_service().add(payload.get("title", "")))), 201
```

Two consequences worth naming.

**Error messages are user-facing strings raised from the domain.** The page
renders them, the API returns them in a 422, and the specification asserts on
them. One message, three interfaces, defined once in `domain/model.py`.

**The markup carries test-facing hooks, not CSS classes.** Classes are a
designer's business and change weekly:

```html
<li data-testid="todo" data-title="{{ todo.title }}"
    data-done="{{ 'true' if todo.is_done else 'false' }}">
```

---

## 6. Integration means the contract, not the whole stack

The usual mistake is spinning up the whole app to prove the database works.
What you actually need is one suite that runs against *every* implementation of
the port:

```python
@pytest.fixture(params=["memory", "sqlite"])
def repository(request):
    if request.param == "memory":
        return InMemoryTodoRepository()
    return SqliteTodoRepository(sqlite3.connect(":memory:"))
```

Same `params` trick, different purpose. One set of tests — *does a timezone
survive the round trip, is title matching case-sensitive, does
`find_active_by_title` ignore finished work* — runs against both.

> **This is the test that earns you the right to use the fast in-memory
> repository everywhere else.**

Without it, "all green" only means your fake agrees with itself, and you learn
in production that SQLite dropped the timezone. The fake is verified, not
trusted. That one habit removes most of the reason people reach for end-to-end
tests.

---

## 7. The order you actually work in

1. **Have the conversation.** Behaviours and invariants both. (`docs/01`)
2. **Write the specification.** It fails — nothing exists yet.
3. **Drop into TDD on the service.** Unit tests for the invariants and the
   edges the conversation could not reach. The specification goes green at the
   domain layer.
4. **Add the API.** Write a driver, not a test suite. The specification runs
   again for free and proves serialisation lost nothing.
5. **Add the UI.** Write a driver. Same specification, third time.

The delivery layers arrive last and add no behaviour — which is exactly why the
same specification passes through them unchanged.

When a requirement changes, one thing changes: a sentence in the specification.
Everything else follows from it.
````

## `docs/03-open-questions.md`

````markdown
# Open questions

Things the code does not settle. Recorded rather than papered over.

---

## 1. Strings versus handles — resolved, in favour of handles

**Status: decided and implemented.** Kept here because the reasoning is the
useful part, and because the first version of this project shipped the losing
option.

### What the first version did

```python
dsl.a_todo_is_added("Buy milk")
dsl.the_todo_is_completed("Buy milk")
dsl.the_completed_todo_is_deleted("Buy milk")     # nobody says this
```

That last phrase is the tell. It exists for one reason: after the reuse rule
lets two rows share a title, the test had no way to point at one of them, so
the DSL grew vocabulary to cover the gap. **Inventing words to paper over a
modelling failure is the tail wagging the dog** — and the ambiguity leaked
downward too, as an `is_done` flag threaded through every driver signature:

```python
def delete(self, title: str, is_done: bool) -> None: ...
```

### What it does now

```python
mondays_milk = dsl.a_todo_is_added("Buy milk")
dsl.the_todo_is_completed(mondays_milk)
thursdays_milk = dsl.a_todo_is_added("Buy milk")

dsl.the_todo_is_deleted(mondays_milk)
dsl.the_list_reads(thursdays_milk)
```

The wart is gone, the driver flag is gone, and the test gained precision it did
not have before: it can now assert that deleting one of two identically-titled
todos leaves the *right* one behind. That behaviour was previously unverifiable
and is now `test_only_the_named_todo_is_thrown_away_when_a_title_is_reused`.

### The test that decided it

> **Does the handle correspond to something the person you had the conversation
> with would recognise?**

Here, yes — emphatically. They said *"the one I finished on Monday."*
`mondays_milk` is that sentence. The handle is not test machinery; it is a
distinction the user was already drawing that the string version had no room
for.

If you are inventing a handle purely to tidy the test machinery, do not. For a
domain where titles genuinely are the user's identity for an item and
duplicates are impossible, strings stay simpler.

### The trap that was nearly walked into

The tempting implementation is to fold the distinction into the isolated title:
`Buy milk [7f3a]` and `Buy milk #2 [7f3a]`.

**That silently destroys the test.** The rule under test is that a finished
title is free for reuse. If the DSL makes the two titles different, the
specification stops testing the rule and starts testing nothing — while still
passing.

So the distinction lives in a token the driver issues, never in the title.
Resolved: domain and HTTP use the todo's id; the browser reads it from the form
`action`, which already has to be `/todos/<id>` for the page to work. **No
test-only attribute was added to the markup.**

### What was given up

A purist reading says a browser test should only do what a user can do, and a
user cannot distinguish two identical rows except by position. Using the id —
even one already in the DOM — lets the driver act on a row a person could not
unambiguously pick.

That is a real loss of fidelity, accepted knowingly. The alternative was
resolving by list position, which is unstable: completing a todo moves it, so
"the first Buy milk" means different things before and after. Trading a little
fidelity for a stable reference was the better deal, but it is a trade.

---

## 2. The browser layer has never executed

`tests/acceptance/drivers/ui_driver.py` is written but unproven — the sandbox
could not download Chromium. It is short and follows the same shape as the
other two, but treat it as a sketch until it runs.

Specifically unverified:

- whether `expect_navigation()` around each form submit is the right
  synchronisation, or whether Playwright's auto-waiting makes it redundant
- whether `form[action$="/{token}"]` survives Playwright's strict mode
- whether reading the token back out of the `action` attribute is robust when
  the route ever gains a query string

---

## 3. Time control assumes one process

The live server runs in a background thread in the test process, which is what
lets the browser and the specification share a `FrozenClock`.

Point the HTTP driver at a deployed environment and that stops being true. The
usual answer is a test-only endpoint that advances a controllable clock, which
means shipping a test affordance into a real deployment. That is a genuine
trade-off and this project does not make it.

---

## 4. Ordering is specified, storage order is not

`TodoService.list()` sorts, and the specification asserts on the result. The
repository contract says nothing about the order `all()` returns.

Deliberate — order is business behaviour, not a storage concern — but it means
a repository could return rows in any order and still pass its contract. If
that ever becomes a performance problem and sorting moves into SQL, the
contract needs to grow a clause first.
````

# The executable specification

## `tests/acceptance/test_todo_specification.py`

```python
"""The executable specification for a todo list.

There is one of these. It runs against the domain service, the HTTP API and a
real browser without changing a character, because it never mentions any of
them. Read it as a description of what the product does; if it stops describing
the product, that is a bug in the product or a change of intent, never a test
to be patched.

Nothing here knows about ids, status codes, selectors or SQL. If you find
yourself wanting one of those, it belongs in a driver.

Each `a_todo_is_added` hands back a reference the test can name. Where a name
carries meaning from the conversation — `mondays_milk` versus `thursdays_milk`
— use it. Where there is only one todo in play, a plain name is clearer.
"""

from __future__ import annotations

from .dsl import done


class TestCapturingWork:
    def test_a_new_todo_appears_on_the_list(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")

        dsl.the_list_reads(milk)

    def test_todos_are_listed_oldest_first(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")
        dsl.time_passes(minutes=5)
        dentist = dsl.a_todo_is_added("Call the dentist")

        dsl.the_list_reads(milk, dentist)

    def test_surrounding_whitespace_is_tidied_away(self, dsl):
        milk = dsl.a_todo_is_added_with_untidy_spacing("Buy milk")

        dsl.the_list_reads(milk)

    def test_a_todo_must_have_a_title(self, dsl):
        dsl.a_todo_is_added_with_no_title()

        dsl.the_message_shown_is("A todo needs a title")
        dsl.the_list_is_empty()

    def test_a_title_has_to_be_readable_at_a_glance(self, dsl):
        dsl.a_todo_is_added_with_an_overlong_title()

        dsl.the_message_shown_is("Keep the title under 120 characters")
        dsl.the_list_is_empty()

    def test_the_same_thing_is_not_added_twice(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")

        dsl.a_todo_is_added_expecting_refusal("Buy milk")

        dsl.the_message_shown_is("'Buy milk' is already on your list")
        dsl.the_list_reads(milk)


class TestGettingWorkDone:
    def test_completing_a_todo_marks_it_done(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")

        dsl.the_todo_is_completed(milk)

        dsl.the_list_reads(done(milk))
        dsl.no_message_is_shown()

    def test_finished_work_sinks_below_outstanding_work(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")
        dentist = dsl.a_todo_is_added("Call the dentist")

        dsl.the_todo_is_completed(milk)

        dsl.the_list_reads(dentist, done(milk))

    def test_the_most_recently_finished_work_sits_at_the_top_of_the_done_pile(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")
        dentist = dsl.a_todo_is_added("Call the dentist")

        dsl.the_todo_is_completed(milk)
        dsl.time_passes(hours=1)
        dsl.the_todo_is_completed(dentist)

        dsl.the_list_reads(done(dentist), done(milk))

    def test_finishing_something_frees_its_title_to_be_used_again(self, dsl):
        mondays_milk = dsl.a_todo_is_added("Buy milk")
        dsl.the_todo_is_completed(mondays_milk)

        thursdays_milk = dsl.a_todo_is_added("Buy milk")

        dsl.no_message_is_shown()
        dsl.the_list_reads(thursdays_milk, done(mondays_milk))

    def test_work_can_be_picked_back_up(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")
        dsl.the_todo_is_completed(milk)

        dsl.the_todo_is_reopened(milk)

        dsl.the_list_reads(milk)

    def test_work_cannot_be_picked_back_up_onto_a_taken_title(self, dsl):
        mondays_milk = dsl.a_todo_is_added("Buy milk")
        dsl.the_todo_is_completed(mondays_milk)
        thursdays_milk = dsl.a_todo_is_added("Buy milk")

        dsl.the_todo_is_reopened(mondays_milk)

        dsl.the_message_shown_is("'Buy milk' is already back on your list")
        dsl.the_list_reads(thursdays_milk, done(mondays_milk))


class TestClearingThingsOut:
    def test_a_todo_can_be_thrown_away(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")
        dentist = dsl.a_todo_is_added("Call the dentist")

        dsl.the_todo_is_deleted(milk)

        dsl.the_list_reads(dentist)

    def test_finished_work_can_be_thrown_away(self, dsl):
        milk = dsl.a_todo_is_added("Buy milk")
        dsl.the_todo_is_completed(milk)

        dsl.the_todo_is_deleted(milk)

        dsl.the_list_is_empty()

    def test_only_the_named_todo_is_thrown_away_when_a_title_is_reused(self, dsl):
        mondays_milk = dsl.a_todo_is_added("Buy milk")
        dsl.the_todo_is_completed(mondays_milk)
        thursdays_milk = dsl.a_todo_is_added("Buy milk")

        dsl.the_todo_is_deleted(mondays_milk)

        dsl.the_list_reads(thursdays_milk)
```

## `tests/acceptance/dsl.py`

```python
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
```

## `tests/acceptance/conftest.py`

```python
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
```

# The drivers: one per way into the system

## `tests/acceptance/drivers/__init__.py`

```python
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
```

## `tests/acceptance/drivers/domain_driver.py`

```python
"""Driver that calls the service in-process. Microseconds per test.

This is the driver you run on every keystroke. It exercises every business rule
and none of the plumbing, which is exactly the trade you want hundreds of times
a day.

Its token is the todo's id, which it has in hand the moment `add` returns.
"""

from __future__ import annotations

from todo.domain.model import RuleViolation
from todo.service.todo_service import TodoService

from . import Token, TodoRow


class DomainDriver:
    def __init__(self, service: TodoService) -> None:
        self._service = service
        self._message: str | None = None

    def add(self, title: str) -> Token | None:
        created = self._attempt(lambda: self._service.add(title))
        return created.id if created else None

    def complete(self, token: Token) -> None:
        self._attempt(lambda: self._service.complete(token))

    def reopen(self, token: Token) -> None:
        self._attempt(lambda: self._service.reopen(token))

    def delete(self, token: Token) -> None:
        self._attempt(lambda: self._service.delete(token))

    def visible_todos(self) -> list[TodoRow]:
        return [
            TodoRow(token=t.id, title=t.title, is_done=t.is_done)
            for t in self._service.list()
        ]

    def last_message(self) -> str | None:
        return self._message

    def _attempt(self, action):
        self._message = None
        try:
            return action()
        except RuleViolation as violation:
            self._message = str(violation)
            return None
```

## `tests/acceptance/drivers/http_driver.py`

```python
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
```

## `tests/acceptance/drivers/ui_driver.py`

```python
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
```

# The domain: rules that know nothing about machinery

## `src/todo/domain/model.py`

```python
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
```

## `src/todo/domain/ports.py`

```python
"""Ports: the interfaces the application depends on but does not implement.

These exist so the service can be driven at speed in tests (in-memory repository,
frozen clock) and in earnest in production (SQLite, the real clock) without the
service knowing which it got.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Protocol

from .model import Todo


class TodoRepository(Protocol):
    def add(self, todo: Todo) -> None: ...

    def replace(self, todo: Todo) -> None: ...

    def remove(self, todo_id: str) -> None: ...

    def get(self, todo_id: str) -> Todo | None: ...

    def find_active_by_title(self, title: str) -> Todo | None: ...

    def all(self) -> list[Todo]: ...


class Clock(Protocol):
    def now(self) -> datetime: ...


class SystemClock:
    def now(self) -> datetime:
        return datetime.now(timezone.utc)


class FrozenClock:
    """A clock the tests control.

    Time is an input to the system like any other. Injecting it is what makes
    'a todo completed yesterday sorts below one completed today' a testable
    statement instead of a sleep().
    """

    def __init__(self, start: datetime) -> None:
        self._now = start

    def now(self) -> datetime:
        return self._now

    def advance(self, **delta) -> None:
        from datetime import timedelta

        self._now = self._now + timedelta(**delta)

    def set(self, moment: datetime) -> None:
        self._now = moment
```

## `src/todo/service/todo_service.py`

```python
"""The application service. This is the real system under test.

Everything above it (JSON API, HTML pages) is delivery mechanism. Everything
below it (SQLite, the clock) is infrastructure. All the behaviour worth
specifying lives here, which is why the fastest acceptance driver can talk
straight to it and still be testing the same system as the browser.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from ..domain.model import RuleViolation, Todo, clean_title
from ..domain.ports import Clock, TodoRepository


@dataclass(frozen=True)
class TodoView:
    """What a caller is allowed to see. Deliberately smaller than the entity."""

    id: str
    title: str
    is_done: bool


class TodoService:
    def __init__(self, repository: TodoRepository, clock: Clock) -> None:
        self._repository = repository
        self._clock = clock

    def add(self, raw_title: str) -> TodoView:
        title = clean_title(raw_title)
        if self._repository.find_active_by_title(title) is not None:
            raise RuleViolation(f"'{title}' is already on your list")
        todo = Todo(id=uuid.uuid4().hex, title=title, created_at=self._clock.now())
        self._repository.add(todo)
        return _view(todo)

    def complete(self, todo_id: str) -> TodoView:
        todo = self._require(todo_id)
        done = todo.completed(at=self._clock.now())
        self._repository.replace(done)
        return _view(done)

    def reopen(self, todo_id: str) -> TodoView:
        todo = self._require(todo_id)
        # Check this todo's own state first. Otherwise an outstanding todo
        # collides with itself in the title check below and gets told it is
        # already back on the list.
        active = todo.reopened()
        if self._repository.find_active_by_title(todo.title) is not None:
            raise RuleViolation(f"'{todo.title}' is already back on your list")
        self._repository.replace(active)
        return _view(active)

    def delete(self, todo_id: str) -> None:
        self._require(todo_id)
        self._repository.remove(todo_id)

    def list(self) -> list[TodoView]:
        """Outstanding work first, oldest first; then what is done, newest first.

        The order is part of the behaviour — it is what the user sees — so it
        belongs in the service and gets specified, not left to the database.
        """
        todos = self._repository.all()
        active = sorted((t for t in todos if not t.is_done), key=lambda t: t.created_at)
        done = sorted(
            (t for t in todos if t.is_done),
            key=lambda t: t.completed_at,
            reverse=True,
        )
        return [_view(t) for t in active + done]

    def _require(self, todo_id: str) -> Todo:
        todo = self._repository.get(todo_id)
        if todo is None:
            raise RuleViolation("That todo is no longer on your list")
        return todo


def _view(todo: Todo) -> TodoView:
    return TodoView(id=todo.id, title=todo.title, is_done=todo.is_done)
```

# Adapters: the ports, implemented

## `src/todo/adapters/memory_repo.py`

```python
"""In-memory repository.

This ships in `src/`, not in `tests/`, on purpose. It is a real implementation
of the port that happens to be fast and disposable, and it is verified by the
same contract test as the SQLite one. A fake that is never verified is just a
second bug farm.
"""

from __future__ import annotations

from ..domain.model import Todo
from ..domain.ports import TodoRepository


class InMemoryTodoRepository(TodoRepository):
    def __init__(self) -> None:
        self._todos: dict[str, Todo] = {}

    def add(self, todo: Todo) -> None:
        self._todos[todo.id] = todo

    def replace(self, todo: Todo) -> None:
        self._todos[todo.id] = todo

    def remove(self, todo_id: str) -> None:
        self._todos.pop(todo_id, None)

    def get(self, todo_id: str) -> Todo | None:
        return self._todos.get(todo_id)

    def find_active_by_title(self, title: str) -> Todo | None:
        for todo in self._todos.values():
            if todo.title == title and not todo.is_done:
                return todo
        return None

    def all(self) -> list[Todo]:
        return list(self._todos.values())
```

## `src/todo/adapters/sqlite_repo.py`

```python
"""SQLite repository. The production implementation of the same port."""

from __future__ import annotations

import sqlite3
from datetime import datetime

from ..domain.model import Todo
from ..domain.ports import TodoRepository

SCHEMA = """
CREATE TABLE IF NOT EXISTS todos (
    id           TEXT PRIMARY KEY,
    title        TEXT NOT NULL,
    created_at   TEXT NOT NULL,
    completed_at TEXT
);
CREATE INDEX IF NOT EXISTS todos_title ON todos (title);
"""


class SqliteTodoRepository(TodoRepository):
    def __init__(self, connection: sqlite3.Connection) -> None:
        self._connection = connection
        self._connection.row_factory = sqlite3.Row
        self._connection.executescript(SCHEMA)
        self._connection.commit()

    def add(self, todo: Todo) -> None:
        self._connection.execute(
            "INSERT INTO todos (id, title, created_at, completed_at) VALUES (?, ?, ?, ?)",
            (todo.id, todo.title, todo.created_at.isoformat(), _iso_or_none(todo.completed_at)),
        )
        self._connection.commit()

    def replace(self, todo: Todo) -> None:
        self._connection.execute(
            "UPDATE todos SET title = ?, created_at = ?, completed_at = ? WHERE id = ?",
            (todo.title, todo.created_at.isoformat(), _iso_or_none(todo.completed_at), todo.id),
        )
        self._connection.commit()

    def remove(self, todo_id: str) -> None:
        self._connection.execute("DELETE FROM todos WHERE id = ?", (todo_id,))
        self._connection.commit()

    def get(self, todo_id: str) -> Todo | None:
        row = self._connection.execute(
            "SELECT * FROM todos WHERE id = ?", (todo_id,)
        ).fetchone()
        return _to_todo(row) if row else None

    def find_active_by_title(self, title: str) -> Todo | None:
        row = self._connection.execute(
            "SELECT * FROM todos WHERE title = ? AND completed_at IS NULL", (title,)
        ).fetchone()
        return _to_todo(row) if row else None

    def all(self) -> list[Todo]:
        rows = self._connection.execute("SELECT * FROM todos").fetchall()
        return [_to_todo(row) for row in rows]


def _iso_or_none(moment: datetime | None) -> str | None:
    return moment.isoformat() if moment else None


def _to_todo(row: sqlite3.Row) -> Todo:
    return Todo(
        id=row["id"],
        title=row["title"],
        created_at=datetime.fromisoformat(row["created_at"]),
        completed_at=(
            datetime.fromisoformat(row["completed_at"]) if row["completed_at"] else None
        ),
    )
```

# Delivery: two thin interfaces over one service

## `src/todo/web/app.py`

```python
"""Composition root.

The factory takes its dependencies rather than constructing them. That single
decision is what lets a test start the identical application with a frozen
clock and an in-memory repository, and lets production start it with the real
clock and a database — with no test-only branches inside the app.
"""

from __future__ import annotations

import sqlite3

from flask import Flask

from ..adapters.memory_repo import InMemoryTodoRepository
from ..adapters.sqlite_repo import SqliteTodoRepository
from ..domain.model import RuleViolation
from ..domain.ports import Clock, SystemClock, TodoRepository
from ..service.todo_service import TodoService
from .api import api
from .ui import ui


def create_app(
    repository: TodoRepository | None = None,
    clock: Clock | None = None,
    secret_key: str = "dev-only-not-a-real-secret",
) -> Flask:
    app = Flask(__name__)
    app.secret_key = secret_key
    app.config["TODO_SERVICE"] = TodoService(
        repository=repository if repository is not None else InMemoryTodoRepository(),
        clock=clock if clock is not None else SystemClock(),
    )
    app.register_blueprint(api)
    app.register_blueprint(ui)

    # Blueprint-level handlers do not catch exceptions raised in other
    # blueprints, so the app-level one keeps the two interfaces consistent.
    app.register_error_handler(RuleViolation, _rule_violation)
    return app


def _rule_violation(error: RuleViolation):
    from flask import jsonify, request

    if request.path.startswith("/api"):
        return jsonify(error=str(error)), 422
    raise error


def create_production_app(database_path: str = "todos.db") -> Flask:
    connection = sqlite3.connect(database_path, check_same_thread=False)
    return create_app(repository=SqliteTodoRepository(connection), clock=SystemClock())
```

## `src/todo/web/api.py`

```python
"""JSON API. Thin by design: parse, delegate, serialise.

There is no business logic here. If a rule ever creeps into this file, the
domain driver stops testing the same system as the HTTP driver and the whole
arrangement quietly rots.
"""

from __future__ import annotations

from flask import Blueprint, current_app, jsonify, request

from ..domain.model import RuleViolation

api = Blueprint("api", __name__, url_prefix="/api")


def _service():
    return current_app.config["TODO_SERVICE"]


@api.errorhandler(RuleViolation)
def _handle_rule_violation(error: RuleViolation):
    return jsonify(error=str(error)), 422


@api.get("/todos")
def list_todos():
    return jsonify(todos=[_json(t) for t in _service().list()])


@api.post("/todos")
def add_todo():
    payload = request.get_json(silent=True) or {}
    todo = _service().add(payload.get("title", ""))
    return jsonify(_json(todo)), 201


@api.post("/todos/<todo_id>/completion")
def complete_todo(todo_id: str):
    return jsonify(_json(_service().complete(todo_id)))


@api.delete("/todos/<todo_id>/completion")
def reopen_todo(todo_id: str):
    return jsonify(_json(_service().reopen(todo_id)))


@api.delete("/todos/<todo_id>")
def delete_todo(todo_id: str):
    _service().delete(todo_id)
    return "", 204


def _json(todo) -> dict:
    return {"id": todo.id, "title": todo.title, "done": todo.is_done}
```

## `src/todo/web/ui.py`

```python
"""HTML pages. The second delivery mechanism over the same service.

Post/Redirect/Get with the message carried in the session, so the browser test
never has to reason about form resubmission.
"""

from __future__ import annotations

from flask import (
    Blueprint,
    current_app,
    redirect,
    render_template,
    request,
    session,
    url_for,
)

from ..domain.model import RuleViolation

ui = Blueprint("ui", __name__)


def _service():
    return current_app.config["TODO_SERVICE"]


@ui.get("/")
def index():
    return render_template(
        "index.html",
        todos=_service().list(),
        message=session.pop("message", None),
    )


@ui.post("/todos")
def add_todo():
    _attempt(lambda: _service().add(request.form.get("title", "")))
    return redirect(url_for("ui.index"))


@ui.post("/todos/<todo_id>")
def change_todo(todo_id: str):
    action = request.form.get("action")
    actions = {
        "complete": lambda: _service().complete(todo_id),
        "reopen": lambda: _service().reopen(todo_id),
        "delete": lambda: _service().delete(todo_id),
    }
    _attempt(actions[action])
    return redirect(url_for("ui.index"))


def _attempt(action) -> None:
    try:
        action()
    except RuleViolation as violation:
        session["message"] = str(violation)
```

## `src/todo/web/templates/index.html`

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Todo</title>
  <link rel="stylesheet" href="{{ url_for('static', filename='todo.css') }}">
</head>
<body>
  <main>
    <header class="masthead">
      <h1>Today</h1>
      {% set remaining = todos | rejectattr('is_done') | list | length %}
      <p class="tally" data-testid="tally">
        {% if remaining == 0 %}Nothing left to do.
        {% elif remaining == 1 %}One thing left.
        {% else %}{{ remaining }} things left.{% endif %}
      </p>
    </header>

    {% if message %}
      <p class="message" role="alert" data-testid="message">{{ message }}</p>
    {% endif %}

    <form class="compose" method="post" action="{{ url_for('ui.add_todo') }}">
      <label class="visually-hidden" for="title">What needs doing?</label>
      <input id="title" name="title" data-testid="new-todo"
             placeholder="What needs doing?" autocomplete="off" autofocus>
      <button type="submit" data-testid="add">Add</button>
    </form>

    {% if todos %}
      <ul class="ledger" data-testid="todo-list">
        {% for todo in todos %}
          <li class="entry {{ 'is-done' if todo.is_done }}"
              data-testid="todo"
              data-title="{{ todo.title }}"
              data-done="{{ 'true' if todo.is_done else 'false' }}">
            <form method="post" action="{{ url_for('ui.change_todo', todo_id=todo.id) }}">
              <button class="marker" type="submit" name="action"
                      value="{{ 'reopen' if todo.is_done else 'complete' }}"
                      data-testid="{{ 'reopen' if todo.is_done else 'complete' }}"
                      aria-label="{{ 'Reopen' if todo.is_done else 'Complete' }} {{ todo.title }}">
                <span aria-hidden="true">{{ '●' if todo.is_done else '○' }}</span>
              </button>
              <span class="title" data-testid="todo-title">{{ todo.title }}</span>
              <button class="discard" type="submit" name="action" value="delete"
                      data-testid="delete" aria-label="Delete {{ todo.title }}">
                <span aria-hidden="true">&times;</span>
              </button>
            </form>
          </li>
        {% endfor %}
      </ul>
    {% else %}
      <p class="empty" data-testid="empty">Your list is clear. Add the first thing above.</p>
    {% endif %}
  </main>
</body>
</html>
```

## `src/todo/web/static/todo.css`

```css
:root {
  --paper: #e8eae6;
  --surface: #fdfdfc;
  --ink: #23282b;
  --rule: #c4c9c3;
  --struck: #7b837e;
  --alert: #7a2e24;
  --serif: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif;
  --sans: ui-sans-serif, "Helvetica Neue", Arial, sans-serif;
}

* { box-sizing: border-box; }

body {
  margin: 0;
  padding: 4rem 1.5rem 6rem;
  background: var(--paper);
  color: var(--ink);
  font-family: var(--serif);
  line-height: 1.5;
}

main {
  max-width: 32rem;
  margin: 0 auto;
  background: var(--surface);
  padding: 2.25rem 2rem 2.5rem;
}

.masthead h1 {
  margin: 0;
  font-size: 2rem;
  font-weight: 400;
  letter-spacing: -0.01em;
}

.tally {
  margin: 0.25rem 0 2rem;
  font-family: var(--sans);
  font-size: 0.8125rem;
  color: var(--struck);
}

.message {
  margin: 0 0 1.5rem;
  padding-left: 0.75rem;
  border-left: 2px solid var(--alert);
  font-family: var(--sans);
  font-size: 0.8125rem;
  color: var(--alert);
}

.compose {
  display: flex;
  gap: 0.75rem;
  align-items: baseline;
  padding-bottom: 0.875rem;
  border-bottom: 1px solid var(--ink);
}

.compose input {
  flex: 1;
  min-width: 0;
  border: 0;
  background: transparent;
  font-family: var(--serif);
  font-size: 1.0625rem;
  color: var(--ink);
  padding: 0;
}

.compose input:focus { outline: none; }
.compose input::placeholder { color: var(--struck); }

.compose button {
  border: 0;
  background: transparent;
  padding: 0;
  font-family: var(--sans);
  font-size: 0.8125rem;
  color: var(--ink);
  cursor: pointer;
}

.compose button:hover { text-decoration: underline; }

.ledger {
  list-style: none;
  margin: 0;
  padding: 0;
}

.entry { border-bottom: 1px solid var(--rule); }

.entry form {
  display: grid;
  grid-template-columns: 1.75rem 1fr 1.75rem;
  align-items: baseline;
  gap: 0.25rem;
  padding: 0.75rem 0;
}

.marker,
.discard {
  border: 0;
  background: transparent;
  padding: 0;
  font-size: 0.9375rem;
  color: var(--struck);
  cursor: pointer;
  line-height: inherit;
  text-align: left;
}

.discard {
  text-align: right;
  opacity: 0;
  font-size: 1.125rem;
}

.entry:hover .discard,
.discard:focus-visible { opacity: 1; }

.marker:hover { color: var(--ink); }

.title {
  font-size: 1.0625rem;
  position: relative;
}

.is-done .title { color: var(--struck); }

.is-done .title::after {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  top: 0.72em;
  border-top: 1px solid currentColor;
  transform-origin: left;
  animation: strike 220ms ease-out;
}

@keyframes strike {
  from { transform: scaleX(0); }
  to   { transform: scaleX(1); }
}

.empty {
  margin: 2rem 0 0;
  font-family: var(--sans);
  font-size: 0.8125rem;
  color: var(--struck);
}

:focus-visible {
  outline: 2px solid var(--ink);
  outline-offset: 2px;
}

.visually-hidden {
  position: absolute;
  width: 1px; height: 1px;
  padding: 0; margin: -1px;
  overflow: hidden; clip: rect(0 0 0 0);
  white-space: nowrap; border: 0;
}

@media (prefers-reduced-motion: reduce) {
  .is-done .title::after { animation: none; }
}
```

# Unit and contract tests

## `tests/unit/test_todo_service.py`

```python
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
```

## `tests/contract/test_repository_contract.py`

```python
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
```

# Project files

## `pyproject.toml`

```toml
[project]
name = "todo-bdd"
version = "1.0.0"
requires-python = ">=3.11"
dependencies = ["flask>=3.0"]

[project.optional-dependencies]
test = ["pytest>=8.0", "playwright>=1.40"]

[tool.pytest.ini_options]
pythonpath = ["src"]
testpaths = ["tests"]
markers = [
    "layer(name): the layer of the system an acceptance run is driving",
]
```

## `run.py`

```python
"""Start the app for real: SQLite on disk, the system clock, port 5000."""
from todo.web import create_production_app

if __name__ == "__main__":
    create_production_app("todos.db").run(debug=True)
```

# Full file list

Included above:

- `README.md`
- `docs/01-the-conversation.md`
- `docs/02-the-specification.md`
- `docs/03-open-questions.md`
- `tests/acceptance/test_todo_specification.py`
- `tests/acceptance/dsl.py`
- `tests/acceptance/conftest.py`
- `tests/acceptance/drivers/__init__.py`
- `tests/acceptance/drivers/domain_driver.py`
- `tests/acceptance/drivers/http_driver.py`
- `tests/acceptance/drivers/ui_driver.py`
- `src/todo/domain/model.py`
- `src/todo/domain/ports.py`
- `src/todo/service/todo_service.py`
- `src/todo/adapters/memory_repo.py`
- `src/todo/adapters/sqlite_repo.py`
- `src/todo/web/app.py`
- `src/todo/web/api.py`
- `src/todo/web/ui.py`
- `src/todo/web/templates/index.html`
- `src/todo/web/static/todo.css`
- `tests/unit/test_todo_service.py`
- `tests/contract/test_repository_contract.py`
- `pyproject.toml`
- `run.py`

In the archive but omitted here (empty or incidental):

- `.gitignore`
- `src/todo/__init__.py`
- `src/todo/adapters/__init__.py`
- `src/todo/domain/__init__.py`
- `src/todo/service/__init__.py`
- `src/todo/web/__init__.py`
- `tests/__init__.py`
- `tests/acceptance/__init__.py`
- `tests/contract/__init__.py`
- `tests/unit/__init__.py`
