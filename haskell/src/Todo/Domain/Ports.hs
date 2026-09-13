-- | Ports: the interfaces the application depends on but does not implement.
--
-- Records of 'IO' actions are the Haskell equivalent of Python's @Protocol@ —
-- the service is handed one and never learns whether it is talking to an
-- in-memory map or SQLite, a frozen clock or the wall clock.
module Todo.Domain.Ports
  ( TodoRepository (..)
  , Clock (..)
  , systemClock
  , FrozenClock (..)
  , newFrozenClock
  ) where

import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Time (NominalDiffTime, UTCTime, addUTCTime, getCurrentTime)

import Todo.Domain.Model (Todo)

data TodoRepository = TodoRepository
  { repoAdd               :: Todo -> IO ()
  , repoReplace           :: Todo -> IO ()
  , repoRemove            :: Text -> IO ()
  , repoGet               :: Text -> IO (Maybe Todo)
  , repoFindActiveByTitle :: Text -> IO (Maybe Todo)
  , repoAll               :: IO [Todo]
  }

newtype Clock = Clock { clockNow :: IO UTCTime }

systemClock :: Clock
systemClock = Clock getCurrentTime

-- | A clock the tests control. Time is an input like any other; injecting it is
-- what makes "finished yesterday sorts below finished today" a testable
-- statement instead of a @sleep@.
data FrozenClock = FrozenClock
  { frozenClock  :: Clock
  , advanceClock :: NominalDiffTime -> IO ()
  , setClock     :: UTCTime -> IO ()
  }

newFrozenClock :: UTCTime -> IO FrozenClock
newFrozenClock start = do
  ref <- newIORef start
  pure FrozenClock
    { frozenClock  = Clock (readIORef ref)
    , advanceClock = \delta -> modifyIORef' ref (addUTCTime delta)
    , setClock     = writeIORef ref
    }
