# DDD — Domain-Driven Design (the whole thing, condensed)

## Like you're 10

If you're building a game about running a lemonade stand, your code should be full
of words like *lemonade*, *cup*, *price*, and *customer* — the words a real
lemonade-seller uses — not words like *table7* and *rowFactory*. And the
important rules ("you can't sell a cup for less than it costs to make") should
live in one obvious place, not be scattered everywhere.

That's DDD: **design your software around the real-world thing it's about (the
"domain"), speak the experts' language in the code, and keep the important rules
in one clean, protected place.**

## The one idea

Software gets messy when the code doesn't match how the business actually thinks.
DDD says: build a **model** of the business, in code, that a domain expert would
recognise — and organise everything else around protecting that model.

DDD has **two halves**. Most teams only need the first well.

## Half 1 — Strategic DDD (how to split a big system)

- **Domain** — the problem you're solving (todos, orders, shipping).
- **Ubiquitous language** — one shared vocabulary used in talk *and* code. If the
  expert says "reopen a todo", the method is `reopen`, not `setStatusActive`.
- **Bounded context** — a boundary inside which each word means exactly one thing.
  "Customer" in *Sales* is not "Customer" in *Support*. Don't force one giant
  model across the whole company; draw boundaries and let each context have its
  own model.
- **Context map** — how those contexts talk to each other.
- **Subdomains** — **core** (your competitive edge, invest here), **supporting**
  (needed but not special), **generic** (buy/borrow it, e.g. auth).
- **Anti-corruption layer (ACL)** — a translator at a boundary so another system's
  messy model doesn't leak into yours.

## Half 2 — Tactical DDD (the building blocks inside one context)

| Block | Plain meaning | Example |
|---|---|---|
| **Entity** | Has an identity that persists over time; two with the same fields are still different. | A `Todo` with an id. |
| **Value object** | Defined purely by its values, no identity, **immutable**. | A `Title`, a `Money`. |
| **Aggregate** | A cluster of objects treated as one unit for changes, with an **aggregate root** as the only entry point that enforces the rules. | An `Order` and its `LineItems`. |
| **Repository** | A pretend in-memory collection for loading/saving aggregates; hides the database. | `TodoRepository`. |
| **Domain service** | A rule that doesn't naturally belong to any single entity. | "transfer money between accounts". |
| **Application service** | Thin orchestration of a use case; no business rules of its own. | `TodoService.add`. |
| **Domain event** | A record that something meaningful happened. | `TodoCompleted`. |
| **Factory** | Encapsulates tricky creation of an aggregate. | — |

**Layering / hexagonal (ports & adapters)** ties it together: keep the domain
**pure** (no framework, no SQL, no HTTP), define **ports** (interfaces) it needs,
and push all technology to **adapters** at the edges. A **composition root** wires
real adapters in for production and fakes in for tests.

## The method (how you actually do it)

1. Learn and capture the **language** with domain experts (examples help — this is
   where BDD and DDD meet).
2. Find the **bounded contexts**; don't over-share models.
3. Model the core domain with entities/value objects/aggregates.
4. Put **every business rule in the domain/application layer**, once.
5. Depend on **ports**; implement infrastructure as **adapters**.
6. Keep delivery (UI, API) **thin** — parse, delegate, serialise.

## Tools & techniques (DDD is design, not a library)

- **EventStorming** — a sticky-note workshop to discover the domain and its
  events fast.
- **Context mapping** — diagram the relationships between contexts.
- Pairs naturally with **hexagonal architecture**, and (advanced, often
  unnecessary) **CQRS** and **event sourcing**.

## Anti-patterns (how DDD goes wrong)

- **Anemic domain model** — entities are just data bags and all logic sits in
  services. This is the classic DDD anti-pattern: you get the ceremony, none of
  the benefit.
- **DDD everywhere** — full tactical patterns on a simple CRUD app. Over-
  engineering. Use the language and clean boundaries; skip aggregates you don't
  need.
- **One model to rule them all** — ignoring bounded contexts until the model
  means five contradictory things.
- **Leaking infrastructure** — ORM annotations, HTTP, or SQL bleeding into the
  domain, so the model can no longer be reasoned about alone.

## Common misconceptions

- DDD is **not a framework or tool** — it's how you think about and structure a
  model.
- DDD is **not just layered architecture** — layering is a tactic; the heart is
  the *ubiquitous language* and *bounded contexts*.
- You **don't need every pattern**. The most valuable, cheapest wins are: shared
  language, a rich (non-anemic) domain, and thin edges.

## In this repo

The `../python/src/todo/` tree is textbook tactical DDD kept deliberately small:

- **Entity / value logic** — `domain/model.py`: `Todo` (identity + immutable
  updates), `clean_title` (value validation), `RuleViolation` (one message per
  broken rule).
- **Ports** — `domain/ports.py`: `TodoRepository`, `Clock`.
- **Application service** — `service/todo_service.py`: every rule, once (including
  the list-ordering rule, which lives here, not in the database).
- **Adapters** — `adapters/`: in-memory + SQLite implementations of the port.
- **Composition root** — `web/app.py`'s `create_app`, which takes its
  dependencies so tests and production wire different adapters with no branches.

The Haskell port mirrors this exactly, translating "port" to a record of `IO`
actions. See [`acceptance-testing.md`](acceptance-testing.md) for how the rules in
this model are verified, and [`bdd.md`](bdd.md) for where the language comes from.

## 30-second summary

Model the business in code using the experts' exact words. Split big systems into
**bounded contexts** so words stay unambiguous. Keep rules in a **pure domain**
with **entities**, **value objects**, and **aggregates**; reach the outside world
through **ports and adapters**. Avoid the **anemic model** (logic-less data bags)
and avoid over-applying the patterns to simple apps. Language and boundaries
first; fancy patterns only where they earn their keep.
