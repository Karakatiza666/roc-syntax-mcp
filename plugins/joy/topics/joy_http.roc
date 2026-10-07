## HTTP from a Joy app: `Http.get`, a full `Http.request` with headers, a JSON
## body and a timeout, the response arriving as a message, and why a 404 is
## `Ok`. Ends with a test that answers the request the way the host does.
app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "https://github.com/niclas-ahden/joy/releases/download/0.34.0/2B3sC6U2dWkVUK2VY2gJS5Wej9YCDo3ZYq2e7tMWUCNp.tar.zst",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [div, button, input, text]
import html.Attribute exposing [on_click, on_input, value]
import pf.Effect
import pf.Http

Model : { query : Str, status : Str }

# The error union is spelled out because a type alias cannot hold `..`, and
# there is no `Http.Error` to name instead. A transport failure is the only
# `Err`: a timeout, or a request that never completed.
Reply : Try(Http.Response, [HttpErr([Timeout, NetworkError])])

Msg : [Typed(Str), Load, Loaded(Reply), Save, Saved(Reply)]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ query: "", status: "" }, [])

# `Http.get` and `Http.post` send no headers and never time out. A request that
# needs either starts from `default_request`.
save_request : Str -> Http.Request
save_request = |q| {
	..Http.default_request,
	# A tag, not "POST".
	method: POST,
	uri: "/api/search",
	headers: [{ name: "Content-Type", value: "application/json" }],
	# Bytes, not a Str.
	body: Str.to_utf8("{\"q\":\"${q}\"}"),
	# A tag around U64 milliseconds, or `NoTimeout`. A bare number is refused.
	timeout_ms: TimeoutMilliseconds(5000),
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Typed(q) => ({ ..model, query: q }, [])
		# The callback is a lambda: `Http.get(url, Loaded)` does not compile,
		# because a tag is not a function.
		Load => ({ ..model, status: "loading" }, [Http.get("/api/items", |r| Loaded(r))])
		Save => ({ ..model, status: "saving" }, [Http.request(save_request(model.query), |r| Saved(r))])
		# The status is not an error. 4xx and 5xx arrive as `Ok`, so check it.
		Loaded(Ok(resp)) | Saved(Ok(resp)) if resp.status >= 200 and resp.status < 300 =>
			({ ..model, status: Str.from_utf8_lossy(resp.body) }, [])
		Loaded(Ok(resp)) | Saved(Ok(resp)) => ({ ..model, status: "HTTP ${resp.status.to_str()}" }, [])
		Loaded(Err(HttpErr(Timeout))) | Saved(Err(HttpErr(Timeout))) => ({ ..model, status: "timed out" }, [])
		Loaded(Err(HttpErr(NetworkError))) | Saved(Err(HttpErr(NetworkError))) => ({ ..model, status: "offline" }, [])
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			# A void element takes its attributes and nothing else.
			input([value(model.query), on_input(|s| Typed(s))]),
			button([on_click(Load)], [text("Load")]),
			button([on_click(Save)], [text("Save")]),
			text(model.status),
		],
	)

subscriptions = |_model| []

# --- Answering a request in a test ------------------------------------------
#
# The effect carries its callback, so a test can call it with what the host
# would pass. The host reports a transport failure as a status: 0 for a request
# that never completed, 1 for a timeout. `Http` turns both into `Err`.

# The message is an argument. If the test wrote `Load` here, the compiler would
# know which effects come back and would warn that the match is already decided.
answer : Msg, U16 -> Str
answer = |sent, status| {
	(_, effects) = update({ query: "", status: "" }, sent)
	match effects {
		[HttpSend(_, _, _, _, _, callback)] => {
			reply = Box.unbox(Box.unbox(callback)({ status, headers: [], body: [] }))
			(after, _) = update({ query: "", status: "" }, reply)
			after.status
		}
		_ => "no request"
	}
}

expect answer(Load, 404) == "HTTP 404"
expect answer(Load, 500) == "HTTP 500"
expect answer(Load, 0) == "offline"
expect answer(Load, 1) == "timed out"
