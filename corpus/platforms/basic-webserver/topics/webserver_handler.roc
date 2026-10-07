## Routing, request reading, and the four response outcomes.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.17.0/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import http.Response

# `init!` builds this once. Every request gets the same immutable value, so
# shared mutable state has to live behind SQLite or the filesystem.
Context : { greeting : Str }

# No annotation: annotating `program` means writing the platform's `requires`
# record by hand.
program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || {
	config =
		Server.default_config
			.with_listen({ host: "127.0.0.1", port: 8080 })
			.with_request_body_limit(1024 * 1024)
	Ok({ config, context: { greeting: "hello" } })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |request, context| {
	# `Target` is `Resource`, `Authority`, or `Asterisk`. Only the first has a path.
	path =
		match request.target() {
			Resource({ raw_path, .. }) => raw_path
			_ => ""
		}

	# Method tags are uppercase. Matching on `Get` does not compile.
	match (request.method(), path) {
		(GET, "/") => Ok(Server.respond(text(200, context.greeting)))
		(POST, "/echo") => Ok(Server.respond(echo!(request)?))
		(GET, "/quit") => Ok(Server.stop_after(text(200, "bye")))
		(GET, _) => Ok(Server.respond(text(404, "not found")))
		_ => Ok(Server.respond(text(405, "method not allowed")))
	}
}

# The body is a request-scoped stream, not a `List(U8)`. Narrow its limit first,
# then read. You can only narrow a limit, never widen it past the config. For
# large payloads use `read!`, `fold_chunks!`, or `write_file!`.
echo! : Server.Request => Try(Response, [ServerErr(Str)])
echo! = |request| {
	body = request.body().with_limit(64 * 1024).read_all!()
		? |err| ServerErr("failed to read body: ${Str.inspect(err)}")
	Ok(Response.from_status(200).with_body(body))
}

text : U16, Str -> Response
text = |status, body|
	Response.from_status(status)
		.add_header("Content-Type", "text/plain; charset=utf-8")
		.with_body(Str.to_utf8(body))

# The host logs an unhandled `respond!` error with request context and sends a
# 500. It logs an unhandled `init!` or `shutdown!` error and exits 1.
shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})
