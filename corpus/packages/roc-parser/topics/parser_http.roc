## Raw HTTP/1.1 messages, parsed from bytes with the `HTTP` module of
## lukewilliamboswell/roc-parser: one request or response, a pipeline of
## requests, header lookup, chunked bodies, and the messages it rejects.
##
## This module only parses bytes, from a socket or a capture file. It is not
## the roc-lang/http package (the `http` package topic), and not the request
## type that basic-webserver gives to a handler.
##
## Full manual: requests, header fields, responses, how the body is found,
## chunked bodies, pipelined messages, use inside a larger grammar, rejected
## messages and request smuggling, and what is out of scope:
## https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/http.adoc
## (`conformance.adoc` says that the parser rejects a lowercase method. It does not.)
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/2.0.0/7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW.tar.zst",
}

import pf.Stdout
import parser.Parser
import parser.Utf8
import parser.HTTP

# --- One request -------------------------------------------------------------
#
# Every `parse_*` function takes `List(U8)`, not `Str`. A string literal is a
# type mismatch, so call `.to_utf8()` on text.

post : List(U8)
post = "POST /notes?id=1 HTTP/1.1\r\nHost: example.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello".to_utf8()

expect {
	{ request, rest } = HTTP.parse_request(post) ?? crash "unreachable"
	# `target` is as sent: not decoded, not split at `?`.
	request.target == "/notes?id=1" and request.body == "hello".to_utf8() and rest == []
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
method_of = |text| HTTP.parse_request(text.to_utf8()).map_ok(|parsed| parsed.request.method)

expect method_of("get / HTTP/1.1\r\nHost: a\r\n\r\n") == Ok(Extension("get"))

# --- Header fields -----------------------------------------------------------
#
# `HTTP.header` compares names without case and gives the first match, or
# `Err(Missing)`. A repeated field stays in `headers` once per line, so walk
# the list to see every value. Values lose the spaces around them.

expect {
	text = "GET / HTTP/1.1\r\nHost: a\r\nX-Tag: one\r\nx-tag:  two \r\n\r\n"
	{ request, rest: _ } = HTTP.parse_request(text.to_utf8()) ?? crash "unreachable"
	HTTP.header(request.headers, "X-TAG") == Ok("one")
	and HTTP.header(request.headers, "Accept") == Err(Missing)
	and request.headers.map(|h| h.value) == ["a", "one", "two"]
}

# --- Responses and framing ---------------------------------------------------
#
# The headers decide where a body ends. With no `Content-Length` and no
# `Transfer-Encoding`, a request has no body, but a response body runs to the
# end of the input. A 1xx, 204 or 304 response has no body. A response to HEAD
# also has none, but the parser cannot see the request, so it reads the next
# bytes as the body. Do not give it such a response with bytes after it.

expect {
	r = HTTP.parse_response("HTTP/1.1 200 OK\r\n\r\nbody then more".to_utf8())
	r.map_ok(|ok| (ok.response.body.len(), ok.rest.len())) == Ok((14, 0))
}

# A chunked body is decoded. Chunk extensions and trailers are checked, then
# dropped.
expect {
	text = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n6;note=x\r\npedia \r\n0\r\n\r\n"
	HTTP.parse_response(text.to_utf8()).map_ok(|ok| ok.response.body) == Ok("Wikipedia ".to_utf8())
}

# --- Pipelines and short input -----------------------------------------------
#
# `parse_request` reads one message and returns the bytes after it as `rest`.
# `parse_requests` reads all of them, and fails unless the input ends exactly
# at the end of a message.

two : List(U8)
two = "GET /a HTTP/1.1\r\nHost: a\r\n\r\nGET /b HTTP/1.1\r\nHost: a\r\n\r\n".to_utf8()

expect HTTP.parse_requests(two).map_ok(|all| all.map(|r| r.target)) == Ok(["/a", "/b"])

# There is no "need more bytes" result. A message cut short is an error, the
# same as a bad one. Read a whole message before you parse. The parser has no
# size limits either, so limit the bytes you read from a socket.
expect HTTP.parse_requests("GET /a HTTP/1.1\r\nHost: a\r\n\r\nGET /b".to_utf8()).is_err()
expect HTTP.parse_request("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 10\r\n\r\nhi".to_utf8()) == Err(InvalidHttp({ offset: 50, message: "body is shorter than Content-Length" }))

# --- Rejected messages -------------------------------------------------------
#
# To prevent request smuggling, the parser rejects a message whose end a proxy
# could read differently. Close the connection. Do not retry a cleaned copy.

rejected : Str -> Str
rejected = |text| match HTTP.parse_request(text.to_utf8()) {
	Ok(_) => "accepted"
	Err(InvalidHttp({ message, offset: _ })) => message
}

expect rejected("POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n") == "both Transfer-Encoding and Content-Length"
expect rejected("POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: gzip, chunked\r\n\r\n") == "unsupported transfer coding (only a single chunked is supported)"
expect rejected("GET / HTTP/1.1\r\nHost : a\r\n\r\n") == "whitespace between a field name and its colon"
# Only CRLF ends a line. A bare LF fails.
expect rejected("GET / HTTP/1.1\nHost: a\n\n") == "LF not preceded by CR"
# HTTP/1.1 needs exactly one Host. HTTP/1.0 needs none.
expect rejected("GET / HTTP/1.1\r\n\r\n") == "an HTTP/1.1 request needs a Host field"
expect rejected("GET / HTTP/1.0\r\n\r\n") == "accepted"

# --- Inside a larger parser --------------------------------------------------
#
# `HTTP.request` and `HTTP.response` are `Parser(Utf8.Bytes, _)`. They leave
# the bytes after the message for the next parser, and fail with
# `ParseError({ message, offset })`, where the message starts with
# "invalid HTTP request:".

capture : Parser(Utf8.Bytes, { label : Str, request : HTTP.Request })
capture =
	Parser.const(|label| |request| { label, request })
		.keep(Parser.chomp_while(|byte| byte != '\n').map(|bytes| Str.from_utf8_lossy(bytes)))
		.skip(Utf8.codeunit('\n'))
		.keep(HTTP.request)

expect Utf8.parse_str(capture, "health\nGET /up HTTP/1.1\r\nHost: a\r\n\r\n").map_ok(|c| c.request.target) == Ok("/up")
expect Utf8.parse_str(HTTP.request, "GET / HTTP/1.1\r\n\r\n").map_ok(|_| {}) == Err(ParseError({ message: "invalid HTTP request: an HTTP/1.1 request needs a Host field", offset: 0 }))

main! = |_args| {
	# `InvalidHttp` is an open tag, so `?` adds it to the error of `main!`.
	{ request, rest: _ } = HTTP.parse_request(post)?
	content_type = HTTP.header(request.headers, "content-type") ?? "none"
	Stdout.line!("${method_name(request.method)} ${request.target} (${content_type})")?
	Ok({})
}
