module State exposing
    ( getFormFieldState
    , init
    , subscriptions
    , update
    )

import Browser.Dom as Dom
import Dict exposing (Dict)
import Email
import Http
import Task
import Types exposing (..)


init : ( Model, Cmd Msg )
init =
    ( { swagForm = Dict.empty
      }
      -- We also need to focus the first form field here
      -- setting 'autofocus' on the input is not sufficient:
      -- It blurs when the content is hydrated.
    , Dom.focus "FIRSTNAME" |> Task.attempt (\_ -> FocusedForm)
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnFormFieldInput { id, value } ->
            ( { model
                | swagForm =
                    model.swagForm
                        |> Dict.update id
                            (Maybe.withDefault formFieldInit
                                >> updateFieldValue value
                                >> Just
                            )
              }
            , Cmd.none
            )

        OnFormFieldBlur { id } ->
            ( { model
                | swagForm =
                    model.swagForm
                        |> Dict.update id
                            (Maybe.withDefault formFieldInit
                                >> updateFieldBlur
                                >> Just
                            )
              }
            , Cmd.none
            )

        OnFormSubmit { submissionUrl } ->
            ( model
            , Http.post
                { url = submissionUrl
                , body =
                    Http.multipartBody
                        (List.append
                            (model.swagForm
                                |> Dict.toList
                                |> List.map formFieldSubmissionPart
                            )
                            [ Http.stringPart "html_type" "simple"
                            , Http.stringPart "locale" "en"
                            ]
                        )
                , expect =
                    Http.expectWhatever GotFormSubmissionResponse
                }
            )

        GotFormSubmissionResponse response ->
            -- TODO handle errors
            -- TODO handle success: show 'thank you'
            ( { model | swagForm = clearFields model.swagForm }
            , Cmd.none
            )

        FocusedForm ->
            ( model, Cmd.none )


formFieldInit : FormField
formFieldInit =
    { value = ""
    , error = Nothing
    }


formFieldSubmissionPart : ( String, FormField ) -> Http.Part
formFieldSubmissionPart ( fieldId, { value } ) =
    Http.stringPart fieldId value


updateFieldValue : String -> FormField -> FormField
updateFieldValue value formField =
    { formField | value = value }


updateFieldBlur : FormField -> FormField
updateFieldBlur formField =
    { formField
        | error = Nothing
    }


clearFields : Dict String FormField -> Dict String FormField
clearFields fields =
    fields
        |> Dict.map (\_ _ -> formFieldInit)


getFormFieldState :
    Model
    -> String
    ->
        { value : String
        , error : Maybe { id : String, description : String }
        , onInput : String -> Msg
        , onBlur : Msg
        }
getFormFieldState model fieldId =
    let
        formFieldModel =
            model.swagForm
                |> Dict.get fieldId
                |> Maybe.withDefault formFieldInit
    in
    { value = formFieldModel.value
    , error = formFieldModel.error
    , onInput = \value -> OnFormFieldInput { id = fieldId, value = value }
    , onBlur = OnFormFieldBlur { id = fieldId }
    }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none
