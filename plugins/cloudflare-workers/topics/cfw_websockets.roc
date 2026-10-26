## WebSockets: a chat room in a Durable Object with the hibernation API, the Worker that gives it the upgrade
## request, and a Worker-side echo for contrast.
##
## The object form is the usual one. Workers can take the object out of memory while its sockets stay open (on the edge,
## after 90 s with no message), and each message wakes it as an event. The constructor and `init!` run again then. Roc
## keeps no state across events, so the state of a socket goes in its attachment (CBOR) or in the storage of the object.
## Roc writes the fields of a record in name order: a JS client reads `{"text":..,"user":..}` for `{ user, text }`.
##
## Project files. `node .roc-cfw/cli.mjs sync` writes worker.js with `export const Room = objectClass("Room");`.
##   wrangler.toml new_sqlite_classes = ["Room"] in the migration, and a [[durable_objects.bindings]] entry for ROOMS
##                 compatibility_flags = ["enable_request_signal"]
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst" }

import pf.Worker
import pf.Request
import pf.Response
import pf.Object
import pf.WebSocket

Room := []

## One slot for each socket, kept while the object sleeps. The constant gives the type for `set!` and `get!`.
## There is one slot for each socket: two constants on one socket share it, and only the text of `BadData` names
## the constant. The value is 16,384 bytes or less (`TooLarge`).
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
	# Close the socket in reply to the close frame, as the Cloudflare example does.
	web_socket_close!: |_self, socket, closed| {
		socket.close!(closed.code, closed.reason)
		Ok({})
	},
})

rooms = Object.namespace("ROOMS", { class: room })

## The Worker side of a socket: for one short connection with no shared state. The task stays alive for the life of
## the socket (a 101 response is complete when its socket closes, and then the task has 30 s more).
echo! : Request => Try(Response, _)
echo! = |req| {
	{ socket, response } = WebSocket.accept!(req)?
	# The response goes out now, and the loop is the work after it. Read the request body before this point.
	# `Ctx.respond!` is gone.
	serve! = || {
		while Bool.True {
			# A wait in `receive!` has no deadline. `.timeout(ms)` makes one: `Err(Infra(TimedOut))`.
			# The close of the socket gives `Closed`. Leave the loop after it.
			match socket.receive().timeout(30_000).run!() {
				Ok(msg) => {
					_ = socket.send!(msg)
				}
				Err(Infra(TimedOut)) => {
					socket.close!(1001, "idle")
					break
				}
				Err(Closed(_)) => break
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
