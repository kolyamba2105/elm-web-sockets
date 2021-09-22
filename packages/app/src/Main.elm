port module Main exposing (..)

import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as D
import Json.Encode as E
import List
import String
import Tuple exposing (mapFirst, pair)



---- INITIAL CONFIG ----


type InitialConfig
    = Presenter (List Technology)
    | Participant


initialConfigToString : InitialConfig -> String
initialConfigToString config =
    case config of
        Presenter technologies ->
            "I am a Presenter! Here is a list of available technologies: "
                ++ String.join ", " (List.map technologyToString technologies)

        Participant ->
            "I am just a Participant!"


initialConfigDecoder : D.Decoder InitialConfig
initialConfigDecoder =
    D.oneOf
        [ D.map2
            (always Presenter)
            (D.field "role" (stringLiteral "Presenter"))
            (D.field "preferences" (D.list technologyDecoder))
        , D.map
            (always Participant)
            (D.field "role" (stringLiteral "Participant"))
        ]


type Technology
    = WebRTC
    | VNC


technologyToString : Technology -> String
technologyToString technology =
    case technology of
        WebRTC ->
            "WebRTC"

        VNC ->
            "VNC"


technologyDecoder : D.Decoder Technology
technologyDecoder =
    D.oneOf
        [ D.map (always WebRTC) (stringLiteral "WebRTC")
        , D.map (always VNC) (stringLiteral "VNC")
        ]



---- CONNECTION ----


type ConnectionConfig
    = WebRTCConfig Bool
    | VNCConfig (Maybe Bool)


isWebRTCConfig : ConnectionConfig -> Bool
isWebRTCConfig config =
    case config of
        WebRTCConfig _ ->
            True

        _ ->
            False


connectionConfigDecoder : D.Decoder ConnectionConfig
connectionConfigDecoder =
    D.oneOf
        [ D.map2
            (always WebRTCConfig)
            (D.field "technology" (stringLiteral "WebRTC"))
            (D.field "isConnected" D.bool)
        , D.map3
            (always pair)
            (D.field "technology" (stringLiteral "VNC"))
            (D.field "isConnected" D.bool)
            (D.field "isMobile" (D.nullable D.bool))
            |> D.andThen
                (\( isConnected, isMobile ) ->
                    case ( isConnected, isMobile ) of
                        ( True, Just a ) ->
                            D.succeed <| VNCConfig <| Just a

                        ( False, Nothing ) ->
                            D.succeed <| VNCConfig Nothing

                        _ ->
                            D.fail "Could not parse VNCResponse!"
                )
        ]


type alias Connection =
    { config : RemoteData ConnectionConfig
    , attempt : Int
    }


initConnection : Connection
initConnection =
    Connection Initial 0



---- TRANSMISSION ----


type TransmisionSource
    = Screen String String
    | Window String String
    | Mobile


isScreen : TransmisionSource -> Bool
isScreen source =
    case source of
        Screen _ _ ->
            True

        _ ->
            False


isWindow : TransmisionSource -> Bool
isWindow source =
    case source of
        Window _ _ ->
            True

        _ ->
            False


transmissionSourceToString : TransmisionSource -> String
transmissionSourceToString source =
    case source of
        Screen id name ->
            "[Screen] " ++ id ++ " - " ++ name

        Window id name ->
            "[Window] " ++ id ++ " - " ++ name

        Mobile ->
            "Mobile display"


transmissionSourceDecoder : D.Decoder TransmisionSource
transmissionSourceDecoder =
    D.oneOf
        [ D.map3
            (\source ->
                if source == "Screen" then
                    Screen

                else
                    Window
            )
            (D.field "label" <|
                D.oneOf
                    [ stringLiteral "Screen"
                    , stringLiteral "Window"
                    ]
            )
            (D.field "id" D.string)
            (D.field "name" D.string)
        , D.map
            (always Mobile)
            (D.field "label" <| stringLiteral "Mobile")
        ]


transmissionSourceEncoder : TransmisionSource -> E.Value
transmissionSourceEncoder source =
    case source of
        Screen id name ->
            E.object [ ( "label", E.string "Screen" ), ( "id", E.string id ), ( "name", E.string name ) ]

        Window id name ->
            E.object [ ( "label", E.string "Window" ), ( "id", E.string id ), ( "name", E.string name ) ]

        Mobile ->
            E.object [ ( "label", E.string "Mobile" ) ]


type TransmissionState
    = Live TransmisionSource
    | Paused TransmisionSource
    | ShutDown


transmissionStateDecoder : D.Decoder TransmissionState
transmissionStateDecoder =
    D.map2
        (\status source ->
            case status of
                "Live" ->
                    Live source

                "Paused" ->
                    Paused source

                _ ->
                    ShutDown
        )
        (D.field "status" <|
            D.oneOf
                [ stringLiteral "Live"
                , stringLiteral "Paused"
                , stringLiteral "ShutDown"
                ]
        )
        (D.field "source" transmissionSourceDecoder)


type ModalTab
    = ScreenTab
    | WindowTab


type alias Transmission =
    { state : TransmissionState
    , selectedSource : Maybe TransmisionSource
    , modalState : Maybe ModalTab
    }


initTransmission : Transmission
initTransmission =
    Transmission ShutDown Nothing Nothing



---- STRING LITERAL DECODER ----


stringLiteral : String -> D.Decoder String
stringLiteral literal =
    D.string
        |> D.andThen
            (\s ->
                if s == literal then
                    D.succeed s

                else
                    D.fail <| "Provided string value is not equal to " ++ literal ++ "!"
            )



---- REMOTE DATA ----


type RemoteData a
    = Initial
    | Pending
    | Success a
    | Failure String



---- MODEL ----


type alias Model =
    { config : RemoteData InitialConfig
    , connection : Connection
    , transmission : Transmission
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( Model Initial initConnection initTransmission
    , Cmd.none
    )



---- UPDATE ----


type Msg
    = ChangeTab ModalTab
    | CloseModal
    | CreateConnection (List Technology)
    | DropConnection
    | GotCreateConnectionResponse E.Value
    | GotDropConnectionResponse E.Value
    | GotInitialConfig E.Value
    | GotStartTransmissionResponse E.Value
    | GotTransmissionState E.Value
    | OpenModal ModalTab
    | SelectTransmissionSource TransmisionSource
    | StartTransmission
    | ToggleTransmissionState


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotCreateConnectionResponse response ->
            let
                { connection, transmission } =
                    model
            in
            case Debug.log "" (D.decodeValue connectionConfigDecoder response) of
                Ok config ->
                    let
                        onSuccess =
                            ( { model
                                | connection =
                                    { connection
                                        | config = Success config
                                        , attempt = 0
                                    }
                              }
                            , Cmd.none
                            )

                        onFailure =
                            case model.config of
                                Success (Presenter technologies) ->
                                    update
                                        (CreateConnection <| List.drop (model.connection.attempt + 1) technologies)
                                        { model
                                            | connection =
                                                { connection
                                                    | config = Failure <| "Error - Cannot start screen sharing session!"
                                                    , attempt = connection.attempt + 1
                                                }
                                        }

                                _ ->
                                    ( model, Cmd.none )
                    in
                    case config of
                        WebRTCConfig True ->
                            onSuccess

                        WebRTCConfig False ->
                            onFailure

                        VNCConfig (Just True) ->
                            onSuccess
                                |> mapFirst (\m -> { m | transmission = { transmission | state = Live Mobile } })

                        VNCConfig (Just False) ->
                            onSuccess

                        VNCConfig Nothing ->
                            onFailure

                Err message ->
                    ( { model
                        | connection =
                            { connection
                                | config = Failure <| D.errorToString message
                            }
                      }
                    , Cmd.none
                    )

        GotStartTransmissionResponse _ ->
            let
                { transmission } =
                    model
            in
            case transmission.selectedSource of
                Just source ->
                    ( { model
                        | transmission =
                            { transmission
                                | state = Live source
                                , modalState = Nothing
                            }
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        GotDropConnectionResponse _ ->
            ( { model | connection = initConnection, transmission = initTransmission }
            , Cmd.none
            )

        GotInitialConfig value ->
            ( case D.decodeValue initialConfigDecoder value of
                Ok config ->
                    { model | config = Success config }

                Err error ->
                    { model | config = Failure <| D.errorToString error }
            , Cmd.none
            )

        CreateConnection technologies ->
            let
                { connection } =
                    model
            in
            technologies
                |> List.head
                |> Maybe.map
                    (\tech ->
                        ( { model | connection = { connection | config = Pending } }
                        , createConnection <| technologyToString <| tech
                        )
                    )
                |> Maybe.withDefault ( model, Cmd.none )

        DropConnection ->
            let
                { connection } =
                    model
            in
            ( { model | connection = { connection | config = Pending } }
            , dropConnection ()
            )

        OpenModal currentTab ->
            let
                { transmission } =
                    model
            in
            ( { model | transmission = { transmission | modalState = Just currentTab } }, Cmd.none )

        CloseModal ->
            let
                { transmission } =
                    model
            in
            case ( transmission.state, transmission.selectedSource ) of
                ( Live current, Just _ ) ->
                    ( { model
                        | transmission =
                            { transmission
                                | modalState = Nothing
                                , selectedSource = Just current
                            }
                      }
                    , Cmd.none
                    )

                ( Paused current, Just _ ) ->
                    ( { model
                        | transmission =
                            { transmission
                                | modalState = Nothing
                                , selectedSource = Just current
                            }
                      }
                    , Cmd.none
                    )

                ( ShutDown, Just _ ) ->
                    ( { model
                        | transmission =
                            { transmission
                                | modalState = Nothing
                                , selectedSource = Nothing
                            }
                      }
                    , Cmd.none
                    )

                _ ->
                    ( { model
                        | transmission =
                            { transmission
                                | modalState = Nothing
                            }
                      }
                    , Cmd.none
                    )

        ChangeTab tab ->
            let
                { transmission } =
                    model
            in
            ( { model | transmission = { transmission | modalState = Just tab } }, Cmd.none )

        SelectTransmissionSource source ->
            let
                { transmission } =
                    model
            in
            ( { model | transmission = { transmission | selectedSource = Just source } }, Cmd.none )

        StartTransmission ->
            let
                { connection, transmission } =
                    model
            in
            case connection.config of
                Success (WebRTCConfig True) ->
                    let
                        onLiveOrPaused current selected =
                            if current == selected then
                                ( { model
                                    | transmission =
                                        { transmission
                                            | modalState = Nothing
                                        }
                                  }
                                , Cmd.none
                                )

                            else
                                ( { model
                                    | transmission =
                                        { transmission
                                            | modalState = Nothing
                                            , state = Live selected
                                        }
                                  }
                                , Cmd.none
                                )
                    in
                    case ( transmission.state, transmission.selectedSource ) of
                        ( Live current, Just selected ) ->
                            onLiveOrPaused current selected

                        ( Paused current, Just selected ) ->
                            onLiveOrPaused current selected

                        ( ShutDown, Just selected ) ->
                            ( { model
                                | transmission =
                                    { transmission
                                        | modalState = Nothing
                                        , state = Live selected
                                    }
                              }
                            , Cmd.none
                            )

                        _ ->
                            ( model, Cmd.none )

                Success (VNCConfig (Just False)) ->
                    let
                        onLiveOrPaused current selected =
                            if current == selected then
                                ( { model
                                    | transmission =
                                        { transmission
                                            | modalState = Nothing
                                        }
                                  }
                                , Cmd.none
                                )

                            else
                                ( model, startTransmission <| transmissionSourceEncoder <| selected )
                    in
                    case ( transmission.state, transmission.selectedSource ) of
                        ( Live current, Just selected ) ->
                            onLiveOrPaused current selected

                        ( Paused current, Just selected ) ->
                            onLiveOrPaused current selected

                        ( ShutDown, Just selected ) ->
                            ( model, startTransmission <| transmissionSourceEncoder <| selected )

                        _ ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ToggleTransmissionState ->
            case model.transmission.state of
                Live source ->
                    ( model, pauseTransmission <| transmissionSourceEncoder <| source )

                Paused source ->
                    ( model, resumeTransmission <| transmissionSourceEncoder <| source )

                _ ->
                    ( model, Cmd.none )

        GotTransmissionState value ->
            let
                { config, transmission } =
                    model
            in
            case ( D.decodeValue transmissionStateDecoder value, config ) of
                ( Ok state, Success (Presenter _) ) ->
                    ( { model
                        | transmission =
                            { transmission
                                | state = state
                                , modalState = Nothing
                            }
                      }
                    , Cmd.none
                    )

                ( Ok state, Success Participant ) ->
                    ( { model
                        | transmission =
                            { transmission
                                | state = state
                            }
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )



---- VIEW ----


view : Model -> Html Msg
view model =
    div [ class "app-container" ] <|
        case model.config of
            Initial ->
                []

            Pending ->
                [ p [] [ text "Loading..." ] ]

            Success config ->
                h3 [] [ text <| initialConfigToString config ]
                    :: (case config of
                            Presenter technologies ->
                                List.append
                                    [ connectionButton model.connection.config technologies
                                    , connectionStatus model.connection.config
                                    ]
                                    (case model.connection.config of
                                        Success status ->
                                            List.append
                                                (case status of
                                                    VNCConfig (Just False) ->
                                                        [ transmissionCanvas model.transmission.state False
                                                        , div []
                                                            [ openModalButton ScreenTab
                                                            , openModalButton WindowTab
                                                            ]
                                                        ]

                                                    VNCConfig (Just True) ->
                                                        [ transmissionCanvas model.transmission.state False ]

                                                    WebRTCConfig True ->
                                                        [ transmissionCanvas model.transmission.state False
                                                        , openModalButton ScreenTab
                                                        ]

                                                    _ ->
                                                        []
                                                )
                                                [ model.transmission.modalState
                                                    |> Maybe.map (modal model.transmission.selectedSource status)
                                                    |> Maybe.withDefault null
                                                ]

                                        _ ->
                                            []
                                    )

                            Participant ->
                                [ transmissionCanvas model.transmission.state True ]
                       )

            Failure errorMsg ->
                [ p [] [ text errorMsg ] ]


connectionButton : RemoteData ConnectionConfig -> List Technology -> Html Msg
connectionButton response technologies =
    let
        ( label, action ) =
            case response of
                Success _ ->
                    ( "Drop connection", DropConnection )

                _ ->
                    ( "Create connection", CreateConnection technologies )
    in
    button [ onClick action ] [ text label ]


connectionStatus : RemoteData screenSharingResponse -> Html Msg
connectionStatus response =
    case response of
        Initial ->
            null

        Pending ->
            p [] [ text "Loading..." ]

        Success _ ->
            p [] [ text "Connection established!" ]

        Failure error ->
            p [] [ text error ]


openModalButton : ModalTab -> Html Msg
openModalButton tab =
    let
        label =
            case tab of
                WindowTab ->
                    "Select window"

                ScreenTab ->
                    "Select screen"
    in
    button [ onClick <| OpenModal tab ] [ text label ]


transmissionCanvas : TransmissionState -> Bool -> Html Msg
transmissionCanvas state isParticipant =
    case state of
        ShutDown ->
            null

        Live source ->
            div [ id "canvas-container" ]
                [ canvas [] []
                , div [ id "canvas-overlay" ]
                    [ p [] [ text <| "LIVE " ++ transmissionSourceToString source ]
                    , if isParticipant then
                        null

                      else
                        button [ onClick ToggleTransmissionState ] [ text "Pause" ]
                    ]
                ]

        Paused source ->
            div [ id "canvas-container" ]
                [ canvas [] []
                , div [ id "canvas-overlay" ]
                    [ p [] [ text <| "PAUSED " ++ transmissionSourceToString source ]
                    , if isParticipant then
                        null

                      else
                        button [ onClick ToggleTransmissionState ] [ text "Resume" ]
                    ]
                ]


modal : Maybe TransmisionSource -> ConnectionConfig -> ModalTab -> Html Msg
modal selectedSource config activeTab =
    let
        sources =
            List.append
                [ Screen "1" "First"
                , Screen "2" "Second"
                ]
                [ Window "1" "First"
                , Window "2" "Second"
                ]
                |> List.filter
                    (\source ->
                        case activeTab of
                            ScreenTab ->
                                isScreen source

                            WindowTab ->
                                isWindow source
                    )
                |> List.map
                    (\source ->
                        div []
                            [ input
                                [ type_ "radio"
                                , onClick <| SelectTransmissionSource source
                                , checked <| Maybe.withDefault False <| Maybe.map (\s -> s == source) <| selectedSource
                                ]
                                []
                            , label [] [ text <| transmissionSourceToString source ]
                            ]
                    )
    in
    div [ class "modal-container" ]
        [ div [ class "modal" ]
            [ div [ class "modal__tabs" ]
                [ modalTab { tab = ScreenTab, isActive = ScreenTab == activeTab, disabled = False }
                , modalTab { tab = WindowTab, isActive = WindowTab == activeTab, disabled = isWebRTCConfig config }
                ]
            , div [ class "modal__body" ] [ div [] sources ]
            , div [ class "modal__footer" ]
                [ selectedSource
                    |> Maybe.map (always <| button [ type_ "button", onClick StartTransmission ] [ text "Apply" ])
                    |> Maybe.withDefault null
                , button [ type_ "button", onClick CloseModal ] [ text "Close" ]
                ]
            ]
        ]


modalTab : { tab : ModalTab, isActive : Bool, disabled : Bool } -> Html Msg
modalTab config =
    let
        label =
            case config.tab of
                ScreenTab ->
                    "Screens"

                WindowTab ->
                    "Windows"
    in
    button
        [ class <|
            className
                [ "modal__tab"
                , if config.isActive then
                    "modal__tab--active"

                  else
                    ""
                ]
        , disabled config.disabled
        , onClick <| ChangeTab config.tab
        ]
        [ text label ]


null : Html msg
null =
    text ""


className : List String -> String
className =
    List.map String.trim >> String.join " "



---- SUBS ----


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ getInitialConfig GotInitialConfig
        , getCreateConnectionResponse GotCreateConnectionResponse
        , getDropConnectionResponse GotDropConnectionResponse
        , getTransmissionState GotTransmissionState
        ]



---- PORTS ----


port getInitialConfig : (E.Value -> msg) -> Sub msg


port createConnection : String -> Cmd msg


port getCreateConnectionResponse : (E.Value -> msg) -> Sub msg


port dropConnection : () -> Cmd msg


port getDropConnectionResponse : (E.Value -> msg) -> Sub msg


port startTransmission : E.Value -> Cmd msg


port pauseTransmission : E.Value -> Cmd msg


port resumeTransmission : E.Value -> Cmd msg


port getTransmissionState : (E.Value -> msg) -> Sub msg



---- PROGRAM ----


main : Program () Model Msg
main =
    Browser.element
        { view = view
        , init = init
        , update = update
        , subscriptions = subscriptions
        }
