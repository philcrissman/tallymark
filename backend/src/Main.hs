{-# LANGUAGE OverloadedStrings #-}

module Main where

import Analytics.TrackHandler (handleTrack)
import Analytics.StatsHandler (handleStats)
import Analytics.DynamoDB (listSites, deleteSiteData)

import Amazonka (Env, newEnv, discover, configureService, setEndpoint)
import qualified Amazonka.DynamoDB as DynamoDB
import Data.Aeson (encode, object, (.=))
import Data.Function ((&))
import AWS.Lambda.Runtime (mRuntime)
import AWS.Lambda.Events.ApiGateway.ProxyRequest (ProxyRequest(..), NoAuthorizer)
import AWS.Lambda.Events.ApiGateway.ProxyResponse (ProxyResponse, response, addHeader, textPlain, applicationJson)
import qualified Data.CaseInsensitive as CI
import qualified Data.HashMap.Strict as HM
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE
import Network.HTTP.Types.Status (status200, status401, status404)
import System.Environment (lookupEnv)

main :: IO ()
main = do
  -- Initialize AWS env once on cold start; reused across warm invocations
  baseEnv <- newEnv discover
  mEndpoint <- lookupEnv "DYNAMODB_ENDPOINT"
  env <- case mEndpoint of
    Nothing -> pure baseEnv
    Just "" -> pure baseEnv
    Just ep ->
      let (host, port) = parseEndpoint ep
          useTLS = "https" `T.isPrefixOf` T.pack ep
          dynamo = setEndpoint useTLS (TE.encodeUtf8 host) port DynamoDB.defaultService
      in  pure $ configureService dynamo baseEnv

  -- Read API key for auth
  mApiKey <- lookupEnv "API_KEY"
  let apiKey = maybe "" T.pack mApiKey

  mRuntime (handler env apiKey)

handler :: Env -> T.Text -> ProxyRequest NoAuthorizer -> IO ProxyResponse
handler env apiKey req =
  case (httpMethod req, path req) of
    -- Tracking endpoint — no auth required
    ("POST", "/track") -> handleTrack env req

    -- Protected endpoints — require Bearer token
    ("GET", "/stats") ->
      requireAuth apiKey req $ handleStats env req

    ("GET", "/sites") ->
      requireAuth apiKey req $ do
        sites <- listSites env
        pure
          ( addHeader "Access-Control-Allow-Origin" "*"
          $ response status200 (applicationJson sites)
          )

    ("DELETE", "/sites") ->
      requireAuth apiKey req $ do
        let params = queryStringParameters req
            mSite = HM.lookup "site" params
        case mSite of
          Nothing ->
            pure
              ( addHeader "Access-Control-Allow-Origin" "*"
              $ response status200 (applicationJson ("{\"error\":\"site query param required\"}" :: T.Text))
              )
          Just siteId -> do
            deleted <- deleteSiteData env siteId
            let body = TL.toStrict $ TLE.decodeUtf8 $ encode $ object
                  [ "ok" .= True
                  , "deleted" .= deleted
                  ]
            pure
              ( addHeader "Access-Control-Allow-Origin" "*"
              $ response status200 (applicationJson body)
              )

    -- Handle CORS preflight
    ("OPTIONS", _) ->
      pure
        ( addHeader "Access-Control-Max-Age" "86400"
        . addHeader "Access-Control-Allow-Headers" "Content-Type, Authorization"
        . addHeader "Access-Control-Allow-Methods" "GET, POST, DELETE, OPTIONS"
        . addHeader "Access-Control-Allow-Origin" "*"
        $ response status200 (textPlain "")
        )

    _ ->
      pure $ response status404 (applicationJson ("{\"error\":\"not found\"}" :: T.Text))

-- Check Authorization: Bearer <key> header
requireAuth :: T.Text -> ProxyRequest NoAuthorizer -> IO ProxyResponse -> IO ProxyResponse
requireAuth apiKey req action
  | T.null apiKey = action  -- No API key configured, allow all
  | otherwise =
    let mAuth = HM.lookup (CI.mk "authorization") (headers req)
        expected = "Bearer " <> apiKey
    in case mAuth of
      Just auth | auth == expected -> action
      _ -> pure
        ( addHeader "Access-Control-Allow-Origin" "*"
        $ response status401 (applicationJson ("{\"error\":\"unauthorized\"}" :: T.Text))
        )

-- Parse "http://host:port" into (host, port)
parseEndpoint :: String -> (T.Text, Int)
parseEndpoint ep =
  let t = T.pack ep
      stripped = T.replace "http://" "" $ T.replace "https://" "" t
      parts = T.splitOn ":" stripped
  in  case parts of
        [h, p] -> (h, read (T.unpack p))
        [h]    -> (h, if "https" `T.isPrefixOf` t then 443 else 80)
        _      -> ("localhost", 8000)
