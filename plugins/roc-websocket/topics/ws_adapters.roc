## Code that takes a WebSocket connection without naming the platform: a closed
## record of the fields it needs, `Ws.Error(e)`, and a test double that is just a
## record of functions. No socket is opened, so the program runs anywhere.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	ws: "https://github.com/Karakatiza666/roc-websocket/releases/download/0.0.5/AKLgwxjBQN2XkE4G5sZtzrjPSxhwo6XmJRSPdWhpgVUN.tar.zst",
}

import pf.Stdout
import ws.Ws

## The operations a function uses are a CLOSED record of exactly those fields.
## An adapter's whole operations record, or `Client.ops({})`, has more fields
## and is refused by a closed `Ws.Core(c, e, {})` ("type mismatch ... Client.Ops
## vs Ws.Core"). Pick the fields at the call site: `{ send!: ops.send!, receive!: ops.receive! }`.
## `..r` in an alias is for a layer that forwards the whole record onward.
##
## `Ws.Error(e)` is `[Closed(Ws.Closure), Closing, ..e]`, shared by every field of
## every adapter, so one `e` fits all the fields and a caller can match on it.
echo_all! : { send! : c, Ws.Message => Try(c, Ws.Error(e)), receive! : c => Try((c, Ws.Message), Ws.Error(e)) }, c => Try(Ws.Closure, Ws.Error(e))
echo_all! = |ws, conn| {
	var $c = conn
	# The loop is the last expression and every exit is a `return`: an `Ok(...)`
	# written after it is reported as unreachable code.
	while Bool.True {
		match (ws.receive!)($c) {
			Ok((next, message)) => {
				# Closing is not an exceptional state here: once this endpoint has sent
				# Close, send! gives Err(Closing), and a plain `?` passes it up.
				$c = (ws.send!)(next, message)?
			}
			# The end of the connection is a value, not a failure: the closure says how.
			Err(Closed(closure)) => return Ok(closure)
			Err(other) => return Err(other)
		}
	}
}

## A test double: the connection is the list of messages still to be delivered,
## and the error row is `[]`, so only `Closed` and `Closing` can happen.
Inbox : List(Ws.Message)

fake : Ws.Basic(Inbox, [])
fake = {
	send!: |inbox, _message| Ok(inbox),
	receive!: |inbox| match inbox {
		[first, .. as rest] => Ok((rest, first))
		[] => Err(Closed(Ws.dropped))
	},
	close!: |inbox, _code, _reason| Ok(inbox),
}

main! = |_args| {
	# An adapter with more fields than echo_all! needs still fits: pick two.
	closure = match echo_all!({ send!: fake.send!, receive!: fake.receive! }, [Text("a"), Binary([1])]) {
		Ok(c) => c
		Err(Closed(c)) => c
		Err(Closing) => Ws.dropped
	}
	Stdout.line!("ended with ${closure.code.to_str()}, clean: ${Str.inspect(closure.clean)}")?

	# Ws.messages is a Stream whose LAST item is the error that ended it,
	# Err(Closed(closure)) at a normal end, so test for that, not for any Err.
	items = Stream.collect!(Ws.messages({ receive!: fake.receive! }, [Text("x")]))
	Stdout.line!(Str.inspect(items))?

	# Ws.drive! runs push-style handlers over a pull connection and threads the
	# state. It returns the state WITH how the run ended, `(state, Try(closure, err))`,
	# so an error does not lose the state; it is not a Try, and `drive!(...)?`
	# does not compile. on_close! gets the connection after the state, like the
	# other two handlers: `|state, conn, closure|`, not `|state, closure|`.
	handlers = {
		on_open!: |seen, conn| Ok((seen, conn)),
		on_message!: |seen, conn, message| Ok((seen.append(message), conn)),
		on_close!: |seen, _conn, _closure| Ok(seen),
	}
	(seen, ended) = Ws.drive!({ receive!: fake.receive! }, [Text("p"), Text("q")], [], handlers)
	Stdout.line!("${Str.inspect(seen)} ended: ${Str.inspect(ended)}")
}
