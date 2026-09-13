-- | Wiring. The specification is parametrised over every way into the system.
--
--     cabal test acceptance                        # all available layers
--     SPEC_LAYERS=domain      cabal test acceptance # inner loop, microseconds
--     SPEC_LAYERS=domain,http cabal test acceptance
--     HEADED=1 SLOWMO=450 SPEC_LAYERS=ui cabal test acceptance   # watch it
--
-- The same application factory is used for every layer. The UI driver does not
-- get a special test build — it gets a real Warp server running the same
-- 'createApp' as production, with an in-memory repository and a frozen clock
-- substituted at the composition root.
module Main (main) where

import Control.Concurrent (forkIO, killThread)
import Control.Exception (finally)
import Control.Monad (when)
import Data.Char (isSpace)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Network.Socket (close)
import qualified Network.Wai.Handler.Warp as Warp
import System.Environment (lookupEnv)
import Test.Hspec

import Todo.Adapters.MemoryRepo (newInMemoryRepository)
import Todo.Domain.Ports
import Todo.Service (TodoService (..))
import Todo.Web (createApp)

import Acceptance.Drivers.Domain (newDomainDriver)
import Acceptance.Drivers.Http (newHttpDriver)
import Acceptance.Drivers.Ui (BrowserSession, newUiDriver, withBrowserSession)
import Acceptance.Dsl (Dsl, newDsl)
import Acceptance.Specification (todoSpecification)

startOfTime :: UTCTime
startOfTime = UTCTime (fromGregorian 2026 3 1) (secondsToDiffTime (9 * 3600))

allLayers :: [String]
allLayers = ["domain", "http", "ui"]

main :: IO ()
main = do
  layers <- requestedLayers
  headed <- (== Just "1") <$> lookupEnv "HEADED"
  slowmo <- maybe 0 ((* 1000) . read) <$> lookupEnv "SLOWMO"  -- milliseconds -> microseconds
  hspec $ do
    when ("domain" `elem` layers) $
      describe "[domain]" $ around withDomainDsl todoSpecification
    when ("http" `elem` layers) $
      describe "[http]" $ around withHttpDsl todoSpecification
    when ("ui" `elem` layers) $
      describe "[ui]" $
        aroundAll (withBrowserSession headed slowmo) $
          aroundWith withUiDsl todoSpecification

requestedLayers :: IO [String]
requestedLayers = do
  raw <- lookupEnv "SPEC_LAYERS"
  pure $ case raw of
    Nothing -> allLayers
    Just s  ->
      let chosen = filter (not . null) (map trim (splitOn ',' s))
       in if null chosen then allLayers else chosen
  where
    trim = f . f where f = reverse . dropWhile isSpace
    splitOn c = foldr step [[]]
      where
        step ch acc@(cur : rest)
          | ch == c   = [] : acc
          | otherwise = (ch : cur) : rest
        step _ []     = [[]]

-- domain: call the service in-process
withDomainDsl :: (Dsl -> IO ()) -> IO ()
withDomainDsl use = do
  repo <- newInMemoryRepository
  fc   <- newFrozenClock startOfTime
  drv  <- newDomainDriver (TodoService repo (frozenClock fc))
  dsl  <- newDsl drv (advanceClock fc) 2.0
  use dsl

-- http: the real WAI app, in-process, no socket
withHttpDsl :: (Dsl -> IO ()) -> IO ()
withHttpDsl use = do
  repo <- newInMemoryRepository
  fc   <- newFrozenClock startOfTime
  app  <- createApp repo (frozenClock fc)
  drv  <- newHttpDriver app
  dsl  <- newDsl drv (advanceClock fc) 2.0
  use dsl

-- ui: a live Warp server on an ephemeral port, driven through the browser. The
-- server runs in this process so it shares the frozen clock.
withUiDsl :: (Dsl -> IO ()) -> BrowserSession -> IO ()
withUiDsl use browser = do
  repo <- newInMemoryRepository
  fc   <- newFrozenClock startOfTime
  app  <- createApp repo (frozenClock fc)
  (port, sock) <- Warp.openFreePort
  server <- forkIO (Warp.runSettingsSocket Warp.defaultSettings sock app)
  let url = "http://127.0.0.1:" <> tshow port
  ( do drv <- newUiDriver browser url
       dsl <- newDsl drv (advanceClock fc) 5.0
       use dsl )
    `finally` (killThread server >> close sock)

tshow :: Show a => a -> Text
tshow = T.pack . show
