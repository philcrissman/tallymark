{-# LANGUAGE OverloadedStrings #-}

module Main where

import Analytics.TrackHandler (handleTrack)
import Analytics.StatsHandler (handleStats)

import Amazonka (Env, newEnv, discover, configureService, setEndpoint)
import qualified Amazonka.DynamoDB as DynamoDB
import Data.Function ((&))
import AWS.Lambda.Runtime (mRuntime)
import AWS.Lambda.Events.ApiGateway.ProxyRequest (ProxyRequest(..), NoAuthorizer)
import AWS.Lambda.Events.ApiGateway.ProxyResponse (ProxyResponse, response, addHeader, textPlain, applicationJson)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Types.Status (status200, status404)
import System.Environment (lookupEnv)

main :: IO ()
main = do
  -- Initialize AWS env once on cold start; reused across warm invocations
  baseEnv <- newEnv discover
  -- Support local DynamoDB endpoint override for development
  env <- do
    mEndpoint <- lookupEnv "DYNAMODB_ENDPOINT"
    case mEndpoint of
      Nothing -> pure baseEnv
      Just ep ->
        let (host, port) = parseEndpoint ep
            useTLS = "https" `T.isPrefixOf` T.pack ep
            dynamo = setEndpoint useTLS (TE.encodeUtf8 host) port DynamoDB.defaultService
        in  pure $ configureService dynamo baseEnv
  mRuntime (handler env)

handler :: Env -> ProxyRequest NoAuthorizer -> IO ProxyResponse
handler env req =
  case (httpMethod req, path req) of
    ("POST", "/track") -> handleTrack env req
    ("GET", "/stats")  -> handleStats env req

    -- Handle CORS preflight
    ("OPTIONS", _) ->
      pure
        ( addHeader "Access-Control-Max-Age" "86400"
        . addHeader "Access-Control-Allow-Headers" "Content-Type"
        . addHeader "Access-Control-Allow-Methods" "GET, POST, OPTIONS"
        . addHeader "Access-Control-Allow-Origin" "*"
        $ response status200 (textPlain "")
        )

    _ ->
      pure $ response status404 (applicationJson ("{\"error\":\"not found\"}" :: T.Text))

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
