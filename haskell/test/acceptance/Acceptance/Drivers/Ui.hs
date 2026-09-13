-- | Driver that goes through a real browser. Seconds per test.
--
-- Everything the browser knows about the application is confined to this file:
-- selectors, form submission, page loads. Rebuild the frontend tomorrow and this
-- is the only file that changes; not one line of the specification moves.
--
-- Its token comes from each row's form @action@ (@/todos/<id>@), which is in the
-- markup already for the page to work — no test-only attribute was added.
--
-- Uses @webdriver@'s standalone-chromedriver launcher (no Selenium server); the
-- library spawns and reaps chromedriver itself.
module Acceptance.Drivers.Ui
  ( BrowserSession
  , withBrowserSession
  , newUiDriver
  ) where

import Control.Monad (filterM, forM, when)
import Control.Monad.Catch (bracket, catch)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Logger (LoggingT, runLoggingT)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import UnliftIO.Concurrent (threadDelay)

import Test.WebDriver
import Test.WebDriver.Capabilities (ChromeOptions (..))
import Test.WebDriver.WD (WD, runWD)

import Acceptance.Drivers

data BrowserSession = BrowserSession
  { bsSession :: Session
  , bsSlowmo  :: Int  -- microseconds to pause after each action, for watching
  }

-- | Discard webdriver's (verbose) logging.
silent :: LoggingT IO a -> IO a
silent m = runLoggingT m (\_ _ _ _ -> pure ())

-- | Start chromedriver + one browser session, hand it to the tests, tear both
-- down afterwards. Shape fits hspec's 'aroundAll'.
withBrowserSession :: Bool -> Int -> (BrowserSession -> IO ()) -> IO ()
withBrowserSession headed slowmoUs use = silent $
  bracket mkEmptyWebDriverContext teardownWebDriverContext $ \wdc -> do
    sess <- startSession wdc driverConfig (caps headed) "todo-bdd"
    liftIO (use (BrowserSession sess slowmoUs))
  where
    driverConfig = DriverConfigChromedriver
      { driverConfigChromedriver         = "/bin/chromedriver"
      , driverConfigChromedriverFlags    = []
      , driverConfigChromedriverExtraEnv = Nothing
      , driverConfigChrome               = "/bin/chromium"
      , driverConfigLogDir               = Nothing
      }

caps :: Bool -> Capabilities
caps headed = defaultCaps
  { _capabilitiesGoogChromeOptions = Just defaultChromeOptions
      { _chromeOptionsBinary = Just "/bin/chromium"
      , _chromeOptionsArgs   = Just (baseArgs ++ [ "--headless=new" | not headed ])
      }
  }
  where
    baseArgs =
      [ "--no-sandbox"
      , "--disable-dev-shm-usage"
      , "--disable-gpu"
      , "--window-size=1000,820"
      ]

newUiDriver :: BrowserSession -> Text -> IO TodoDriver
newUiDriver (BrowserSession sess slowmo) baseUrl = do
  let runAction :: WD a -> IO a
      runAction action =
        silent (runWD sess (action <* when (slowmo > 0) (threadDelay slowmo)))

  runAction (openPage (T.unpack baseUrl))

  pure TodoDriver
    { drvAdd = \title -> runAction $ do
        before <- currentTokens
        field  <- findElem (ByCSS "[data-testid=\"new-todo\"]")
        clearInput field
        sendKeys title field
        submitClick "[data-testid=\"add\"]"
        after <- currentTokens
        pure (listToMaybe (filter (`notElem` before) after))

    , drvComplete = \tok -> runAction (clickInRow tok "complete")
    , drvReopen   = \tok -> runAction (clickInRow tok "reopen")
    , drvDelete   = \tok -> runAction (clickInRow tok "delete")

    , drvVisibleTodos = runAction $ do
        rows <- findElems (ByCSS "[data-testid=\"todo\"]")
        forM rows $ \row -> do
          tok      <- tokenOf row
          title    <- attrOr "" row "data-title"
          doneAttr <- attr row "data-done"
          pure (TodoRow tok title (doneAttr == Just "true"))

    , drvLastMessage = runAction $ do
        banners <- findElems (ByCSS "[data-testid=\"message\"]")
        case banners of
          (b : _) -> Just . T.strip <$> getText b
          []      -> pure Nothing
    }

-- | Every action is a form post, so every action is a navigation. The client's
-- @click@ returns before the new page has loaded, so we capture the current page
-- and wait for it to go stale — the WebDriver equivalent of Playwright's
-- @expect_navigation@. Without it, the next observation races the reload.
navClick :: Element -> WD ()
navClick control = do
  anchor <- findElem (ByCSS "body")
  click control
  awaitStale anchor

awaitStale :: Element -> WD ()
awaitStale el = go (250 :: Int)  -- up to ~5s
  where
    go 0 = pure ()
    go n = do
      alive <- (True <$ getText el) `catch` \(_ :: FailedCommand) -> pure False
      if alive then threadDelay 20000 >> go (n - 1) else pure ()

submitClick :: Text -> WD ()
submitClick selector = findElem (ByCSS selector) >>= navClick

clickInRow :: Token -> Text -> WD ()
clickInRow tok testid = do
  rows  <- findElems (ByCSS "[data-testid=\"todo\"]")
  match <- filterM (fmap (== tok) . tokenOf) rows
  case match of
    (row : _) -> findElemFrom row (ByCSS ("[data-testid=\"" <> testid <> "\"]")) >>= navClick
    []        -> pure ()

currentTokens :: WD [Token]
currentTokens = findElems (ByCSS "[data-testid=\"todo\"]") >>= mapM tokenOf

tokenOf :: Element -> WD Token
tokenOf row = do
  form   <- findElemFrom row (ByCSS "form")
  action <- attrOr "" form "action"
  pure (lastSegment action)

lastSegment :: Text -> Token
lastSegment = last' . T.splitOn "/" . T.dropWhileEnd (== '/')
  where
    last' [] = ""
    last' xs = last xs

attrOr :: Text -> Element -> Text -> WD Text
attrOr def el name = maybe def id <$> attr el name
