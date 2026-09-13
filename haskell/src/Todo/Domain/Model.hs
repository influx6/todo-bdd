-- | The domain model. Knows nothing about Scotty, HTTP, SQL or tests.
--
-- The rules that can be broken return 'Either' 'RuleViolation'; the application
-- service turns a 'Left' into a thrown 'RuleViolation' at the IO boundary, which
-- is where the delivery layers catch it. Keeping the failure explicit here means
-- the model stays pure and every rule has exactly one user-facing message —
-- which is what lets a single specification assert on all three interfaces.
module Todo.Domain.Model
  ( Todo (..)
  , isDone
  , completed
  , reopened
  , cleanTitle
  , RuleViolation (..)
  , ruleMessage
  , maxTitleLength
  ) where

import Control.Exception (Exception)
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)

maxTitleLength :: Int
maxTitleLength = 120

-- | A rule the user broke. The message is user-facing: shown in the UI,
-- returned by the API and asserted on in the specification.
newtype RuleViolation = RuleViolation Text
  deriving (Eq, Show)

instance Exception RuleViolation

ruleMessage :: RuleViolation -> Text
ruleMessage (RuleViolation m) = m

data Todo = Todo
  { todoId          :: Text
  , todoTitle       :: Text
  , todoCreatedAt   :: UTCTime
  , todoCompletedAt :: Maybe UTCTime
  }
  deriving (Eq, Show)

isDone :: Todo -> Bool
isDone = isJust . todoCompletedAt

completed :: UTCTime -> Todo -> Either RuleViolation Todo
completed at todo
  | isDone todo = Left (RuleViolation ("'" <> todoTitle todo <> "' is already done"))
  | otherwise   = Right todo { todoCompletedAt = Just at }

reopened :: Todo -> Either RuleViolation Todo
reopened todo
  | not (isDone todo) = Left (RuleViolation ("'" <> todoTitle todo <> "' is not done yet"))
  | otherwise         = Right todo { todoCompletedAt = Nothing }

-- | Normalise and validate a title, or explain why it is not acceptable.
-- @T.words@ collapses runs of whitespace and trims, matching @" ".join(raw.split())@.
cleanTitle :: Text -> Either RuleViolation Text
cleanTitle raw
  | T.null title                    = Left (RuleViolation "A todo needs a title")
  | T.length title > maxTitleLength = Left (RuleViolation "Keep the title under 120 characters")
  | otherwise                       = Right title
  where
    title = T.unwords (T.words raw)
