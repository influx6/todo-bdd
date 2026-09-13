# Acceptance Testing (the whole thing, condensed)

## Like you're 10

You built a vending machine. A **unit test** checks one gear turns correctly. An
**acceptance test** is a person walking up, putting in a coin, pressing B4, and
checking a chocolate bar actually drops. It tests the *whole thing*, from the
outside, the way someone who *uses* it cares about.

That's acceptance testing: **checking the software does what people agreed it
should, from the outside, end to end.**

## The one idea

Two different questions:

- **Unit tests:** "Did we build the thing *right*?" (small, fast, internal.)
- **Acceptance tests:** "Did we build the *right thing*, and does it actually
  work together?" (broad, behaviour-focused, external.)

You need both. Acceptance tests catch the bugs that only appear when the pieces
meet; unit tests catch the fiddly edges and pin down invariants.

## The test pyramid (memorise this shape)

```
        /\        few   — End-to-end / UI acceptance (slow, brittle, high value per test)
       /  \       some  — Integration / API acceptance (medium)
      /____\      many  — Unit tests (fast, cheap, precise)
```

- Push tests **as low as possible**: test a behaviour at the API or domain level
  if you can, through the browser only when the browser is the point.
- **Anti-pattern: the "ice-cream cone"** — lots of slow UI tests, few unit tests.
  Slow, flaky, expensive. Invert it.

## Acceptance criteria & ATDD

- **Acceptance criteria** — the conditions a feature must meet to be "done",
  agreed with stakeholders (often written Given/When/Then, the BDD overlap).
- **ATDD (Acceptance-Test-Driven Development)** — write the acceptance test
  *first*, from the criteria, then build until it passes.
- **Definition of Done** — criteria met + tests green.

## The four-layer model (the pattern that makes acceptance tests last)

From *Growing Object-Oriented Software, Guided by Tests* — the single most useful
structure for automated acceptance tests:

```
1. Test / Specification   what the system does — no HTTP, no SQL, no selectors
2. DSL                    business vocabulary, test-data isolation, waiting
3. Protocol driver        how you reach the system (domain call / HTTP / browser)
4. System under test      the real application
```

Decoupling **what** you test (layer 1) from **how** you reach it (layer 3) is
what lets one specification run against many entry points, and what keeps tests
from shattering every time the UI changes.

## The three hard problems of automated acceptance tests

1. **Test-data isolation** — runs must not see each other's data (so they can run
   in parallel and against shared environments). Tag data with a unique suffix
   per run.
2. **Determinism** — control anything that varies: **freeze time** (inject a
   clock), seed randomness, avoid real network where possible. Flaky = worthless.
3. **Synchronisation** — for anything async (a browser, a queue), **wait for the
   expected outcome**, don't `sleep`. Retry the observation until it's true or a
   budget runs out. (See [`04-browser-synchronisation.md`](04-browser-synchronisation.md).)

Most flakiness comes from getting these three wrong.

## Must-know vocabulary

| Term | Plain meaning |
|---|---|
| **E2E (end-to-end)** | Exercises the whole stack, usually through the UI. |
| **Functional test** | Tests behaviour/requirements (≈ acceptance); the opposite of testing internals. |
| **Black-box / white-box** | Testing via behaviour vs via internal structure. Acceptance is black-box. |
| **Smoke test** | A quick "is it even alive?" check. |
| **Regression test** | Guards a fixed bug from coming back. |
| **Executable specification** | An acceptance test that *is* the spec (BDD). |
| **Protocol driver** | The adapter that translates test intent into a real request. |
| **Flakiness** | A test that passes/fails without code changing. The trust-killer. |
| **Contract test** | Verifies an implementation honours an interface (e.g. every repository). |

## Tools

- **Browser:** Playwright, Cypress, Selenium/WebDriver.
- **API-level:** REST clients, in-process test clients (Flask test client,
  `Network.Wai.Test`), Postman/newman.
- **BDD-style runners:** Cucumber, behave, pytest-bdd, SpecFlow.
- **Test runners / assertions:** pytest, JUnit, hspec, etc.

Rule of thumb: **API/domain-level acceptance is faster and far more stable than
UI**; use the UI layer for what only the UI can prove.

## Anti-patterns

- **Flaky tests** from `sleep`-based waits or shared state. Fix the cause; never
  "just re-run".
- **Ice-cream cone** — too many slow E2E tests.
- **Testing through the UI** what you could test at the API/domain.
- **Asserting implementation details** (ids, DOM structure, status codes) in a
  spec that's supposed to describe behaviour — put those in the driver/unit tests.
- **Duplicating unit coverage** in acceptance tests (slow and redundant).

## Common misconceptions

- Acceptance tests are **not only UI/E2E tests** — they can (and should) often run
  at the domain or API level.
- They **don't replace unit tests** — different jobs (right thing vs thing right).
- "Acceptance" is about **agreed behaviour**, not any particular tool.

## In this repo — the whole idea, demonstrated

This project *is* a worked example of the four-layer model:

- **Layer 1 (spec):** `test_todo_specification.py` — 15 behaviours, no protocol
  mentioned.
- **Layer 2 (DSL):** `dsl.py` — vocabulary, the per-run suffix (**isolation**), a
  frozen clock (**determinism**), and `_eventually` retry (**synchronisation**).
- **Layer 3 (drivers):** `drivers/` — one per way in: **domain** (microseconds),
  **HTTP** (milliseconds, in-process), **browser** (seconds).
- **Layer 4:** the same `create_app` used in production.

The *same specification* runs against all three drivers (`SPEC_LAYERS` chooses
which). Underneath sits the rest of the pyramid: **unit tests**
(`tests/unit/`) for invariants and edges, and a **contract test**
(`tests/contract/`) run against every repository implementation. The Haskell port
reproduces all of it. See [`bdd.md`](bdd.md) (where the behaviours come from) and
[`ddd.md`](ddd.md) (where the rules they check actually live).

## 30-second summary

Test that the software does the **agreed behaviour**, from the outside. Keep the
**pyramid**: many unit, some integration, few E2E — never the ice-cream cone.
Structure automated acceptance tests in **four layers** (spec → DSL → driver →
system) so one specification can run at many levels and survive UI churn. Win the
three hard problems — **isolation, determinism, synchronisation** — or your suite
becomes flaky and ignored. Test as low in the stack as the behaviour allows.
