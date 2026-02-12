{-# LANGUAGE OverloadedStrings #-}

module Analytics.DynamoDB
  ( writePageView
  , queryByDateRange
  ) where

import Analytics.Types

import Amazonka (Env, send, runResourceT)
import Amazonka.DynamoDB.PutItem (newPutItem, putItem_item)
import Amazonka.DynamoDB.Query (newQuery, query_indexName, query_keyConditionExpression, query_expressionAttributeValues, queryResponse_items)
import Amazonka.DynamoDB.Types (AttributeValue(..))
import Control.Lens ((&), (.~), (?~), (^.))
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (formatTime, defaultTimeLocale)
import Data.UUID (toText)
import System.Environment (lookupEnv)

tableName :: IO Text
tableName = do
  mName <- lookupEnv "TABLE_NAME"
  pure $ maybe "PageViews" T.pack mName

-- Write a single page view to DynamoDB
writePageView :: Env -> PageView -> IO ()
writePageView env pv = do
  table <- tableName
  let ts = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" (pvTimestamp pv)
      dateOnly = formatTime defaultTimeLocale "%Y-%m-%d" (pvTimestamp pv)
      monthKey = formatTime defaultTimeLocale "%Y-%m" (pvTimestamp pv)
      uuidSuffix = toText (pvId pv)
      item = HM.fromList $
        [ ("pk", S ("PAGE#" <> pvUrl pv))
        , ("sk", S ("TS#" <> T.pack ts <> "#" <> uuidSuffix))
        , ("url", S (pvUrl pv))
        , ("timestamp", S (T.pack ts))
        , ("date", S (T.pack dateOnly))
        , ("gsi1pk", S ("MONTH#" <> T.pack monthKey))
        , ("gsi1sk", S ("DATE#" <> T.pack ts <> "#" <> uuidSuffix))
        ] ++ maybe [] (\r -> [("referrer", S r)]) (pvReferrer pv)
          ++ maybe [] (\u -> [("ua", S u)]) (pvUserAgent pv)

  _ <- runResourceT $ send env (newPutItem table & putItem_item .~ item)
  pure ()

-- Query page views for a date range using the ByDate GSI
-- startDate and endDate are "YYYY-MM-DD" strings
queryByDateRange :: Env -> Text -> Text -> IO [HashMap Text AttributeValue]
queryByDateRange env startDate endDate = do
  table <- tableName
  let months = monthsBetween startDate endDate
  results <- mapM (queryMonth env table startDate endDate) months
  pure (concat results)

queryMonth :: Env -> Text -> Text -> Text -> Text -> IO [HashMap Text AttributeValue]
queryMonth env table startDate endDate monthKey = do
  let req = newQuery table
        & query_indexName ?~ "ByDate"
        & query_keyConditionExpression ?~ "gsi1pk = :pk AND gsi1sk BETWEEN :start AND :end"
        & query_expressionAttributeValues ?~ HM.fromList
            [ (":pk", S ("MONTH#" <> monthKey))
            , (":start", S ("DATE#" <> startDate <> "T00:00:00Z"))
            , (":end", S ("DATE#" <> endDate <> "T23:59:59Z~"))
            ]
  resp <- runResourceT $ send env req
  pure (resp ^. queryResponse_items)

-- Generate list of "YYYY-MM" month keys between two dates
monthsBetween :: Text -> Text -> [Text]
monthsBetween start end =
  let startMonth = T.take 7 start  -- "YYYY-MM"
      endMonth = T.take 7 end
  in  expandMonths startMonth endMonth

expandMonths :: Text -> Text -> [Text]
expandMonths current end
  | current > end = []
  | otherwise = current : expandMonths (nextMonth current) end

nextMonth :: Text -> Text
nextMonth ym =
  let (yearStr, rest) = T.splitAt 4 ym
      monthStr = T.drop 1 rest  -- drop the '-'
      year = read (T.unpack yearStr) :: Int
      month = read (T.unpack monthStr) :: Int
      (year', month') = if month == 12 then (year + 1, 1) else (year, month + 1)
  in  T.pack $ show year' ++ "-" ++ (if month' < 10 then "0" else "") ++ show month'
