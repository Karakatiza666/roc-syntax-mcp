## The app `roc_check` wraps bare code in when the caller names a scope and the
## code carries no header of its own.
##
## Everything above `@user-code` is the prelude. `roc_check` appends each
## `@default` block below it only when the submitted code does not define that
## name. src/roc_check.ts reads both markers, and
## scripts/check-platform-examples.sh compiles the whole file, so the scaffold
## always matches the pinned platform.
app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "https://github.com/niclas-ahden/joy/releases/download/0.34.0/2B3sC6U2dWkVUK2VY2gJS5Wej9YCDo3ZYq2e7tMWUCNp.tar.zst",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

# Every exposed module, qualified, so a snippet that uses any of them compiles
# as submitted. The compiler does not warn about an unused import.
import html.Html
import html.Attribute
import html.Event
import pf.Effect
import pf.Sub
import pf.Http
import pf.Time
import pf.Keyboard
import pf.Console
import pf.DOM
import pf.Port
import pf.WebCrypto

# @user-code

# @default Model
Model : {}

# @default Msg
# The header exposes this type, so an app with no messages still declares one.
Msg : [NoOp]

# @default init
# `crash` has the bottom type, so this type-checks against the Model that the
# submitted code declares. `roc check` stops at types, so nothing here runs.
init : Str -> (Model, List(Effect(Msg)))
init = |_flags| crash "scaffolded init: define your own to build a Model"

# @default update
update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, _msg| (model, [])

# @default render
render : Model -> Html(Msg)
render = |_model| Html.text("")

# @default subscriptions
subscriptions : Model -> List(Sub(Msg))
subscriptions = |_model| []
