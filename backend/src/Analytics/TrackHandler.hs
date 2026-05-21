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
import Network.HTTP.Types.Status (status200, status400, status403)
import System.Environment (lookupEnv)

handleTrack :: Env -> ProxyRequest NoAuthorizer -> IO ProxyResponse
handleTrack env req = do
  allowedSites <- getAllowedSites
  case eitherDecode (body req) of
    Left err ->
      pure
        ( addHeader "Access-Control-Allow-Origin" "*"
        $ response status400 (applicationJson ("{\"error\":\"" <> T.pack err <> "\"}" :: Text))
        )
    Right trackReq ->
      if not (null allowedSites) && trSiteId trackReq `notElem` allowedSites
        then pure
          ( addHeader "Access-Control-Allow-Origin" "*"
          $ response status403 (applicationJson ("{\"error\":\"unknown site\"}" :: Text))
          )
        else do
          now <- getCurrentTime
          uuid <- nextRandom
          let userAgent = HM.lookup (CI.mk "user-agent") (headers req)
              pv = PageView
                { pvId = uuid
                , pvUrl = trUrl trackReq
                , pvTimestamp = now
                , pvReferrer = trReferrer trackReq
                , pvUserAgent = userAgent
                , pvSiteId = trSiteId trackReq
                }
          writePageView env pv
          pure
            ( addHeader "Access-Control-Allow-Origin" "*"
            $ response status200 (applicationJson ("{\"ok\":true}" :: Text))
            )

-- Returns the list of allowed site IDs from ALLOWED_SITES env var.
-- Empty list means no restriction (useful for local dev).
getAllowedSites :: IO [Text]
getAllowedSites = do
  mSites <- lookupEnv "ALLOWED_SITES"
  pure $ case mSites of
    Nothing -> []
    Just "" -> []
    Just s  -> map T.strip $ T.splitOn "," (T.pack s)
