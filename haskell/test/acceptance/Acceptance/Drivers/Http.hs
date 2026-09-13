-- | Driver that goes through the JSON API. Milliseconds per test.
--
-- Adds routing, request parsing, serialisation and error mapping to what the
-- domain driver covered. It runs the real WAI 'Application' in-process via
-- 'Network.Wai.Test' — no socket — which is the Haskell counterpart of Flask's
-- test client. Point 'runSession' at a live base URL instead and the identical
-- specification would run against a deployed environment.
--
-- Its token is the id the API returns on creation.
module Acceptance.Drivers.Http
  ( newHttpDriver
  ) where

import Data.Aeson (FromJSON (..), decode, encode, object, withObject, (.:), (.=))
import Data.IORef
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import Network.HTTP.Types (hContentType, methodDelete, methodGet, methodPost, statusCode)
import Network.Wai (Application, Request (..))
import Network.Wai.Test

import Acceptance.Drivers

newHttpDriver :: Application -> IO TodoDriver
newHttpDriver app = do
  message <- newIORef Nothing
  let run session = runSession session app

      record resp = writeIORef message $
        if statusCode (simpleStatus resp) == 422
          then (\(ApiError m) -> m) <$> decode (simpleBody resp)
          else Nothing

  pure TodoDriver
    { drvAdd = \title -> do
        let bodyLbs = encode (object ["title" .= title])
        resp <- run (srequest (SRequest (jsonReq methodPost "/api/todos") bodyLbs))
        record resp
        pure $ if statusCode (simpleStatus resp) == 201
                 then atId <$> decode (simpleBody resp)
                 else Nothing

    , drvComplete = \tok ->
        run (request (plainReq methodPost (todoPath tok "/completion"))) >>= record

    , drvReopen = \tok ->
        run (request (plainReq methodDelete (todoPath tok "/completion"))) >>= record

    , drvDelete = \tok ->
        run (request (plainReq methodDelete (todoPath tok ""))) >>= record

    , drvVisibleTodos = do
        resp <- run (request (plainReq methodGet "/api/todos"))
        pure $ case decode (simpleBody resp) of
          Just (ApiList todos) -> map toRow todos
          Nothing              -> []

    , drvLastMessage = readIORef message
    }
  where
    todoPath tok suffix = "/api/todos/" <> encodeUtf8 tok <> suffix

    plainReq method path = setPath (defaultRequest { requestMethod = method }) path
    jsonReq method path =
      setPath (defaultRequest { requestMethod = method
                              , requestHeaders = [(hContentType, "application/json")] }) path

    toRow (ApiTodo i t d) = TodoRow i t d

-- The shapes the API returns, just enough to read back what we need.

data ApiTodo = ApiTodo Text Text Bool

atId :: ApiTodo -> Text
atId (ApiTodo i _ _) = i

instance FromJSON ApiTodo where
  parseJSON = withObject "todo" $ \o -> ApiTodo <$> o .: "id" <*> o .: "title" <*> o .: "done"

newtype ApiList = ApiList [ApiTodo]

instance FromJSON ApiList where
  parseJSON = withObject "list" $ \o -> ApiList <$> o .: "todos"

newtype ApiError = ApiError Text

instance FromJSON ApiError where
  parseJSON = withObject "error" $ \o -> ApiError <$> o .: "error"
