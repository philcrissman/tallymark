port module Main exposing (main)

import Api exposing (DailyCount, PageCount, RefCount, StatsData, deleteSite, fetchSites, fetchStats)
import Browser
import Chart.Visits
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Task
import Time


port saveApiKey : String -> Cmd msg


type alias Flags =
    { apiUrl : String
    , savedApiKey : String
    }


type alias Model =
    { apiUrl : String
    , apiKey : String
    , apiKeyInput : String
    , authState : AuthState
    , today : String
    , startDate : String
    , endDate : String
    , sites : List String
    , selectedSite : Maybe String
    , stats : RemoteData StatsData
    , showSnippet : Bool
    }


type AuthState
    = NeedAuth
    | Authenticated
    | AuthFailed String


type RemoteData a
    = NotLoaded
    | Loading
    | Failure String
    | Success a


type Msg
    = GotTime Time.Posix
    | ApiKeyInputChanged String
    | SubmitApiKey
    | GotSites (Result Http.Error (List String))
    | GotStats (Result Http.Error StatsData)
    | SiteSelected String
    | StartDateChanged String
    | EndDateChanged String
    | QuickSelect Int
    | Refresh
    | ToggleSnippet
    | NoOp


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = \_ -> Sub.none
        , view = view
        }


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        hasSavedKey =
            not (String.isEmpty flags.savedApiKey)

        initCmd =
            if hasSavedKey then
                Cmd.batch
                    [ Task.perform GotTime Time.now
                    , fetchSites flags.apiUrl flags.savedApiKey GotSites
                    ]

            else
                Task.perform GotTime Time.now
    in
    ( { apiUrl = flags.apiUrl
      , apiKey = flags.savedApiKey
      , apiKeyInput = ""
      , authState =
            if hasSavedKey then
                Authenticated

            else
                NeedAuth
      , today = "2026-02-13"
      , startDate = "2026-01-14"
      , endDate = "2026-02-13"
      , sites = []
      , selectedSite = Nothing
      , stats =
            if hasSavedKey then
                Loading

            else
                NotLoaded
      , showSnippet = False
      }
    , initCmd
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotTime posix ->
            let
                today =
                    posixToDateString posix

                startDate =
                    addDays -30 today
            in
            ( { model | today = today, startDate = startDate, endDate = today }
            , Cmd.none
            )

        ApiKeyInputChanged val ->
            ( { model | apiKeyInput = val }, Cmd.none )

        SubmitApiKey ->
            let
                key =
                    model.apiKeyInput
            in
            ( { model | apiKey = key, authState = Authenticated, stats = Loading }
            , Cmd.batch
                [ fetchSites model.apiUrl key GotSites
                , saveApiKey key
                ]
            )

        GotSites result ->
            case result of
                Ok sites ->
                    let
                        selected =
                            List.head sites
                    in
                    case selected of
                        Just site ->
                            ( { model | sites = sites, selectedSite = Just site, stats = Loading }
                            , fetchStats model.apiUrl model.apiKey site model.startDate model.endDate GotStats
                            )

                        Nothing ->
                            ( { model | sites = sites, selectedSite = Nothing, stats = NotLoaded }, Cmd.none )

                Err err ->
                    if isUnauthorized err then
                        ( { model | authState = AuthFailed "Invalid API key", apiKey = "", stats = NotLoaded }, saveApiKey "" )

                    else
                        ( { model | stats = Failure (httpErrorToString err) }, Cmd.none )

        GotStats result ->
            case result of
                Ok data ->
                    ( { model | stats = Success data }, Cmd.none )

                Err err ->
                    if isUnauthorized err then
                        ( { model | authState = AuthFailed "Session expired", apiKey = "", stats = NotLoaded }, saveApiKey "" )

                    else
                        ( { model | stats = Failure (httpErrorToString err) }, Cmd.none )

        SiteSelected site ->
            ( { model | selectedSite = Just site, stats = Loading }
            , fetchStats model.apiUrl model.apiKey site model.startDate model.endDate GotStats
            )

        StartDateChanged date ->
            case model.selectedSite of
                Just site ->
                    ( { model | startDate = date, stats = Loading }
                    , fetchStats model.apiUrl model.apiKey site date model.endDate GotStats
                    )

                Nothing ->
                    ( { model | startDate = date }, Cmd.none )

        EndDateChanged date ->
            case model.selectedSite of
                Just site ->
                    ( { model | endDate = date, stats = Loading }
                    , fetchStats model.apiUrl model.apiKey site model.startDate date GotStats
                    )

                Nothing ->
                    ( { model | endDate = date }, Cmd.none )

        QuickSelect days ->
            let
                start =
                    if days == 0 then
                        "2020-01-01"

                    else
                        addDays (negate days) model.today

                end =
                    model.today
            in
            case model.selectedSite of
                Just site ->
                    ( { model | startDate = start, endDate = end, stats = Loading }
                    , fetchStats model.apiUrl model.apiKey site start end GotStats
                    )

                Nothing ->
                    ( { model | startDate = start, endDate = end }, Cmd.none )

        Refresh ->
            case model.selectedSite of
                Just site ->
                    ( { model | stats = Loading }
                    , fetchStats model.apiUrl model.apiKey site model.startDate model.endDate GotStats
                    )

                Nothing ->
                    ( model, Cmd.none )

        ToggleSnippet ->
            ( { model | showSnippet = not model.showSnippet }, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


isUnauthorized : Http.Error -> Bool
isUnauthorized err =
    case err of
        Http.BadStatus 401 ->
            True

        _ ->
            False


httpErrorToString : Http.Error -> String
httpErrorToString err =
    case err of
        Http.BadUrl url ->
            "Bad URL: " ++ url

        Http.Timeout ->
            "Request timed out"

        Http.NetworkError ->
            "Network error"

        Http.BadStatus status ->
            "Server error: " ++ String.fromInt status

        Http.BadBody body ->
            "Unexpected response: " ++ body



-- VIEW


view : Model -> Html Msg
view model =
    case model.authState of
        NeedAuth ->
            viewAuthForm model ""

        AuthFailed err ->
            viewAuthForm model err

        Authenticated ->
            viewDashboard model


viewAuthForm : Model -> String -> Html Msg
viewAuthForm model error =
    div [ class "auth-container" ]
        [ div [ class "auth-form" ]
            [ h1 [] [ text "Analytics" ]
            , p [ class "auth-subtitle" ] [ text "Enter your API key to continue" ]
            , Html.form [ onSubmit SubmitApiKey ]
                [ input
                    [ type_ "password"
                    , placeholder "API key"
                    , value model.apiKeyInput
                    , onInput ApiKeyInputChanged
                    , class "auth-input"
                    , attribute "autocomplete" "current-password"
                    ]
                    []
                , button [ type_ "submit", class "auth-button" ] [ text "Sign in" ]
                ]
            , if String.isEmpty error then
                text ""

              else
                p [ class "auth-error" ] [ text error ]
            ]
        ]


viewDashboard : Model -> Html Msg
viewDashboard model =
    div [ class "dashboard" ]
        [ viewHeader model
        , viewDateControls model
        , viewBody model
        , if model.showSnippet then
            viewSnippetPanel model

          else
            text ""
        ]


viewHeader : Model -> Html Msg
viewHeader model =
    header [ class "header" ]
        [ div [ class "header-top" ]
            [ h1 [] [ text "Analytics" ]
            , div [ class "header-actions" ]
                [ if List.length model.sites > 1 then
                    select [ onInput SiteSelected, class "site-select" ]
                        (List.map
                            (\s ->
                                option
                                    [ value s
                                    , selected (model.selectedSite == Just s)
                                    ]
                                    [ text s ]
                            )
                            model.sites
                        )

                  else
                    case model.selectedSite of
                        Just site ->
                            span [ class "site-name" ] [ text site ]

                        Nothing ->
                            text ""
                , button [ onClick ToggleSnippet, class "snippet-button" ]
                    [ text
                        (if model.showSnippet then
                            "Hide Tracker Code"

                         else
                            "Get Tracker Code"
                        )
                    ]
                ]
            ]
        , case model.stats of
            Success data ->
                p [ class "total" ]
                    [ span [ class "total-number" ] [ text (String.fromInt data.total) ]
                    , text " page views"
                    ]

            _ ->
                text ""
        ]


viewDateControls : Model -> Html Msg
viewDateControls model =
    div [ class "date-controls" ]
        [ div [ class "date-inputs" ]
            [ label [] [ text "From" ]
            , input
                [ type_ "date"
                , value model.startDate
                , onInput StartDateChanged
                ]
                []
            , label [] [ text "To" ]
            , input
                [ type_ "date"
                , value model.endDate
                , onInput EndDateChanged
                ]
                []
            ]
        , div [ class "quick-select" ]
            [ button [ onClick (QuickSelect 7) ] [ text "7d" ]
            , button [ onClick (QuickSelect 30) ] [ text "30d" ]
            , button [ onClick (QuickSelect 90) ] [ text "90d" ]
            , button [ onClick (QuickSelect 0) ] [ text "All" ]
            , button [ onClick Refresh ] [ text "Refresh" ]
            ]
        ]


viewBody : Model -> Html Msg
viewBody model =
    case model.stats of
        NotLoaded ->
            div [ class "loading" ] [ text "Select a site to view stats" ]

        Loading ->
            div [ class "loading" ] [ text "Loading..." ]

        Failure err ->
            div [ class "error" ] [ text err ]

        Success data ->
            div [ class "content" ]
                [ viewChart data.daily
                , div [ class "tables" ]
                    [ viewTopPages data.topPages
                    , viewTopRefs data.topRefs
                    ]
                ]


viewChart : List DailyCount -> Html Msg
viewChart daily =
    div [ class "chart-container" ]
        [ h2 [] [ text "Daily Views" ]
        , Chart.Visits.view daily
        ]


viewTopPages : List PageCount -> Html Msg
viewTopPages pages =
    div [ class "table-section" ]
        [ h2 [] [ text "Top Pages" ]
        , table []
            [ thead []
                [ tr []
                    [ th [ class "col-page" ] [ text "Page" ]
                    , th [ class "col-count" ] [ text "Views" ]
                    ]
                ]
            , tbody []
                (List.map
                    (\p ->
                        tr []
                            [ td [ class "col-page" ] [ text p.page ]
                            , td [ class "col-count" ] [ text (String.fromInt p.count) ]
                            ]
                    )
                    pages
                )
            ]
        ]


viewTopRefs : List RefCount -> Html Msg
viewTopRefs refs =
    div [ class "table-section" ]
        [ h2 [] [ text "Top Referrers" ]
        , table []
            [ thead []
                [ tr []
                    [ th [ class "col-page" ] [ text "Referrer" ]
                    , th [ class "col-count" ] [ text "Views" ]
                    ]
                ]
            , tbody []
                (List.map
                    (\r ->
                        tr []
                            [ td [ class "col-page" ] [ text r.page ]
                            , td [ class "col-count" ] [ text (String.fromInt r.count) ]
                            ]
                    )
                    refs
                )
            ]
        ]


viewSnippetPanel : Model -> Html Msg
viewSnippetPanel model =
    let
        siteId =
            Maybe.withDefault "your-site.com" model.selectedSite

        apiUrl =
            if String.isEmpty model.apiUrl then
                "https://YOUR-API-URL.execute-api.us-west-2.amazonaws.com/prod"

            else
                model.apiUrl

        snippet =
            "<script>\n"
                ++ "(function() {\n"
                ++ "  \"use strict\";\n"
                ++ "  var endpoint = \""
                ++ apiUrl
                ++ "/track\";\n"
                ++ "  var siteId = \""
                ++ siteId
                ++ "\";\n"
                ++ "  if (document.visibilityState === \"prerender\") return;\n"
                ++ "  var data = JSON.stringify({\n"
                ++ "    url: window.location.pathname,\n"
                ++ "    referrer: document.referrer || null,\n"
                ++ "    siteId: siteId\n"
                ++ "  });\n"
                ++ "  if (navigator.sendBeacon) {\n"
                ++ "    navigator.sendBeacon(endpoint, data);\n"
                ++ "  } else {\n"
                ++ "    var xhr = new XMLHttpRequest();\n"
                ++ "    xhr.open(\"POST\", endpoint, true);\n"
                ++ "    xhr.setRequestHeader(\"Content-Type\", \"text/plain\");\n"
                ++ "    xhr.send(data);\n"
                ++ "  }\n"
                ++ "})();\n"
                ++ "</script>"
    in
    div [ class "snippet-panel" ]
        [ h2 [] [ text "Tracker Code" ]
        , p [ class "snippet-help" ]
            [ text "Add this snippet to your site's "
            , code [] [ text "<head>" ]
            , text " or before "
            , code [] [ text "</body>" ]
            , text ":"
            ]
        , textarea
            [ class "snippet-code"
            , readonly True
            , rows 20
            , onClick NoOp
            , id "snippet-textarea"
            ]
            [ text snippet ]
        ]



-- DATE HELPERS


posixToDateString : Time.Posix -> String
posixToDateString posix =
    let
        year =
            String.fromInt (Time.toYear Time.utc posix)

        month =
            String.padLeft 2 '0' (String.fromInt (monthToInt (Time.toMonth Time.utc posix)))

        day =
            String.padLeft 2 '0' (String.fromInt (Time.toDay Time.utc posix))
    in
    year ++ "-" ++ month ++ "-" ++ day


monthToInt : Time.Month -> Int
monthToInt month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12


addDays : Int -> String -> String
addDays days dateStr =
    -- Simple date arithmetic for YYYY-MM-DD strings
    case String.split "-" dateStr of
        [ yearStr, monthStr, dayStr ] ->
            let
                year =
                    Maybe.withDefault 2026 (String.toInt yearStr)

                month =
                    Maybe.withDefault 1 (String.toInt monthStr)

                day =
                    Maybe.withDefault 1 (String.toInt dayStr)

                totalDays =
                    toDayNumber year month day + days

                ( newYear, newMonth, newDay ) =
                    fromDayNumber totalDays
            in
            String.fromInt newYear
                ++ "-"
                ++ String.padLeft 2 '0' (String.fromInt newMonth)
                ++ "-"
                ++ String.padLeft 2 '0' (String.fromInt newDay)

        _ ->
            dateStr


toDayNumber : Int -> Int -> Int -> Int
toDayNumber y m d =
    let
        y1 =
            if m <= 2 then
                y - 1

            else
                y

        m1 =
            if m <= 2 then
                m + 9

            else
                m - 3
    in
    365 * y1 + y1 // 4 - y1 // 100 + y1 // 400 + (m1 * 306 + 5) // 10 + d - 1


fromDayNumber : Int -> ( Int, Int, Int )
fromDayNumber g =
    let
        y =
            (10000 * g + 14780) // 3652425

        doy =
            g - (365 * y + y // 4 - y // 100 + y // 400)

        ( y2, doy2 ) =
            if doy < 0 then
                let
                    yy =
                        y - 1
                in
                ( yy, g - (365 * yy + yy // 4 - yy // 100 + yy // 400) )

            else
                ( y, doy )

        mi =
            (100 * doy2 + 52) // 3060

        month =
            mi + 3 - 12 * (mi // 10)

        year =
            y2 + mi // 10

        day =
            doy2 - (mi * 306 + 5) // 10 + 1
    in
    ( year, month, day )
