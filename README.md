# A todo list, specified once and tested three ways

One idea, demonstrated twice in two very different stacks: **you do not write a
separate executable specification for the unit, integration and UI layers. You
write one specification and swap what it drives.**

Fifteen behaviours are described in a single specification file. That file
mentions no HTTP, no SQL, no selectors and no ids. It runs unchanged against the
domain service, against the JSON API, and against a real browser.

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

The point of having **two** implementations is that the design is what matters,
not the language. The specification, the DSL, the driver interface and the
layering are the same shape in both; only what each layer is *made of* changes.

## Two implementations

| | [`python/`](python/) | [`haskell/`](haskell/) |
|---|---|---|
| Web        | Flask + Jinja                 | Scotty + blaze-html            |
| Ports      | `Protocol`                    | records of `IO` actions        |
| Rule errors| `RuleViolation` exception     | `Either` in the domain, thrown at the IO boundary |
| Flash (PRG)| server session                | a `flash` cookie               |
| HTTP driver| Flask test client (in-process)| `Network.Wai.Test` (in-process)|
| Browser    | Playwright → Chromium         | `webdriver` (W3C) → chromedriver → Chromium |
| Tests      | pytest, parametrised fixtures | hspec `around` / `aroundAll`   |
| Status     | 96 runs green                 | 91 runs green                  |

Both expose the same knobs: `SPEC_LAYERS` chooses which drivers the one
specification runs against, `HEADED=1` shows the browser, `SLOWMO=<ms>` slows it
so you can watch.

### Running the Python version

```bash
cd python
pip install flask pytest playwright && playwright install chromium
export PYTHONPATH=src

pytest tests/unit tests/contract              # 51 unit + contract
SPEC_LAYERS=domain,http pytest tests/acceptance
pytest                                        # all three drivers
HEADED=1 SLOWMO=450 SPEC_LAYERS=ui pytest tests/acceptance

python run.py                                 # the app on :5000
```

### Running the Haskell version

```bash
cd haskell                                    # needs GHC 9.10 + cabal, chromedriver + chromium
cabal build all

cabal test spec                               # 46 unit + contract
SPEC_LAYERS=domain,http cabal test acceptance
cabal test acceptance                         # all three drivers
HEADED=1 SLOWMO=450 SPEC_LAYERS=ui cabal test acceptance

cabal run todo-hs                             # the app on :5000
```

## The design argument

The essays in [`docs/`](docs/) work through where the behaviours came from, how
the specification, DSL and drivers were derived, and the questions left open.
They are written against the Python implementation but describe the design both
share:

1. `docs/01-the-conversation.md` — the behaviours, and plain-language DDD + BDD.
2. `docs/02-the-specification.md` — how the spec, DSL and drivers were derived.
3. `docs/03-open-questions.md` — the arguments not fully settled.
4. `docs/04-browser-synchronisation.md` — navigation waits, WebDriver vs CDP vs
   BiDi, and why the browser driver synchronises the way it does.

## One thing worth knowing

Writing this caught a real bug. The service checked for a title clash before
checking that a todo was actually finished, so an outstanding todo collided with
itself and was told it was "already back on your list". A unit test found it; the
specification never could — you cannot reach that state through any interface.
Both implementations carry the fix, and a unit test in each holds it. That is the
division of labour in one example: the specification covers what was agreed, the
unit tests hold the invariants in the place you decided they belong.
