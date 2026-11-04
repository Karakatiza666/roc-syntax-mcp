## WebSockets: a chat room in a Durable Object with the hibernation API, the Worker that gives it the upgrade
## request, and a Worker-side echo with a subprotocol for contrast.
##
## The object form is the usual one. Workers can take the object out of memory while its sockets stay open (on the edge,
## after 90 s with no message), and each message wakes it as an event. The constructor and `init!` run again then. Roc
## keeps no state across events, so the state of a socket goes in its attachment (CBOR) or in the storage of the object.
## Roc writes the fields of a record in name order: a JS client reads `{"text":..,"user":..}` for `{ user, text }`.
##
## Project files. `roc-cfw sync` writes worker.js with `export const Room = objectClass("Room");`.
##   wrangler.toml new_sqlite_classes = ["Room"] in the migration, and a [[durable_objects.bindings]] entry for ROOMS
##                 compatibility_flags = ["enable_request_signal"]
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.6/HgUugW5V5QQbmrjdjkRhjiZ8B9D9gzpEkSwdojqJcW4p.tar.zst" }

import pf.Worker
import pf.Request
import pf.Response
import pf.Object
import pf.WebSocket
import pf.Log

Room := []

## One slot for each socket, kept while the object sleeps. The constant gives the type for `set!` and `get!`.
## There is one slot for each socket: two constants on one socket share it, and only the text of `BadData` names
## the constant. The value is 16,384 bytes or less (`TooLarge`).
## The attachment is CBOR: a field that can be empty is `x ?: a` or `x : Try(a, [Missing])`, not `Try(a, [Null])`.
Member : { name : Str }

member_slot : Object.Attachment(Member)
member_slot = Object.attachment("member")

Said : { text : Str }

room : Object.Class(Room)
room = Object.class("Room", {
	fetch!: |self, req| {
		name = req.query("name") ?? "anon"
		# One call: the socket pair, `acceptWebSocket`, and the 101 response with the client end.
		# `accept_with!(req, { tags: [name] })` adds tags: 10 or fewer, 256 characters or less each (`TooLarge`).
		# `self.sockets_with!({ tag: name })` finds the sockets with a tag.
		{ socket, response } = self.accept!(req)?
		# Write `{ name: name }` when the value has one field: `{ name }` is the value of `name`, a `Str`, and
		# `set!` says that it needs `{ name: Str }`.
		member_slot.set!(socket, { name: name })?
		# Workers answers "ping" with "pong" and sends no event, so the object can stay asleep.
		self.set_auto_response!({ request: "ping", response: "pong" })?
		# `broadcast_json!` sends the JSON text of a value to each open socket. `broadcast_json_with!` gives the count.
		self.broadcast_json!({ user: "room", text: "${name} joined" })?
		Ok(response)
	},
	# The message is a `WebSocket.Message`: `Text(...)` or `Bytes(...)`. `msg.json()` reads a text frame only.
	web_socket_message!: |self, from, msg| {
		member = member_slot.get!(from)?
		said : Said
		said = msg.json()?
		# `sockets!` gives the open sockets of this object. `!=` finds the sender: one JS socket has one id.
		for peer in self.sockets!() {
			if peer != from {
				# `send_json!` gives a `Try`. A statement must be `{}`, so write `_ =`. A closed peer is `Err(Closed)`.
				_ = peer.send_json!({ user: member.name, text: said.text })
			}
		}
		Ok({})
	},
	# Close the socket in reply to the close frame, as the Cloudflare example does. `close!` gives a `Try`, so a
	# statement is `_ = ...`: a bare call is "this expression produces a value", or a type mismatch of `close!` reported
	# at the `accept!` line. The code of the peer can be 1005 or 1006 (no code, no close frame), which an app cannot
	# send: that `close!` is `Err(BadCode)`. A reason of more than 123 bytes is `Err(TooLarge)`.
	# `closed.by` is `Peer`, `Us` (this side closed first) or `Transport` (1006: the connection dropped).
	web_socket_close!: |_self, socket, closed| {
		_ = socket.close!(closed.code, closed.reason)
		Ok({})
	},
})

rooms = Object.namespace("ROOMS", { class: room })

## The Worker side of a socket: for one short connection with no shared state. The task stays alive for the life of
## the socket (a 101 response is complete when its socket closes, and then the task has 30 s more).
echo! : Request => Try(Response, _)
echo! = |req| {
	# `accept_with!` picks the first of `protocols` (the order of the server) that the client asks for in
	# `Sec-WebSocket-Protocol`, and the 101 response names it. `socket.protocol()` gives it, "" for none.
	# `max_queued_bytes` (default 4 MiB): Workers has no backpressure, so a message that comes while the queue of
	# unread messages holds that much closes the socket with 1008. `self.accept_with!` of an object takes `protocols`.
	{ socket, response } = WebSocket.accept_with!(req, { protocols: ["echo.v1"] })?
	# The response goes out now, and the loop is the work after it. Read the request body before this point.
	# `Ctx.respond!` is gone.
	serve! = || {
		while Bool.True {
			# A wait in `receive!` has no deadline. `.timeout(ms)` makes one: `Err(Infra(TimedOut))`.
			# The close of the socket gives `Closed(record)`. Leave the loop after it.
			match socket.receive().timeout(30_000).run!() {
				# `send!` is `Err(Closed)` once either side closed, and `Err(Infra(SocketErr(t)))` for another throw.
				# A match on it needs both arms.
				Ok(msg) => match socket.send!(msg) {
					Ok({}) => {}
					Err(Closed) => break
					Err(Infra(SocketErr(_))) => break
				}
				Err(Infra(TimedOut)) => {
					_ = socket.close!(1001, "idle")
					break
				}
				# The record is `{ code, reason, clean, by }`: a pattern names `by` or ends in `..`, else the arm
				# "can never match". After this side's `close!`, `by` is `Us` and the code is the reply of the peer.
				Err(Closed({ code, by, .. })) => {
					if by == Peer and code != 1000 {
						Log.warn!("peer closed", { code })
					}
					break
				}
			}
		}
		Ok({})
	}
	Ok(response.after(serve!))
}

fetch! : Request => Try(Response, _)
fetch! = |req| match req.segments() {
	["room", name] =>
		if WebSocket.is_upgrade(req) {
			# Give the upgrade request to the object with `fetch!`, and its 101 response to the client with no
			# change. An RPC call cannot carry a socket.
			Ok(rooms.named(name).fetch!(req)?)
		} else {
			Ok(Response.from_status(426))
		}

	["echo"] => echo!(req)
	_ => Ok(Response.from_status(404))
}

worker = Worker.new({ fetch!: fetch!, objects: [room.erase()], bindings: [rooms.declare()] })

event! = |e| worker.event!(e)
