# basic-cli in one page

The platform, with the HTTP types from the `roc-lang/http` package.
`get_roc_module Path` for the full API, `search_symbols Cmd.capture!`
for one method, `search scope="basic-cli"` when you do not know the name,
`list_roc_index kind="examples"` for complete programs that all compile.

## The application contract

An app provides exactly one function. The header names `main!`, and the
platform fixes its type.

```roc
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst" }

import pf.OsStr
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	Stdout.line!("Hello, World!")?
	Ok({})
}
```

`args` holds only the real arguments; `Env.program_name!()` is the program name. `Err(Exit(code))` sets the process exit code. `Err(Interrupted)` exits 130
(Ctrl-C) or 143 (`Signal.catch!`ed `Terminate`). The platform prints any other
`Err` with `Str.inspect` and exits 1. Annotate the error as `_` so that the
union stays open, because every effect adds its own tag. `OsStr` and `Path`
compare by content, so `args.contains("--verbose")` works.

## Paths are the filesystem API

`File` holds only the buffered `File.Reader` (`lines()`, `chunks()`) and
`File.Writer` (`File.with_writer!`). `Path` has everything else, and an
annotation turns a string literal into a `Path`:

```roc
config : Path
config = "app/config.toml"

text = config.read_utf8!()?
config.write_utf8!(text)?
kids = Path.utf8("app").list!()?
```

Reads, writes, metadata, links, and directories: `Path.read_bytes!`,
`Path.write_bytes!`, `Path.append_utf8!`, `Path.replace_utf8!`, `Path.delete!`, `Path.exists!`,
`Path.type!`, `Path.size_in_bytes!`, `Path.time_modified!` (a `Utc`), `Path.rename!`,
`Path.symlink!`, `Path.set_permissions!`, `Path.create_dir!`, `Path.create_all!`, `Path.delete_all!`,
`Path.list!`, `Path.join`, `Path.filename`, `Path.ext`.

Each one fails as `PathErr(IOErr, Path)`. The error holds the failing path, so
match on it and do not build it again.

```roc
match missing.read_utf8!() {
	Err(PathErr(NotFound, path)) => Stderr.line!("no such file: ${path.display()}")
	Err(err) => Err(ReadFailed(err))
	Ok(content) => Stdout.line!(content)
}
```

`IOErr` has `NotFound`, `PermissionDenied`, `AlreadyExists`, `TimedOut`,
`ConnectionRefused`, `Interrupted`, `Other(Str)` and eight more.

## OsStr, because arguments are not text

`OsStr` is `[Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]`. Use
`OsStr.display` to show one, `OsStr.to_str_try` when you need real `Str`, and
`OsStr.to_raw` to branch on the three cases. `Path` carries the same three.

## Standard streams

`Stdout.line!` and `Stderr.line!` append a newline. `write!` does not.
`write_bytes!` takes bytes. `Stdin.line!` strips the newline and returns
`Err(EndOfInput)` at the end. An empty `Ok` is real data. `lines()` and `chunks()` are streams for `for!`, on `Stdin`, file readers,
`Tcp.Connection` and HTTP responses. `Stdin.read_to_end!` reads
the pipe to its end.

## Commands

Four runners. `Cmd.call!(program, args)` inherits your terminal and requires
success. To read the output, chain a `Cmd.Command`:

```roc
head = Cmd.new("git").args(["rev-parse", "HEAD"]).capture!()?
Stdout.line!(head.trim())?
```

`capture!` returns stdout as text and requires success. `run!` returns a
`Cmd.Output` (`status`, `stdout_bytes`, `stderr_bytes`) and treats a bad exit as
data; `require_success()` makes it an error. `spawn!` returns a `Child` to
`read!`, `wait!`, `poll!` or `kill!`. Builders: `Cmd.new`, `arg`, `args`,
`env`, `clear_envs`, `cwd`, `stdout`, `stderr`, `timeout(Duration)`. Arguments are `OsStr`, and a literal is one.
Failures are `CmdErr(Cmd.Err)`, `BadExitStatus(output)` and `Interrupted`.
`Cmd.check_available!` checks `PATH` without running anything.

## HTTP client

The platform has the effects and the `http` package has the types, so an app
that sends requests declares both packages and imports from each.

```roc
import pf.Http
import http.Request
import http.Response

body = Http.get_utf8!("https://example.com", {})?
res = Http.send!(Request.from_method(GET).with_uri("https://example.com"), {})?
code = Response.status(res)
```

`Http.get!` and `Http.send_json!` decode JSON into the record you annotate.
`Http.decode_json_response` decodes a response that you already have. Failures are
`InvalidUrl(Url.ParseErr)`, `HttpErr(TransportErr)`, `BadBody(Str)`, `JsonErr(_)`.
Every sender takes trailing options: `{}` returns the first response, and
`{ max_redirects: 5 }` follows redirects. `Http.send_streaming!` returns the
status before the body, and `response.chunks()` streams it. Method tags are
uppercase: `GET`, `POST`, `PUT`, `DELETE`.

## SQLite

`Sqlite.open!(path, {})` returns a `Db`. `db.query_one!`, `db.query_all!`,
`db.execute!`, `db.rows` (a lazy stream) and `db.transaction!` take a query
and, for reads, a `Decoder`. Each `${...}` in a query is a bound parameter that
names its storage class (`String(s)`, `Integer(n)`), never pasted into the SQL.
A decoder is a value: build one from `Sqlite.Decoder.i64`, `Sqlite.Decoder.str`
and the other leaves with the record builder `.Sqlite.Decoder`.

```roc
db = Sqlite.open!("todos.db", {})?
rows = db.query_all!(
	"SELECT id, task FROM todos WHERE status = ${String("todo")}",
	{ id: Sqlite.Decoder.i64("id"), task: Sqlite.Decoder.str("task") }.Sqlite.Decoder,
)?
```

## The rest

| Module | What it gives you |
|---|---|
| `Env` | `Env.var!`, `Env.var_str!`, `Env.dict!`, `Env.cwd!`, `Env.exe_path!`, `Env.temp_dir!` |
| `System` | `System.target!()`, then `.arch()` and `.os()` |
| `Utc`, `Monotonic`, `Duration` | `Utc.now!`, `Monotonic.now!` and `elapsed!` / `since` give a `Duration`; `Duration.seconds`, `.to_str` |
| `Sleep` | `Sleep.millis!`, `Sleep.seconds!`. Both are fallible |
| `Signal` | `Signal.catch!`, `Signal.poll!`. Caught requests add `Interrupted` to effects |
| `Random` | `Random.seed_u32!`, `Random.seed_u64!`. Seeds only, not a generator |
| `Tcp`, `UnixSocket` | `Tcp.connect!(host, port, { connect_timeout, io_timeout })` gives a `Tcp.Connection` with `read_line!`, `read_exactly!`, `read_until!`, `read_up_to!`, `write_utf8!`, `write_bytes!`, `lines()`. Failures are `TcpErr(IOErr)` |
| `Tty` | `Tty.enable_raw_mode!`, `Tty.disable_raw_mode!` |
| `Url` | `Url.parse`, `Url.to_str`, `Url.resolve`, and accessors for scheme, host, port, path, query |
| `Locale` | `Locale.get!`, `Locale.all!`, `Locale.parse` |

## Common mistakes on this platform

- `File` is not the file API. Use `Path`.
- A bare string literal is a `Path` only where an annotation says so. In an
  expression position write `Path.utf8("x")`.
- `Utc` and `Monotonic` are types. Subtract with `since`, and compare `Duration`s.
- A timeout is a `Duration`, and `Duration.zero` expires at once.
- Write `True` and `False`, not `Bool.True`.
- Verify with `roc_check`. It wraps a bare `main!` in this exact app header.
