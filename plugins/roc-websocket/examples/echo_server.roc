## The server driver over a scripted link with no platform: Server.accept! and Ws.drive! echoing each message.
app [] { ws: "https://github.com/Karakatiza666/roc-websocket/releases/download/0.0.5/AKLgwxjBQN2XkE4G5sZtzrjPSxhwo6XmJRSPdWhpgVUN.tar.zst" }

import ws.Ws
import ws.Server
import ws.Frame

## The server driver over a link with no platform: what a client would send
## (an upgrade request, two masked messages, a Close) comes from a list, one
## item per read, and the server's writes are kept. `Ws.drive!` runs push
## handlers that echo each message over the pull connection.
Link : { reads : List(List(U8)), written : List(List(U8)) }

transport : Server.Transport(Link, [])
transport = {
	write_bytes!: |link, bytes| Ok({ ..link, written: link.written.append(bytes) }),
	read_up_to!: |link, n| match link.reads {
		[] => Ok((link, End))
		[bytes, .. as rest] =>
			if bytes.len() > n {
				Ok(({ ..link, reads: [bytes.drop_first(n)].concat(rest) }, Data(bytes.take_first(n))))
			} else {
				Ok(({ ..link, reads: rest }, Data(bytes)))
			}
	},
}

main! = |_args| {
	request = "GET /echo HTTP/1.1\r\nHost: example.com\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: chat, echo\r\n\r\n"
	from_client =
		[Frame.text("hello"), Frame.binary([1, 2, 3]), { fin: Bool.True, opcode: Close, payload: [0x03, 0xE8] }]
			.map(|f| Frame.encode(f, Masked([0x37, 0xfa, 0x21, 0x3d])) ?? [])
	link = { reads: [request.to_utf8()].concat(from_client), written: [] }

	opened = match Server.accept!(transport, link, { protocols: ["echo"] }) {
		Ok(o) => o
		Err(err) => crash "not accepted: ${Str.inspect(err)}"
	}
	echo!("subprotocol: ${opened.protocol}\n")

	ops = Server.ops({})
	handlers = {
		on_open!: |count, conn| Ok((count, conn)),
		on_message!: |count, conn, message| match (ops.send!)(conn, message) {
			Ok(sent) => Ok((count + 1, sent))
			Err(err) => Err(err)
		},
		on_close!: |count, conn, closure| {
			echo!("closed with ${closure.code.to_str()} by ${Str.inspect(closure.by)} after ${count.to_str()} messages, ${conn.link().written.len().to_str()} writes\n")
			Ok(count)
		},
	}
	# drive! gives the state whether the run ended cleanly or with an error.
	(count, ended) = Ws.drive!(ops, opened.conn, 0.U64, handlers)
	match ended {
		Ok(closure) => echo!("drive! ended with ${closure.code.to_str()} after ${count.to_str()} messages\n")
		Err(err) => crash "drive! failed after ${count.to_str()} messages: ${Str.inspect(err)}"
	}

	# What the server wrote first: the 101.
	echo!(Str.from_utf8(opened.conn.link().written.first() ?? []) ?? "")
	Ok({})
}
