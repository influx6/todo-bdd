-- | The application service. This is the real system under test.
--
-- Everything above it (JSON API, HTML pages) is delivery mechanism; everything
-- below it (SQLite, the clock) is infrastructure. All the behaviour worth
-- specifying lives here, which is why the fastest acceptance driver can talk
-- straight to it and still be testing the same system as the browser.
module Todo.Service
  ( TodoView (..)
  , TodoService (..)
  , addTodo
  , completeTodo
  , reopenTodo
  , deleteTodo
  , listTodos
  ) where

import Control.Exception (throwIO)
import Data.List (sortBy)
import Data.Ord (Down (..), comparing)
import Data.Text (Text)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID

import Todo.Domain.Model
import Todo.Domain.Ports

-- | What a caller is allowed to see. Deliberately smaller than the entity.
data TodoView = TodoView
  { viewId    :: Text
  , viewTitle :: Text
  , viewDone  :: Bool
  }
  deriving (Eq, Show)

data TodoService = TodoService
  { svcRepo  :: TodoRepository
  , svcClock :: Clock
  }

-- | Turn a broken rule into a thrown exception at the IO boundary.
orThrow :: Either RuleViolation a -> IO a
orThrow = either throwIO pure

addTodo :: TodoService -> Text -> IO TodoView
addTodo (TodoService repo clock) rawTitle = do
  title <- orThrow (cleanTitle rawTitle)
  existing <- repoFindActiveByTitle repo title
  case existing of
    Just _  -> throwIO (RuleViolation ("'" <> title <> "' is already on your list"))
    Nothing -> do
      newId <- UUID.toText <$> UUID.nextRandom
      now   <- clockNow clock
      let todo = Todo { todoId = newId, todoTitle = title, todoCreatedAt = now, todoCompletedAt = Nothing }
      repoAdd repo todo
      pure (viewOf todo)

completeTodo :: TodoService -> Text -> IO TodoView
completeTodo (TodoService repo clock) tid = do
  todo <- require repo tid
  now  <- clockNow clock
  done <- orThrow (completed now todo)
  repoReplace repo done
  pure (viewOf done)

reopenTodo :: TodoService -> Text -> IO TodoView
reopenTodo (TodoService repo _) tid = do
  todo <- require repo tid
  -- Check this todo's own state first. Otherwise an outstanding todo collides
  -- with itself in the title check below and gets told it is already back on
  -- the list.
  active <- orThrow (reopened todo)
  clash  <- repoFindActiveByTitle repo (todoTitle todo)
  case clash of
    Just _  -> throwIO (RuleViolation ("'" <> todoTitle todo <> "' is already back on your list"))
    Nothing -> do
      repoReplace repo active
      pure (viewOf active)

deleteTodo :: TodoService -> Text -> IO ()
deleteTodo (TodoService repo _) tid = do
  _ <- require repo tid
  repoRemove repo tid

-- | Outstanding work first, oldest first; then what is done, newest first.
-- The order is part of the behaviour — it is what the user sees — so it belongs
-- in the service and gets specified, not left to the database.
listTodos :: TodoService -> IO [TodoView]
listTodos (TodoService repo _) = do
  todos <- repoAll repo
  let active = sortBy (comparing todoCreatedAt) (filter (not . isDone) todos)
      done   = sortBy (comparing (Down . todoCompletedAt)) (filter isDone todos)
  pure (map viewOf (active ++ done))

require :: TodoRepository -> Text -> IO Todo
require repo tid = do
  found <- repoGet repo tid
  maybe (throwIO (RuleViolation "That todo is no longer on your list")) pure found

viewOf :: Todo -> TodoView
viewOf todo = TodoView { viewId = todoId todo, viewTitle = todoTitle todo, viewDone = isDone todo }
