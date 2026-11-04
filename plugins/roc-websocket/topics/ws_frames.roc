## The pure core with no I/O: frames and masking, close codes, the opening
## handshake and the protocol state machine, each as plain functions over bytes
## and text. Every `expect` here runs under `roc test`.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	ws: "https://github.com/Karakatiza666/roc-websocket/releases/download/0.0.5/AKLgwxjBQN2XkE4G5sZtzrjPSxhwo6XmJRSPdWhpgVUN.tar.zst",
}

import pf.Stdout
import ws.Frame
import ws.CloseCode
import ws.Handshake
import ws.Protocol

# A frame is a record, `{ fin, opcode, payload }`, with the payload unmasked. The
# constructors `Frame.text`, `binary`, `ping` and `pong` make whole frames. The
# opcode is a tag (`Continuation`, `Text`, `Binary`, `Close`, `Ping`, `Pong`),
# and `fin` takes `Bool.True` or `True`.
#
# Masking is chosen at the wire, not on the frame: a client encodes with
# `Masked(key)` (4 random bytes), a server with `Unmasked`.
expect Frame.encode(Frame.text("hi"), Unmasked) == Ok([129, 2, 104, 105])
expect Frame.encode(Frame.text("hi"), Masked([1, 2, 3, 4])) == Ok([129, 130, 1, 2, 3, 4, 105, 107])

# encode refuses what RFC 6455 forbids instead of writing it.
expect Frame.encode(Frame.text("hi"), Masked([1, 2, 3])) == Err(BadMask(3))
expect Frame.encode(Frame.ping(List.repeat(0, 126)), Unmasked) == Err(ControlTooLong(126))
expect Frame.encode({ fin: Bool.False, opcode: Ping, payload: [] }, Unmasked) == Err(FragmentedControl)

# decode takes the masking the RECEIVER requires (a server `ExpectMasked`, a
# client `ExpectUnmasked`), returns the frame and the bytes after it, and says
# how many bytes in all an unfinished frame needs: read `n - bytes.len()` more
# and never read into the next frame.
expect Frame.decode([0x81], ExpectMasked) == Err(Incomplete(2))
expect Frame.decode([0x81, 0x02, 104, 105, 0xFF], ExpectUnmasked) == Ok({ frame: Frame.text("hi"), rest: [255] })
expect Frame.decode([0x81, 0x02, 104, 105], ExpectMasked) == Err(Invalid("a client frame is not masked"))

# fragments splits ONE message into frames of at most `size` bytes: the first
# keeps the opcode, the rest are Continuation, only the last has fin. A size of
# 0 is read as 1, and a Text message is cut by bytes, not characters. It is the
# reader that joins the payloads before decoding as UTF-8.
expect Frame.fragments(Text("abcdefg"), 3).map(|f| f.fin) == [Bool.False, Bool.False, Bool.True]

# Close codes. They are values, not functions: `CloseCode.normal`, not `normal()`.
# payload builds the body of a Close frame and refuses a code that may never be
# sent (1005 and 1006 are only ever reported), or a reason over 123 bytes.
expect CloseCode.payload(1000, "bye") == Ok([3, 232, 98, 121, 101])
expect CloseCode.payload(1006, "") == Err(InvalidCode(1006))
expect CloseCode.is_sendable(3000) and !CloseCode.is_sendable(1004)
# An empty Close body is code 1005 (none given), not an error.
expect CloseCode.parse([]) == Ok({ code: 1005, has_code: Bool.False, reason: "" })

# Handshake. parse_url gives the default port (80 for ws, 443 for wss) and a
# resource that is never empty; a fragment is an error.
expect Handshake.parse_url("wss://example.com") == Ok({ host: "example.com", port: 443, resource: "/", secure: Bool.True })
expect Handshake.parse_url("ws://example.com/#x") == Err(BadUrl("a WebSocket URL has no fragment: ws://example.com/#x"))
# The key is the RFC 6455 section 1.3 vector.
expect Handshake.accept_key("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
# client_request wants EXACTLY 16 key bytes; the error carries the length it got.
expect Handshake.client_request({ url: { host: "h", port: 80, resource: "/", secure: Bool.False }, key: [1], protocols: [], headers: [] }) == Err(BadKey(1))

# Protocol is the receiving state machine. Feed it the bytes of any read: it keeps
# a half frame, joins fragments, answers Ping with a Write(pong), and turns
# every protocol violation into Write(Close) then Closed(closure). Bytes after a
# whole frame stay in the state until the next call.
expect {
	(_, events) = Protocol.new(Server, 1024).receive([0x81, 0x82, 0, 0, 0, 0, 104, 105])
	events == [Message(Text("hi"))]
}
expect {
	# An unmasked frame to a server: the connection fails with 1002 by us.
	(p, events) = Protocol.new(Server, 1024).receive([0x81, 0x02, 104, 105])
	events.len() == 2 and p.is_done()
}

main! = |_args| Stdout.line!("run `roc test` on this file")
