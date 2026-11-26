## Raw HTTP/1.1 messages, parsed from bytes with the `HTTP` module of
## lukewilliamboswell/roc-parser 6.0: one request or response, a pipeline of
## requests, header lookup, chunked bodies, and the messages it rejects.
##
## This module only parses bytes, from a socket or a capture file. It is not
## the roc-lang/http package (the `http` package topic), and not the request
## type that basic-webserver gives to a handler. `HTTP.Request` and
## `HTTP.Response` are the types and also hold the functions:
## `HTTP.Request.parse_bytes`, `.parser`, `.decoder` and `.header`. A message
## that arrives in pieces is read with `HTTP.Request.decoder` (the
## parser_streaming topic). An `HTTP.Request` literal is checked at build time
## (parser_compile_time).
##
## Full manual: requests, header fields, responses, how the body is found,
## chunked bodies, pipelined messages, use inside a larger grammar, rejected
## messages and request smuggling, and what is out of scope:
## https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/http.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst",
}

import pf.Stdout
import parser.Parser
import parser.HTTP

# --- One request -------------------------------------------------------------
#
# `HTTP.Request.parse_bytes(bytes, {})` takes `List(U8)`, not `Str`. A string
# literal is a type mismatch, so call `.to_utf8()` on text. It returns the
# request itself, and the input must hold exactly one message.

post : List(U8)
post = "POST /notes?id=1 HTTP/1.1\r\nHost: example.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello".to_utf8()

expect {
	request = HTTP.Request.parse_bytes(post, {}) ?? crash "unreachable"
	# `target` is as sent: not decoded, not split at `?`.
	request.target == "/notes?id=1" and request.body == "hello".to_utf8()
}

# A match on `Method` must have an `Extension` branch, or it is not exhaustive.
# Method names are case-sensitive, so `get` is `Extension("get")`, not `Get`.
method_name : HTTP.Method -> Str
method_name = |method| match method {
	Get => "GET"
	Head => "HEAD"
	Post => "POST"
	Put => "PUT"
	Delete => "DELETE"
	Connect => "CONNECT"
	Options => "OPTIONS"
	Trace => "TRACE"
	Patch => "PATCH"
	Extension(name) => name
}

method_of : Str -> Try(HTTP.Method, [InvalidHttp(HTTP.Error)])
method_of = |text| HTTP.Request.parse_bytes(text.to_utf8(), {}).map_ok(|request| request.method)

expect method_of("get / HTTP/1.1\r\nHost: a\r\n\r\n") == Ok(Extension("get"))

# --- Header fields -----------------------------------------------------------
#
# `request.header(name)` compares names without case and gives the first
# match, or `Err(Missing)`. There is no `HTTP.header`. A repeated field stays
# in `headers` once per line, so walk the list to see every value. Values lose
# the spaces around them.

expect {
	text = "GET / HTTP/1.1\r\nHost: a\r\nX-Tag: one\r\nx-tag:  two \r\n\r\n"
	request = HTTP.Request.parse_bytes(text.to_utf8(), {}) ?? crash "unreachable"
	request.header("X-TAG") == Ok("one")
	and request.header("Accept") == Err(Missing)
	and request.headers.map(|h| h.value) == ["a", "one", "two"]
}

# --- Responses and framing ---------------------------------------------------
#
# The headers decide where a body ends. With no `Content-Length` and no
# `Transfer-Encoding`, a request has no body, but a response body runs to the
# end of the input. A 1xx, 204 or 304 response has no body. A response to HEAD
# also has none, but `parse_bytes` cannot see the request: the response
# decoder takes the request methods for that.

expect HTTP.Response.parse_bytes("HTTP/1.1 200 OK\r\n\r\nbody then more".to_utf8(), {}).map_ok(|r| r.body.len()) == Ok(14)

# A chunked body is decoded. Chunk extensions and trailers are checked, then
# dropped.
expect {
	text = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n6;note=x\r\npedia \r\n0\r\n\r\n"
	HTTP.Response.parse_bytes(text.to_utf8(), {}).map_ok(|r| r.body) == Ok("Wikipedia ".to_utf8())
}

# --- Pipelines and short input -----------------------------------------------
#
# `parse_bytes` fails on bytes after the message. For one message and the
# bytes after it, run the parser: `HTTP.Request.parser({}).run(bytes)` gives
# `{ value, rest }`. `HTTP.parse_requests(bytes, {})` reads all of them, and
# fails unless the input ends exactly at the end of a message.

two : List(U8)
two = "GET /a HTTP/1.1\r\nHost: a\r\n\r\nGET /b HTTP/1.1\r\nHost: a\r\n\r\n".to_utf8()

expect HTTP.Request.parse_bytes(two, {}).is_err()
expect HTTP.Request.parser({}).run(two).map_ok(|r| (r.value.target, r.rest.len())) == Ok(("/a", 28))
expect HTTP.parse_requests(two, {}).map_ok(|all| all.map(|r| r.target)) == Ok(["/a", "/b"])

# The error is `InvalidHttp(Parser.Diagnostic(HTTP.Problem))`: match the
# problem tag. A message cut short is an error, the same as a bad one, so
# read a whole message before `parse_bytes`, or feed pieces to the decoder.
problem : Str -> Str
problem = |text|
	match HTTP.Request.parse_bytes(text.to_utf8(), {}) {
		Ok(_) => "accepted"
		Err(InvalidHttp({ problem: p, .. })) => Str.inspect(p)
	}

expect problem("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 10\r\n\r\nhi") == "IncompleteBody"

# --- Rejected messages -------------------------------------------------------
#
# To prevent request smuggling, the parser rejects a message whose end a proxy
# could read differently. Close the connection. Do not retry a cleaned copy.

expect problem("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n") == "ConflictingFraming"
expect problem("POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: gzip, chunked\r\n\r\n") == "UnsupportedTransferCoding"
expect problem("GET / HTTP/1.1\r\nHost : a\r\n\r\n") == "WhitespaceBeforeColon"
# Only CRLF ends a line. A bare LF fails.
expect problem("GET / HTTP/1.1\nHost: a\n\n") == "LfWithoutCr"
# HTTP/1.1 needs exactly one Host. HTTP/1.0 needs none.
expect problem("GET / HTTP/1.1\r\n\r\n") == "MissingHost"
expect problem("GET / HTTP/1.0\r\n\r\n") == "accepted"

# --- Inside a larger parser --------------------------------------------------
#
# `HTTP.Request.parser({})` is a `Parser(Parser.Utf8.Bytes, HTTP.Request, _)`.
# Give it a tag of your own with `map_problem`, so a caller can tell an HTTP
# failure from a failure of the rest of the grammar.

capture : Parser(Parser.Utf8.Bytes, { label : Str, request : HTTP.Request }, _)
capture =
	Parser.const(|label| |request| { label, request })
		.keep(Parser.chomp_while(|byte| byte != '\n').map(|bytes| Str.from_utf8_lossy(bytes)))
		.skip(Parser.Utf8.codeunit('\n'))
		.keep(HTTP.Request.parser({}).map_problem(|p| HttpProblem(p)))

expect capture.parse_str("health\nGET /up HTTP/1.1\r\nHost: a\r\n\r\n").map_ok(|c| c.request.target) == Ok("/up")
expect
	match capture.parse_str("health\nGET / HTTP/1.1\r\n\r\n") {
		Err(ParseError({ problem: HttpProblem(MissingHost), .. })) => True
		_ => False
	}

main! = |_args| {
	# `InvalidHttp` is an open tag, so `?` adds it to the error of `main!`.
	request = HTTP.Request.parse_bytes(post, {})?
	content_type = request.header("content-type") ?? "none"
	Stdout.line!("${method_name(request.method)} ${request.target} (${content_type})")?
	Ok({})
}
