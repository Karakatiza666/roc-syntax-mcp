## A WebSocket client for basic-cli, through the roc-basic-cli-websocket adapter:
## `WsClient.connect!` opens the connection (TCP and handshake), and the
## connection's methods send, receive, ping and close.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	ws: "https://github.com/Karakatiza666/roc-websocket/releases/download/0.0.7/EBNZjRmQ5PZiJAE5UMUFePtQFdb1FnsQX1qagVuiCwM9.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.5/AZpgG3RszEahBa67zc9yCJcAKe4MKw5HucDouNpi727b.tar.zst",
}

import pf.OsStr
import pf.Stdout
import pf.Stderr
import pf.Duration
import ws.Ws
import cli_ws.WsClient

# The app names exactly the platform the adapter was built for (basic-cli
# 0.28.1) and the roc-websocket release it uses (0.0.7): the adapter's own header
# pins both, and any other release is a different type at the boundary. `ws` is
# imported for `Ws.close_and_wait!`; a type used only in an annotation (like
# `Ws.Message`) needs its import too.

## The session, as lines of text. `WsClient.Error` is a CLOSED union
## (`Closed`, `Closing`, and the adapter's own tags), so a `?` on `Stdout.line!`
## inside this function is a type mismatch: print in `main!` and keep this
## function to WebSocket calls.
session! : {} => Try(List(Str), WsClient.Error)
session! = |{}| {
	# `connect_with!` is `connect!` with the platform's timeouts; every field of
	# the options is optional (5 s to connect, 30 s per read and per write).
	# `protocols`, `headers` and `max_message` of the request are optional too.
	# Only `ws://` works: Tcp has no TLS, and `wss://` is `Refused`.
	opened = WsClient.connect_with!(
		{ url: "ws://127.0.0.1:9001/", protocols: ["echo"] },
		{ read_timeout: Duration.millis(200) },
	)?

	# Each call returns the updated connection: keep using the newest one. The
	# connection is opaque, so its methods work and `conn.link` as a field does not.
	sent = opened.conn.send!(Text("hi"))?
	(conn, reply) = sent.receive!()?

	# receive! waits through the read timeout. poll! is an idle deadline: it
	# gives TimedOut only when one read passes the platform's read deadline with
	# no bytes, so a peer that pings keeps it waiting. It keeps every byte read,
	# even inside a frame. Bound a wait for data with receive_within!.
	(conn2, polled) = conn.poll!()?

	# receive_within! is a total deadline: it gives TimedOut `ms` milliseconds
	# after the call, and a Ping, a Pong or a partial frame does not extend it.
	# (The adapter's 0.0.2 bounded each read instead, so a peer that pinged every
	# second kept it waiting for ever.)
	(conn3, within) = WsClient.receive_within!(conn2, 50)?
	conn4 = conn3.ping!([1, 2, 3])?

	# close_and_wait! sends Close and reads until the peer's Close arrives, and
	# gives the closure. `WsClient.ops` is the operations record it takes.
	closure = Ws.close_and_wait!(WsClient.ops, conn4, 1000, "done")?
	Ok(
		[
			"subprotocol: ${opened.protocol}",
			"reply: ${Str.inspect(reply)}",
			"poll: ${Str.inspect(polled)}",
			"within: ${Str.inspect(within)}",
			"closed: ${Str.inspect(closure)}",
		],
	)
}

## main!'s error type is fixed by the platform: `[Exit(I32), Interrupted]`
## plus what `?` adds. Map the adapter's error to an exit code here.
main! : List(OsStr) => Try({}, _)
main! = |_args|
	match session!({}) {
		Ok(lines) => Stdout.line!(Str.join_with(lines, "\n"))
		Err(err) => {
			Stderr.line!("WebSocket failed: ${Str.inspect(err)}")?
			Err(Exit(1))
		}
	}
