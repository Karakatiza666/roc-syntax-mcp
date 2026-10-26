# cloudflare-workers

A Roc platform for Cloudflare Workers: the app is a wasm32 module behind a JS
shim, and each Workers API is a typed module. It brings `Method` and `Header`
from `roc-lang/http` and wraps `roc-cbor` as `Cbor`, so the app header has only
the `pf` entry. `get_roc_module D1` for one module, `search_symbols
Http.send!` for one function, `list_roc_index kind="examples"` for complete
programs, `get_roc_syntax topic="cfw_worker"` for the contract with comments.

## Starting a project

There is no npm package and no `package.json`. The shim is the `js/` directory
of the platform bundle. The helper `roc-cfw` (`tln x roc-cfw -- init`) would
write the files, but it is not released. Write them by hand:

| File | Content |
| --- | --- |
| `main.roc` | The app. The header is `app [event!] { pf: platform "<bundle URL>" }` |
| `talon.toml` | `[scripts]`: `build` is the two commands below, `dev` is `["@build", "wrangler dev --local"]`, `deploy` is `["@build", "wrangler deploy"]` |
| `worker.js` | Written by `sync`. It imports `./.roc-cfw/index.js` and has `export default makeHandler(app)`, with one `objectClass("Room")` line before it for each Durable Object class |
| `wrangler.toml` | `main = "worker.js"`, `compatibility_flags = ["enable_request_signal"]`, one binding for each `X.binding("NAME")`, each Durable Object class in `new_sqlite_classes` |
| `.roc-cfw/` | A copy of `js/` of the bundle. Put it, `app.wasm` and `.wrangler/` in `.gitignore` |

```toml
[scripts]
build = ["roc build --target=wasm32 --no-cache --output=app.wasm main.roc", "node .roc-cfw/cli.mjs sync"]
```

Run `roc check main.roc` once: it unpacks the bundle into the Roc package
cache. Copy the shim from there: `cp -r ~/.cache/roc/packages/<hash>/js
.roc-cfw` (`<hash>` is the file name in the URL, and the cache is under
`$XDG_CACHE_HOME` when that is set). Copy it again after each repin: the shim
and the host must come from the same release. `sync` reads `app.wasm`, writes
`worker.js`, and checks `wrangler.toml` (bindings, crons, classes). It exits 1
and prints the missing lines. `--no-cache` makes the same source give the same
bytes. A `roc build` with type errors still writes `app.wasm` and exits 1.
`roc main.roc` does not run a Worker. `sync` also warns of a handler that
`main.roc` defines and `Worker.new` does not list (`--file` names another source
file). `sync --check` writes nothing and exits 1 for such a handler. An app with
`makeHandler` options (`ops`) puts them in `worker.options.js` next to
`worker.js`: `export default { ops: { ... } }`. `sync` imports that file and keeps
writing `worker.js`, so `sync` stays in the build script.

## The contract

```roc
fetch! : Request => Try(Response, _)
fetch! = |req| match (req.method(), req.segments()) {
	(GET, []) => Ok(Response.from_text(200, "hello from Roc"))
	_ => Ok(Response.from_status(404))
}

purge! : Worker.Scheduled => Try({}, _)
purge! = |s| {
	_ = db.run!("DELETE FROM items WHERE expires_ms < ?", [s.time_ms()])?
	Ok({})
}

worker = Worker.new({ fetch!: fetch!, scheduled!: purge!, bindings: [db.declare()] })

event! = |e| worker.event!(e)
```

The platform requires `event!`, not `main!`. `Worker.new` takes one optional
field for each event kind: `fetch!`, `scheduled!`, `queue!`, `email!`, `tail!`,
`other!`, `rpc`, `entrypoints`, `objects`, `bindings`, `crons`. Each handler has
its own error type. A kind with no field gives `Unhandled` (a 500 for fetch). A
handler that you define and do not list is never called, and the compiler does
not warn. `sync` warns, and `sync --check` exits 1. An `Err` of a handler is a
500 with no body and a log line with `Str.inspect(e)`, so match the error to
give another status.

With one field, write `Worker.new({ fetch!: fetch! })`: `{ fetch! }` alone is a
block. `Worker.{ ... }` is "opaque type". `Request`, `Response`,
`Worker.Scheduled` and `Queue.Batch` are opaque: read them with methods
(`req.method()`, `res.status()`, `s.time_ms()`). A field read (`req.method`)
makes the type a record, and the error is at `Worker.new`, far from the cause.
A function with no argument takes `()`: `Time.now_ms!()`. A call with `({})` is
"too many args". A helper that matches all its errors and is annotated
`Try(Response, _)` infers `[]`, and an arm of `fetch!` that gives it as it is
closes the errors of `fetch!`. Make the helper give a `Response`, or write
`Ok(helper!()?)`.

## Core modules

`Request` and `Response` are one type each for both directions: the request of
a handler and of `Http.send!`, the response of a handler and of `Http.send!`.
`Http` is outbound `fetch` only. `Js` and `Io` are the bridge under the
modules: an app uses them only for a Workers API with no module (topic
`cfw_escape_hatch`). `Crypto` is the Roc builtin. Workers crypto is
`WebCrypto`.

A binding is a constant from its name in the Wrangler config:
`D1.binding("DB")`, `Kv.json("PREFS")`, `Queue.json("JOBS")`,
`Object.namespace("ROOMS", { class: room })`, `Service.binding("AUTH", iface)`.
It is data, so it goes at the top of the module. Functions are methods:
`db.first!(sql, params)`.

Each function `f!` that waits has a pure twin `f` that gives an `Io`.
`Io.both!`, `Io.all!` and `Io.race!` run twins in one crossing, at the same
time. `io.timeout(ms)` gives `Err(Infra(TimedOut))` after the time. A tag is
not a function, so write `.map(|r| Got(r))`, not `.map(Got)`. Sizes end in
`_bytes`, times in `_ms`. `Time.now_ms!()` is a `U64`.

The errors of the platform are inside one tag: `Infra(KvErr(t))`,
`Infra(D1Err(t))`. Bad input stays flat (`BadData` and `TooLarge` of a body
read). A failed SQL constraint is flat too: `Err(Constraint({ kind, message }))`
(D1 and `Object.Self` SQL). A pattern `Err(Infra(Constraint(_)))` never
matches: it compiles when the error type is `_`.

## HTTP

```roc
ask : Ask
ask = req.json!()?
```

Annotate each JSON read. With no annotation, the error is "encoder_for ...
never resolved to a concrete type" at the read. `Http.send!` gives `Ok` for
each status. Only a throw of fetch is `Network` or `HttpErr`. On the edge, a
DNS failure is a 530 and a blocked address is a 403, so check `res.status()`,
or ask `Http.cloudflare_error(res)`. `send!` reads the body in the same
crossing, so `res.json!()` after it does not wait. `Http.open!` keeps the body a
stream. Each read into wasm stops at 1 MiB (`TooLarge`), and the `_with` form
takes `max_bytes`. A body is a tag: `Text("hi")`, `Bytes(b)`, not a bare `Str`.

There is no `Ctx.respond!`. The handler gives the response, and
`Response.after` runs work once Workers has it:

```roc
Ok(Response.from_text(202, ask.name).after(|| note!(text)))
```

The work has the type `() => Try({}, e)`. Its `Err` goes only to the log. Read
the request body in the handler, not in the work (`BodyErr`). A stream:
`{ body, writer } = Body.writer!()?`, then `Response.from_body(...).after(...)`
and `writer.write_text!` in the work. A `write!` in the handler waits for a
reader that does not exist yet. `Ctx.wait_until!(io)` takes only an
`Io({}, e)`.

A `Secret` (`Env.secret!`) has no codec: it does not show in `Str.inspect` and
does not compile into `Log.info!` or JSON. `secret.reveal()` gives the text.

## Data

```roc
item : Item
item = db.first!("SELECT id, name FROM items WHERE id = ?", id)?
```

One bare value is one SQL parameter (`id`, `"ann"`), the same as `[id]`. Write
a tuple for two or more (`(a, b)`), of any encodable value, also a `U64`.
`Sql.none` is no parameter: a bare `[]` does not compile. The old `Sql` tag
form (`Text("ann")`) is a `BadParam` at run time, and its text names the new
form. A NULL in a field that is not `Try(a, [Null])`, and a 0/1 in a `Bool`
field, are `BadData`. The text names the fix (read an `I64` for a `Bool`). Annotate each row type: a row that goes only to
`Response.from_json` is "type not determined" at the call. D1 rounds an
INTEGER of 2^53 or more, and a typed read of it is `BadData`: read it as
`CAST(x AS TEXT)`. A BLOB reads into `List(U8)` or `Cbor.Bytes`.
`Cbor.bytes(list)` makes a `Cbor.Bytes`: `Cbor.Bytes.(...)` is refused.
`db.batch!` is one transaction.

R2 takes a stream with no known length (multipart above 5 MiB, with no
`only_if` or `checksum`). KV raises a `ttl_ms` under 60 s to 60 s. `Cache.put!`
tees a stream body and gives the response to send. `Cache` is local to one data
center.

## Durable Objects, RPC, queues

```roc
Counter := []

counter_iface : Rpc.Iface(Counter)
counter_iface = Rpc.iface("Counter")

increment : Rpc(Counter, U64, U64, [Infra(Rpc.Infra)])
increment = counter_iface.method("increment")

total : Object.Cell(U64)
total = Object.cell("total")

counter : Object.Class(Counter)
counter = Object.class(
	"Counter",
	{
		alarm!: |self, _info| {
			self.set_alarm_in!(60_000)?
			Ok({})
		},
		rpc: [
			increment.on(
				|self, by| {
					n = total.get_or!(self, 0)? + by
					total.set!(self, n)?
					Ok(n)
				},
			),
		],
	},
)

counters = Object.namespace("COUNTERS", { class: counter })
```

The class goes in `objects: [counter.erase()]`. The namespace takes the class
value, so `call!` accepts only the `Rpc` constants of that interface. The `err`
of a method must hold the platform tags that its body can raise:
`Infra(Rpc.Infra)`, or an alias of fewer tags (its 28 tags cost wasm size).
`Rpc.Infra` has no `Constraint`: a method that passes a SQL constraint failure
on lists `Constraint(Sql.Constraint)` in its `err`. The
caller gets `Remote(err)` or `Infra([RpcErr(t), BadData(s)])`. `init!` runs at
each start of the object, also after eviction, so it must be idempotent.
`set_alarm_at!` takes a time in ms since 1970, `set_alarm_in!` a delay, and a
class with no `alarm!` gets `StorageErr`. Annotate each `self.sql!` row type.
Storage calls with no wait between them are atomic. The argument and the reply
of an RPC call cross as CBOR. A `Try` has no codec. An RPC call cannot carry a
socket, a stream or a stub: give a WebSocket upgrade to an object with
`stub.fetch!(req)`.

```roc
queue! : Queue.Batch => Try({}, _)
queue! = |batch| {
	_ = jobs.each!(batch, |_msg, job| note!(job.pkg))
	Ok({})
}
```

`Queue.json("JOBS")` sends one type. `jobs.each!` acks on `Ok` and retries on
`Err`. A `Queue.json` message cannot hold an integer of 2^53 or more: use
`Queue.v8`.

## Traps

- `{ name }` with one field is a block, not a record. Write `{ name: name }`.
- `Object.Cell`, `Object.attachment` and `Memo` values are CBOR. A changed type
  under the same name reads as `BadData` (`Memo` loads again).
- `Http.send_with!(req, { timeout_ms })` gives `Network` with the name
  `TimeoutError`.
