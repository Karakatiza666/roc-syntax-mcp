## A basic-webserver handler that runs a typed query on SurrealDB for each request through roc-basic-webserver-websocket.
# A web server that runs a typed query on SurrealDB for each request, on
# the basic-webserver platform.
#
# `GET /readings?min_pulse=N` answers with the readings of `monitoring.roc`
# whose pulse is at least `N`, one line each, fastest first. Each request
# opens a WebSocket session of its own, through
# roc-basic-webserver-websocket (`WsClient`), and the session ends with
# the request: basic-webserver scopes a connection to the handler that
# opened it, and each TCP read times out after 30 s, so a session cannot
# outlive its request, and a watch, which waits for notices, has no place
# here. `Session.run!` sends the query with the RPC method `query`, and
# reads the reply as `List(Reading)`. The same server runs over HTTP with
# the transport in the comment next to `transport`.
#
# The tables are the tables of `monitoring.roc`, and `tests/check.py` makes
# them (it also starts this server, asks it for the readings, and stops
# it). The server listens on 127.0.0.1:8001, next to SurrealDB on 8000:
#
#     roc examples/server.roc &
#     curl 'http://127.0.0.1:8001/readings?min_pulse=120'
app [Context, program] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.4.0/EnfRKFT7uPHmd3zT5PcwAiBWUtGmBXapJqFK5166U33J.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.20.0/7dR2ewuEbpPQXTAZL3aH62weBwpNNjbCJtyyiRsufTNZ.tar.zst",
	bws_ws: "https://github.com/Karakatiza666/roc-basic-webserver-websocket/releases/download/0.0.2/63RHisM5dNvGRLkMFurQZd7Gp1AqWpThfd5Dvtb2CTKj.tar.zst",
	surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.1/7MmdAaAt5bThg6ih3nR9ewVgw4CtNGvuK5HNQhEgZoSV.tar.zst",
}

import pf.Server
import http.Response
import bws_ws.WsClient
import surreal.Surreal

# ------------------------------------------------- the tables of monitoring.roc

Kennel : { id : Str, label : Str }

Vital : { id : Surreal.TimeKey(Surreal.Id(Kennel)), pulse : I64, temp_c : Dec, fevered : Bool }

vitals : Surreal.Table(Vital)
vitals = Surreal.table("vital")

# ------------------------------------------------------------- the query

Reading : { kennel : Str, at : Str, pulse : I64, temp_c : Dec }

## A reading, with its time written by the database.
reading : Vital -> Reading
reading = |v| { kennel: v.id.series().key(), at: Surreal.Time.format(v.id.time(), "%Y-%m-%dT%H:%M:%SZ"), pulse: v.pulse, temp_c: v.temp_c }

## The readings whose pulse is at least `least`, fastest first.
readings_above : I64 -> Try(Surreal.Prepared(List(Reading)), Surreal.Error)
readings_above = |least| Surreal.from(vitals).filter_by(|p, v| v.pulse >= p.least).select(reading).order_by(|r| r.pulse, Desc).prepare({ least: least })

line : Reading -> Str
line = |r| "kennel ${r.kennel} at ${r.at}: pulse ${r.pulse.to_str()}, temp_c ${r.temp_c.to_str()}"

# ------------------------------------------------------------- the platform

## The transport of each session: a WebSocket on `/rpc`, through
## roc-basic-webserver-websocket (`WsClient`). It is `websocket`, not
## `websocket_timed`: basic-webserver's adapter has no `receive_within!`.
transport : Surreal.Transport
transport = Surreal.Transport.websocket(WsClient.connect, WsClient.ops, "ws://127.0.0.1:8000")

# The same server over HTTP: each request of the session is one `POST /rpc`
# through the platform's `Http.send!`. Put these in place of `transport`
# above, and `import pf.Http` and `import http.Request` next to the
# imports at the top (the `bws_ws` package is then not needed).
#
# transport : Surreal.Transport
# transport = Surreal.Transport.http(http_client, "http://127.0.0.1:8000")
#
# http_client : Surreal.HttpClient
# http_client = {
# 	post!: |post| {
# 		request = post.headers.fold(Request.from_method(POST).with_uri(post.uri).with_body(post.body), |r, h| r.add_header(h.name, h.value))
# 		response = Http.send!(request).map_err(Str.inspect)?
# 		Ok({ status: response.status(), body: response.body() })
# 	},
# }

login : Surreal.Login
login = Root({ ns: "roc", db: "roc_surreal", user: "root", pass: "root" })

# ------------------------------------------------------------- the server

Context : {}

program = { init!, respond!, shutdown! }

init! = || Ok({ config: Server.default_config.with_listen({ host: "127.0.0.1", port: 8001 }), context: {} })

respond! = |request, _context| {
	(path, query) = match request.target() {
		Resource({ raw_path, raw_query }) => (raw_path, raw_query)
		_ => ("", Absent)
	}
	match (request.method(), path) {
		(GET, "/readings") =>
			match min_pulse(query) {
				Ok(least) => Ok(Server.respond(answer!(least)))
				Err(why) => Ok(Server.respond(text(400, why)))
			}
		_ => Ok(Server.respond(text(404, "GET /readings?min_pulse=N")))
	}
}

shutdown! = |_reason, _context| Ok({})

## `min_pulse=N` in the query of the target.
min_pulse : [Absent, Present(Str)] -> Try(I64, Str)
min_pulse = |query| {
	pairs = match query {
		Present(q) => q.split_on("&")
		Absent => []
	}
	found = pairs.keep_oks(
		|pair| match pair.split_on("=") {
			["min_pulse", value] => I64.from_str(value).map_err(|_| NotNumber)
			_ => Err(Other)
		},
	)
	match found {
		[least] => Ok(least)
		_ => Err("give one `min_pulse=N`, N a whole number")
	}
}

## The readings of one query, read as `List(Reading)`, on a session of
## its own. A failure is the text of the error, with status 502.
answer! : I64 => Response.Response
answer! = |least| match run!(least) {
	Ok(rows) => text(200, Str.join_with(rows.map(line), "\n"))
	Err(why) => text(502, why)
}

run! : I64 => Try(List(Reading), Str)
run! = |least| {
	prepared = readings_above(least).map_err(Str.inspect)?
	session = Surreal.Session.open!(transport, login).map_err(Str.inspect)?
	session.run!(prepared).result.map_err(Str.inspect)
}

text : U16, Str -> Response.Response
text = |status, body| Response.from_status(status).add_header("Content-Type", "text/plain; charset=utf-8").with_body("${body}\n".to_utf8())
