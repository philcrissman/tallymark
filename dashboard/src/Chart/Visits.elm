module Chart.Visits exposing (Hovering, init, view)

import Api exposing (DailyCount)
import Chart as C
import Chart.Attributes as CA
import Chart.Events as CE
import Chart.Item as CI
import Html exposing (Html)


type alias DataPoint =
    { x : Float
    , y : Float
    , label : String
    }


type alias Hovering =
    List (CI.One DataPoint CI.Dot)


init : Hovering
init =
    []


toDataPoints : List DailyCount -> List DataPoint
toDataPoints daily =
    List.indexedMap
        (\i d ->
            { x = toFloat i
            , y = toFloat d.count
            , label = d.date
            }
        )
        daily


view : (Hovering -> msg) -> Hovering -> List DailyCount -> Html msg
view onHover hovering daily =
    let
        points =
            toDataPoints daily
    in
    C.chart
        [ CA.height 250
        , CA.width 800
        , CA.padding { top = 10, bottom = 0, left = 0, right = 20 }
        , CA.margin { top = 10, bottom = 30, left = 40, right = 10 }
        , CE.onMouseMove onHover (CE.getNearest CI.dots)
        , CE.onMouseLeave (onHover [])
        ]
        [ C.yAxis []
        , C.yTicks [ CA.amount 5 ]
        , C.yLabels [ CA.amount 5 ]
        , C.xLabels
            [ CA.amount (min 10 (List.length points))
            , CA.format (\v -> labelForIndex (round v) daily)
            ]
        , C.grid []
        , C.series .x
            [ C.interpolated .y
                [ CA.monotone, CA.color CA.blue, CA.opacity 0.8 ]
                [ CA.circle, CA.size 4, CA.color CA.blue ]
            ]
            points
        , C.each hovering
            (\plane dot ->
                [ C.tooltip dot
                    []
                    []
                    [ Html.text (CI.getData dot).label
                    , Html.text ": "
                    , Html.text (String.fromInt (round (CI.getY dot)))
                    , Html.text " views"
                    ]
                ]
            )
        ]


labelForIndex : Int -> List DailyCount -> String
labelForIndex idx daily =
    case List.drop idx daily of
        d :: _ ->
            -- Show just month-day: "02-09"
            String.right 5 d.date

        [] ->
            ""
