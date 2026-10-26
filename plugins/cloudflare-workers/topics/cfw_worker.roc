## The contract of a cloudflare-workers app: one `event!`, a `Worker.new`
## record of handlers with one error type for each handler, a cron handler,
## and the files of a project.
##
## A project (no npm, no package.json):
##
## | File | Content |
## | --- | --- |
## | main.roc | This file. Build: `roc build --target=wasm32 --no-cache --output=app.wasm main.roc` |
## | talon.toml | `[scripts]`: `build` is that command, then `node .roc-cfw/cli.mjs sync`. `dev` is `["@build", "wrangler dev --local"]` |
## | worker.js | Written by `sync` from the app. Do not write it by hand |
## | worker.options.js | Optional. Your file: `export default { ops, other, ... }`, the options of `makeHandler`. `sync` imports it |
## | wrangler.toml | `main = "worker.js"`, `compatibility_flags = ["enable_request_signal"]`, one binding for each `X.binding("NAME")` |
## | .roc-cfw/ | A copy of `js/` of the platform bundle (the shim). Put it in .gitignore. `sync` is `node .roc-cfw/cli.mjs sync` |
##
## `--no-cache` makes the same source give the same bytes. A `roc build` with
## type errors still writes app.wasm and exits with 1: check the exit code.
## Without `enable_request_signal`, a task does not stop when the client goes away.
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst" }

import pf.Worker
import pf.Request
import pf.Response
import pf.D1
import pf.Sql
import pf.Log

db = D1.binding("DB")

# `Request` and `Response` are opaque: read them with methods (`req.method()`,
# `res.status()`). A field read (`req.method`) does not compile, and the error
# is far away, at `Worker.new`. With methods the annotation is optional: the
# type comes from `Worker.new`. Write it anyway, it keeps the errors near the cause.
fetch! : Request => Try(Response, _)
fetch! = |req| match (req.method(), req.segments()) {
	(GET, []) => Ok(Response.from_text(200, "hello from Roc"))
	(GET, ["count"]) => Ok(count!())
	(POST, ["echo"]) => {
		# Read the request body in the handler. In the work of `Response.after` it
		# is gone: `BodyErr` "Can't read from request stream after response has
		# been sent". Give the work the value that it needs.
		text = req.text!()?
		Ok(Response.from_text(200, text))
	}
	_ => Ok(Response.from_status(404))
}

Count : { n : I64 }

# An `Err` of a handler is a 500 response with no body and a log line with
# `Str.inspect(e)`. To give another status, match the error in the handler.
#
# Each handler has its own error type. `fetch!` here has the errors of `text!`,
# and `scheduled!` below has `UnknownCron`. They do not need to agree.
#
# Trap: a helper whose `match` gives `Ok(...)` in every arm (it handles all of its
# errors, as `count!` does) and is annotated `Try(Response, _)` infers the closed
# `Try(Response, [])`. A helper with a plain `Ok(...)` body is not closed. An arm of
# `fetch!` that gives it as it is (`=> count!()`) then closes the errors of
# `fetch!`, and the next `?` in `fetch!` fails. Make the helper give a `Response`
# (as here), or write `Ok(count!()?)`.
count! : () => Response
count! = || {
	got : Try(Count, _)
	got = db.first!("SELECT count(*) AS n FROM items", Sql.none)
	match got {
		Ok({ n }) => Response.from_text(200, n.to_str())
		Err(NotFound) => Response.from_status(404)
		Err(e) => {
			Log.error!("count", { error: Str.inspect(e) })
			Response.from_status(503)
		}
	}
}

# `cron()` is the cron expression of the run. `time_ms()` is the planned time of
# the run in milliseconds, not the start time. An `Err` is a failed run.
# Production does not run it again.
purge! : Worker.Scheduled => Try({}, _)
purge! = |s| {
	Log.info!("cron", { cron: s.cron(), time_ms: s.time_ms() })
	# SQL parameters are a list (`[x]`) or a tuple (`(a, b)`). A `U64` binds as it is:
	# above 2^63 - 1 it is `BadParam`, it never wraps.
	_ = db.run!("DELETE FROM items WHERE expires_ms < ?", [s.time_ms()])?
	Ok({})
}

scheduled! : Worker.Scheduled => Try({}, [UnknownCron(Str)])
scheduled! = |s| Err(UnknownCron(s.cron()))

# `Worker.new` takes one optional field for each event kind: `fetch!`,
# `scheduled!`, `queue!`, `email!`, `tail!`, `other!`, and `rpc`, `entrypoints`,
# `objects`. A kind with no field gives `Unhandled` (for fetch, a 500 and a log
# line). A handler that you define and do not list is never called. The
# compiler does not warn, but `sync` does (`sync: main.roc:12: scheduled! is
# defined but Worker.new does not list it; it never runs`). `sync` exits 0 with
# the warning, and `sync --check` exits 1.
#
# `crons`: a handler for each cron expression. A run of another cron goes to
# `scheduled!`. `bindings`: `declare()` of each binding. The shim checks `env` at
# load, and `sync` checks wrangler.toml.
#
# Trap: with one field, write `Worker.new({ fetch!: fetch! })`. `{ fetch! }` alone
# is a block, not a record. `Worker.{ fetch! }` (the old form) is "opaque type".
worker = Worker.new({
	fetch!: fetch!,
	scheduled!: scheduled!,
	crons: [Worker.cron("*/5 * * * *", purge!)],
	bindings: [db.declare()],
})

# The platform requires `event!`, not `main!`. It takes each event.
event! = |e| worker.event!(e)
