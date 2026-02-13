module Api exposing (StatsData, DailyCount, PageCount, RefCount, fetchStats, fetchSites, deleteSite)

import Http
import Json.Decode as Decode exposing (Decoder, field, int, list, string)


type alias StatsData =
    { daily : List DailyCount
    , topPages : List PageCount
    , topRefs : List RefCount
    , total : Int
    }


type alias DailyCount =
    { date : String
    , count : Int
    }


type alias PageCount =
    { page : String
    , count : Int
    }


type alias RefCount =
    { page : String
    , count : Int
    }


statsDecoder : Decoder StatsData
statsDecoder =
    Decode.map4 StatsData
        (field "daily" (list dailyDecoder))
        (field "topPages" (list pageCountDecoder))
        (field "topRefs" (list refCountDecoder))
        (field "total" int)


dailyDecoder : Decoder DailyCount
dailyDecoder =
    Decode.map2 DailyCount
        (field "date" string)
        (field "count" int)


pageCountDecoder : Decoder PageCount
pageCountDecoder =
    Decode.map2 PageCount
        (field "page" string)
        (field "count" int)


refCountDecoder : Decoder RefCount
refCountDecoder =
    Decode.map2 RefCount
        (field "page" string)
        (field "count" int)


authHeader : String -> Http.Header
authHeader apiKey =
    Http.header "Authorization" ("Bearer " ++ apiKey)


fetchStats : String -> String -> String -> String -> String -> (Result Http.Error StatsData -> msg) -> Cmd msg
fetchStats apiUrl apiKey siteId startDate endDate toMsg =
    Http.request
        { method = "GET"
        , headers = [ authHeader apiKey ]
        , url = apiUrl ++ "/stats?start=" ++ startDate ++ "&end=" ++ endDate ++ "&site=" ++ siteId
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg statsDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


fetchSites : String -> String -> (Result Http.Error (List String) -> msg) -> Cmd msg
fetchSites apiUrl apiKey toMsg =
    Http.request
        { method = "GET"
        , headers = [ authHeader apiKey ]
        , url = apiUrl ++ "/sites"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg (list string)
        , timeout = Nothing
        , tracker = Nothing
        }


deleteSite : String -> String -> String -> (Result Http.Error Decode.Value -> msg) -> Cmd msg
deleteSite apiUrl apiKey siteId toMsg =
    Http.request
        { method = "DELETE"
        , headers = [ authHeader apiKey ]
        , url = apiUrl ++ "/sites?site=" ++ siteId
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg Decode.value
        , timeout = Nothing
        , tracker = Nothing
        }
