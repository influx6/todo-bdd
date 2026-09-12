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

## 2. The browser layer — now executed, mostly resolved

**Status: it runs.** `tests/acceptance/drivers/ui_driver.py` was written before
Chromium could be downloaded in the original build sandbox, and stayed a
sketch. All 15 specifications now pass through it, headless and headed, on
Playwright 1.62 / Chromium 151. Set `HEADED=1 SLOWMO=450` to watch it.

What the three unknowns turned out to be:

- `expect_navigation()` around each form submit **works**, but Playwright 1.62
  marks it deprecated. Every action here is a full-page form post, so the wait
  is not redundant — auto-waiting alone would let the next locator query race
  the reload. The modern spelling is to wrap the click in
  `page.expect_navigation()`'s successor or assert on a post-navigation locator;
  swapping it is cosmetic, not a correctness fix. Left as-is, flagged.
- `form[action$="/{token}"]` **survives strict mode** — each row's action is
  unique, so `:has(form[action$="/{id}"])` resolves to exactly one `li`.
- reading the token out of the `action` attribute is robust for the current
  routes, which carry no query string. Still latent: if `/todos/<id>` ever
  grows a `?…`, `rstrip("/").split("/")[-1]` would pick up the query. Parse the
  path if that day comes.

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
