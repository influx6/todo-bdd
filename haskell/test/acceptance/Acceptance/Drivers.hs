-- | Protocol drivers: one per way of reaching the system.
--
-- Every driver is the same record of 'IO' actions, so the specification never
-- learns which one it is talking to. Adding a fourth way in (a CLI, a queue
-- consumer, a deployed environment) means writing one more of these and changing
-- no tests at all.
--
-- Tokens are opaque. @add@ hands one back and every later action quotes it; what
-- a token *is* stays each driver's private business (the domain and HTTP drivers
-- use the todo's id; the browser driver reads it out of the form action). The
-- specification never sees one — it holds a named reference and the DSL keeps the
-- mapping.
module Acceptance.Drivers
  ( Token
  , TodoRow (..)
  , TodoDriver (..)
  ) where

import Data.Text (Text)

type Token = Text

-- | One line of what the user can currently see.
data TodoRow = TodoRow
  { rowToken :: Token
  , rowTitle :: Text
  , rowDone  :: Bool
  }
  deriving (Eq, Show)

data TodoDriver = TodoDriver
  { drvAdd          :: Text -> IO (Maybe Token)  -- ^ 'Nothing' if the system refused it
  , drvComplete     :: Token -> IO ()
  , drvReopen       :: Token -> IO ()
  , drvDelete       :: Token -> IO ()
  , drvVisibleTodos :: IO [TodoRow]
  , drvLastMessage  :: IO (Maybe Text)
  }
