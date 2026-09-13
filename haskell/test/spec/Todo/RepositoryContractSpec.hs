-- | One contract, every implementation of the port.
--
-- This is the test that earns you the right to use a fast in-memory repository
-- everywhere else. Add an implementation, add one @describe@ line. Nothing else
-- moves.
module Todo.RepositoryContractSpec (spec) where

import Data.List (sort)
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Database.SQLite.Simple (open)
import Test.Hspec

import Todo.Adapters.MemoryRepo (newInMemoryRepository)
import Todo.Adapters.SqliteRepo (newSqliteRepository)
import Todo.Domain.Model (Todo (..))
import Todo.Domain.Ports

noon :: UTCTime
noon = UTCTime (fromGregorian 2026 3 1) (secondsToDiffTime (12 * 3600))

aTodo :: Todo
aTodo = Todo { todoId = "t1", todoTitle = "Buy milk", todoCreatedAt = noon, todoCompletedAt = Nothing }

spec :: Spec
spec = do
  describe "InMemory" (contract newInMemoryRepository)
  describe "Sqlite"   (contract (open ":memory:" >>= newSqliteRepository))

contract :: IO TodoRepository -> Spec
contract mk = before mk $ do
  describe "storing and fetching" $ do
    it "a stored todo comes back unchanged" $ \repo -> do
      repoAdd repo aTodo
      got <- repoGet repo "t1"
      got `shouldBe` Just aTodo

    it "the timestamp survives the round trip" $ \repo -> do
      repoAdd repo aTodo
      got <- repoGet repo "t1"
      (todoCreatedAt <$> got) `shouldBe` Just noon

    it "a completion time survives the round trip" $ \repo -> do
      repoAdd repo aTodo { todoCompletedAt = Just noon }
      got <- repoGet repo "t1"
      (todoCompletedAt =<< got) `shouldBe` Just noon

    it "an unknown id is absent rather than an error" $ \repo -> do
      got <- repoGet repo "never-stored"
      got `shouldBe` Nothing

    it "all returns everything that was added" $ \repo -> do
      repoAdd repo aTodo { todoId = "t1", todoTitle = "Buy milk" }
      repoAdd repo aTodo { todoId = "t2", todoTitle = "Call the dentist" }
      ids <- map todoId <$> repoAll repo
      sort ids `shouldBe` ["t1", "t2"]

    it "all is empty before anything is added" $ \repo -> do
      todos <- repoAll repo
      todos `shouldBe` []

  describe "replacing" $ do
    it "replace overwrites the stored state" $ \repo -> do
      repoAdd repo aTodo
      repoReplace repo aTodo { todoCompletedAt = Just noon }
      got <- repoGet repo "t1"
      (todoCompletedAt =<< got) `shouldBe` Just noon

    it "replace does not create a duplicate" $ \repo -> do
      repoAdd repo aTodo
      repoReplace repo aTodo { todoTitle = "Buy oat milk" }
      todos <- repoAll repo
      length todos `shouldBe` 1

  describe "removing" $ do
    it "a removed todo is gone" $ \repo -> do
      repoAdd repo aTodo
      repoRemove repo "t1"
      got <- repoGet repo "t1"
      got `shouldBe` Nothing

    it "removing something absent is quietly accepted" $ \repo -> do
      repoRemove repo "never-stored"
      todos <- repoAll repo
      todos `shouldBe` []

  describe "finding active work by title" $ do
    it "finds an outstanding todo" $ \repo -> do
      repoAdd repo aTodo
      got <- repoFindActiveByTitle repo "Buy milk"
      (todoId <$> got) `shouldBe` Just "t1"

    it "ignores finished work" $ \repo -> do
      repoAdd repo aTodo { todoCompletedAt = Just noon }
      got <- repoFindActiveByTitle repo "Buy milk"
      got `shouldBe` Nothing

    it "matches the whole title exactly" $ \repo -> do
      repoAdd repo aTodo
      got <- repoFindActiveByTitle repo "Buy"
      got `shouldBe` Nothing

    it "is case sensitive" $ \repo -> do
      repoAdd repo aTodo
      got <- repoFindActiveByTitle repo "buy milk"
      got `shouldBe` Nothing

    it "finds the outstanding one when a title is reused" $ \repo -> do
      repoAdd repo aTodo { todoId = "done", todoCompletedAt = Just noon }
      repoAdd repo aTodo { todoId = "active" }
      got <- repoFindActiveByTitle repo "Buy milk"
      (todoId <$> got) `shouldBe` Just "active"
