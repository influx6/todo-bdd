-- | Unit tests: the TDD inner loop.
--
-- Not smaller copies of the specification. The specification says *what the
-- product does*; these say *how this unit behaves*, including the edges no user
-- story would mention. They know about ids, exception types and the repository
-- port on purpose.
module Todo.ServiceSpec (spec) where

import Control.Monad (void)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime (..), addUTCTime, fromGregorian, secondsToDiffTime)
import Test.Hspec

import Todo.Adapters.MemoryRepo (newInMemoryRepository)
import Todo.Domain.Model (Todo (..), RuleViolation (..), maxTitleLength)
import Todo.Domain.Ports
import Todo.Service

noon :: UTCTime
noon = UTCTime (fromGregorian 2026 3 1) (secondsToDiffTime (12 * 3600))

data Fix = Fix
  { fSvc   :: TodoService
  , fRepo  :: TodoRepository
  , fClock :: FrozenClock
  }

mkFix :: IO Fix
mkFix = do
  repo <- newInMemoryRepository
  fc   <- newFrozenClock noon
  pure (Fix (TodoService repo (frozenClock fc)) repo fc)

ruleMatching :: Text -> Selector RuleViolation
ruleMatching sub (RuleViolation m) = sub `T.isInfixOf` m

spec :: Spec
spec = before mkFix $ do
  describe "Adding" $ do
    it "assigns an identity" $ \f -> do
      first  <- addTodo (fSvc f) "Buy milk"
      second <- addTodo (fSvc f) "Call the dentist"
      viewId first `shouldNotBe` viewId second

    it "stamps the creation time from the clock" $ \f -> do
      created <- addTodo (fSvc f) "Buy milk"
      stored  <- repoGet (fRepo f) (viewId created)
      (todoCreatedAt <$> stored) `shouldBe` Just noon

    it "collapses runs of whitespace" $ \f -> do
      v <- addTodo (fSvc f) "  Buy   milk  "
      viewTitle v `shouldBe` "Buy milk"

    it "rejects a title that says nothing" $ \f ->
      mapM_ (\blank -> addTodo (fSvc f) blank `shouldThrow` ruleMatching "needs a title")
            ["", "   ", "\t\n"]

    it "accepts a title at the limit" $ \f -> do
      let title = T.replicate maxTitleLength "x"
      v <- addTodo (fSvc f) title
      viewTitle v `shouldBe` title

    it "rejects a title one character past the limit" $ \f ->
      addTodo (fSvc f) (T.replicate (maxTitleLength + 1) "x")
        `shouldThrow` ruleMatching "under 120 characters"

    it "treats differently spaced titles as the same thing" $ \f -> do
      _ <- addTodo (fSvc f) "Buy milk"
      addTodo (fSvc f) "Buy    milk" `shouldThrow` ruleMatching "already on your list"

  describe "Completing" $ do
    it "stamps the completion time from the clock" $ \f -> do
      todo <- addTodo (fSvc f) "Buy milk"
      advanceClock (fClock f) (3 * 3600)
      _ <- completeTodo (fSvc f) (viewId todo)
      stored <- repoGet (fRepo f) (viewId todo)
      (todoCompletedAt =<< stored) `shouldBe` Just (addUTCTime (3 * 3600) noon)

    it "refuses to complete something twice" $ \f -> do
      todo <- addTodo (fSvc f) "Buy milk"
      _ <- completeTodo (fSvc f) (viewId todo)
      completeTodo (fSvc f) (viewId todo) `shouldThrow` ruleMatching "already done"

    it "refuses to reopen something that was never finished" $ \f -> do
      todo <- addTodo (fSvc f) "Buy milk"
      reopenTodo (fSvc f) (viewId todo) `shouldThrow` ruleMatching "not done yet"

    it "reopening clears the completion time" $ \f -> do
      todo <- addTodo (fSvc f) "Buy milk"
      _ <- completeTodo (fSvc f) (viewId todo)
      _ <- reopenTodo (fSvc f) (viewId todo)
      stored <- repoGet (fRepo f) (viewId todo)
      (todoCompletedAt =<< stored) `shouldBe` Nothing

    it "preserves the original creation time through a round trip" $ \f -> do
      todo <- addTodo (fSvc f) "Buy milk"
      advanceClock (fClock f) (2 * 86400)
      _ <- completeTodo (fSvc f) (viewId todo)
      _ <- reopenTodo (fSvc f) (viewId todo)
      stored <- repoGet (fRepo f) (viewId todo)
      (todoCreatedAt <$> stored) `shouldBe` Just noon

  describe "Missing todos" $
    it "every operation says the same thing about a vanished todo" $ \f -> do
      let ops = [ void . completeTodo (fSvc f)
                , void . reopenTodo (fSvc f)
                , deleteTodo (fSvc f)
                ]
      mapM_ (\op -> op "an-id-that-was-never-issued"
                      `shouldThrow` ruleMatching "no longer on your list") ops

  describe "Ordering" $ do
    it "puts outstanding work before finished work" $ \f -> do
      first <- addTodo (fSvc f) "Buy milk"
      advanceClock (fClock f) 60
      _ <- addTodo (fSvc f) "Call the dentist"
      _ <- completeTodo (fSvc f) (viewId first)
      titles <- map viewTitle <$> listTodos (fSvc f)
      titles `shouldBe` ["Call the dentist", "Buy milk"]

    it "breaks ties among finished work by most recently finished" $ \f -> do
      first  <- addTodo (fSvc f) "Buy milk"
      second <- addTodo (fSvc f) "Call the dentist"
      _ <- completeTodo (fSvc f) (viewId first)
      advanceClock (fClock f) 60
      _ <- completeTodo (fSvc f) (viewId second)
      titles <- map viewTitle <$> listTodos (fSvc f)
      titles `shouldBe` ["Call the dentist", "Buy milk"]

    it "an empty list is not a special case" $ \f -> do
      todos <- listTodos (fSvc f)
      todos `shouldBe` []
