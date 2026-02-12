{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Analytics.Types where

import Data.Aeson (FromJSON, ToJSON, defaultOptions, fieldLabelModifier, genericParseJSON, genericToJSON, parseJSON, toJSON)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)

-- Incoming tracking request (from JS tracker)
data TrackRequest = TrackRequest
  { trUrl :: Text
  , trReferrer :: Maybe Text
  } deriving (Show, Generic)

instance FromJSON TrackRequest where
  parseJSON = genericParseJSON defaultOptions { fieldLabelModifier = camelTo2 }

instance ToJSON TrackRequest where
  toJSON = genericToJSON defaultOptions { fieldLabelModifier = camelTo2 }

-- Stored page view event
data PageView = PageView
  { pvId :: UUID
  , pvUrl :: Text
  , pvTimestamp :: UTCTime
  , pvReferrer :: Maybe Text
  , pvUserAgent :: Maybe Text
  } deriving (Show, Generic)

-- Stats response types
data DailyCounts = DailyCounts
  { dcDate :: Text
  , dcCount :: Int
  } deriving (Show, Generic)

instance ToJSON DailyCounts where
  toJSON = genericToJSON defaultOptions { fieldLabelModifier = camelTo2 }

data PageCounts = PageCounts
  { pcPage :: Text
  , pcCount :: Int
  } deriving (Show, Generic)

instance ToJSON PageCounts where
  toJSON = genericToJSON defaultOptions { fieldLabelModifier = camelTo2 }

data StatsResponse = StatsResponse
  { srDaily :: [DailyCounts]
  , srTopPages :: [PageCounts]
  , srTopRefs :: [PageCounts]
  , srTotal :: Int
  } deriving (Show, Generic)

instance ToJSON StatsResponse where
  toJSON = genericToJSON defaultOptions { fieldLabelModifier = camelTo2 }

-- Drop the 2-char prefix and lowercase the first char
camelTo2 :: String -> String
camelTo2 [] = []
camelTo2 [_] = []
camelTo2 (_:_:rest) = lowFirst rest
  where
    lowFirst [] = []
    lowFirst (c:cs) = toLower' c : cs
    toLower' c
      | c >= 'A' && c <= 'Z' = toEnum (fromEnum c + 32)
      | otherwise = c
