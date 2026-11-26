## Events from outside the page's own elements: keyboard, timers, URL changes,
## and JavaScript ports. Which ones are subscriptions and which are effects,
## what the time values mean, and how a subscription is switched off.
##
## The host keeps a `Sub` active while `subscriptions` returns it, and drops it
## when `subscriptions` stops returning it. An `Effect` happens once, returned
## from `init` or `update`. The two are different types, and each is rejected
## in the other's place.
app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "https://github.com/niclas-ahden/joy/releases/download/0.35.0/FtRCTy7CSPSdS2vLzGJPwYfcGurQfoaADXPNT8aJBBCr.tar.zst",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
}

import html.Html exposing [div, input, text]
import html.Attribute exposing [on_input]
import pf.Effect
import pf.Sub
import pf.Time
import pf.Keyboard
import pf.Navigation
import pf.Port

Model : { running : Bool, ticks : U64, path : Str, price : Str, query : Str, searched : Str }

Msg : [Key(Str), Tick(I64), UrlChanged(Str), LinkClicked(Str), Price(Str), Typed(Str), Search(I64)]

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
		# The URL is `Navigation`'s, not `DOM`'s: `DOM.on_url_change` and
		# `DOM.replace_url` "do not exist". The message carries the whole
		# address, and hears Back, Forward, `push_url` and `replace_url`.
		Navigation.on_url_change(|url| UrlChanged(url)),
		# Without this, every link loads its page. With it, a click on one of
		# the app's own links arrives here, and `push_url` goes there.
		Navigation.on_link_click(|url| LinkClicked(url)),
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
		# Changes the URL with no page load and adds a step for Back.
		# `Navigation.navigate` loads the page, and the model is gone.
		LinkClicked(url) => (model, [Navigation.push_url(url)])
		Price(p) => ({ ..model, price: p }, [])
		# A debounce re-arms on every keystroke, so only the last one fires.
		# The key is global to the app: two debounces sharing one cancel each
		# other. `Time.cancel("search")` would discard it.
		# `replace_url` adds no step for Back, so Back does not walk through
		# every key press.
		Typed(q) => ({ ..model, query: q }, [Time.debounce("search", 300, |now| Search(now)), Navigation.replace_url("?q=${q}")])
		# An effect, not a subscription: one value to JavaScript.
		Search(_now) => ({ ..model, searched: model.query }, [Port.send("search", model.query)])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			input([on_input(|q| Typed(q))]),
			text("${model.ticks.to_str()} ticks at ${model.path}, price ${model.price}"),
		],
	)
