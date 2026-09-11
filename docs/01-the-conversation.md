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
