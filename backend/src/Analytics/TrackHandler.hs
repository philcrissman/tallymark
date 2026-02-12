{-# LANGUAGE OverloadedStrings #-}

module Analytics.TrackHandler (handleTrack) where

import Analytics.DynamoDB (writePageView)
import Analytics.Types

import Amazonka (Env)
import AWS.Lambda.Events.ApiGateway.ProxyRequest (ProxyRequest(..), NoAuthorizer)
import AWS.Lambda.Events.ApiGateway.ProxyResponse (ProxyResponse, response, addHeader, applicationJson)
import Data.Aeson (eitherDecode)
import qualified Data.CaseInsensitive as CI
import qualified Data.HashMap.Strict as HM
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (getCurrentTime)
import Data.UUID.V4 (nextRandom)
import Network.HTTP.Types.Status (status200, status400)

handleTrack :: Env -> ProxyRequest NoAuthorizer -> IO ProxyResponse
handleTrack env req = do
  case eitherDecode (body req) of
    Left err ->
      pure
        ( addHeader "Access-Control-Allow-Origin" "https://philcrissman.net"
        $ response status400 (applicationJson ("{\"error\":\"" <> T.pack err <> "\"}" :: Text))
        )
    Right trackReq -> do
      now <- getCurrentTime
      uuid <- nextRandom
      let userAgent = HM.lookup (CI.mk "user-agent") (headers req)
          pv = PageView
            { pvId = uuid
            , pvUrl = trUrl trackReq
            , pvTimestamp = now
            , pvReferrer = trReferrer trackReq
            , pvUserAgent = userAgent
            }
      writePageView env pv
      pure
        ( addHeader "Access-Control-Allow-Origin" "https://philcrissman.net"
        $ response status200 (applicationJson ("{\"ok\":true}" :: Text))
        )
