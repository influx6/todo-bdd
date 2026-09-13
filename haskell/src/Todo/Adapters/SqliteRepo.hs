-- | SQLite repository. The production implementation of the same port.
module Todo.Adapters.SqliteRepo
  ( newSqliteRepository
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import Data.Time.Format.ISO8601 (iso8601ParseM, iso8601Show)
import Database.SQLite.Simple

import Todo.Domain.Model (Todo (..))
import Todo.Domain.Ports (TodoRepository (..))

newSqliteRepository :: Connection -> IO TodoRepository
newSqliteRepository conn = do
  execute_ conn
    "CREATE TABLE IF NOT EXISTS todos \
    \(id TEXT PRIMARY KEY, title TEXT NOT NULL, created_at TEXT NOT NULL, completed_at TEXT)"
  execute_ conn "CREATE INDEX IF NOT EXISTS todos_title ON todos (title)"
  pure TodoRepository
    { repoAdd = \todo ->
        execute conn
          "INSERT INTO todos (id, title, created_at, completed_at) VALUES (?, ?, ?, ?)"
          (rowOf todo)
    , repoReplace = \todo ->
        execute conn
          "UPDATE todos SET title = ?, created_at = ?, completed_at = ? WHERE id = ?"
          (todoTitle todo, isoText (todoCreatedAt todo), isoText <$> todoCompletedAt todo, todoId todo)
    , repoRemove = \tid ->
        execute conn "DELETE FROM todos WHERE id = ?" (Only tid)
    , repoGet = \tid -> do
        rows <- query conn "SELECT id, title, created_at, completed_at FROM todos WHERE id = ?" (Only tid)
        pure (fromRow' <$> listToMaybe' rows)
    , repoFindActiveByTitle = \title -> do
        rows <- query conn
          "SELECT id, title, created_at, completed_at FROM todos WHERE title = ? AND completed_at IS NULL"
          (Only title)
        pure (fromRow' <$> listToMaybe' rows)
    , repoAll = do
        rows <- query_ conn "SELECT id, title, created_at, completed_at FROM todos"
        pure (map fromRow' rows)
    }

type Row = (Text, Text, Text, Maybe Text)

rowOf :: Todo -> Row
rowOf todo =
  ( todoId todo
  , todoTitle todo
  , isoText (todoCreatedAt todo)
  , isoText <$> todoCompletedAt todo
  )

fromRow' :: Row -> Todo
fromRow' (i, ti, created, completed) =
  Todo
    { todoId          = i
    , todoTitle       = ti
    , todoCreatedAt   = parseIso created
    , todoCompletedAt = parseIso <$> completed
    }

isoText :: UTCTime -> Text
isoText = T.pack . iso8601Show

parseIso :: Text -> UTCTime
parseIso t = fromMaybe (error ("SqliteRepo: unparseable timestamp " <> T.unpack t))
                       (iso8601ParseM (T.unpack t))

listToMaybe' :: [a] -> Maybe a
listToMaybe' []      = Nothing
listToMaybe' (x : _) = Just x
