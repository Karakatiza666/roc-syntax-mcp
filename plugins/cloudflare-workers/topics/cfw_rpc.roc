## RPC between Workers: `Rpc` constants that the caller and the callee share, the methods of the default entry point
## (the `rpc` field of `Worker.new`), a named entry point (`Rpc.entrypoint`), a service binding (`Service.binding_with`)
## and a nested call with `Rpc.forward`. A Durable Object stub uses the same constants (see cfw_objects).
##
## Put the interface types, the interface values and the `Rpc` constants in one module that both Workers import
## (here they are in one file). Then the caller and the callee have the same types.
##
## Project files. `node .roc-cfw/cli.mjs sync` writes worker.js with `export const Admin = entrypointClass("Admin");`
## before `export default makeHandler(app);`, and it checks the link to the other Worker of the repo by the interface name.
##   wrangler.toml [[services]] binding = "LEDGER", service = "ledger-worker"
##                 [[services]] binding = "ADMIN", service = "front-worker", entrypoint = "Admin"
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst" }

import pf.Worker
import pf.Request
import pf.Response
import pf.Rpc
import pf.Service

## One interface for each callee: a type with no values, and a value with the name. The type connects both sides in the
## compiler. The name goes to the manifest, and `sync` compares it across Workers (the link of a service binding is in
## the Wrangler config, so no type can check it).
Front := []

Ledger := []

Admin := []

front_api : Rpc.Iface(Front)
front_api = Rpc.iface("Front")

ledger_api : Rpc.Iface(Ledger)
ledger_api = Rpc.iface("Ledger")

admin_api : Rpc.Iface(Admin)
admin_api = Rpc.iface("Admin")

## A method: its name, the argument, the reply and the errors that the callee can give. Write the annotation of each
## constant: with none, the error type is open, and the compiler says "polymorphic value".
## A handler that gives a tag that is not in the error type does not compile.
## The caller gets a domain error as `Remote(Unknown)`. A `Try` is not a reply type: the error is its own type argument.
lookup : Rpc(Front, { key : Str }, Str, [Unknown])
lookup = front_api.method("lookup")

## `Infra(Rpc.Infra)` lets the handler use `?` on a platform call (storage, SQL, another RPC). `Rpc.NoErr` is for a
## method that cannot fail: a `?` on a platform call in its handler is a type mismatch.
## `Rpc.Infra` is a union of 28 tags, and each tag costs 3 to 6 KB of wasm. A small app lists only its tags:
## `Faults : [StorageErr(Io.Thrown), BadData(Str)]`, then `Infra(Faults)`. `Rpc.forward` needs `Infra(Rpc.Infra)`.
## `Rpc.Infra` has no `Constraint` tag. A failed SQL constraint (`D1`, `Object.Self.sql!`) is the flat tag
## `Constraint(Sql.Constraint)`. A method whose handler passes it on with `?` lists it in its `err`:
## `[NoAccount, Constraint(Sql.Constraint), Infra(Rpc.Infra)]`. The caller gets `Remote(Constraint(..))`.
total : Rpc(Front, { who : Str }, U64, [NoAccount, Infra(Rpc.Infra)])
total = front_api.method("total")

balance : Rpc(Ledger, { who : Str }, U64, [NoAccount, Infra(Rpc.Infra)])
balance = ledger_api.method("balance")

## A method with no argument takes `{}` as its argument: `call!(m, {})`. `()` is for functions, and `call!(m, ())` is a
## parse error. A JS caller that sends no argument (`stub.ping()`) sends `{}`.
## A method that two interfaces serve is a function of the interface value. A constant with a free interface does not
## compile ("polymorphic value").
ping : Rpc.Iface(iface) -> Rpc(iface, {}, Str, Rpc.NoErr)
ping = |i| i.method("ping")

purge : Rpc(Admin, { prefix : Str }, U64, Rpc.NoErr)
purge = admin_api.method("purge")

## A service binding is data: the binding name and the interface of the Worker behind it. `call!` takes the constants of
## that interface only. `service` and `entrypoint` are for the manifest: the calls use the binding that Workers made.
ledger = Service.binding_with("LEDGER", ledger_api, { service: "ledger-worker" })

admin = Service.binding_with("ADMIN", admin_api, { service: "front-worker", entrypoint: "Admin" })

## A nested call in a handler. `Infra(RpcErr)` and `Infra(BadData)` of this call stay `Infra`. The function maps the
## domain error of the callee into the one of this method (`|e| e` when the two are the same).
## Write `{ who: who }`. `{ who }` is a block that gives the `Str`, and the compiler can point at the line that binds `who`.
total! : { who : Str } => Try(U64, [NoAccount, Infra(Rpc.Infra)])
total! = |{ who }| {
	n = ledger.call!(balance, { who: who }) ? Rpc.forward(|e| e)
	Ok(n)
}

## A call has four kinds of result: the value, a domain error of the callee (`Remote(NoAccount)`), a platform error
## inside the callee (`Remote(Infra(..))`), and a failure of this call (`Infra(..)`). A throw of the callee (a crash, a
## missing method) is `Infra(RpcErr({ name, message }))`. A reply that does not fit the types is `Infra(BadData(text))`.
fetch! : Request => Try(Response, _)
fetch! = |req| match req.segments() {
	["balance", who] =>
		match ledger.call!(balance, { who: who }) {
			Ok(n) => Ok(Response.from_text(200, n.to_str()))
			Err(Remote(NoAccount)) => Ok(Response.from_status(404))
			Err(Remote(Infra(_))) => Ok(Response.from_status(502))
			Err(Infra(e)) => Err(Infra(e))
		}

	# A request to a service binding with an entry point goes to the `fetch!` of that entry point.
	["admin", ..] => Ok(admin.fetch!(req)?)
	_ => Ok(Response.from_status(404))
}

## A named entry point: a `WorkerEntrypoint` class. It has no `self`. With no `fetch!`, it has no `fetch` method.
admin_entrypoint = Rpc.entrypoint("Admin", {
	fetch!: |_req| Ok(Response.from_text(200, "admin")),
	rpc: [
		purge.on_worker(|{ prefix }| Ok(prefix.count_utf8_bytes())),
	],
})

## The methods of the default entry point. All methods of one list have one interface: a list with `lookup` and a
## method of `Ledger` is a type error ("incompatible types"). One argument and one reply, as CBOR. No streams, no stubs,
## no callbacks, and 32 MiB for a call: send a name, and make the stub on the other side.
worker = Worker.new({
	fetch!: fetch!,
	rpc: [
		lookup.on_worker(|{ key }| if (key == "a") Ok("alpha") else Err(Unknown)),
		total.on_worker(total!),
		ping(front_api).on_worker(|{}| Ok("pong")),
	],
	entrypoints: [admin_entrypoint],
	bindings: [ledger.declare(), admin.declare()],
})

event! = |e| worker.event!(e)
