## Rendering joy-html on a server: a basic-webserver app that answers with an
## HTML page built from the same `Html` values a Joy app renders, with
## `Html.ssr_document` and `Html.render`. No Joy platform is involved: joy-html
## is a package, and any platform's app can pin it.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.17.0/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
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

# Text and attribute values are escaped. The output has no trace of the click handler.
expect Html.render(clickable) == "<div class=\"hi\">a&amp;b</div>"
expect Html.render(greeting("<b>")).contains("Hello &lt;&lt;b&gt;&gt;")
