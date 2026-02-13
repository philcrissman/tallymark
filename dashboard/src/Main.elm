module Main exposing (main)

import Api exposing (DailyCount, PageCount, RefCount, StatsData, fetchStats)
import Browser
import Chart.Visits
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Http


type alias Flags =
    { apiUrl : String
    }


type alias Model =
    { apiUrl : String
    , startDate : String
    , endDate : String
    , stats : RemoteData StatsData
    }


type RemoteData a
    = Loading
    | Failure String
    | Success a


type Msg
    = GotStats (Result Http.Error StatsData)
    | StartDateChanged String
    | EndDateChanged String
    | QuickSelect String String
    | Refresh


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
        -- Default to last 14 days
        startDate =
            "2026-01-30"

        endDate =
            "2026-02-13"
    in
    ( { apiUrl = flags.apiUrl
      , startDate = startDate
      , endDate = endDate
      , stats = Loading
      }
    , fetchStats flags.apiUrl startDate endDate GotStats
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotStats result ->
            case result of
                Ok data ->
                    ( { model | stats = Success data }, Cmd.none )

                Err err ->
                    ( { model | stats = Failure (httpErrorToString err) }, Cmd.none )

        StartDateChanged date ->
            let
                newModel =
                    { model | startDate = date }
            in
            ( newModel, fetchStats model.apiUrl date model.endDate GotStats )

        EndDateChanged date ->
            let
                newModel =
                    { model | endDate = date }
            in
            ( newModel, fetchStats model.apiUrl model.startDate date GotStats )

        QuickSelect start end ->
            ( { model | startDate = start, endDate = end, stats = Loading }
            , fetchStats model.apiUrl start end GotStats
            )

        Refresh ->
            ( { model | stats = Loading }
            , fetchStats model.apiUrl model.startDate model.endDate GotStats
            )


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


view : Model -> Html Msg
view model =
    div [ class "dashboard" ]
        [ viewHeader model
        , viewDateControls model
        , viewBody model
        ]


viewHeader : Model -> Html Msg
viewHeader model =
    header [ class "header" ]
        [ h1 [] [ text "Analytics" ]
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
            [ button [ onClick (QuickSelect "2026-02-06" "2026-02-13") ] [ text "7d" ]
            , button [ onClick (QuickSelect "2026-01-14" "2026-02-13") ] [ text "30d" ]
            , button [ onClick (QuickSelect "2026-01-01" "2026-12-31") ] [ text "All" ]
            , button [ onClick Refresh ] [ text "Refresh" ]
            ]
        ]


viewBody : Model -> Html Msg
viewBody model =
    case model.stats of
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
