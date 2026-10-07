## Events from outside the page's own elements: keyboard, timers, URL changes,
## and JavaScript ports. Which ones are subscriptions and which are effects,
## what the time values mean, and how a subscription is switched off.
##
## The host keeps a `Sub` active while `subscriptions` returns it, and drops it
## when `subscriptions` stops returning it. An `Effect` happens once, returned
## from `init` or `update`. The two are different types, and each is rejected
## in the other's place.
app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "https://github.com/niclas-ahden/joy/releases/download/0.34.0/2B3sC6U2dWkVUK2VY2gJS5Wej9YCDo3ZYq2e7tMWUCNp.tar.zst",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [div, input, text]
import html.Attribute exposing [on_input]
import pf.Effect
import pf.Sub
import pf.Time
import pf.Keyboard
import pf.DOM
import pf.Port

Model : { running : Bool, ticks : U64, path : Str, price : Str, query : Str, searched : Str }

Msg : [Key(Str), Tick(I64), UrlChanged(Str), Price(Str), Typed(Str), Search(I64)]

init : Str -> (Model, List(Effect(Msg)))
init = |flags| ({ running: Bool.True, ticks: 0, path: flags, price: "", query: "", searched: "" }, [])

# The key event type is `Sub.KeyEvent`. `Keyboard.KeyEvent` does not exist.
on_key : Sub.KeyEvent -> Msg
on_key = |e| if e.ctrl and e.key == "s" Key("save") else Key(e.key)

subscriptions : Model -> List(Sub(Msg))
subscriptions = |model| {
	always = [
		# The prevent-default variant keeps the browser from also acting on
		# these keys, here its own save dialog.
		Keyboard.on_down_keys_prevent_default(["s", "S", "Escape"], on_key),
		DOM.on_url_change(|url| UrlChanged(url)),
		# Values a JavaScript handler sends on the "prices" port.
		Port.listen("prices", |v| Price(v)),
	]
	# Leave the interval out of the list to stop it. There is no other off switch.
	# The delay is U32 milliseconds. The callback gets I64 milliseconds since
	# the Unix epoch, not nanoseconds.
	if model.running always.concat([Time.every(1000, |now| Tick(now))]) else always
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Key("Escape") => ({ ..model, running: Bool.False }, [])
		Key(_) => (model, [])
		Tick(_now) => ({ ..model, ticks: model.ticks + 1 }, [])
		UrlChanged(path) => ({ ..model, path }, [])
		Price(p) => ({ ..model, price: p }, [])
		# A debounce re-arms on every keystroke, so only the last one fires.
		# The key is global to the app: two debounces sharing one cancel each
		# other. `Time.cancel("search")` would discard it.
		Typed(q) => ({ ..model, query: q }, [Time.debounce("search", 300, |now| Search(now)), DOM.replace_url("?q=${q}")])
		# An effect, not a subscription: one value to JavaScript.
		Search(_now) => ({ ..model, searched: model.query }, [Port.send("search", model.query)])
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			input([on_input(|q| Typed(q))]),
			text("${model.ticks.to_str()} ticks at ${model.path}, price ${model.price}"),
		],
	)
