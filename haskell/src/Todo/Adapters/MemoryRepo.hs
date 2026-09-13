-- | In-memory repository.
--
-- A real implementation of the port that happens to be fast and disposable, and
-- it is verified by the same contract test as the SQLite one. A fake that is
-- never verified is just a second bug farm.
module Todo.Adapters.MemoryRepo
  ( newInMemoryRepository
  ) where

import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (find)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)

import Todo.Domain.Model (Todo (..), isDone)
import Todo.Domain.Ports (TodoRepository (..))

newInMemoryRepository :: IO TodoRepository
newInMemoryRepository = do
  ref <- newIORef (Map.empty :: Map Text Todo)
  pure (fromRef ref)
  where
    fromRef ref = TodoRepository
      { repoAdd     = \todo -> modifyIORef' ref (Map.insert (todoId todo) todo)
      , repoReplace = \todo -> modifyIORef' ref (Map.insert (todoId todo) todo)
      , repoRemove  = \tid  -> modifyIORef' ref (Map.delete tid)
      , repoGet     = \tid  -> Map.lookup tid <$> readIORef ref
      , repoFindActiveByTitle = \title -> do
          todos <- readIORef ref
          pure (find (\t -> todoTitle t == title && not (isDone t)) (Map.elems todos))
      , repoAll = Map.elems <$> readIORef ref
      }
