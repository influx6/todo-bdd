# todo-bdd — Haskell

A faithful port of the Python [`todo-bdd`](../python/) project to a completely
different stack — GHC, Scotty, blaze, hspec, W3C WebDriver — demonstrating the
same single idea:

> You do not write a separate executable specification for the unit, integration
> and UI layers. You write **one** specification and swap what it drives.

The fifteen behaviours in `test/acceptance/Acceptance/Specification.hs` mention
no HTTP, no SQL, no selectors and no ids. They run unchanged against the domain
service, against the JSON API, and against a real browser.

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

That the *same* design ports to Haskell without changing its shape is the point:
the specification, the DSL, the driver interface and the layering are identical
in structure to the Python version. What changes is only what each layer is made
of. This README explains the architecture, the singular-specification mechanism,
the testing layers, and — most usefully — the decisions taken when translating
each Python idiom into Haskell.

---

## 1. The architecture: rules in one place, everything else at the edges

Ports-and-adapters (hexagonal) with a DDD split, exactly as in Python.

```
src/Todo/
  Domain/
    Model.hs      Todo entity, completed/reopened, cleanTitle, RuleViolation
    Ports.hs      TodoRepository, Clock  (records of IO actions)
  Service.hs      the application service — the real system under test
  Adapters/
    MemoryRepo.hs   IORef (Map Text Todo), fast and disposable
    SqliteRepo.hs   sqlite-simple, production persistence
  Web.hs          Scotty routes (JSON API + HTML), blaze template, cookie flash
app/Main.hs       production entrypoint: SQLite on disk, system clock, :5000
```

**Domain (`Model.hs`).** Pure rules. `Todo` is an immutable record; `completed`
and `reopened` return `Either RuleViolation Todo`; `cleanTitle` normalises and
validates. No IO, no web, no SQL.

**Ports (`Ports.hs`).** `TodoRepository` and `Clock`, the interfaces the
application depends on but does not implement. The service is handed one and
never learns whether it is an in-memory map or SQLite, a frozen clock or the wall
clock — dependency inversion, the core owning the interface.

**Application service (`Service.hs`).** *The real system under test.* Every rule
lives here once: uniqueness, completion, reopening, deletion, and list ordering
(outstanding oldest-first, then done newest-first). The fastest driver talks
straight to it and is still exercising the same system as the browser.

**Adapters.** Two `TodoRepository` implementations, both held to one contract
test. The in-memory one lives in `src/`, not the test tree — a real
implementation that happens to be fast.

**Delivery (`Web.hs`).** JSON and HTML over the same service, each thin: parse,
delegate, serialise. `createApp` is the composition root — it *takes* a
repository and clock, so a test starts the identical app with an in-memory repo
and a frozen clock, and production starts it with SQLite and the wall clock, with
no test-only branches.

### Haskell translation decisions (architecture)

- **Ports are records of `IO` actions**, the idiomatic Haskell stand-in for
  Python's `Protocol`. `TodoRepository { repoAdd :: Todo -> IO (), … }` is a
  first-class value you build once and pass around — swappable at the composition
  root without a typeclass.
- **Rule failures are `Either` in the domain, exceptions at the IO boundary.**
  The pure model returns `Either RuleViolation`, keeping it total and testable.
  The service turns a `Left` into `throwIO` (`orThrow`), and the delivery layer
  catches it with `try` — the same raise/catch control flow Flask used, so the
  drivers map one-to-one. `RuleViolation` derives `Exception` and carries one
  user-facing message per rule.
- **Web = Scotty + blaze-html + aeson.** Scotty is the thin-delivery analogue of
  Flask; blaze reproduces the template attribute-for-attribute
  (`data-testid`, `data-title`, `data-done`, form `action="/todos/<id>"`) so the
  browser driver's selectors and its read-token-from-`action` trick port
  directly.
- **Flash message via a `flash` cookie.** Flask carried the message across the
  Post/Redirect/Get in a server session; the faithful, multi-user-safe Haskell
  equivalent is a URL-encoded cookie set on failure and cleared on the next GET.
- **Time is a mutable `IORef` behind the `Clock` port.** `newFrozenClock` returns
  a `Clock` plus `advanceClock`/`setClock`; the DSL advances it.

---

## 2. The singular specification: how one file drives three protocols

The specification reads in a business vocabulary:

```haskell
it "finishing something frees its title to be used again" $ \dsl -> do
  mondaysMilk <- aTodoIsAdded dsl "Buy milk"
  theTodoIsCompleted dsl mondaysMilk
  thursdaysMilk <- aTodoIsAdded dsl "Buy milk"
  noMessageIsShown dsl
  theListReads dsl [open thursdaysMilk, done mondaysMilk]
```

Three pieces keep it protocol-free.

### The DSL (`Acceptance/Dsl.hs`)

The vocabulary, with four jobs and no logic:

1. **Business language** — `aTodoIsAdded`, not `postJson`.
2. **Named references** — `aTodoIsAdded` returns a `TodoRef` the spec names
   (`mondaysMilk`); the DSL keeps the mapping from that name to the opaque token
   a driver issued, in an `IORef [(Token, TodoRef)]`.
3. **Test-data isolation** — the spec says "Buy milk", the system sees
   "Buy milk [7f3a]" (a random suffix), so runs cannot collide. The suffix never
   distinguishes two deliberately-identical titles — that is the token's job.
4. **Synchronisation** — every observation retries until it matches or a timeout
   elapses (`eventually`, polling every 50 ms).

Expected list lines are built with `open :: TodoRef -> Entry` and
`done :: TodoRef -> Entry`, so `theListReads dsl [open dentist, done milk]` reads
close to the Python `the_list_reads(dentist, done(milk))`.

### The driver interface (`Acceptance/Drivers.hs`)

A record of six `IO` actions — `drvAdd`, `drvComplete`, `drvReopen`, `drvDelete`,
`drvVisibleTodos`, `drvLastMessage`. The spec never learns which one it holds.
Tokens are opaque: the domain and HTTP drivers use the todo's id; the browser
reads it from the form `action` already in the markup. That is what lets two
todos share a title without the tests going blind.

### The layered runner (`test/acceptance/Main.hs`)

Where Python used a parametrised pytest fixture, Haskell uses hspec's `around`
combinators. `todoSpecification :: SpecWith Dsl` is written once; the runner
wraps it per layer and `SPEC_LAYERS` (default all) selects which run:

```haskell
when ("domain" `elem` layers) $ describe "[domain]" $ around withDomainDsl todoSpecification
when ("http"   `elem` layers) $ describe "[http]"   $ around withHttpDsl   todoSpecification
when ("ui"     `elem` layers) $ describe "[ui]"     $
  aroundAll (withBrowserSession headed slowmo) $ aroundWith withUiDsl todoSpecification
```

- `around` supplies a fresh `Dsl` (fresh repo + frozen clock) per test.
- `aroundAll` starts chromedriver and one browser session once for the whole UI
  block; `aroundWith` then gives each test its own live server + app + `Dsl` over
  that shared browser. The UI layer runs the *same* `createApp` as production.

---

## 3. Consistent testing: three costs, plus a pyramid under it

| driver  | goes through                          | cost      | run it… |
|---------|---------------------------------------|-----------|---------|
| domain  | the service, in-process               | microseconds | on every keystroke |
| http    | the WAI app via `Network.Wai.Test` (no socket) | milliseconds | on every commit |
| browser | `webdriver` (W3C) against a live Warp server | seconds | before deploy |

Underneath, two more kinds of test the acceptance spec does not duplicate:

- **Unit tests** (`test/spec/Todo/ServiceSpec.hs`) — how the unit behaves,
  including edges (ids, exception types, the clock).
- **The repository contract** (`test/spec/Todo/RepositoryContractSpec.hs`) — one
  contract, run against both the in-memory and SQLite repositories. This earns
  the right to use the fast fake everywhere else.

The division of labour is the same one the Python project documents, including
the reopen bug (checking a title clash before checking the todo was finished) —
ported deliberately with the fix in place (`Service.reopenTodo`) and held by a
unit test the specification could never have written.

### Haskell translation decisions (testing)

- **`Network.Wai.Test` for the HTTP tier.** `runSession`/`srequest` drive the
  real `Application` in-process with no socket — the exact counterpart of Flask's
  test client, preserving the "milliseconds, no socket" property. Point it at a
  live base URL instead and the same spec would test a deployed environment.
- **`webdriver` 0.15 speaks W3C straight to chromedriver** — no Selenium server;
  the library launches and reaps chromedriver itself
  (`DriverConfigChromedriver`). Chrome runs headless by default; `HEADED=1` shows
  it and `SLOWMO=<ms>` pauses after each action.
- **`navClick` is the navigation wait.** Every action is a form POST → full-page
  reload. The WebDriver `click` returns *before* that navigation finishes, so the
  driver captures the current `<body>` element, clicks, and waits for it to go
  stale — the WebDriver equivalent of Playwright's `expect_navigation`. Without
  it, the next observation races the reload (this was the whole cause of the
  first, failing, run). The full discussion — WebDriver vs CDP vs BiDi, why not
  BiDi here, and `pageLoadStrategy` as an alternative — is in
  [`../docs/04-browser-synchronisation.md`](../docs/04-browser-synchronisation.md).
- **Test failures abort via HUnit's `assertFailure`** (`String -> IO a`), so DSL
  bookkeeping (`remember`, `tokenFor`) can fail a test and still be used where a
  value is expected.
- **Logging is silenced.** `webdriver` runs in `LoggingT IO`; `silent` discards
  its (verbose) output so test results stay readable.

---

## 4. How this simplifies things

- **One specification instead of three.** A change of intent is one edit; a
  divergence between layers becomes impossible to express.
- **Adding a way in is one file** — write another `TodoDriver` and change no
  tests.
- **Swapping the frontend is one file** — only `Acceptance/Drivers/Ui.hs` knows
  about selectors and page loads.
- **The rules cannot drift** — delivery is thin, every rule is in the service, so
  the domain and HTTP drivers provably exercise the same behaviour.

---

## 5. Running it

Needs GHC 9.10 + cabal (via ghcup). The browser layer needs `chromedriver` and
`chromium` on the system — here a matched 152 pair at `/bin/chromedriver` and
`/bin/chromium`.

```bash
cabal build all

cabal test spec                               # 46 unit + contract, ~4ms

SPEC_LAYERS=domain      cabal test acceptance # inner loop, microseconds
SPEC_LAYERS=domain,http cabal test acceptance # every commit
cabal test acceptance                         # all three, browser included

HEADED=1 SLOWMO=450 SPEC_LAYERS=ui cabal test acceptance   # watch the browser

cabal run todo-hs                             # the app on :5000, SQLite on disk
```

`SPEC_LAYERS` selects which drivers the one specification runs against (default:
all). If chromedriver/chromium are absent, run only `SPEC_LAYERS=domain,http`.

**Status:** 46 unit and contract examples, and the 15 specifications across all
three drivers — 45 acceptance runs, 91 in total; the two in-process layers in
milliseconds, the full suite in about three seconds.

---

## 6. File map

| File | Role |
|------|------|
| `src/Todo/Domain/Model.hs`   | entity + rules (pure) |
| `src/Todo/Domain/Ports.hs`   | repository + clock interfaces |
| `src/Todo/Service.hs`        | the application service |
| `src/Todo/Adapters/*.hs`     | in-memory + SQLite repositories |
| `src/Todo/Web.hs`            | Scotty routes, blaze template, cookie flash |
| `test/spec/…`                | unit tests + repository contract |
| `test/acceptance/Acceptance/Specification.hs` | the 15 behaviours, protocol-free |
| `test/acceptance/Acceptance/Dsl.hs`           | vocabulary, references, isolation, retry |
| `test/acceptance/Acceptance/Drivers/*.hs`     | domain / http / ui drivers |
| `test/acceptance/Main.hs`    | the layered runner (`SPEC_LAYERS`) |

See `../docs/` for the longer design essays and `../python/` for the original.
