## A live query on basic-cli: `live` builds a `Watch`, `Session.live!` starts it,
## and `next_within!` waits for the next change with a deadline. The session
## writes and watches on one connection. It needs SurrealDB 3.3.4 on
## 127.0.0.1:8000, as the topic `surreal_session` does.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.3/9c6XLWHRSREuaoELdH1a835Yopw92Jxy2b5e151X6mZj.tar.zst",
	surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.1/7MmdAaAt5bThg6ih3nR9ewVgw4CtNGvuK5HNQhEgZoSV.tar.zst",
}

import pf.Stdout
import cli_ws.WsClient
import surreal.Surreal

Reading : { id : Str, temp_c : Dec }

readings : Surreal.Table(Reading)
readings = Surreal.table("reading")

# `live` takes the definitions of the tables, because a link in a row holds the
# row type and not the table. Here there is no link, but the list is required.
definitions : List(Surreal.Defined)
definitions = [readings.define().done()]

hot : Reading -> Bool
hot = |r| r.temp_c > 39

HotLine : { id : Str, temp_c : Dec }

hot_line : Reading -> HotLine
hot_line = |r| { id: r.id, temp_c: r.temp_c }

# A watch is the same builder as `prepare`, with the same clauses and refusals.
# `limit`, `start`, `order_by`, `group_by`, `between` and a subquery have no
# live form: after `limit` or `start` there is no `live` method (a compile
# error), and the others are an `Unsupported` value. Watch a view for a group.
hot_watch : Try(Surreal.Watch(HotLine), Surreal.Error)
hot_watch = Surreal.from(readings).filter(hot).select(hot_line).live({}, definitions)

transport : Surreal.Transport
transport = Surreal.Transport.websocket_timed(WsClient.connect, WsClient.ops, "ws://127.0.0.1:8000")

watch! : {} => Try(Str, Str)
watch! = |{}| {
	schema = Surreal.schema(definitions).map_err(Str.inspect)?
	opened = Surreal.Session.open!(transport, Root({ ns: "roc", db: "roc_live", user: "root", pass: "root" })).map_err(Str.inspect)?
	defined = Surreal.Unchecked.query!(opened, schema).map_err(Str.inspect)?

	# `started.live` is the state of the watch, pure data. `started.view` is the
	# snapshot of the rows that match now.
	started = defined.session.live!(hot_watch.map_err(Str.inspect)?).map_err(Str.inspect)?
	written = started.session.run!(readings.create({ id: "r1", temp_c: 40 }).map_err(Str.inspect)?)
	# `written.result` holds the stored rows. Match on it: `.map_err(Str.inspect)?`
	# on a `result` that holds a list stops the debug compiler of the reify fork
	# with an internal error (ARC).
	match written.result {
		Ok(_) => {}
		Err(e) => return Err(Str.inspect(e))
	}

	# Pass the `live` and the session that the last call gave. `ms` bounds each
	# wait for a message, and a ping does not count. `TimedOut` loses nothing.
	# On `Transport.websocket` or HTTP this call is an `Unsupported` error.
	got = written.session.next_within!(started.live, 5000).map_err(Str.inspect)?
	text = match got.next {
		Got(changes) => Str.inspect(changes)
		TimedOut => "no change in 5 s"
		Ended => "the watch ended"
		Unread(e) => Str.inspect(e)
	}

	# `kill!` ends the watch on the server.
	_ended = got.session.kill!(got.live.lives()).map_err(Str.inspect)?
	Ok(text)
}

main! = |_args| match watch!({}) {
	Ok(text) => Stdout.line!(text)
	Err(why) => {
		Stdout.line!("failed: ${why}")?
		Err(Exit(1))
	}
}
