module Chart.Visits exposing (view)

import Api exposing (DailyCount)
import Chart as C
import Chart.Attributes as CA
import Html exposing (Html)


type alias DataPoint =
    { x : Float
    , y : Float
    , label : String
    }


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


view : List DailyCount -> Html msg
view daily =
    let
        points =
            toDataPoints daily
    in
    C.chart
        [ CA.height 250
        , CA.width 800
        , CA.padding { top = 10, bottom = 0, left = 0, right = 20 }
        , CA.margin { top = 10, bottom = 30, left = 40, right = 10 }
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
        ]


labelForIndex : Int -> List DailyCount -> String
labelForIndex idx daily =
    case List.drop idx daily of
        d :: _ ->
            -- Show just month-day: "02-09"
            String.right 5 d.date

        [] ->
            ""
