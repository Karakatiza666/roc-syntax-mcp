# roc-websocket

WebSocket (RFC 6455) for Roc, independent of any platform. It is a package that
does no I/O itself: it holds the shared types, a pure core of frames, handshake
and a protocol state machine, and a client over a byte stream. An app gets I/O
from an adapter, a separate package for one platform (see Adapters below), so
it pins the platform, this package and the adapter.

`get_roc_syntax(topic: "ws_client")` and `ws_server` for basic-cli programs,
`ws_adapters` for code generic over adapters, `ws_frames` for the pure core. `get_roc_module Ws` for every feature
alias, `search_symbols Client.open!` for one signature.

## The contract

```roc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	ws: "https://github.com/Karakatiza666/roc-websocket/releases/download/0.0.5/AKLgwxjBQN2XkE4G5sZtzrjPSxhwo6XmJRSPdWhpgVUN.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.3/9c6XLWHRSREuaoELdH1a835Yopw92Jxy2b5e151X6mZj.tar.zst",
}
```

Modules: `Ws` (shared types), `Client`, `Server`, `Protocol`, `Handshake`, `Frame`,
`CloseCode`, plus `Base64` and `Sha1`. A type from `Ws` used only in an
annotation still needs `import ws.Ws`. There are no extensions
(`permessage-deflate` is never offered; a server that picks one is refused).

The server driver is `Server`: an adapter gives `Server.accept!(transport, link,
options)` a `Server.Transport` (`write_bytes!`, `read_up_to!`) and the link value,
and gets the 101 written and a `Server.Conn` back; `Server.read_request!` stops
after reading, so the app can `request.upgrade()` and `request.accept!` or
`request.refuse!({ status, headers, body })` (any final status 200 to 599).
`Server.Conn` has the methods of the client's, and `Server.ops({})` is its record.
It serves one connection per call: running several is the adapter's or the app's.

## A connection is a value

Each call takes the connection and returns the updated one, so bytes read past a
frame, a half-received message and a pending close travel from call to call.
Thread the new value; the old one lacks that state. `WsClient.Error` is a closed
union, so keep `Stdout` calls out of a function that returns it (`ws_client`).

```roc
ask! : Str => Try(Ws.Message, WsClient.Error)
ask! = |text| {
	opened = WsClient.connect!({ url: "ws://127.0.0.1:9001/", protocols: ["echo"] })?
	sent = opened.conn.send!(Text(text))?
	(conn, reply) = sent.receive!()?
	_ = Ws.close_and_wait!(WsClient.ops, conn, 1000, "")?
	Ok(reply)
}
```

A connection is opaque: methods work, `conn.link` as a field does not, and
`conn.link()` gives the link value back. `conn.map_link(change)` changes it
between calls (a read timeout for one call) without touching the protocol state.

## Code generic over adapters

An adapter is a record of the operations its platform has. Code that needs a few
takes a closed record of exactly those fields, so it does not compile with an
adapter that lacks one, and works with every adapter that has them. The error is
`Ws.Error(e)`, which is `[Closed(Ws.Closure), Closing, ..e]`, shared by every
field.

```roc
echo_once! : { send! : c, Ws.Message => Try(c, Ws.Error(e)), receive! : c => Try((c, Ws.Message), Ws.Error(e)) }, c => Try(c, Ws.Error(e))
echo_once! = |ws, conn| {
	(conn2, message) = (ws.receive!)(conn)?
	(ws.send!)(conn2, message)
}
```

A closed record is exact: passing a whole adapter record, or `Client.ops({})`,
where `Ws.Core(c, e, {})` is wanted is a type mismatch. Pick the fields at the
call site, `echo_once!({ send!: ops.send!, receive!: ops.receive! }, conn)`. The
open `..r` of the aliases is for a layer that forwards the record onward.

## Closing

`close!` sends Close and returns at once. `receive!` then delivers the messages
still on their way and ends with `Err(Closed({ by: Us, .. }))`, and `send!` and
a second `close!` give `Err(Closing)` meanwhile. The end of a connection is the
`Closed(closure)` tag, so match it as the normal exit. `Ws.close_and_wait!`
does both steps. `Ws.drive!(ops, conn, state, handlers)` runs push-style
handlers over a pull connection and returns `(state, ended)`, not a `Try`, so
`drive!(...)?` does not compile; `on_close!` gets the connection after the state. `Ws.messages(ops, conn)` is a `Stream` whose last item is the
`Err(Closed(closure))` that ended it.

## Features

| Alias | Fields |
| --- | --- |
| `Core(c, e, r)` | `send!`, `receive!`, `close!` |
| `Ping`, `Pong` | `ping!`, `pong!`, payload at most 125 bytes (`ControlTooLong`) |
| `Frames` | `send_frame!`, `receive_frame!` |
| `ReceiveWithin` | `receive_within!(conn, ms)` |
| `Poll` | `poll!`, `TimedOut` after the platform's own read deadline |
| `Sender`, `Handlers(s, c, e)` | push-model servers: send and close, and callbacks |
| `Connect`, `Accept` | open a client connection, accept an upgrade |
| `Topics`, `Persist`, `Buffered`, `AutoResponse` | publish/subscribe, saved state, queue size, runtime-side replies |
| `Bytes`, `Random`, `Transport(b, e)` | what `Client.open!` needs from a platform |

`Basic`, `Raw`, `Timed`, `Push` are pre-composed. Names that earlier releases
had are gone: `Ws.Dial` is `Ws.Connect`, `Ws.Request` is `Ws.ConnectRequest`,
`Client.Link` is `Client.Transport`, and `poll!` gives `TimedOut`, not `Idle`.

## Adapters

Adapters are separate packages. An adapter is a record of the operations its
platform supports, typed with the aliases below (`Ws.Core`, `Connect`, `Accept`,
`Sender`, `AutoResponse`, `Persist`, ...), so code that needs a feature does not
compile with an adapter that lacks it. A platform that gives the program a byte
stream (basic-cli, basic-webserver) is wrapped over `Client` and `Server` and the
pure core: the adapter supplies a `Client.Transport` or `Server.Transport` and
the package does the handshake, masking, fragments and Ping replies. A platform that hands out whole messages
(cloudflare-workers) implements `Ws.Core` directly and uses none of the pure core.

| Adapter | Release | Platform | Side | Why a side is missing |
| --- | --- | --- | --- | --- |
| `roc-basic-cli-websocket`, modules `WsClient` and `WsServer` | `https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.3/9c6XLWHRSREuaoELdH1a835Yopw92Jxy2b5e151X6mZj.tar.zst` | basic-cli 0.26.0, roc-websocket 0.0.5 | client and server | none |
| `roc-basic-webserver-websocket`, module `WsClient` | `https://github.com/Karakatiza666/roc-basic-webserver-websocket/releases/download/0.0.2/63RHisM5dNvGRLkMFurQZd7Gp1AqWpThfd5Dvtb2CTKj.tar.zst` | basic-webserver 0.20.0, roc-websocket 0.0.5 | client | basic-webserver refuses 1xx responses, so it cannot answer an upgrade |
| `roc-cloudflare-workers-websocket`, modules `Conn` (pull, connect and accept) and `Push` (Durable Object sockets) | `https://github.com/Karakatiza666/roc-cloudflare-workers-websocket/releases/download/0.0.3/FTAaUpFV8tZKVVbLUaB4SdMKykJNsC9q6MtXRwwqKTJi.tar.zst` | cloudflare-workers 0.0.6, roc-websocket 0.0.5 | client and server | none |

The app pins the platform release an adapter was built for, with this package's
release that the adapter names and the adapter beside it; any other release is a different type. Only
`ws://` works over basic-cli and basic-webserver, which have no TLS.

## Traps

- A library error is a tag of `e`, not a new type: matching `Closed` and passing
  the rest on works with `return Err(other)`. A loop whose every exit is a
  `return` ends the function, and an `Ok(...)` after it is "unreachable code".
- `Protocol.receive` never fails. A violation comes back as `Write(close_frame)`
  then `Closed(closure)`, and the Close goes out only if you write it.
- A client must mask what it sends and a server must not: take it from
  `protocol.masking(key)`, not from a hard-coded `Masked` or `Unmasked`.
- `CloseCode.normal` is a value of type `U16`; `normal()` is "not a function".
- Close codes 1005 and 1006 are only reported, never sent: `close!` gives
  `InvalidClose`, and `CloseCode.payload` gives `InvalidCode`.
