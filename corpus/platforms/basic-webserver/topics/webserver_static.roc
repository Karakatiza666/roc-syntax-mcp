## Serving files: native routes the host answers, and `file_response` from Roc.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.17.0/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Path
import http.Response

# A `FileRoot` is a directory the config authorized. A `RelativeFile` is a path
# inside one, validated at startup rather than per request.
Context : {
	downloads : Server.FileRoot,
	report : Server.RelativeFile,
}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || {
	assets = Server.file_root_with_cache({
		id: "assets",
		path: Path.utf8("assets"),
		cache: Server.public_for(3600),
	})
	downloads = Server.file_root({ id: "downloads", path: Path.utf8("downloads") })
	report = Server.relative_file("reports/annual report.txt").map_err(|_| Exit(1))?

	config =
		Server.default_config
			# Every root a request may reach has to be declared here.
			.with_file_roots([assets, downloads])
			# A native route never enters Roc: the host serves it directly, so
			# `respond!` is not called and the request costs no application time.
			.with_native_routes({
				files: [Server.static_mount({ at: "/assets", files: assets })],
				liveness: [],
				readiness: [],
			})

	Ok({ config, context: { downloads, report } })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |request, context|
	match request.target() {
		# Authorize in Roc, then give the transfer back to the host. The file is
		# never read into the application.
		Resource({ raw_path: "/report", raw_query: Present("token=secret") }) =>
			Ok(
				Server.file_response_with({
					files: context.downloads,
					relative: context.report,
					disposition: Server.attachment("annual report.txt"),
					cache: Server.override_cache(Server.no_store),
				}),
			)
		Resource({ raw_path: "/report", .. }) =>
			Ok(Server.respond(Response.from_status(403).with_body(Str.to_utf8("denied"))))
		_ =>
			Ok(Server.respond(Response.from_status(404).with_body(Str.to_utf8("not found"))))
	}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})
