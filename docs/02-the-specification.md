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
