-- | Driver that calls the service in-process. Microseconds per test.
--
-- The driver you run on every keystroke: every business rule, none of the
-- plumbing. Its token is the todo's id, in hand the moment @add@ returns.
module Acceptance.Drivers.Domain
  ( newDomainDriver
  ) where

import Control.Exception (try)
import Data.IORef

import Todo.Domain.Model (RuleViolation (..))
import Todo.Service

import Acceptance.Drivers

newDomainDriver :: TodoService -> IO TodoDriver
newDomainDriver svc = do
  message <- newIORef Nothing
  let attempt :: IO a -> IO (Maybe a)
      attempt action = do
        writeIORef message Nothing
        outcome <- try action
        case outcome of
          Right a                -> pure (Just a)
          Left (RuleViolation m) -> writeIORef message (Just m) >> pure Nothing
  pure TodoDriver
    { drvAdd      = \title -> fmap viewId <$> attempt (addTodo svc title)
    , drvComplete = \tok -> () <$ attempt (completeTodo svc tok)
    , drvReopen   = \tok -> () <$ attempt (reopenTodo svc tok)
    , drvDelete   = \tok -> () <$ attempt (deleteTodo svc tok)
    , drvVisibleTodos =
        map (\v -> TodoRow (viewId v) (viewTitle v) (viewDone v)) <$> listTodos svc
    , drvLastMessage = readIORef message
    }
