{-# LANGUAGE OverloadedStrings #-}

module Analytics.StatsHandler (handleStats) where

import Analytics.DynamoDB (queryByDateRange)
import Analytics.Types

import Amazonka (Env)
import Amazonka.DynamoDB.Types (AttributeValue(..))
import AWS.Lambda.Events.ApiGateway.ProxyRequest (ProxyRequest(..), NoAuthorizer)
import AWS.Lambda.Events.ApiGateway.ProxyResponse (ProxyResponse, response, addHeader, applicationJson)
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
import Data.List (sortBy)
import Data.Ord (Down(..), comparing)
import Data.Text (Text)
import Network.HTTP.Types.Status (status200, status400)

handleStats :: Env -> ProxyRequest NoAuthorizer -> IO ProxyResponse
handleStats env req = do
  let params = queryStringParameters req
      mStart = HM.lookup "start" params
      mEnd = HM.lookup "end" params
      mSite = HM.lookup "site" params
  case (mStart, mEnd, mSite) of
    (Just startDate, Just endDate, Just siteId) -> do
      items <- queryByDateRange env siteId startDate endDate
      let daily = aggregateByDay items
          topPages = aggregateByField "url" items
          topRefs = aggregateByField "referrer" items
          total = length items
          stats = StatsResponse
            { srDaily = daily
            , srTopPages = take 20 topPages
            , srTopRefs = take 20 topRefs
            , srTotal = total
            }
      pure
        ( addHeader "Access-Control-Allow-Origin" "*"
        $ response status200 (applicationJson stats)
        )
    _ ->
      pure
        ( addHeader "Access-Control-Allow-Origin" "*"
        $ response status400 (applicationJson ("{\"error\":\"start, end, and site query params required\"}" :: Text))
        )

-- Aggregate items by the 'date' field, producing daily counts sorted by date
aggregateByDay :: [HashMap Text AttributeValue] -> [DailyCounts]
aggregateByDay items =
  let dates = map (getField "date") items
      counts = countValues dates
  in  sortBy (comparing dcDate) [DailyCounts d c | (d, c) <- HM.toList counts]

-- Aggregate items by a given field, producing sorted counts (descending)
aggregateByField :: Text -> [HashMap Text AttributeValue] -> [PageCounts]
aggregateByField field items =
  let values = map (getField field) items
      counts = countValues values
  in  sortBy (comparing (Down . pcCount)) [PageCounts v c | (v, c) <- HM.toList counts, v /= ""]

-- Extract a text field from a DynamoDB item, defaulting to ""
getField :: Text -> HashMap Text AttributeValue -> Text
getField field item =
  case HM.lookup field item of
    Just (S t) -> t
    _          -> ""

-- Count occurrences of each value
countValues :: [Text] -> HashMap Text Int
countValues = foldl (\acc v -> HM.insertWith (+) v 1 acc) HM.empty
