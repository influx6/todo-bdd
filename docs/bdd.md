# BDD — Behaviour-Driven Development (the whole thing, condensed)

## Like you're 10

Before you build a toy, you and your friend agree on exactly what it should do,
using little stories: *"When I press the red button, the light turns on."* You
write those stories down. Then you build the toy so every story comes true — and
you keep the stories as a checklist you can run again and again.

That's BDD: **agree on concrete examples of what the software should do, in plain
language, before you build it — then turn those examples into automated checks.**

## The one idea

Vague requirements ("users can manage todos") cause arguments and bugs. Concrete
**examples** ("when I add 'Buy milk', it appears on my list; adding it twice is
refused") don't. BDD makes examples the unit of work: they drive the
conversation, the code, and the tests — all at once.

BDD is **TDD with the focus moved to conversation and behaviour**. TDD asks "did
I build the thing right?" BDD asks "are we building the right thing, and can we
all describe it the same way?"

## The three practices (this is the actual method)

1. **Discovery** — *talk.* Business + developer + tester (the "**three amigos**")
   work through real examples together, hunting edge cases. Most of BDD's value
   is here, before any code. A common technique is **Example Mapping** (cards:
   rules, examples, questions).
2. **Formulation** — *write the examples down* in a structured, readable form
   everyone agrees on (Gherkin, or a plain-language DSL).
3. **Automation** — *wire the examples to the system* so they run as tests and
   become **living documentation** (docs that can't lie, because they execute).

## Given / When / Then (and Gherkin)

Examples get a standard shape:

```
Given  some starting context
When   something happens
Then   this is the observable outcome
```

**Gherkin** is the plain-text format (`.feature` files) that uses those keywords.
It is *optional*. Gherkin is a tool, not BDD itself — you can do BDD with a plain
test framework and good method names (this repo does exactly that).

## Must-know vocabulary

| Term | Plain meaning |
|---|---|
| **Ubiquitous language** | One shared vocabulary used in conversation, code, and tests. |
| **Scenario** | One concrete example (one Given/When/Then). |
| **Feature** | A group of related scenarios. |
| **Step definition** | The glue code that makes a Gherkin step actually do something. |
| **Three amigos** | Business, dev, tester reviewing examples together. |
| **Example mapping** | A quick workshop to surface rules, examples, and open questions. |
| **Specification by Example** | Another name for the whole approach. |
| **Living documentation** | Executable examples that describe the system and stay true. |
| **Outside-in** | Start from user-visible behaviour, work inward to code. |

## Tools (know they exist; don't confuse them with BDD)

- **Cucumber** (Ruby/JVM/JS), **SpecFlow** (.NET), **behave** / **pytest-bdd**
  (Python) — run Gherkin.
- **Plain xUnit + a DSL** — BDD with no Gherkin at all (like `python/` and
  `haskell/` here).

## Anti-patterns (how BDD goes wrong)

- **"BDD = Cucumber."** No. BDD is the *practice of examples and conversation*;
  Gherkin/Cucumber is one way to write them down.
- **Gherkin written after coding**, by developers only, as brittle test scripts
  nobody in the business ever reads. That's the most common failure.
- **Imperative scenarios** full of UI mechanics ("click #add-btn, type…") instead
  of behaviour ("a todo is added"). Keep steps at the *behaviour* altitude.
- **Testing implementation** instead of observable outcomes.
- **Skipping the conversation** — automating examples nobody discussed defeats the
  point.

## Common misconceptions

- BDD is **not a testing tool** — it's a collaboration practice that *happens to*
  produce automated tests.
- BDD is **not "just automated acceptance tests"** — the discovery conversation is
  where most bugs die.
- You **don't need Gherkin** to do BDD.

## In this repo

`../python/tests/acceptance/test_todo_specification.py` (and the Haskell twin) is
BDD without Gherkin: fifteen behaviours in a business vocabulary
(`a_todo_is_added`, `the_list_reads`, `done(...)`), agreed as examples, run as
tests, readable as documentation. The vocabulary lives in a **DSL**
(`dsl.py`) — the "formulation" layer — and the behaviours never mention HTTP or
SQL. See [`acceptance-testing.md`](acceptance-testing.md) for how those same
examples are automated, and [`ddd.md`](ddd.md) for where the rules they describe
actually live.

## 30-second summary

Talk through concrete examples with the people who care, in one shared language,
*before* building. Write the examples down (Given/When/Then). Automate them so
they double as tests and living docs. The examples describe **behaviour**, never
implementation. Gherkin is optional; the conversation is not.
