-- | The executable specification for a todo list.
--
-- There is one of these. It runs against the domain service, the HTTP API and a
-- real browser without changing a character, because it never mentions any of
-- them. Read it as a description of what the product does; if it stops
-- describing the product, that is a bug in the product or a change of intent,
-- never a test to be patched.
--
-- Nothing here knows about ids, status codes, selectors or SQL. If you find
-- yourself wanting one of those, it belongs in a driver.
module Acceptance.Specification
  ( todoSpecification
  ) where

import Test.Hspec

import Acceptance.Dsl

todoSpecification :: SpecWith Dsl
todoSpecification = do
  describe "Capturing work" $ do
    it "a new todo appears on the list" $ \dsl -> do
      milk <- aTodoIsAdded dsl "Buy milk"
      theListReads dsl [open milk]

    it "todos are listed oldest first" $ \dsl -> do
      milk <- aTodoIsAdded dsl "Buy milk"
      timePasses dsl (minutes 5)
      dentist <- aTodoIsAdded dsl "Call the dentist"
      theListReads dsl [open milk, open dentist]

    it "surrounding whitespace is tidied away" $ \dsl -> do
      milk <- aTodoIsAddedWithUntidySpacing dsl "Buy milk"
      theListReads dsl [open milk]

    it "a todo must have a title" $ \dsl -> do
      aTodoIsAddedWithNoTitle dsl
      theMessageShownIs dsl "A todo needs a title"
      theListIsEmpty dsl

    it "a title has to be readable at a glance" $ \dsl -> do
      aTodoIsAddedWithAnOverlongTitle dsl
      theMessageShownIs dsl "Keep the title under 120 characters"
      theListIsEmpty dsl

    it "the same thing is not added twice" $ \dsl -> do
      milk <- aTodoIsAdded dsl "Buy milk"
      aTodoIsAddedExpectingRefusal dsl "Buy milk"
      theMessageShownIs dsl "'Buy milk' is already on your list"
      theListReads dsl [open milk]

  describe "Getting work done" $ do
    it "completing a todo marks it done" $ \dsl -> do
      milk <- aTodoIsAdded dsl "Buy milk"
      theTodoIsCompleted dsl milk
      theListReads dsl [done milk]
      noMessageIsShown dsl

    it "finished work sinks below outstanding work" $ \dsl -> do
      milk <- aTodoIsAdded dsl "Buy milk"
      dentist <- aTodoIsAdded dsl "Call the dentist"
      theTodoIsCompleted dsl milk
      theListReads dsl [open dentist, done milk]

    it "the most recently finished work sits at the top of the done pile" $ \dsl -> do
      milk <- aTodoIsAdded dsl "Buy milk"
      dentist <- aTodoIsAdded dsl "Call the dentist"
      theTodoIsCompleted dsl milk
      timePasses dsl (hours 1)
      theTodoIsCompleted dsl dentist
      theListReads dsl [done dentist, done milk]

    it "finishing something frees its title to be used again" $ \dsl -> do
      mondaysMilk <- aTodoIsAdded dsl "Buy milk"
      theTodoIsCompleted dsl mondaysMilk
      thursdaysMilk <- aTodoIsAdded dsl "Buy milk"
      noMessageIsShown dsl
      theListReads dsl [open thursdaysMilk, done mondaysMilk]

    it "work can be picked back up" $ \dsl -> do
      milk <- aTodoIsAdded dsl "Buy milk"
      theTodoIsCompleted dsl milk
      theTodoIsReopened dsl milk
      theListReads dsl [open milk]

    it "work cannot be picked back up onto a taken title" $ \dsl -> do
      mondaysMilk <- aTodoIsAdded dsl "Buy milk"
      theTodoIsCompleted dsl mondaysMilk
      thursdaysMilk <- aTodoIsAdded dsl "Buy milk"
      theTodoIsReopened dsl mondaysMilk
      theMessageShownIs dsl "'Buy milk' is already back on your list"
      theListReads dsl [open thursdaysMilk, done mondaysMilk]

  describe "Clearing things out" $ do
    it "a todo can be thrown away" $ \dsl -> do
      milk <- aTodoIsAdded dsl "Buy milk"
      dentist <- aTodoIsAdded dsl "Call the dentist"
      theTodoIsDeleted dsl milk
      theListReads dsl [open dentist]

    it "finished work can be thrown away" $ \dsl -> do
      milk <- aTodoIsAdded dsl "Buy milk"
      theTodoIsCompleted dsl milk
      theTodoIsDeleted dsl milk
      theListIsEmpty dsl

    it "only the named todo is thrown away when a title is reused" $ \dsl -> do
      mondaysMilk <- aTodoIsAdded dsl "Buy milk"
      theTodoIsCompleted dsl mondaysMilk
      thursdaysMilk <- aTodoIsAdded dsl "Buy milk"
      theTodoIsDeleted dsl mondaysMilk
      theListReads dsl [open thursdaysMilk]
