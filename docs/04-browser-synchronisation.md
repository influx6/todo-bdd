# Browser synchronisation: navigation waits, protocols, and why

A discussion doc, kept for future reference. It grew out of building the Haskell
port's browser driver, where the first run failed in a way the Python/Playwright
version never visibly did — and the reasons turn out to be a good tour of how
browser automation actually synchronises with a page.

This is cross-cutting: it applies to both `python/` (Playwright) and `haskell/`
(W3C WebDriver → chromedriver), and it expands on open-question #2 in
[`03-open-questions.md`](03-open-questions.md).

---

## 1. The problem, concretely

Every action in this app is a form POST that does Post/Redirect/Get: submitting
"Add" (or complete/reopen/delete) throws away the current page and loads a fresh
one. A browser driver that clicks and then *immediately* reads the DOM is racing
that reload.

The Haskell driver hit this on its first run. Symptoms:

- **"The system refused to add 'Buy milk'."** `drvAdd` computes the new token by
  diffing the visible row-tokens before and after the click. The new page had not
  rendered yet, so the "after" read saw no new row, the diff was empty, and `add`
  returned `Nothing` — reported by the DSL as a refusal. (The server *had*
  created the todo; the browser just had not shown it.)
- **`StaleElementReference`.** In multi-step tests, a still-in-flight reload from
  the *previous* click meant the next `findElems` grabbed elements that were
  destroyed mid-reload.

A few tests passed anyway — the ones that don't depend on a successful add
showing up immediately ("a todo must have a title", "a title too long", which
assert a flash message and no row) — plus the very first add, which won the race
once. Nothing reliable.

---

## 2. Why the two stacks behaved differently

### Playwright (Python) rarely shows this

Playwright is robust here for two reasons, and the design matters more than the
protocol:

- **Protocol:** for Chromium it speaks **CDP (Chrome DevTools Protocol)** — a
  bidirectional, event-driven WebSocket. Chromium streams lifecycle events
  (frame navigated, DOMContentLoaded, load, network activity) in real time, so
  the client always knows where the page is without polling.
- **Client design (the bigger reason):** locators are **lazy queries**
  re-resolved on every use (so there is no stale-handle class of bug), and every
  action has built-in **actionability + auto-wait**. `expect_navigation()` and
  web-first assertions like `expect(locator).to_be_visible()` just expose that
  machinery.

### Classic W3C WebDriver (Haskell) does not, by default

WebDriver is a **stateless request/response HTTP protocol**. There is no event
stream: the client cannot be *notified* that a navigation finished. It can only

1. rely on the **server** (chromedriver) to block a command until the page-load
   strategy is satisfied, or
2. **poll** for a condition.

Element references are **stateful handles** to specific DOM nodes; once the page
reloads, the node is gone → `StaleElementReference`.

The W3C spec *does* say "Element Click", when it triggers a navigation, should
wait for that navigation (bounded by the page-load timeout, per
`pageLoadStrategy`). Classic Selenium relied on exactly this with the default
`normal` strategy, so form submits "just worked". In practice the Haskell
`webdriver 0.15` client's `click` returned before the new document was ready —
whether because of the strategy it negotiates or how it issues the click, the
server-side wait was not something to lean on.

---

## 3. The fix: `navClick`, and where retries belong

Two layers of synchronisation, and it matters which layer owns which:

- **Observation retries live in the DSL, once, for all three drivers.** The
  DSL's `_eventually` (Python) / `eventually` (Haskell) re-reads an observation
  until it matches or a budget elapses. This *is* the "web-first assertion"
  pattern (`expect(locator).to_be_visible()`), but factored into the
  protocol-agnostic layer so the domain and HTTP drivers get it too. A driver
  holds no assertions — it only acts and reports — so the retry cannot live in
  the browser driver without being re-implemented three times.

- **The navigation wait is action-level and lives in the driver**, because the
  DSL retries *observations*, not *actions*: a stale element mid-action happens
  before any observation runs. In Haskell this is `navClick`:

  ```haskell
  navClick control = do
    anchor <- findElem (ByCSS "body")   -- capture the current page
    click control
    awaitStale anchor                    -- poll until it is gone => new page loaded
  ```

  That is the WebDriver equivalent of Playwright's `expect_navigation()`. In the
  Python driver the same role is played by `with page.expect_navigation():`.

---

## 4. Playwright's `waitUntil` options — do they apply here?

A common suggestion is to use Playwright's navigation `waitUntil` variants
(`load`, `domcontentloaded`, `networkidle`) or `page.reload({waitUntil})`. Two
reasons they mostly don't apply to *this* app:

1. **It is not an SPA.** The pages are server-rendered with **zero client-side
   JavaScript**. There is no background fetching and no post-load JS, so
   `networkidle` and `domcontentloaded` distinctions are moot — the only
   meaningful state is `load`, i.e. "the navigation finished".
2. **We never call `reload()`.** Navigation is triggered by submitting a form,
   so the relevant tool is a wait on the click's navigation (or an auto-retrying
   assertion afterward), not the `reload()` variants.

So the recommended modern pattern — auto-retrying web-first assertions — is
already what the design uses, spelled `eventually` in the DSL. `expect_navigation`
is belt-and-suspenders on top and is now deprecated in Playwright; it could be
dropped in favour of auto-wait plus the DSL retry.

`networkidle`/DOM-mutation waits would become the *only* clean option if this
were a real SPA — that is the case where staleness-polling breaks down (there is
no full navigation to detect).

---

## 5. WebDriver equivalents of the Playwright knobs

| Playwright | WebDriver equivalent | Where it lives |
|---|---|---|
| `waitUntil: 'load' / 'domcontentloaded' / 'commit'` | `pageLoadStrategy` = `normal` / `eager` / `none` | set once at session creation, enforced server-side by chromedriver |
| `expect(locator).toBeVisible()` (auto-retry) | `Test.WebDriver.Waits.waitUntil` — poll a condition you write | manual, per call |
| per-action actionability auto-wait | *(none — WebDriver has no equivalent)* | — |

Note `pageLoadStrategy=normal` is the closest native analogue of
`waitUntil:'load'` and is arguably a cleaner fix than `navClick`: with it,
chromedriver is supposed to block the click until `document.readyState` is
`complete`. `navClick` was chosen because it is protocol-agnostic and verified to
work, rather than depending on how a specific library negotiates the strategy.
**Follow-up worth trying:** set the strategy explicitly and see whether
`navClick` can shrink to nothing.

---

## 6. Why not WebDriver BiDi in Haskell?

**BiDi** (Bidirectional WebDriver) is the new event-driven extension to the
WebDriver standard — CDP-style events over a WebSocket, but vendor-neutral. It is
the *conceptually* right fix: subscribe to `browsingContext.load` and `await` the
navigation instead of polling for staleness. `webdriver 0.15` already ships
partial BiDi modules, and its `Session` type carries a `sessionWebSocketUrl`.

It was not used here, deliberately:

1. **BiDi is an *addition*, not a drop-in.** Its strength is the event stream and
   low-level control; it does not replace the ergonomic element commands. You
   still use classic `findElem`/`click`/`sendKeys`/`attr` for interactions and
   layer BiDi on top *just for navigation events* — a hybrid with more moving
   parts, not fewer.
2. **The library's BiDi support is nascent.** The classic W3C path is mature and
   rock-solid against chromedriver 152; BiDi is sparsely exercised. Building on
   the proven API and patching one known gap is safer than building on the new
   one and discovering its gaps mid-build.
3. **The problem is tiny and already solved.** `navClick` is ~8 lines. BiDi means
   managing a second (WebSocket) connection, subscribing to events, and driving
   an async event loop — a lot of surface to replace a working helper on a
   static, no-JS app.
4. **Faithfulness.** The exercise was to prove the *architecture* ports, with the
   browser driver as a thin translator — not to turn a supporting detail into a
   protocol research project.

**When BiDi *would* be worth it:** a real SPA with background fetches and
client-side routing, where there is no full navigation to detect and
`network.responseCompleted` / DOM-mutation events are the only clean way to know
the app has settled. That is also where you would reasonably just use Playwright.

---

## 7. Takeaways

- Put **observation retries in the DSL** (once, all drivers); put the
  **navigation wait in the driver** (protocol-specific).
- Playwright's robustness is mostly its **auto-waiting + lazy-locator design**,
  which CDP's event stream makes precise and cheap — not the protocol alone.
- Classic WebDriver can reach the same reliability via `pageLoadStrategy`
  (server-side) or explicit waits (client-side); this library needed one explicit
  `navClick` where Playwright needs nothing.
- **BiDi** is the ecosystem's long-term convergence on the event-driven model.
  Adopt it when the app is dynamic enough that polling stops being adequate.
