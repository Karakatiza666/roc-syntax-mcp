## A Workers API with no module: a program of `Js` ops in an `Io`, and JS
## functions that the app adds with the options of `makeHandler` (`ops`, in `worker.options.js`).
##
## A program is a list of ops that JS runs in one crossing. Each op puts its
## result in the next slot (from 0), and a later op reads it with `Slot(n)`.
## The result of the program is the last slot. A program has no branch and no
## loop: for those, add a JS function to `ops`.
##
## | Op | JS |
## | --- | --- |
## | `Get(t, "x")` | `t.x`, and `undefined` when `t` is null (as `?.`) |
## | `Call(t, "f", args)` | `t.f(...args)`, awaited in `Io.new` |
## | `New(t, "C", args)` | `new t.C(...args)` |
## | `Fields(t, ["a", "b"])` | `{ a: t.a, b: t.b }`, also for getters of a class |
## | `Record`, `Array` | a plain object, an array |
## | `Keep(t)` | a ref to the value of `t` (also a plain value or a promise), so it stays for a later program |
##
## Roots: `env` (bindings), `ctx`, `event`, `global` (`fetch`, `crypto`,
## constructors), `ops` (the functions of the app), `signal`. The root `pf` is the helpers of the platform: an app does not call it.
## The op and value tags (`Get`, `Slot`, `Lit`, `Text`, `Int`) need no import:
## the type of `Io.new` gives them their type. Import `pf.Js` to name `Js`.
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst" }

import pf.Worker
import pf.Request
import pf.Response
import pf.Io
import pf.Ctx
import pf.Js

## `Io.new` runs with a JSPI wait: use it when an op gives a promise.
## The read function gets the last slot as a `Js` value, or the JS throw as
## `{ name, message }`. A JS `Number` that is a safe integer is `Int(I64)`, any
## other number is `Num(F64)`, a `Date` is milliseconds, and a class instance is
## `Ref`. Match each shape that JS can give, and map the rest to an error.
browser_status : Str -> Io(I64, [BrowserErr(Io.Thrown), BadData(Str)])
browser_status = |url| Io.new(
	[
		Get(Root("env"), "BROWSER"),
		Call(Slot(0), "fetch", [Lit(Text(url))]),
		Get(Slot(1), "status"),
	],
	|result| match result {
		Ok(Int(n)) => Ok(n)
		Ok(other) => Err(BadData(Str.inspect(other)))
		Err(thrown) => Err(BrowserErr(thrown))
	},
)

## `Io.sync` runs with no wait. An op that gives a promise in it is an error
## (`PromiseInCall`), so use it only for sync JS.
now_iso : Io(Str, [JsErr(Io.Thrown), BadData(Str)])
now_iso = Io.sync(
	[New(Root("global"), "Date", []), Call(Slot(0), "toISOString", [])],
	|result| match result {
		Ok(Text(s)) => Ok(s)
		Ok(other) => Err(BadData(Str.inspect(other)))
		Err(thrown) => Err(JsErr(thrown))
	},
)

## A JS function of the app. The options of `makeHandler` go in an options file
## next to the entry file: `worker.options.js` for `worker.js`. It is your file.
## Its default export is the options object. `sync` reads it and never writes it.
## When the file is there, `sync` writes the entry file with the import and
## `makeHandler(app, options)`. So `sync` can stay in the `build` script.
## `sync` fails (exit 1) when the options file has no default export.
## After you add or remove the file, run `sync` again: `sync --check` fails
## when the entry file does not match the options file.
##
##     // worker.options.js
##     export default {
##       ops: { slugify: async (s) => s.toLowerCase().replaceAll(" ", "-") },
##     };
##
## `sync` writes this entry file:
##
##     import app from "./app.wasm";
##     import { makeHandler } from "./.roc-cfw/index.js";
##     import options from "./worker.options.js";
##     export default makeHandler(app, options);
##
## Trap: an entry file that you wrote by hand (no `sync` line at its top) is not
## written over. `sync` prints the lines to put in it and exits 1, with or without
## `--check`. Never use `--force` on it: that overwrites your file. Let `sync`
## write the entry file and use the options file. (The platform needs no
## package.json. A JS library that you import in the options file needs one,
## for Wrangler.)
##
## A value of `ops` can also be an object (an imported library): reach its
## methods with `Get(Root("ops"), "lib")`, then `Call(Slot(0), "method", ...)`.
## An HTMLRewriter, or any API that calls back into Roc, needs this: a Roc
## function cannot be a JS callback.
slugify : Str -> Io(Str, [OpsErr(Io.Thrown), BadData(Str)])
slugify = |s| Io.new(
	[Call(Root("ops"), "slugify", [Lit(Text(s))])],
	|result| match result {
		Ok(Text(out)) => Ok(out)
		Ok(other) => Err(BadData(Str.inspect(other)))
		Err(thrown) => Err(OpsErr(thrown))
	},
)

## The same call, for work whose result is dropped. `Ctx.wait_until!` takes only
## an `Io({}, e)`: an `Io` with a result is a type error. Map it to `{}` first.
slugify_unit : Str -> Io({}, [OpsErr(Io.Thrown), BadData(Str)])
slugify_unit = |s| slugify(s).map(|_| {})

## An `Io` is data: nothing runs until `Io.run!`, `Io.both!`, `Io.all!`,
## `Io.race!`, `Io.start!` or `Ctx.wait_until!`. Each module function `f!` is
## `Io.run!(f(...))`, so a program of the app joins the module twins.
fetch! : Request => Try(Response, _)
fetch! = |_req| {
	status = Io.run!(browser_status("https://example.com"))?
	stamp = Io.run!(now_iso)?
	# The errors of the two `Io` values join, as for the module twins.
	(slug, again) = Io.both!(slugify("Hello World"), slugify("Second Page"))?
	# `Io.start!` starts the program and does not wait. The read function does
	# not run, so a Roc `Err` is not seen, and a JS throw goes only to the log.
	# The task stays alive until the program ends, 30 s at most.
	_ref = Io.start!(browser_status("https://example.com/ping"))
	# `Ctx.wait_until!` is the same for work after the response.
	Ctx.wait_until!(slugify_unit("after the response"))
	pinned = pin_now!()
	Ok(Response.from_text(200, "${status.to_str()} ${stamp} ${slug} ${again} ${pinned}"))
}

## The pin table keeps a JS value for later requests of the same isolate, by
## name. It is in `Js`, not `Io`. In a stateless Worker, a stream, a body, a
## socket or a `Response` of another request cannot be used later (Workers
## throws). For typed data, use `Memo`, which keeps CBOR bytes.
pin_now! : () => Str
pin_now! = || match Js.pinned!("boot-time") {
	Ok(Text(s)) => s
	Ok(other) => Str.inspect(other)
	Err(NotPinned) => {
		stamp = Io.run!(now_iso) ?? "unknown"
		_ = Js.pin!("boot-time", Text(stamp), { max_age_ms: 3_600_000 })
		stamp
	}
}

worker = Worker.new({ fetch!: fetch! })

event! = |e| worker.event!(e)
