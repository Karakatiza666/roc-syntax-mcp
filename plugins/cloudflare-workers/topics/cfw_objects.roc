## A Durable Object: a counter with SQL, a cell, an RPC method and an alarm, and the Worker that calls it.
##
## Project files (a model cannot find them in the index). See cfw_worker for the others.
##
##   worker.js     `node .roc-cfw/cli.mjs sync` writes it from the manifest of the built app. It has one line for
##                 each class, BEFORE `export default makeHandler(app);`:
##                 export const Counter = objectClass("Counter");
##   wrangler.toml [[durable_objects.bindings]]
##                 name = "COUNTERS"
##                 class_name = "Counter"
##                 [[migrations]]
##                 tag = "v1"
##                 new_sqlite_classes = ["Counter"]   # not new_classes: the platform needs a SQLite-backed class
##
## `sync` also checks the Wrangler config against `Worker.new` (`objects`, `bindings`). A class with no export line, or
## an export line with no class, stops the load. The error names the class. A class in `new_classes` (KV-backed) fails
## at its first event.
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst" }

import pf.Worker
import pf.Request
import pf.Response
import pf.Object
import pf.Rpc
import pf.Sql
import pf.Time

## The interface of the class: a type with no values. The class, its namespace and its Rpc constants share it, so a
## call of a method that the class does not have is a type error. The text of `Rpc.iface` goes to the manifest, and
## `sync` compares it across Workers.
Counter := []

counter_api : Rpc.Iface(Counter)
counter_api = Rpc.iface("Counter")

## One constant names the method and its types, for the caller and for the callee. The last type is the error that
## the callee can give. `[Infra(Rpc.Infra)]` lets the handler use `?` on every platform call.
## Write the annotation: with none, the error type is open and the constant does not compile.
## A method with `Rpc.NoErr` fits only a handler that cannot fail: a `?` on a storage call is a type mismatch there.
increment : Rpc(Counter, { by : I64 }, I64, [Infra(Rpc.Infra)])
increment = counter_api.method("increment")

## A SQL call of `Object.Self` (`sql!`, `sql_run!`) can give the flat `Constraint(Sql.Constraint)`, and `Rpc.Infra` has
## no `Constraint` tag. A method whose handler uses `?` on such a call lists `Constraint(Sql.Constraint)` in its `err`.
## With only `[Infra(Rpc.Infra)]`, the compiler says that `sql_run!` has an incompatible type. The caller gets the
## constraint failure as `Remote(Constraint({ kind, message }))`.
add_hit : Rpc(Counter, { at : U64 }, {}, [Constraint(Sql.Constraint), Infra(Rpc.Infra)])
add_hit = counter_api.method("add_hit")

## A typed value in the storage of one object: strong consistency, and no wait. Workers keeps the value across deploys.
## A value that does not parse as the new type is `BadData` (there is no fallback), so change the type with care.
count : Object.Cell(I64)
count = Object.cell("count")

Hit : { at : U64 }

counter : Object.Class(Counter)
counter = Object.class("Counter", {
	# `init!` runs each time the object starts: the first event, and the first event after Workers takes the object
	# out of memory. So it must be idempotent: "if not exists". An `Err` of `init!` resets the object, and the event
	# that started it fails (`ObjectErr` for the caller of `fetch!`, `RpcErr` for the caller of `call!`).
	# `Sql.none` means no parameters. A bare `[]` does not compile ("encoder_for ... item ... never resolved").
	init!: |self| {
		_ = self.sql_run!("create table if not exists hits (at integer)", Sql.none)?
		Ok({})
	},
	fetch!: |self, _req| {
		now = Time.now_ms!()
		# Parameters: one bare value is one parameter (`now`, the same as `[now]`). Write `(a, b)` for more.
		# The old `Sql` tag form (`Int(x)`, `Text(x)`) is `BadParam` at run time, and its text names the new form.
		# A U64 binds as it is. A U64 above 2^63-1 is `BadParam`, never a wrap.
		# This call can give `Constraint`. It is a flat tag: match `Err(Constraint(_))`.
		_ = self.sql_run!("insert into hits (at) values (?)", now)?
		# `sql!` reads into the type of the call. With no annotation the row type is not known, and the compiler
		# says "never resolved to a concrete type". `rows.len()` alone does not fix it.
		hits : List(Hit)
		hits = self.sql!("select at from hits", Sql.none)?
		# `sql_run!` gives `rows_read` and `rows_written`, no last row id. Use `insert ... returning id` with `sql!`.
		# `set_alarm_in!` takes a delay. `set_alarm_at!` takes a time in ms since 1970, so `set_alarm_at!(60_000)`
		# is in 1970 and the alarm runs at once. A class with no `alarm!` gets `StorageErr` here.
		self.set_alarm_in!(60_000)?
		# `count.get!(self) ?? 0` would also hide a `StorageErr`. `get_or!` gives the default for a missing key only.
		n = count.get_or!(self, 0)?
		Ok(Response.from_text(200, "count ${n.to_str()}, hits ${hits.len().to_str()}"))
	},
	# The callee: the same constant, with `on`. The first argument is the `Object.Self`.
	# All methods of one class are of one interface.
	rpc: [
		increment.on(|self, { by }| {
			n = count.get_or!(self, 0)? + by
			count.set!(self, n)?
			Ok(n)
		}),
		add_hit.on(|self, { at }| {
			_ = self.sql_run!("insert into hits (at) values (?)", at)?
			Ok({})
		}),
	],
	# `Err` makes Workers run the alarm again (6 retries or less, from 2 s, doubled each time). Give `Ok` to stop.
	alarm!: |self, info| {
		if info.retry_count >= 3 {
			Ok({})
		} else {
			_ = self.sql_run!("delete from hits", Sql.none)?
			Ok({})
		}
	},
})

# The namespace takes the class value, so the class name is written once, and the namespace has its interface.
# For a class in another Worker, the app has only the name:
#   Object.namespace_remote("FAR", { class: "Counter", script: "other-worker" }, counter_api)
# For a class of this Worker with no importable value (a module cycle):
#   Object.namespace_named("COUNTERS", "Counter", counter_api)
counters = Object.namespace("COUNTERS", { class: counter })

fetch! : Request => Try(Response, _)
fetch! = |req| match req.segments() {
	["inc", name] => {
		# Write `{ by: 1 }`. A record of one field with no value is a block: `{ by }` is the value of `by`, and the
		# compiler says that `call!` needs `{ by: I64 }`.
		n = counters.named(name).call!(increment, { by: 1 })?
		Ok(Response.from_text(200, n.to_str()))
	}
	# Give the whole request to the object. Its response comes back with no change.
	["show", name] => Ok(counters.named(name).fetch!(req)?)
	_ => Ok(Response.from_status(404))
}

# `objects` takes `counter.erase()`, not `counter`. `bindings` is optional. It makes the shim check `env` at load,
# and it makes `sync` check the Wrangler config. A function that you define but do not put in the record of a class
# or of `Worker.new` never runs, and the compiler does not warn. `sync` warns, and `sync --check` fails.
worker = Worker.new({
	fetch!: fetch!,
	objects: [counter.erase()],
	bindings: [counters.declare()],
})

event! = |e| worker.event!(e)
