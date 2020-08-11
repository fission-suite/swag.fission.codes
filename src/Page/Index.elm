module Page.Index exposing (view)

import Html exposing (Html)
import Metadata exposing (Metadata(..))


view : Metadata -> List (Html msg) -> { title : String, body : List (Html msg) }
view LandingPage viewForPage =
    { title = "Get Fission Swag"
    , body =
        viewForPage
    }
