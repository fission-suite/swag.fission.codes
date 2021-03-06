{-
   This module multiplexes between the various views according
   to the frontmatter.
-}


module View exposing (yamlDocument)

import Browser.Dom as Dom
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes exposing (action, autofocus, method, name, type_, value)
import Html.Extra as Html
import Json.Decode
import Metadata exposing (Frontmatter)
import Pages.Manifest as Manifest
import Pages.StaticHttp as StaticHttp
import Result.Extra as Result
import State
import Types exposing (..)
import Validate
import View.SwagForm
import Yaml.Decode as Yaml
import Yaml.Extra as Yaml


yamlDocument :
    { extension : String
    , metadata : Json.Decode.Decoder Frontmatter
    , body : String -> Result String (Model -> Html Msg)
    }
yamlDocument =
    { extension = "yml"
    , metadata = Metadata.decoder
    , body =
        \body ->
            Yaml.fromString decodeData body
                |> Result.mapError Yaml.errorToString
                |> Result.map view
    }



-- DATA DEFINITIONS


type alias Data =
    { hero : HeroData
    , form : FormData
    }


type alias HeroData =
    { message : List (Html Msg)
    }


type alias FormData =
    { submissionUrl : String
    , submitButton : SubmitButtonData
    , autofocus : String
    , fields : List FieldData
    }


type FieldData
    = InputField
        { id : String
        , title : String
        , column : { start : View.SwagForm.Alignment, end : View.SwagForm.Alignment }
        , description : Maybe String
        , validation : String -> FieldErrorState
        }
    | CheckboxField
        { id : String
        , column : { start : View.SwagForm.Alignment, end : View.SwagForm.Alignment }
        , description : String
        , requireChecked : Maybe String
        }


type alias SubmitButtonData =
    { waiting : String
    , submitting : String
    , error : String
    , submitted : String
    }



-- VIEWS


view : Data -> Model -> Html Msg
view data model =
    View.SwagForm.swagPage
        { hero = data.hero.message
        , form =
            -- The hidden inputs and method + action attributes make it possible to submit with javascript turned off
            { attributes =
                [ method "POST"
                , action data.form.submissionUrl
                ]
            , onSubmit =
                OnFormSubmit
                    { submissionUrl = data.form.submissionUrl
                    , fields = data.form.fields |> List.map extractFieldInfo
                    }
            , content =
                List.concat
                    [ [ Html.input [ type_ "hidden", name "locale", value "en" ] []
                      , Html.input [ type_ "hidden", name "html_type", value "simple" ] []
                      ]
                    , List.map (viewField model data.form.autofocus) data.form.fields
                    , [ View.SwagForm.submitButton
                            { attributes = []
                            , message =
                                case model.submissionStatus of
                                    Waiting ->
                                        data.form.submitButton.waiting

                                    Submitting ->
                                        data.form.submitButton.submitting

                                    Error ->
                                        data.form.submitButton.error

                                    Submitted ->
                                        data.form.submitButton.submitted
                            }
                      ]
                    ]
            }
        }


viewField : Model -> String -> FieldData -> Html Msg
viewField model autofocusId field =
    case field of
        InputField { id, title, column, description, validation } ->
            View.SwagForm.textInput
                { attributes =
                    [ autofocus (id == autofocusId)
                    , name id
                    ]
                , column = column
                , id = id
                , title = title
                , description =
                    case description of
                        Just text ->
                            View.SwagForm.helpDescription [] text

                        Nothing ->
                            Html.nothing
                }
                (State.getFormFieldState model id validation)

        CheckboxField { id, column, description } ->
            View.SwagForm.checkbox
                { id = id
                , column = column
                , description = View.SwagForm.checkboxDescription description
                }
                (State.getCheckboxState model id)


extractFieldInfo : FieldData -> FieldDataInfo
extractFieldInfo fieldData =
    case fieldData of
        InputField field ->
            FieldInfoInput { id = field.id, validate = field.validation }

        CheckboxField field ->
            FieldInfoCheckbox { id = field.id, requireChecked = field.requireChecked }



-- DECODERS


decodeData : Yaml.Decoder Data
decodeData =
    Yaml.succeed Data
        |> Yaml.andMap (Yaml.field "hero" decodeHeroData)
        |> Yaml.andMap (Yaml.field "form" decodeFormData)


decodeHeroData : Yaml.Decoder HeroData
decodeHeroData =
    Yaml.succeed HeroData
        |> Yaml.andMap (Yaml.field "message" Yaml.markdownString)


decodeFormData : Yaml.Decoder FormData
decodeFormData =
    Yaml.succeed FormData
        |> Yaml.andMap (Yaml.field "submission_url" Yaml.string)
        |> Yaml.andMap (Yaml.field "submit_button" submitButtonData)
        |> Yaml.andMap (Yaml.field "autofocus" Yaml.string)
        |> Yaml.andMap (Yaml.field "fields" (Yaml.list decodeFieldData))


submitButtonData : Yaml.Decoder SubmitButtonData
submitButtonData =
    Yaml.succeed SubmitButtonData
        |> Yaml.andMap (Yaml.field "waiting" Yaml.string)
        |> Yaml.andMap (Yaml.field "submitting" Yaml.string)
        |> Yaml.andMap (Yaml.field "error" Yaml.string)
        |> Yaml.andMap (Yaml.field "submitted" Yaml.string)


decodeFieldData : Yaml.Decoder FieldData
decodeFieldData =
    -- Let's hope this style gets fixed in elm-format 1.0.0
    Yaml.field "type" Yaml.string
        |> Yaml.andThen
            (\type_ ->
                case type_ of
                    "text" ->
                        decodeInputField
                            |> Yaml.map InputField

                    "checkbox" ->
                        decodeCheckboxField
                            |> Yaml.map CheckboxField

                    _ ->
                        Yaml.fail "The 'type' field must be either 'text' or 'checkbox'"
            )


decodeInputField :
    Yaml.Decoder
        { id : String
        , title : String
        , column : { start : View.SwagForm.Alignment, end : View.SwagForm.Alignment }
        , description : Maybe String
        , validation : String -> FieldErrorState
        }
decodeInputField =
    Yaml.field "id" Yaml.string
        |> Yaml.andThen
            (\id ->
                Yaml.field "title" Yaml.string
                    |> Yaml.andThen
                        (\title ->
                            decodeSubtext
                                |> Yaml.andThen
                                    (\description ->
                                        decodeColumn
                                            |> Yaml.andThen
                                                (\column ->
                                                    Yaml.field "validation" decodeValidation
                                                        |> Yaml.map
                                                            (\validation ->
                                                                { id = id
                                                                , title = title
                                                                , column = column
                                                                , description = description
                                                                , validation = validation
                                                                }
                                                            )
                                                )
                                    )
                        )
            )


decodeCheckboxField :
    Yaml.Decoder
        { id : String
        , column : { start : View.SwagForm.Alignment, end : View.SwagForm.Alignment }
        , description : String
        , requireChecked : Maybe String
        }
decodeCheckboxField =
    Yaml.field "id" Yaml.string
        |> Yaml.andThen
            (\id ->
                decodeColumn
                    |> Yaml.andThen
                        (\column ->
                            Yaml.field "description" Yaml.string
                                |> Yaml.andThen
                                    (\description ->
                                        Yaml.field "require_checked"
                                            (Yaml.oneOf
                                                [ Yaml.string |> Yaml.map Just
                                                , Yaml.bool
                                                    |> Yaml.andThen
                                                        (\isRequired ->
                                                            if isRequired then
                                                                Yaml.fail ""

                                                            else
                                                                Yaml.succeed Nothing
                                                        )
                                                , Yaml.fail "requireChecked must be either false or a string containing an error message"
                                                ]
                                            )
                                            |> Yaml.map
                                                (\requireChecked ->
                                                    { id = id
                                                    , column = column
                                                    , description = description
                                                    , requireChecked = requireChecked
                                                    }
                                                )
                                    )
                        )
            )


decodeColumn : Yaml.Decoder { start : View.SwagForm.Alignment, end : View.SwagForm.Alignment }
decodeColumn =
    Yaml.succeed (\start end -> { start = start, end = end })
        |> Yaml.andMap (Yaml.field "column_start" decodeAlignment)
        |> Yaml.andMap (Yaml.field "column_end" decodeAlignment)


decodeSubtext : Yaml.Decoder (Maybe String)
decodeSubtext =
    Yaml.oneOf
        [ Yaml.field "description" (Yaml.map Just Yaml.string)
        , Yaml.succeed Nothing
        ]


decodeAlignment : Yaml.Decoder View.SwagForm.Alignment
decodeAlignment =
    let
        errorText =
            "This value must be a number between 1 and 8, or 'first', 'last' or 'middle'."
    in
    Yaml.oneOf
        [ Yaml.int
            |> Yaml.andThen
                (\col ->
                    case col of
                        1 ->
                            Yaml.succeed View.SwagForm.First

                        2 ->
                            Yaml.succeed View.SwagForm.Column2

                        3 ->
                            Yaml.succeed View.SwagForm.Column3

                        4 ->
                            Yaml.succeed View.SwagForm.Column4

                        5 ->
                            Yaml.succeed View.SwagForm.Column5

                        6 ->
                            Yaml.succeed View.SwagForm.Column6

                        7 ->
                            Yaml.succeed View.SwagForm.Column7

                        8 ->
                            Yaml.succeed View.SwagForm.Last

                        _ ->
                            Yaml.fail errorText
                )
        , Yaml.string
            |> Yaml.andThen
                (\str ->
                    case str of
                        "first" ->
                            Yaml.succeed View.SwagForm.First

                        "middle" ->
                            Yaml.succeed View.SwagForm.Middle

                        "last" ->
                            Yaml.succeed View.SwagForm.Last

                        _ ->
                            Yaml.fail errorText
                )
        , Yaml.fail errorText
        ]


decodeValidation : Yaml.Decoder (String -> FieldErrorState)
decodeValidation =
    Yaml.list decodeValidationItem |> Yaml.map Validate.all


decodeValidationItem : Yaml.Decoder (String -> FieldErrorState)
decodeValidationItem =
    let
        errorText =
            "Invalid validation test. Only 'email' and 'filled' are available at the moment."
    in
    Yaml.oneOf
        [ decodeValidationFilled
        , Yaml.string
            |> Yaml.andThen
                (\str ->
                    case str of
                        "email" ->
                            Yaml.succeed Validate.email

                        _ ->
                            Yaml.fail errorText
                )
        , Yaml.fail errorText
        ]


decodeValidationFilled : Yaml.Decoder (String -> FieldErrorState)
decodeValidationFilled =
    Yaml.field "filled" (Yaml.field "description" Yaml.string)
        |> Yaml.map Validate.filled
