-- | Two thin delivery mechanisms over one service: a JSON API and HTML pages.
--
-- No business logic here. If a rule ever creeps into this file, the domain
-- driver stops testing the same system as the HTTP driver and the whole
-- arrangement quietly rots. The HTML uses Post/Redirect/Get with the message
-- carried in a @flash@ cookie, so the browser test never reasons about form
-- resubmission.
module Todo.Web
  ( routes
  , createApp
  ) where

import Control.Exception (try)
import Data.Aeson (FromJSON (..), Value, object, decode, withObject, (.!=), (.:?), (.=))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Lazy as TL
import Network.HTTP.Types (created201, noContent204, unprocessableEntity422)
import Network.HTTP.Types.URI (urlDecode, urlEncode)
import Network.Wai (Application)
import Web.Cookie (parseCookies)
import Web.Scotty

import Text.Blaze.Html (Html, toHtml, toValue, (!))
import Text.Blaze.Html.Renderer.Text (renderHtml)
import Text.Blaze.Html5 (customAttribute)
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

import Todo.Domain.Model (RuleViolation (..))
import Todo.Domain.Ports (Clock, TodoRepository)
import Todo.Service

createApp :: TodoRepository -> Clock -> IO Application
createApp repo clock = scottyApp (routes (TodoService repo clock))

routes :: TodoService -> ScottyM ()
routes svc = do
  -- ---- JSON API: parse, delegate, serialise -----------------------------
  get "/api/todos" $ do
    todos <- liftIO (listTodos svc)
    json (object ["todos" .= map todoJson todos])

  post "/api/todos" $ do
    raw <- body
    let title = maybe "" unTitle (decode raw)
    withRule (addTodo svc title) $ \v -> do
      status created201
      json (todoJson v)

  post "/api/todos/:id/completion" $ do
    tid <- pathParam "id"
    withRule (completeTodo svc tid) (json . todoJson)

  delete "/api/todos/:id/completion" $ do
    tid <- pathParam "id"
    withRule (reopenTodo svc tid) (json . todoJson)

  delete "/api/todos/:id" $ do
    tid <- pathParam "id"
    withRule (deleteTodo svc tid) (\() -> status noContent204)

  -- ---- HTML pages: Post/Redirect/Get with a flash cookie ----------------
  get "/" $ do
    msg <- readFlash
    clearFlash
    todos <- liftIO (listTodos svc)
    html (renderHtml (page todos msg))

  post "/todos" $ do
    title <- formParamMaybe "title"
    attempt (addTodo svc (fromMaybe "" title))
    redirect "/"

  post "/todos/:id" $ do
    tid <- pathParam "id"
    action <- formParamMaybe "action"
    case (action :: Maybe Text) of
      Just "complete" -> attempt (completeTodo svc tid)
      Just "reopen"   -> attempt (reopenTodo svc tid)
      Just "delete"   -> attempt (deleteTodo svc tid)
      _               -> pure ()
    redirect "/"

-- | Run an action; on a rule violation return 422 with the message. The API's
-- error contract.
withRule :: IO a -> (a -> ActionM ()) -> ActionM ()
withRule act k = do
  outcome <- liftIO (try act)
  case outcome of
    Right a               -> k a
    Left (RuleViolation m) -> do
      status unprocessableEntity422
      json (object ["error" .= m])

-- | Run an action; on a rule violation stash the message in the flash cookie.
-- The UI's error contract.
attempt :: IO a -> ActionM ()
attempt act = do
  outcome <- liftIO (try act)
  case outcome of
    Right _                -> pure ()
    Left (RuleViolation m) -> setFlash m

todoJson :: TodoView -> Value
todoJson t = object ["id" .= viewId t, "title" .= viewTitle t, "done" .= viewDone t]

newtype TitlePayload = TitlePayload { unTitle :: Text }

instance FromJSON TitlePayload where
  parseJSON = withObject "payload" $ \o -> TitlePayload <$> o .:? "title" .!= ""

-- ---- flash cookie ---------------------------------------------------------

setFlash :: Text -> ActionM ()
setFlash msg =
  setHeader "Set-Cookie" (TL.fromStrict ("flash=" <> encode msg <> "; Path=/"))
  where encode = TE.decodeUtf8 . urlEncode True . TE.encodeUtf8

clearFlash :: ActionM ()
clearFlash = setHeader "Set-Cookie" "flash=; Path=/; Max-Age=0"

readFlash :: ActionM (Maybe Text)
readFlash = do
  raw <- header "Cookie"
  pure $ do
    cookie <- raw
    value  <- lookup "flash" (parseCookies (TE.encodeUtf8 (TL.toStrict cookie)))
    pure (TE.decodeUtf8 (urlDecode True value))

-- ---- template (reproduces templates/index.html attribute-for-attribute) ---

page :: [TodoView] -> Maybe Text -> Html
page todos msg = H.docTypeHtml $ do
  H.head $ do
    H.meta ! A.charset "utf-8"
    H.meta ! A.name "viewport" ! A.content "width=device-width, initial-scale=1"
    H.title "Todo"
  H.body $ H.main $ do
    H.header ! A.class_ "masthead" $ do
      H.h1 "Today"
      H.p ! A.class_ "tally" ! testid "tally" $ toHtml (tally (length (filter (not . viewDone) todos)))
    case msg of
      Just m  -> H.p ! A.class_ "message" ! A.role "alert" ! testid "message" $ toHtml m
      Nothing -> pure ()
    H.form ! A.class_ "compose" ! A.method "post" ! A.action "/todos" $ do
      H.input ! A.id "title" ! A.name "title" ! testid "new-todo"
              ! A.placeholder "What needs doing?" ! A.autocomplete "off"
      H.button ! A.type_ "submit" ! testid "add" $ "Add"
    if null todos
      then H.p ! A.class_ "empty" ! testid "empty" $ "Your list is clear. Add the first thing above."
      else H.ul ! A.class_ "ledger" ! testid "todo-list" $ mapM_ row todos
  where
    testid = customAttribute "data-testid"

    tally 0 = "Nothing left to do." :: Text
    tally 1 = "One thing left."
    tally n = tshow n <> " things left."

    row t =
      H.li ! A.class_ (toValue (if viewDone t then "entry is-done" else "entry" :: Text))
           ! testid "todo"
           ! customAttribute "data-title" (toValue (viewTitle t))
           ! customAttribute "data-done" (if viewDone t then "true" else "false") $
        H.form ! A.method "post" ! A.action (toValue ("/todos/" <> viewId t)) $ do
          H.button ! A.class_ "marker" ! A.type_ "submit" ! A.name "action"
                   ! A.value (if viewDone t then "reopen" else "complete")
                   ! testid (if viewDone t then "reopen" else "complete") $
            H.span ! customAttribute "aria-hidden" "true" $ (if viewDone t then "●" else "○")
          H.span ! A.class_ "title" ! testid "todo-title" $ toHtml (viewTitle t)
          H.button ! A.class_ "discard" ! A.type_ "submit" ! A.name "action" ! A.value "delete"
                   ! testid "delete" $
            H.span ! customAttribute "aria-hidden" "true" $ H.preEscapedToHtml ("&times;" :: Text)

tshow :: Show a => a -> Text
tshow = TL.toStrict . TL.pack . show
