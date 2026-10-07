app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.17.0/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import http.Response

Context : { greeting : Str }

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || {
	config = Server.default_config.with_listen({ host: "127.0.0.1", port: 8080 })
	Ok({ config, context: { greeting: "hello" } })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |request, context| {
	path =
		match request.target() {
			Resource({ raw_path, .. }) => raw_path
			_ => ""
		}

	match (request.method(), path) {
		(GET, "/") => Ok(Server.respond(text(200, context.greeting)))
		_ => Ok(Server.respond(text(404, "not found")))
	}
}

text : U16, Str -> Response
text = |status, body|
	Response.from_status(status)
		.add_header("Content-Type", "text/plain; charset=utf-8")
		.with_body(Str.to_utf8(body))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})
