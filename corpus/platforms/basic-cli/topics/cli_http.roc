## The HTTP client: effects from the platform's `Http`, types from the
## `roc-lang/http` package, so an app that sends requests declares both.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Http
import pf.OsStr
import pf.Stdout
import pf.Url
import http.Header
import http.Method
import http.Request
import http.Response

main! : List(OsStr) => Try({}, _)
main! = |_args| demo!()

## The work lives in a helper, as in upstream's http-client example. Nightly
## 2026-10-04 crashes in `roc check` when `?` on `send_json!` sits directly in
## an annotated `main!`.
demo! : () => Try({}, _)
demo! = || {
	# The shortest path: a GET whose body you want as text.
	body = Http.get_utf8!("https://example.com")?
	Stdout.line!("${body.count_utf8_bytes().to_str()} bytes")?

	# The general path: build a Request, send it, read the Response.
	req = Request.from_method(GET)
		.with_uri("https://example.com/api")
		.add_header("accept", "application/json")
		.with_timeout(TimeoutMilliseconds(5_000))
	res = Http.send!(req)?
	Stdout.line!("status ${Response.status(res).to_str()}")?

	# JSON in one step. The annotation tells the decoder what to build, so it
	# is required.
	user : { name : Str, id : U64 }
	user = Http.get!("https://example.com/user/1")?
	Stdout.line!("${user.name} is ${user.id.to_str()}")?

	# JSON out. `send_json!` encodes the second argument as the body and returns
	# the raw Response, so decoding the reply is a separate, annotated step.
	res2 = Http.send_json!(
		Request.from_method(POST).with_uri("https://example.com/users"),
		{ name: "ada" },
	)?
	created : { id : U64 }
	created = Http.decode_json_response(res2)?
	Stdout.line!("created ${created.id.to_str()}")?

	Ok({})
}

## Method tags are uppercase. `Get` does not compile.
methods : List(Method)
methods = [GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS]

## Every failure mode, named. The tags are closed at the edges, so a caller
## that matches all of them needs no catch-all.
classify : [
	InvalidUrl(Url.ParseErr),
	HttpErr(Http.TransportErr),
	BadBody(Str),
] -> Str
classify = |err|
	match err {
		InvalidUrl(_) => "the URL is not one we can send to"
		HttpErr(_) => "the request never completed"
		BadBody(_) => "the response body was not what we asked for"
	}

expect classify(BadBody("not utf-8")) == "the response body was not what we asked for"

## `Header` is a plain record, so building one takes no constructor. `add_header`
## appends one to a request.
accept_json : Header
accept_json = { name: "accept", value: "application/json" }

## You can decode a response that you already have as a separate step. Do this
## when the status decides whether the body needs decoding.
read_body! : Response => Try({ ok : Bool }, _)
read_body! = |res|
	if Response.status(res) == 200 {
		Http.decode_json_response(res)
	} else {
		Err(UnexpectedStatus(Response.status(res)))
	}
