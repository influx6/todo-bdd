-- | The DSL layer: the vocabulary the specification is written in.
--
-- Four jobs live here and nowhere else:
--
--   1. Business language — functions named for what a person does.
--   2. Named references — 'aTodoIsAdded' hands back a 'TodoRef' the spec can
--      name (@mondaysMilk@, @thursdaysMilk@); the DSL keeps the mapping to
--      whatever opaque token the driver issued.
--   3. Test-data isolation — the spec says "Buy milk", the system sees
--      "Buy milk [7f3a]", so two runs cannot see each other. The suffix must
--      never distinguish two todos the spec deliberately gave the same title:
--      telling those apart is the token's job, not the title's.
--   4. Synchronisation — every observation retries until it matches or the
--      budget runs out.
--
-- What the DSL must never contain is logic. A step may only drive the system and
-- report what is observable; the moment it computes an answer, the test becomes
-- a mirror and can never fail for a real reason.
module Acceptance.Dsl
  ( Dsl
  , newDsl
  , TodoRef
  , Entry
  , open
  , done
  , minutes
  , hours
  , days
    -- things a person does
  , aTodoIsAdded
  , aTodoIsAddedWithUntidySpacing
  , aTodoIsAddedWithNoTitle
  , aTodoIsAddedExpectingRefusal
  , aTodoIsAddedWithAnOverlongTitle
  , theTodoIsCompleted
  , theTodoIsReopened
  , theTodoIsDeleted
  , timePasses
    -- things a person sees
  , theListReads
  , theListIsEmpty
  , theMessageShownIs
  , noMessageIsShown
  ) where

import Control.Concurrent (threadDelay)
import Data.IORef
import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (NominalDiffTime)
import GHC.Clock (getMonotonicTime)
import System.Random (randomRIO)
import Test.HUnit.Lang (assertFailure)
import Text.Printf (printf)

import Acceptance.Drivers

-- | A specification's name for one particular todo. Deliberately not an id: the
-- spec is naming an occasion ("the milk I added on Monday") and the DSL knows
-- which token that turned into.
newtype TodoRef = TodoRef { refName :: Text }
  deriving (Eq)

instance Show TodoRef where
  show = T.unpack . refName

-- | An expected line of the list.
data Entry = Entry TodoRef Bool
  deriving (Eq)

instance Show Entry where
  show (Entry ref d) = show ref ++ (if d then " (done)" else "")

-- | @open milk@ — this todo, outstanding.
open :: TodoRef -> Entry
open ref = Entry ref False

-- | @done milk@ — this todo, completed.
done :: TodoRef -> Entry
done ref = Entry ref True

minutes, hours, days :: Int -> NominalDiffTime
minutes m = fromIntegral m * 60
hours h = fromIntegral h * 3600
days d = fromIntegral d * 86400

data Dsl = Dsl
  { dslDriver  :: TodoDriver
  , dslAdvance :: NominalDiffTime -> IO ()
  , dslTimeout :: Double                     -- seconds
  , dslSuffix  :: Text
  , dslTokens  :: IORef [(Token, TodoRef)]   -- insertion order preserved
  }

newDsl :: TodoDriver -> (NominalDiffTime -> IO ()) -> Double -> IO Dsl
newDsl driver advance timeout = do
  n   <- randomRIO (0, 0xFFFFFF) :: IO Int
  ref <- newIORef []
  pure Dsl
    { dslDriver  = driver
    , dslAdvance = advance
    , dslTimeout = timeout
    , dslSuffix  = T.pack (printf " [%06x]" n)
    , dslTokens  = ref
    }

-- --- things a person does ---------------------------------------------------

aTodoIsAdded :: Dsl -> Text -> IO TodoRef
aTodoIsAdded dsl name = do
  token <- drvAdd (dslDriver dsl) (isolated dsl name)
  remember dsl name token

aTodoIsAddedWithUntidySpacing :: Dsl -> Text -> IO TodoRef
aTodoIsAddedWithUntidySpacing dsl name = do
  let sloppy = "   " <> T.replace " " "   " (isolated dsl name) <> "  "
  token <- drvAdd (dslDriver dsl) sloppy
  remember dsl name token

aTodoIsAddedWithNoTitle :: Dsl -> IO ()
aTodoIsAddedWithNoTitle dsl = () <$ drvAdd (dslDriver dsl) "   "

aTodoIsAddedExpectingRefusal :: Dsl -> Text -> IO ()
aTodoIsAddedExpectingRefusal dsl name = do
  token <- drvAdd (dslDriver dsl) (isolated dsl name)
  case token of
    Nothing -> pure ()
    Just _  -> assertFailure ("Expected " ++ show name ++ " to be refused, but it was added")

aTodoIsAddedWithAnOverlongTitle :: Dsl -> IO ()
aTodoIsAddedWithAnOverlongTitle dsl = () <$ drvAdd (dslDriver dsl) (T.replicate 200 "x")

theTodoIsCompleted :: Dsl -> TodoRef -> IO ()
theTodoIsCompleted dsl ref = tokenFor dsl ref >>= drvComplete (dslDriver dsl)

theTodoIsReopened :: Dsl -> TodoRef -> IO ()
theTodoIsReopened dsl ref = tokenFor dsl ref >>= drvReopen (dslDriver dsl)

theTodoIsDeleted :: Dsl -> TodoRef -> IO ()
theTodoIsDeleted dsl ref = tokenFor dsl ref >>= drvDelete (dslDriver dsl)

timePasses :: Dsl -> NominalDiffTime -> IO ()
timePasses dsl = dslAdvance dsl

-- --- things a person sees ---------------------------------------------------

theListReads :: Dsl -> [Entry] -> IO ()
theListReads dsl wanted =
  eventually dsl (ourEntries dsl) wanted ("Expected the list to read " ++ show wanted)

theListIsEmpty :: Dsl -> IO ()
theListIsEmpty dsl = theListReads dsl []

theMessageShownIs :: Dsl -> Text -> IO ()
theMessageShownIs dsl expected =
  eventually dsl probe expected ("Expected the message " ++ show expected)
  where
    probe = do
      m <- drvLastMessage (dslDriver dsl)
      pure (T.replace (dslSuffix dsl) "" (maybe "" id m))

noMessageIsShown :: Dsl -> IO ()
noMessageIsShown dsl =
  eventually dsl (drvLastMessage (dslDriver dsl)) Nothing "Expected no message"

-- --- bookkeeping ------------------------------------------------------------

isolated :: Dsl -> Text -> Text
isolated dsl name = name <> dslSuffix dsl

remember :: Dsl -> Text -> Maybe Token -> IO TodoRef
remember _   name Nothing      = assertFailure ("The system refused to add " ++ show name)
remember dsl name (Just token) = do
  name' <- uniqueName dsl name
  let ref = TodoRef name'
  modifyIORef' (dslTokens dsl) (++ [(token, ref)])
  pure ref

-- | Two todos may share a title, so the second gets a distinguishable name in
-- failure output. The system never sees this.
uniqueName :: Dsl -> Text -> IO Text
uniqueName dsl name = do
  tokens <- readIORef (dslTokens dsl)
  let taken = length (filter (\(_, TodoRef n) -> name `T.isPrefixOf` n) tokens)
  pure (if taken == 0 then name else name <> " #" <> T.pack (show (taken + 1)))

tokenFor :: Dsl -> TodoRef -> IO Token
tokenFor dsl ref = do
  tokens <- readIORef (dslTokens dsl)
  case fst <$> find ((== ref) . snd) tokens of
    Just token -> pure token
    Nothing    -> assertFailure ("No todo known as " ++ show ref ++ " in this test")

ourEntries :: Dsl -> IO [Entry]
ourEntries dsl = do
  tokens <- readIORef (dslTokens dsl)
  rows   <- drvVisibleTodos (dslDriver dsl)
  pure [ Entry ref (rowDone row)
       | row <- rows
       , Just ref <- [lookup (rowToken row) tokens]  -- ignore anything this test did not create
       ]

eventually :: (Eq a, Show a) => Dsl -> IO a -> a -> String -> IO ()
eventually dsl probe expected description = do
  deadline <- (+ dslTimeout dsl) <$> getMonotonicTime
  let loop = do
        actual <- probe
        if actual == expected
          then pure ()
          else do
            now <- getMonotonicTime
            if now >= deadline
              then assertFailure
                     (description ++ ", but after " ++ show (dslTimeout dsl)
                       ++ "s it was " ++ show actual)
              else threadDelay 50000 >> loop
  loop
