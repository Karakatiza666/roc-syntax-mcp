## A session on basic-cli: open it over a WebSocket through the platform's
## adapter (roc-basic-cli-websocket, see the roc-websocket plugin), define the
## schema, write, read the rows as a Roc type, and match a typed server error.
## It needs SurrealDB 3.3.4 on 127.0.0.1:8000 (`docker run --rm -p 8000:8000
## surrealdb/surrealdb:v3.3.4 start --user root --pass root memory`).
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.3/9c6XLWHRSREuaoELdH1a835Yopw92Jxy2b5e151X6mZj.tar.zst",
	surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.1/7MmdAaAt5bThg6ih3nR9ewVgw4CtNGvuK5HNQhEgZoSV.tar.zst",
}

import pf.Stdout
import cli_ws.WsClient
import surreal.Surreal

Bin : { id : Str, label : Str, qty : I64 }

bins : Surreal.Table(Bin)
bins = Surreal.table("bin")

bin_def : Surreal.Defined
bin_def = bins.define().unique(|b| b.label).check("qty not negative", |b| b.qty >= 0).done()

Least : { least : I64 }

enough : Least, Bin -> Bool
enough = |p, b| b.qty >= p.least

Line : { id : Str, qty : I64 }

line : Bin -> Line
line = |b| { id: b.id, qty: b.qty }

# The transport is the only thing that names the platform. The adapter's
# `connect` and `ops` come from it. `websocket_timed` wants an adapter with
# `receive_within!`, which roc-basic-cli-websocket has and
# roc-basic-webserver-websocket has not: use `Transport.websocket` there. Over
# HTTP it is `Surreal.Transport.http(client, url)`, and `live!` is then an
# `Unsupported` error. The URL has no `/rpc`: the session adds it.
transport : Surreal.Transport
transport = Surreal.Transport.websocket_timed(WsClient.connect, WsClient.ops, "ws://127.0.0.1:8000")

login : Surreal.Login
login = Root({ ns: "roc", db: "roc_surreal", user: "root", pass: "root" })

# Every `Err` here is a `Surreal.Error`. `Str.inspect` is enough to report it.
run! : {} => Try(Str, Str)
run! = |{}| {
	schema = Surreal.schema([bin_def]).map_err(Str.inspect)?
	opened = Surreal.Session.open!(transport, login).map_err(Str.inspect)?

	# `knowing` lets the session read a unique-index failure against the schema.
	# Without it the same failure is `Index(..)`, with no table or fields.
	session = opened.knowing([bin_def])

	# `Unchecked.query!` sends a text and gives `{ session, reply }`. The reply
	# is not read. Use it for the schema script.
	defined = Surreal.Unchecked.query!(session, schema).map_err(Str.inspect)?

	# Every call gives the session back. Use that one, never an older copy.
	# `run!` always gives the session, and holds a failure in `result`: only an
	# `Err` from a transport or a socket ends it.
	created = defined.session.run!(bins.create({ id: "b1", label: "Top", qty: 4 }).map_err(Str.inspect)?)
	twin = created.session.run!(bins.create({ id: "b2", label: "Top", qty: 1 }).map_err(Str.inspect)?)
	refused = match twin.result {
		Ok(_) => "created twice"
		Err(Server(Unique({ fields: ["label"], .. }))) => "the label is taken"
		Err(other) => Str.inspect(other)
	}

	# The result is `List(Line)`: the rows as the projection's record. Match on
	# `read.result`. In this program, `rows = read.result.map_err(Str.inspect)?`
	# followed by `Str.inspect(rows)` stops the debug compiler of the reify fork
	# with an internal error (ARC, "use of unbound refcounted local").
	query = Surreal.from(bins).filter_by(enough).select(line).order_by(|r| r.id, Asc).prepare({ least: 2 })
	read = twin.session.run!(query.map_err(Str.inspect)?)
	rows = match read.result {
		Ok(found) => Str.inspect(found)
		Err(e) => "query failed: ${Str.inspect(e)}"
	}
	Ok("${refused}; ${rows}")
}

main! = |_args| match run!({}) {
	Ok(text) => Stdout.line!(text)
	Err(why) => {
		Stdout.line!("failed: ${why}")?
		Err(Exit(1))
	}
}
