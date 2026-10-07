# basic-webserver in one page

The platform, with the HTTP types from the `roc-lang/http` package.
`get_builtin_module Server` for the full API, `lookup_builtin Server.Outcome`
for one type, `search scope="basic-webserver"` when you do not know the name,
`list_roc_index kind="examples"` for complete programs that all compile.

## The application contract

An app provides exactly three functions. The header names `Context` and
`program`. The platform requires `[Context : context] for program`.

```roc
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.17.0/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import http.Response

# `init!` builds this once. Every request gets the same immutable value.
Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |request, _context| Ok(Server.respond(Response.from_status(200)))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})
```

`program = { init!, respond!, shutdown! }` takes no annotation: annotating it
means writing the platform's `requires` record by hand. The host logs an
unhandled `respond!` error with request context and sends a 500. It logs an
unhandled `init!` or `shutdown!` error and exits 1.

`ShutdownReason` is `[ApplicationRequested, Interrupt, Terminate,
StartupFailed(Str), RuntimeFailed(Str)]`.

## Config

`Server.default_config` is a complete production configuration. Narrow it by
chaining, never by building a `Config` literal.

```roc
config =
	Server.default_config
		.with_listen({ host: "127.0.0.1", port: 8080 })
		.with_request_body_limit(1024 * 1024)
		.with_timeouts({ header_ms: 5000, body_idle_ms: 10_000, keep_alive_idle_ms: 30_000,
			handler_queue_ms: 5000, response_idle_ms: 10_000 })
		.with_file_roots([Server.file_root({ id: "static", path: Path.utf8("public") })])
```

Other builders: `with_limits`, `with_request_body_limits`,
`with_request_metadata_limits`, `with_graceful_shutdown`, `with_writable_roots`,
`with_native_routes`, `with_file_transfer_limits`, `with_body_sink_limits`,
`with_sse_limits`, `with_access_log`, `with_metrics`. Every `default_*`
constant on `Server` is the value one of them overrides.

## Reading the request

| Call | Returns |
| --- | --- |
| `request.method()` | `Method` |
| `request.target()` | `Target`: `Resource({ raw_path, raw_query })`, `Authority(..)`, or `Asterisk` |
| `request.headers()` | `List(Header)` in received order |
| `request.authority()` | `[Absent, Present(Authority)]` |
| `request.body()` | `Body`, a request-scoped stream |

`Method` tags are uppercase: `[OPTIONS, GET, POST, PUT, DELETE, HEAD, TRACE,
CONNECT, PATCH, QUERY, Unknown(Str)]`. Matching on `Get` does not compile.

```roc
raw_path =
	match request.target() {
		Resource({ raw_path: p, .. }) => p
		_ => ""
	}

match request.method() {
	GET => list!(context)
	POST => create!(context, request)
	other => Ok(Server.respond(Response.from_status(405)))
}
```

The body is a stream, not a `List(U8)`. Narrow the limit first, then read:
`request.body().with_limit(64 * 1024).read_all!()?`. For large payloads use
`read!` (one `Chunk`/`End` at a time), `fold_chunks!`, or `write_file!`.
You can only narrow a limit, never widen it past the config.

## Responding

`respond!` returns a `Server.Outcome`, built by one of four constructors:

| Constructor | Effect |
| --- | --- |
| `Server.respond(response)` | Send the response, keep serving |
| `Server.stream(source)` | Server-sent events from an `Sse.Source` |
| `Server.file_response({ files, relative })` | Serve a file under a configured `FileRoot` |
| `Server.stop_after(response)` | Send it, then shut down. `stop_after_with_code` sets the exit code |

`Response` comes from the `http` package, not the platform:
`Response.from_status(200)`, then `with_status`, `with_headers`, `add_header`,
`with_body`. The body is `List(U8)`, so use `Str.to_utf8`.

```roc
Ok(Server.respond(
	Response.from_status(200)
		.add_header("Content-Type", "text/html; charset=utf-8")
		.with_body(Str.to_utf8("<h1>hi</h1>"))))
```

SSE builds a source from a state machine:
`Sse.unfold!(state, |s| Ok(Emit({ event: Sse.Event.data(text), state: next, wake: Immediately })))`,
where a step returns `Emit`, `Wait`, or `End`.

## The rest of the platform

| Module | For |
| --- | --- |
| `Sqlite` | `open!`, `execute!`, `query!`, `query_many!`, `prepare!`, `begin!`. Params and rows use derived codecs |
| `Path` `File` `OsStr` | Filesystem paths and file I/O. Errors are `IOErr` |
| `Cmd` | Child processes: `exec_str!`, output capture, timeouts |
| `Http` | Outbound HTTP client, separate from the inbound server |
| `Html` `Attribute` | Server-rendered HTML, escaped by default. `Html.text` escapes, `dangerously_include_unescaped_html` does not |
| `MultipartFormData` | `parse_multipart_form_data`, `parse_form_url_encoded` |
| `Sse` | Event sources for `Server.stream` |
| `Tcp` `Env` `Sleep` `Stdout` `Stderr` `UnixTime` | The remaining primitives |

## Concurrency and lifecycle

`respond!` calls run concurrently and in no defined order, each synchronously on
one host thread. For ordering or atomicity between requests, use a SQLite
transaction or an external service. There is no reducer and no global store.

`Context` is immutable startup data the host lends to each handler. A subsystem
handle inside it, such as `Sqlite.Db`, refers to host-owned concurrency-safe
state. So a pool belongs there, and a mutable record does not.

Handlers and ready SSE transitions share one bounded FIFO execution domain, so a
handler that blocks uses capacity that the config limits. Parked SSE sources
use none. On shutdown the host stops accepting, drains within a deadline,
then calls `shutdown!` once. Effects that cannot start during the drain return a
stopping error.

## Traps

- Every example in the upstream 0.17.0 tag pins platform 0.16.0. Pin
  0.17.0.
- `respond!` receives the context by value and cannot mutate it. Per-request
  state lives in the handler. Shared mutable state lives behind SQLite.
- `Server.Request` is not `http.Request`. The inbound type has a streaming
  body. The outbound one has a complete `List(U8)`.
- `to_host` and `from_host` methods are the ABI boundary. An application must
  never call them, and search excludes them for that reason.
- `Path.Path` is not `Str`. Build it with `Path.utf8`, read it with `Path.display`.
