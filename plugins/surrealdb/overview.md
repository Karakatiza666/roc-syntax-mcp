# roc-reify-surrealdb 0.0.4

A SurrealDB ORM for Roc. A row type is a plain Roc record, a table is a
`Surreal.Table(row)` over it, and every clause, projection and constraint is a
Roc function that the compiler takes as a `Code(f)` and the package translates
to SurrealQL. The same function stays an ordinary Roc function: call it on your
own rows, and test it with `expect`. `Surreal` is the only public module
(`import surreal.Ql` is "package module is private").

Topics, each a complete program that compiles: `surreal_schema` (rows, links,
edges, constraints, the `DEFINE` script), `surreal_queries` (filter, project,
order, group, writes, captured values), `surreal_session` (a basic-cli session,
typed results and errors), `surreal_live` (a watch). Run them with
`get_roc_syntax(topic: "surreal_queries")`.

## The compiler is a fork

`Code(f)` is a type of the reify fork of Roc, not of any nightly. Use
`Karakatiza666/roc`, branch `reify`, at commit
`76ed44249ac086e593325c58f56d96d8dc4ffd47` (the package's `.roc-version`). A
stock nightly fails with "missing method" errors on `.unique`, `.assert` and the
other builder calls, and none of them mentions `Code`. The release
`nightly-reify-2026-11-07-76ed442` of `Karakatiza666/roc-reify-nightlies` has
prebuilt binaries (`roc version` prints that name). Unpack one and point this
server at it:

```sh
gh release download nightly-reify-2026-11-07-76ed442 -R Karakatiza666/roc-reify-nightlies -p '*linux_x86_64*'
tar -xzf roc_nightly-reify-linux_x86_64-2026-11-07-76ed442.tar.gz
roc-syntax-mcp roc use $PWD/roc_nightly-reify-linux_x86_64-2026-11-07-76ed442/roc
```

SurrealDB 4.0.1 or later is the server. 3.x is not supported.

## The header

A script app has no platform: `app [main!] { surreal: "..." }` prints SurrealQL
with `echo!`. An app that reaches a server needs a platform and the WebSocket
adapter of that platform from roc-websocket (the roc-websocket plugin documents
`WsClient`):

```roc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.27.0/9yjxqdGTP4xSpSEmDazwTmRsehfRZzA19pwEKkR6fj1g.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.4/B5j45zNdyW8Qxq6GpQ6ZVNmcPC5hwx3TxPRW4cq8wiLV.tar.zst",
	surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.4/CkLUeGcqAc6kNLaDf5rMbQEaZAE7nxapCE4EsHnqh5HY.tar.zst",
}
```

`echo!` exists only in a platformless app. With a platform, use `Stdout.line!`.
The package depends on roc-cbor 0.5.0 and roc-websocket 0.0.6, so an app that
uses `Cbor` itself names roc-cbor 0.5.0 too. On basic-webserver 0.21.0 the
adapter is roc-basic-webserver-websocket and the transport is `Transport.websocket`.

## A table and a query

```roc
Owner : { id : Str, name : Str, city : Str }

owners : Surreal.Table(Owner)
owners = Surreal.table("owner")

CityParam : { city : Str }

in_city : CityParam, Owner -> Bool
in_city = |p, o| o.city == p.city

Surreal.from(owners).filter_by(in_city).select(|o| { id: o.id, name: o.name }).prepare({ city: "Oslo" })
# LET $city = 'Oslo'; SELECT record::id(id) AS id, name AS name FROM owner WHERE city = $city;
```

## Traps the compiler found

- **Values from around the chain.** Inside a function whose result is a
  `Prepared` or a `Watch`, a clause reads the function's values as `$_1`, `$_2`
  slots: `dearer = |limit| Surreal.from(visits).filter(|v| v.fee > limit).ready()`.
  A parameter record also works (`filter_by`, then `prepare({ city: city })`).
  Write `{ city: city }`, not `{ city }`, which parses as a block.
  `select_where` and `bind_captured` are gone.
- **`Surreal.Time.now()` and the other intrinsics** exist only inside a clause.
  In a top-level constant or an `expect` it is "exists only in reified code".
- **A refusal is a value, not a compile error.** A builtin with no SurrealQL
  form (`Str.replace_first`, for one) gives a `Prepared` that holds
  `Unsupported("in `select`: ...")`. There is no `Try` around a `Prepared`:
  `checked()`, `statement()` and `request()` give the error, and `run!` puts it
  in `result`.
- **Defaults need a nominal.** `x : I64 ?? 9` is an error on an alias row. A
  nominal row declares `encoder_for : _` and `parser_for : _`, or a write is a
  missing-method error.
- **Write order.** After a projection the steps are `order_by`, `start`, `limit`
  in that order. `.limit(2).order_by(..)` has no `order_by` method, and a
  `Limited` has no `live`.
- **Return types differ.** `create` and `insert` give a `Prepared`.
  `update_at`, `set_at` and `delete_at` give a `Write` whose `ready` (or
  `prepare`) gives it. A key is a `Code(Id(row))`: write `owners.id("ann")` in a
  top-level value or take it from the function around the chain. A query with
  no parameter ends with `ready()`. `select` needs a record, `select_value` a
  bare value.
- **An unannotated query fragment** (`whole = |q| q.select(|r| r)`) is a type
  mismatch, because the lambda is not a `Code`. Annotate the query type with
  open rows, as the `Clinic` helpers of the upstream repo do.
- **Edges** name their ends `from` and `to` (`in` is a keyword). An edge table
  used in the wrong direction is a type error.
- **A session value is single use.** Every call returns the session to use
  next. `run!` always returns it, with the failure in `result`.
- **A watch** needs `Transport.websocket_timed` for `next_within!`. HTTP has no
  watch. Read each change before the next write: SurrealDB 3.3.4 delivered the
  notices of two writes out of order.
- **Values go in `vars`.** Parameters, captured values and written rows are the
  `vars` of the RPC request, not `LET` text. `to_script()` prints the `LET` form
  for logs. For a hand-written query, `Unchecked.send!(session, request)` takes
  the `Request` that `prepared.request()` gives.
- **Migrations** are files. `Surreal.plan(snapshot, schema)?.to_file(name,
  KeepData)` gives the next `.surql` file from the committed snapshot text and
  the Roc schema, and `session.migrate!(migrations)` applies the files the
  database lacks. `migrate!` refuses a database below compatibility level 4
  with `Level({ found })`. Upstream's `examples/migrate.roc` is the tool to copy.

For the WebSocket layer see the roc-websocket plugin.
