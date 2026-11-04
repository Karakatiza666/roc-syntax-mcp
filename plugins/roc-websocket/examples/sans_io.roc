## A server handshake and a few frames through the protocol state machine, with no platform.
app [] { ws: "https://github.com/Karakatiza666/roc-websocket/releases/download/0.0.5/AKLgwxjBQN2XkE4G5sZtzrjPSxhwo6XmJRSPdWhpgVUN.tar.zst" }

import ws.Handshake
import ws.Frame
import ws.Protocol

## The pure core with no I/O: a server-side handshake and a few frames from a
## client, fed through the protocol state machine.
main! = |_args| {
	key = "dGhlIHNhbXBsZSBub25jZQ=="
	echo!("Sec-WebSocket-Accept for ${key}: ${Handshake.accept_key(key)}\n")

	request = "GET /chat HTTP/1.1\r\nHost: example.com\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: chat\r\n\r\n"
	match Handshake.parse_upgrade(request) {
		Ok(upgrade) =>
			match Handshake.accept_response(upgrade, Handshake.choose_protocol(upgrade, ["chat"]), []) {
				Ok(response) => echo!(response)
				Err(NotOffered(p)) => echo!("not offered: ${p}\n")
			}
		Err(Rejected({ status, why })) => echo!(Handshake.rejection(status, why))
	}

	mask = [0x37, 0xfa, 0x21, 0x3d]
	bytes =
		Frame.fragments(Text("Hello, fragments"), 5)
			.append(Frame.ping("hi".to_utf8()))
			.append({ fin: Bool.True, opcode: Close, payload: [0x03, 0xE8] })
			.join_map(|f| Frame.encode(f, Masked(mask)) ?? [])
	(_, events) = Protocol.new(Server, 1024).receive(bytes)
	for event in events {
		echo!("${Str.inspect(event)}\n")
	}
	Ok({})
}
