# roc-reify-surrealdb 0.0.1

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
`c1e6af27a29303f2e409b037aa1d4a32ebd68217` (the package's `.roc-version`). A
stock nightly fails with "missing method" errors on `.unique`, `.assert` and the
other builder calls, and none of them mentions `Code`. Build the fork with Zig
0.17.0 and point this server at it:

```sh
git clone https://github.com/Karakatiza666/roc.git && cd roc
git checkout c1e6af27a29303f2e409b037aa1d4a32ebd68217
zig build roc                       # zig-out/bin/roc, `roc version` prints debug-c1e6af27
roc-syntax-mcp roc use $PWD/zig-out/bin/roc
```

A debug build takes 10 to 30 s per `roc check`. SurrealDB 3.3.4 is the tested
server.

## The header

A script app has no platform: `app [main!] { surreal: "..." }` prints SurrealQL
with `echo!`. An app that reaches a server needs a platform and the WebSocket
adapter of that platform from roc-websocket (the roc-websocket plugin documents
`WsClient`):

```roc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.3/9c6XLWHRSREuaoELdH1a835Yopw92Jxy2b5e151X6mZj.tar.zst",
	surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.1/7MmdAaAt5bThg6ih3nR9ewVgw4CtNGvuK5HNQhEgZoSV.tar.zst",
}
```

`echo!` exists only in a platformless app. With a platform, use `Stdout.line!`.
The package depends on roc-cbor 0.4.0 and roc-websocket 0.0.5, so an app that
uses `Cbor` itself names roc-cbor too. On basic-webserver 0.20.0 the adapter is
roc-basic-webserver-websocket and the transport is `Transport.websocket`.

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

- **No captured values.** A clause that reads a variable of its scope is the
  compile error "reified function captures a value". Pass it in a parameter
  record (`filter_by`, then `prepare({ city: city })`), or use
  `Surreal.bind_captured(Surreal.select_where(table, |r| r.f > limit))`. Write
  `{ city: city }`, not `{ city }`, which parses as a block.
- **`Surreal.Time.now()` and the other intrinsics** exist only inside a clause.
  In a top-level constant or an `expect` it is "exists only in reified code".
- **A refusal is a value, not a compile error.** A builtin with no SurrealQL
  form (`Str.replace_first`, for one) makes `prepare` return `Err(Unsupported("in `select`: ..."))`. Always read the `Try`.
- **Defaults need a nominal.** `x : I64 ?? 9` is an error on an alias row. A
  nominal row declares `encoder_for : _` and `parser_for : _`, or a write is a
  missing-method error.
- **Write order.** After a projection the steps are `order_by`, `start`, `limit`
  in that order. `.limit(2).order_by(..)` has no `order_by` method, and a
  `Limited` has no `live`.
- **Return types differ.** `create` and `insert` give a `Try(Prepared, Error)`.
  `update_at`, `set_at` and `delete_at` give a `Write` whose `prepare` gives the
  `Try`. `select` needs a record, `select_value` a bare value.
- **An unannotated query fragment** (`whole = |q| q.select(|r| r)`) is a type
  mismatch, because the lambda is not a `Code`. Annotate the query type with
  open rows, as the `Clinic` helpers of the upstream repo do.
- **Edges** name their ends `from` and `to` (`in` is a keyword). An edge table
  used in the wrong direction is a type error.
- **A session value is single use.** Every call returns the session to use
  next. `run!` always returns it, with the failure in `result`.
- **`.map_err(Str.inspect)?` on the `result` of `run!`** stops the debug fork
  compiler with an ARC internal error. Match on `result`.
- **A watch** needs `Transport.websocket_timed` for `next_within!`. HTTP has no
  watch. SurrealDB 3.3.4 may deliver the notices of two writes out of order, so
  read each change before the next write.

For the WebSocket layer see the roc-websocket plugin.
