## Server-rendered HTML. Every node escapes by default. You must opt out explicitly.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.17.0/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Html
import pf.Attribute
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |_request, _context|
	Ok(
		Server.respond(
			Response.from_status(200)
				.add_header("Content-Type", "text/html; charset=utf-8")
				.with_body(Str.to_utf8(Html.render(page(["Ada", "<script>alert(1)</script>"])))),
		),
	)

# The node type is `Html.Node`. Each element takes attributes and children, both
# lists. A tag with no helper is `Html.element("tag", attrs, children)`. A tag
# with no children, such as `<input>`, is `Html.void_element("input", attrs)`.
page : List(Str) -> Html.Node
page = |names|
	Html.html(
		[Attribute.attribute("lang", "en")],
		[
			Html.head([], [Html.title([], [Html.text("Names")])]),
			Html.body(
				[Attribute.class("plain")],
				[
					Html.h1([], [Html.text("Names")]),
					# `Html.text` escapes, so the script tag above renders as
					# literal characters rather than executing.
					Html.ul([], names.map(|name| Html.li([], [Html.text(name)]))),
					Html.form(
						[Attribute.action("/add"), Attribute.method("post")],
						[
							Html.label([Attribute.for_("name")], [Html.text("Name")]),
							Html.void_element(
								"input",
								[Attribute.type("text"), Attribute.name("name"), Attribute.id("name")],
							),
							Html.button([Attribute.type("submit")], [Html.text("Add")]),
						],
					),
					# The only way to skip escaping. Its name makes a reviewer notice it.
					# Never pass user input through it.
					Html.div([], [Html.dangerously_include_unescaped_html("<em>trusted markup</em>")]),
				],
			),
		],
	)

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})
