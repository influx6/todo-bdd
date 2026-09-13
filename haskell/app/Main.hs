-- | Start the app for real: SQLite on disk, the system clock, port 5000.
module Main (main) where

import Database.SQLite.Simple (open)
import Web.Scotty (scotty)

import Todo.Adapters.SqliteRepo (newSqliteRepository)
import Todo.Domain.Ports (systemClock)
import Todo.Service (TodoService (..))
import Todo.Web (routes)

main :: IO ()
main = do
  connection <- open "todos.db"
  repository <- newSqliteRepository connection
  putStrLn "todo-bdd (Haskell) on http://127.0.0.1:5000"
  scotty 5000 (routes (TodoService repository systemClock))
