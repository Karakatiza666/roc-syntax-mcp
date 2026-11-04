## A WebSocket server for basic-cli, through the roc-basic-cli-websocket adapter:
## `WsServer.serve!` accepts clients on a `Tcp.Listener`, routes each upgrade
## request, and runs your handlers over each connection.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	ws: "https://github.com/Karakatiza666/roc-websocket/releases/download/0.0.5/AKLgwxjBQN2XkE4G5sZtzrjPSxhwo6XmJRSPdWhpgVUN.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.3/9c6XLWHRSREuaoELdH1a835Yopw92Jxy2b5e151X6mZj.tar.zst",
}

import pf.Duration
import pf.OsStr
import pf.Stdout
import pf.Stderr
import pf.Tcp
import ws.Ws
import cli_ws.WsServer

## The one state `s` that every handler threads, across all connections.
State : { messages : U64, closed : U64, limit : U64 }

## Decide from the upgrade request: accept it with the subprotocols the server
## supports, IN THE SERVER'S ORDER OF PREFERENCE (the first one the client also
## offered is chosen, the client's own order does not matter), or refuse it with
## any final status from 200 to 599. A 1xx is `InvalidStatus`.
route : Ws.Upgrade -> WsServer.Route
route = |upgrade|
	if upgrade.resource.starts_with("/private") {
		Refuse({ status: 403, body: "no access to ${upgrade.resource}" })
	} else {
		Accept({ protocols: ["echo", "chat"], max_message: 1024 * 1024 })
	}

service : WsServer.Service(State)
service = {
	route,
	# Ws.Handlers: each handler gets the state and the connection, and returns
	# both. A connection is a value, so return the one a call gave you.
	handlers: {
		on_open!: |s, conn| Ok((s, conn)),
		on_message!: |s, conn, message| match conn.send!(message) {
			Ok(sent) => Ok(({ ..s, messages: s.messages + 1 }, sent))
			Err(err) => Err(err)
		},
		# on_close! also gets the connection, after the state: `|s, conn, closure|`.
		# The closing handshake has finished by the time it runs.
		on_close!: |s, _conn, closure| {
			_ = Stdout.line!("closed: ${Str.inspect(closure)}")
			Ok({ ..s, closed: s.closed + 1 })
		},
	},
	# serve! checks this after each connection, and returns when it is True.
	stop: |s| s.closed >= s.limit,
}

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	listener = Tcp.listen!("127.0.0.1", 9002, Duration.seconds(5))?
	# One connection at a time. `WsServer.serve_many!(listener, options, service,
	# slice_ms, state)` takes the same arguments plus a slice, and serves several
	# in turns by polling each for `slice_ms`; basic-cli has no readiness primitive
	# or threads, so latency grows with the number of idle connections.
	#
	# Like Ws.drive!, serve! returns the state WITH how the call ended, not a
	# Try, so a failed listener does not lose what the handlers counted.
	# A client whose handshake fails is dropped and serving goes on.
	(state, ended) = WsServer.serve!(listener, { read_timeout: Duration.seconds(30) }, service, { messages: 0, closed: 0, limit: 1 })
	Stdout.line!("done: ${state.messages.to_str()} messages, ${state.closed.to_str()} connections")?
	match ended {
		Ok({}) => Ok({})
		Err(err) => {
			Stderr.line!("server failed: ${Str.inspect(err)}")?
			Err(Exit(1))
		}
	}
}
