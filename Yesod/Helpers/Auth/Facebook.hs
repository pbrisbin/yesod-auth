{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE CPP #-}
module Yesod.Helpers.Auth.Facebook
    ( authFacebook
    , facebookUrl
    ) where

import Yesod.Helpers.Auth
import qualified Web.Authenticate.Facebook as Facebook
import Data.Object (fromMapping, lookupScalar)
import Data.Maybe (fromMaybe)

import Yesod.Form
import Yesod.Handler
import Yesod.Widget
import Text.Hamlet (hamlet)
import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString.Char8 as S8
import Control.Monad.Trans.Class (lift)

facebookUrl :: AuthRoute
facebookUrl = PluginR "facebook" ["forward"]

authFacebook :: YesodAuth m
             => String -- ^ Application ID
             -> String -- ^ Application secret
             -> [String] -- ^ Requested permissions
             -> AuthPlugin m
authFacebook cid secret perms =
    AuthPlugin "facebook" dispatch login
  where
    url = PluginR "facebook" []
    dispatch "GET" ["forward"] = do
        tm <- getRouteToMaster
        render <- getUrlRender
        let fb = Facebook.Facebook cid secret $ render $ tm url
        redirectString RedirectTemporary $ S8.pack $ Facebook.getForwardUrl fb perms
    dispatch "GET" [] = do
        render <- getUrlRender
        tm <- getRouteToMaster
        let fb = Facebook.Facebook cid secret $ render $ tm url
        code <- runFormGet' $ stringInput "code"
        at <- liftIO $ Facebook.getAccessToken fb code
        let Facebook.AccessToken at' = at
        so <- liftIO $ Facebook.getGraphData at "me"
        let c = fromMaybe (error "Invalid response from Facebook") $ do
            m <- fromMapping so
            id' <- lookupScalar "id" m
            let name = lookupScalar "name" m
            let email = lookupScalar "email" m
            let id'' = "http://graph.facebook.com/" ++ id'
            return
                $ Creds "facebook" id''
                $ maybe id (\x -> (:) ("verifiedEmail", x)) email
                $ maybe id (\x -> (:) ("displayName ", x)) name
                [ ("accessToken", at')
                ]
        setCreds True c
    dispatch _ _ = notFound
    login tm = do
        render <- lift getUrlRender
        let fb = Facebook.Facebook cid secret $ render $ tm url
        let furl = Facebook.getForwardUrl fb $ perms
        y <- lift getYesod
        addHtml
#if GHC7
            [hamlet|
#else
            [$hamlet|
#endif
<p>
    <a href="#{furl}">#{messageFacebook y}
|]
