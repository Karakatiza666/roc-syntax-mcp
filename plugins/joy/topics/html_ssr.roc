## Rendering joy-html on a server: a basic-webserver app that answers with an
## HTML page built from the same `Html` values a Joy app renders, with
## `Html.ssr_document` and `Html.render`. No Joy platform is involved: joy-html
## is a package, and any platform's app can pin it.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.22.0/BM2BUXA8mwbcoKPUfRV8cLtsUdnsSBPwjNLPRUJQAQ7Q.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
}

import pf.Server
import http.Response
# basic-webserver has an `Html` module of its own. If you import both without
# an alias, you get only a "duplicate definition" warning, and the platform's
# module wins. Then `Html.ssr_document` "does not exist". Alias the platform's
# module if you need it: `import pf.Html as WsHtml`.
import html.Html exposing [div, h1, p, text]
import html.Attribute exposing [class, on_click]

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || Ok({ config: Server.default_config, context: {} })

# A view typed over any message, so a Joy app and this server can share it.
# Rendering to a string drops event handlers.
greeting : Str -> Html(msg)
greeting = |name|
	div([class("greeting")], [h1([], [text("Hello <${name}>")]), p([], [text("Rendered on the server.")])])

# A view with a handler, to show that the markup does not contain the handler.
clickable : Html([Clicked])
clickable = div([class("hi"), on_click(Clicked)], [text("a&b")])

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |_request, _context|
	Ok(
		Server.respond(
			Response.from_status(200)
				.add_header("Content-Type", "text/html; charset=utf-8")
				# `ssr_document` is `render` with "<!DOCTYPE html>" in front.
				.with_body(Str.to_utf8(Html.ssr_document(greeting("Roc")))),
		),
	)

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})

# A server page that runs a Joy app: `Html.document` takes the URLs of Joy's
# files (`loader`, `runtime`, and `wasm` as a function of a bundle id) and
# the page. Every element with `data-joy-bundle` gets its wasm URL in
# `data-joy-wasm`, and the end of `head` gets the loader as a module script
# and preload hints. The page itself names no file of Joy's. A page with no
# bundle root renders as `ssr_document` does.
joy_files : Html.JoyFiles
joy_files = { loader: "/joy.1a.js", runtime: "/runtime.2b.js", wasm: |id| "/${id}/app.3c.wasm" }

with_app : Str -> Str
with_app = |flags|
	Html.document(
		joy_files,
		Html.html([], [Html.head([], [Html.title([], [text("Shop")])]), Html.body([], [div([Attribute.data("joy-bundle", "app"), Attribute.data("joy-flags", flags)], [])])]),
	)

expect with_app("{}").contains("data-joy-wasm=\"/app/app.3c.wasm\"")
expect with_app("{}").contains("<script type=\"module\" src=\"/joy.1a.js\"></script></head>")

# Text and attribute values are escaped. The output has no trace of the click handler.
expect Html.render(clickable) == "<div class=\"hi\">a&amp;b</div>"
expect Html.render(greeting("<b>")).contains("Hello &lt;&lt;b&gt;&gt;")
