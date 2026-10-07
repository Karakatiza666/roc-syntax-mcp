## Server-sent events: `Server.stream` over an `Sse.Source` state machine.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.17.0/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Sse
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |request, _context| {
	path =
		match request.target() {
			Resource({ raw_path, .. }) => raw_path
			_ => ""
		}
	match path {
		# `stream`, not `respond`. The connection stays open and the host owns
		# framing, timers, and cancellation.
		"/events" => Ok(Server.stream(Sse.unfold!(0, tick!)))
		"/named" => Ok(Server.stream(Sse.unfold!(0, named!)))
		_ => Ok(Server.respond(Response.from_status(404)))
	}
}

# `unfold!` retains the state between steps. Each step returns one of three
# tags: `Emit` sends an event, `Wait` sleeps without sending, `End` closes.
# `wake` is `Immediately` or `After(millis)`.
tick! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
tick! = |count|
	if count >= 5 {
		Ok(End)
	} else {
		Ok(
			Emit({
				event: Sse.Event.data("tick ${U64.to_str(count)}"),
				state: count + 1,
				wake: After(1000),
			}),
		)
	}

# A named event carries a type the browser dispatches on, plus one data line
# per list entry. `id` lets a client resume with `Last-Event-ID`, and `retry`
# sets its reconnect delay.
named! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
named! = |count| {
	id =
		match Sse.event_id("event-${U64.to_str(count)}") {
			Ok(valid) => valid
			Err(_) => Sse.clear_event_id
		}
	options = { ..Sse.default_event_options, id, retry: Sse.retry_after(2000) }
	Ok(
		Emit({
			event: Sse.Event.named_with("update", ["target #board", "payload ${U64.to_str(count)}"], options),
			state: count + 1,
			wake: Immediately,
		}),
	)
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})
