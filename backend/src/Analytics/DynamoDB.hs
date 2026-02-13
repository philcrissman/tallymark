{-# LANGUAGE OverloadedStrings #-}

module Analytics.DynamoDB
  ( writePageView
  , queryByDateRange
  , listSites
  , deleteSiteData
  ) where

import Analytics.Types

import Amazonka (Env, send, runResourceT)
import Amazonka.DynamoDB.PutItem (newPutItem, putItem_item)
import Amazonka.DynamoDB.Query (newQuery, query_indexName, query_keyConditionExpression, query_expressionAttributeValues, queryResponse_items)
import Amazonka.DynamoDB.Scan (newScan, scan_filterExpression, scan_expressionAttributeValues, scanResponse_items)
import Amazonka.DynamoDB.DeleteItem (newDeleteItem, deleteItem_key)
import Amazonka.DynamoDB.Types (AttributeValue(..))
import Control.Lens ((&), (.~), (?~), (^.))
import Data.HashMap.Strict (HashMap)
import Data.Maybe (fromMaybe)
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

-- Write a single page view to DynamoDB, plus a site registry entry
writePageView :: Env -> PageView -> IO ()
writePageView env pv = do
  table <- tableName
  let siteId = pvSiteId pv
      ts = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" (pvTimestamp pv)
      dateOnly = formatTime defaultTimeLocale "%Y-%m-%d" (pvTimestamp pv)
      monthKey = formatTime defaultTimeLocale "%Y-%m" (pvTimestamp pv)
      uuidSuffix = toText (pvId pv)
      item = HM.fromList $
        [ ("pk", S ("SITE#" <> siteId <> "#PAGE#" <> pvUrl pv))
        , ("sk", S ("TS#" <> T.pack ts <> "#" <> uuidSuffix))
        , ("url", S (pvUrl pv))
        , ("siteId", S siteId)
        , ("timestamp", S (T.pack ts))
        , ("date", S (T.pack dateOnly))
        , ("gsi1pk", S ("SITE#" <> siteId <> "#MONTH#" <> T.pack monthKey))
        , ("gsi1sk", S ("DATE#" <> T.pack ts <> "#" <> uuidSuffix))
        ] ++ maybe [] (\r -> [("referrer", S r)]) (pvReferrer pv)
          ++ maybe [] (\u -> [("ua", S u)]) (pvUserAgent pv)

  -- Write the page view
  _ <- runResourceT $ send env (newPutItem table & putItem_item .~ item)

  -- Write/update site registry entry (idempotent)
  let siteItem = HM.fromList
        [ ("pk", S "SITES")
        , ("sk", S ("SITE#" <> siteId))
        , ("siteId", S siteId)
        ]
  _ <- runResourceT $ send env (newPutItem table & putItem_item .~ siteItem)
  pure ()

-- Query page views for a date range and site using the ByDate GSI
queryByDateRange :: Env -> Text -> Text -> Text -> IO [HashMap Text AttributeValue]
queryByDateRange env siteId startDate endDate = do
  table <- tableName
  let months = monthsBetween startDate endDate
  results <- mapM (queryMonth env table siteId startDate endDate) months
  pure (concat results)

queryMonth :: Env -> Text -> Text -> Text -> Text -> Text -> IO [HashMap Text AttributeValue]
queryMonth env table siteId startDate endDate monthKey = do
  let req = newQuery table
        & query_indexName ?~ "ByDate"
        & query_keyConditionExpression ?~ "gsi1pk = :pk AND gsi1sk BETWEEN :start AND :end"
        & query_expressionAttributeValues ?~ HM.fromList
            [ (":pk", S ("SITE#" <> siteId <> "#MONTH#" <> monthKey))
            , (":start", S ("DATE#" <> startDate <> "T00:00:00Z"))
            , (":end", S ("DATE#" <> endDate <> "T23:59:59Z~"))
            ]
  resp <- runResourceT $ send env req
  pure (resp ^. queryResponse_items)

-- List all known site IDs
listSites :: Env -> IO [Text]
listSites env = do
  table <- tableName
  let req = newQuery table
        & query_keyConditionExpression ?~ "pk = :pk"
        & query_expressionAttributeValues ?~ HM.fromList
            [ (":pk", S "SITES") ]
  resp <- runResourceT $ send env req
  let items = resp ^. queryResponse_items
  pure [ sid | item <- items, Just (S sid) <- [HM.lookup "siteId" item] ]

-- Delete all data for a site
deleteSiteData :: Env -> Text -> IO Int
deleteSiteData env siteId = do
  table <- tableName
  -- Find all items for this site via scan
  let req = newScan table
        & scan_filterExpression ?~ "begins_with(pk, :sitePrefix) OR (pk = :sites AND sk = :siteKey)"
        & scan_expressionAttributeValues ?~ HM.fromList
            [ (":sitePrefix", S ("SITE#" <> siteId <> "#"))
            , (":sites", S "SITES")
            , (":siteKey", S ("SITE#" <> siteId))
            ]
  resp <- runResourceT $ send env req
  let items = fromMaybe [] (resp ^. scanResponse_items)
      extractKey :: HashMap Text AttributeValue -> Maybe (HashMap Text AttributeValue)
      extractKey item = do
        pk <- HM.lookup "pk" item
        sk <- HM.lookup "sk" item
        pure $ HM.fromList [("pk", pk), ("sk", sk)]
      keys = concatMap (maybe [] (:[]) . extractKey) items
  -- Delete each item
  mapM_ (\key -> runResourceT $ send env (newDeleteItem table & deleteItem_key .~ key)) keys
  pure (length keys)

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
