# basic-cli in one page

The platform, with the HTTP types from the `roc-lang/http` package.
`get_roc_module Path` for the full API, `search_symbols Cmd.exec_output!`
for one method, `search scope="basic-cli"` when you do not know the name,
`list_roc_index kind="examples"` for complete programs that all compile.

## The application contract

An app provides exactly one function. The header names `main!`, and the
platform fixes its type.

```roc
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst" }

import pf.OsStr
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	Stdout.line!("Hello, World!")?
	Ok({})
}
```

`args` holds only the real arguments. `Env.program_name!()` gives the program
name. `Err(Exit(code))` sets the process exit code. The platform prints any
other `Err` with `Str.inspect` and exits 1. Annotate the error as `_` so that
the union stays open, because every effect adds its own tag.

## Paths are the filesystem API

`File` holds only the buffered `File.Reader`. `Path` has everything else, and
an annotation turns a string literal into a `Path`:

```roc
config : Path
config = "app/config.toml"

text = config.read_utf8!()?
config.write_utf8!(text)?
kids = Path.utf8("app").list!()?
```

Reads, writes, metadata, links, and directories: `Path.read_bytes!`,
`Path.write_bytes!`, `Path.replace_utf8!`, `Path.delete!`, `Path.exists!`,
`Path.type!`, `Path.size_in_bytes!`, `Path.time_modified!`, `Path.rename!`,
`Path.hard_link!`, `Path.create_dir!`, `Path.create_all!`, `Path.delete_empty!`,
`Path.delete_all!`, `Path.list!`, `Path.join`, `Path.filename`, `Path.ext`.

Each one fails as `PathErr(IOErr, Path)`. The error holds the failing path, so
match on it and do not build it again.

```roc
match missing.read_utf8!() {
	Err(PathErr(NotFound, path)) => Stderr.line!("no such file: ${path.display()}")
	Err(err) => Err(ReadFailed(err))
	Ok(content) => Stdout.line!(content)
}
```

`IOErr` is `[AlreadyExists, BrokenPipe, Interrupted, IsADirectory, NotFound,
NotADirectory, Other(Str), OutOfMemory, PermissionDenied, Unsupported]`.

## OsStr, because arguments are not text

`OsStr` is `[Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]`. Use
`OsStr.display` to show one, `OsStr.to_str_try` when you need real `Str`, and
`OsStr.to_raw` to branch on the three cases. `Path` carries the same three.

## Standard streams

`Stdout.line!` and `Stderr.line!` append a newline. `write!` does not.
`write_bytes!` takes bytes. `Stdin.line!` strips the newline and returns
`Err(EndOfFile)` at the end. `Stdin.bytes!` reads what is buffered, and
`Stdin.read_to_end!` reads the pipe to its end.

## Commands

`Cmd.exec!` inherits your terminal. To capture output, chain a `Cmd`:

```roc
out = Cmd.new("git").args(["rev-parse", "HEAD"]).exec_output!()?
Stdout.line!(out.stdout_utf8)?
```

Builders: `Cmd.new`, `Cmd.new_str`, `Cmd.arg`, `Cmd.args`, `Cmd.env`,
`Cmd.envs`, `Cmd.clear_envs`, each with a `_str` variant that takes `Str`
instead of `OsStr`. Runners: `Cmd.exec_cmd!`, `Cmd.exec_output!`,
`Cmd.exec_output_bytes!`, `Cmd.exec_exit_code!`. `Cmd.check_available!` tells
whether a program is on `PATH` and does not run it.
`Cmd.run!` adds limits (`timeout_ms`, `output_limit`) and returns a `RunOutput`.
`Cmd.spawn!` returns a `Child` to `write!`, `read!`, `wait!` or `kill!`.

Also new in 0.24.0: `Tcp.listen!`/`accept!`, `Env.with_temp_dir!`,
`Monotonic.now!`, `Path.copy!`/`copy_dir!`/`canonicalize!`, and a seekable
`File.Reader` (`seek!`, `read_exactly!`, `chunks`).

## HTTP client

The platform has the effects and the `http` package has the types, so an app
that sends requests declares both packages and imports from each.

```roc
import pf.Http
import http.Request
import http.Response

body = Http.get_utf8!("https://example.com")?
res = Http.send!(Request.from_method(GET).with_uri("https://example.com"))?
code = Response.status(res)
```

`Http.get!` and `Http.send_json!` decode JSON into the record you annotate.
`Http.decode_json_response` decodes a response that you already have. Failures are
`InvalidUrl(Url.ParseErr)`, `HttpErr(TransportErr)`, `BadBody(Str)`, `JsonErr(_)`.
Method tags are uppercase: `GET`, `POST`, `PUT`, `DELETE`.

## SQLite

`Sqlite.query_many!` for many rows, `Sqlite.query!` for one, `Sqlite.execute!`
for writes, `Sqlite.prepare!` to reuse a statement. A row decoder is
`List(Str) -> (Stmt => Try(a, err))` built from the leaf decoders `Sqlite.str`,
`Sqlite.i64`, `Sqlite.f64`, `Sqlite.bytes` and their nullable variants. `Sqlite`
has no `map2`, so the record builder `{ ... }.Sqlite` does not compile. Combine
them by hand.

```roc
rows = Sqlite.query_many!({
	path: "todos.db",
	query: "SELECT id, task FROM todos WHERE status = :status;",
	bindings: [{ name: ":status", value: String("todo") }],
	rows: |cols| |stmt| Ok({ id: Sqlite.i64("id")(cols)(stmt)?, task: Sqlite.str("task")(cols)(stmt)? }),
})?
```

## The rest

| Module | What it gives you |
|---|---|
| `Env` | `Env.var!`, `Env.var_str!`, `Env.dict!`, `Env.cwd!`, `Env.set_cwd!`, `Env.exe_path!`, `Env.temp_dir!`, `Env.platform!` |
| `Utc` | `Utc.now!` as `U128` nanoseconds, `Utc.to_iso_8601`, `Utc.delta_as_millis`, `Utc.delta_as_nanos` |
| `Sleep` | `Sleep.millis!`, `Sleep.seconds!` |
| `Random` | `Random.seed_u32!`, `Random.seed_u64!`. Seeds only, not a generator |
| `Tcp` | `Tcp.connect!`, then `Tcp.Stream.read_line!` and its `read_exactly!`, `read_until!`, `read_up_to!`, `write!`, `write_utf8!` siblings. Every call takes an explicit timeout in ms |
| `Tty` | `Tty.enable_raw_mode!`, `Tty.disable_raw_mode!` |
| `Url` | `Url.parse`, `Url.to_str`, `Url.resolve`, and accessors for scheme, host, port, path, query, fragment |
| `Locale` | `Locale.get!`, `Locale.all!`, `Locale.parse` |

## Common mistakes on this platform

- `File` is not the file API. Use `Path`.
- A bare string literal is a `Path` only where an annotation says so. In an
  expression position write `Path.utf8("x")`.
- `Utc.now!` returns nanoseconds since the epoch, not seconds and not millis.
- `Tcp` and `Http` never block forever: the timeout is an argument, not a config.
- Verify with `roc_check`. It wraps a bare `main!` in this exact app header.
