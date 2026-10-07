## Every code snippet in corpus/platforms/basic-webserver/overview.md, in one
## app. If the page stops matching the pinned platform,
## scripts/check-platform-examples.sh fails.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.17.0/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Path
import pf.Sse
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || {
	config =
		Server.default_config
			.with_listen({ host: "127.0.0.1", port: 8080 })
			.with_request_body_limit(1024 * 1024)
			.with_timeouts({ header_ms: 5000, body_idle_ms: 10_000, keep_alive_idle_ms: 30_000,
				handler_queue_ms: 5000, response_idle_ms: 10_000 })
			.with_file_roots([Server.file_root({ id: "static", path: Path.utf8("public") })])
	Ok({ config, context: {} })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |request, _context| {
	raw_path =
		match request.target() {
			Resource({ raw_path: p, .. }) => p
			_ => ""
		}

	body = request.body().with_limit(64 * 1024).read_all!() ? |err| ServerErr(Str.inspect(err))

	match request.method() {
		GET => Ok(Server.respond(
			Response.from_status(200)
				.add_header("Content-Type", "text/html; charset=utf-8")
				.with_body(Str.to_utf8("<h1>${raw_path} ${Str.inspect(List.len(body))}</h1>"))))
		POST => Ok(Server.stream(
			Sse.unfold!(0, |s| Ok(Emit({ event: Sse.Event.data("tick"), state: s + 1, wake: Immediately })))))
		_other => Ok(Server.respond(Response.from_status(405)))
	}
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})
