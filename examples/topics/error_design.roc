# Designing error tag unions in Roc.
#
# Roc's `Try(ok, err)` (formerly `Result`) lets you put anything in the
# `err` position. The new compiler's OPEN tag union (`[..]`) makes it
# possible to compose errors across modules without coupling them.
# This topic distills the conventions used by basic-cli.
#
# ─────────────────────────────────────────────────────────────────────────────
# 1. Tag with structured payload (record)
# ─────────────────────────────────────────────────────────────────────────────
#
# A tag's payload doesn't have to be a single scalar — use a RECORD when an
# error carries multiple related fields. This keeps signatures readable and
# lets callers destructure with field access instead of positional unpacking.

exec_failed_demo : I32 -> Try({}, [ExecFailed({ command : Str, exit_code : I32 })])
exec_failed_demo = |code|
	if code == 0 {
		Ok({})
	} else {
		Err(ExecFailed({ command: "ls -lah", exit_code: code }))
	}

# Caller matches with record destructuring:
#   match exec_failed_demo(1) {
#       Ok({}) => "ok"
#       Err(ExecFailed({ command, exit_code })) =>
#           "${command} failed with ${exit_code.to_str()}"
#   }

# ─────────────────────────────────────────────────────────────────────────────
# 2. Per-subsystem wrapper tags
# ─────────────────────────────────────────────────────────────────────────────
#
# Multiple modules can fail with the SAME underlying error type (e.g. IOErr),
# but the caller may want to know WHICH module failed. The convention is to
# wrap shared error types in a per-subsystem tag:
#
#   Stdout returns [StdoutErr(IOErr), ..]
#   Stderr returns [StderrErr(IOErr), ..]
#   File   returns [FileErr(IOErr), ..]
#   Path   returns [PathErr(IOErr), ..]
#
# Callers can write GENERIC handlers (`Err(_)`) OR specific ones
# (`Err(FileErr(NotFound))`) — both work because the wrapper preserves
# the inner IOErr.

handle_io : Try({}, [FileErr([NotFound, Other(Str)]), StdoutErr([Other(Str)])]) -> Str
handle_io = |result| match result {
	Ok({}) => "ok"
	Err(FileErr(NotFound)) => "file not found"
	Err(FileErr(Other(msg))) => "file: ${msg}"
	Err(StdoutErr(Other(msg))) => "stdout: ${msg}"
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Open unions (`[..]`) for composability
# ─────────────────────────────────────────────────────────────────────────────
#
# An OPEN error type means "this function's errors AND any others the caller
# adds." This is what lets `?` thread errors through a function that calls
# many different platform APIs.

# Returning an OPEN union: the actual return type the compiler infers will
# be `[StdoutErr(IOErr), FileErr(IOErr), ..]` — every Try the function
# bubbled up via `?` is unioned in.
pipeline! : Str => Try({}, _)
pipeline! = |name| {
	# Stdout.line!   returns Try({}, [StdoutErr(IOErr), ..])
	# File.read_utf8!returns Try(Str, [FileErr(IOErr)])
	# echo!(...)
	# contents = File.read_utf8!(name)?
	# echo!(contents)
	Ok({})
}

# Use `_` in the err position when you want the COMPILER to infer the full
# union for you. It's the idiomatic choice in application code — the compiler
# will tell you, in the error message of any unhandled match, exactly which
# tags need a branch.

# ─────────────────────────────────────────────────────────────────────────────
# 4. Multi-variant tag union (multiple ways to fail)
# ─────────────────────────────────────────────────────────────────────────────
#
# When a single API can fail in a few distinct ways, group them in one tag
# union and document each variant.

# Stdin's `line!` distinguishes EOF from a real IO error:
read_line_demo : Try(Str, [EndOfFile, StdinErr([Other(Str)])]) -> Str
read_line_demo = |r| match r {
	Ok(line) => line
	Err(EndOfFile) => ""
	Err(StdinErr(Other(msg))) => "stdin: ${msg}"
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Bubbling vs. mapping
# ─────────────────────────────────────────────────────────────────────────────
#
# Three ways to deal with an inner error you don't want to handle locally:
#
#   (a) `?` — bubble it as-is.
bubble : List(Str) -> Try(Str, _)
bubble = |strs| {
	first = strs.first()?
	Ok(first)
}

#   (b) `? Tag` — bubble it WRAPPED in a tag.
wrap : List(Str) -> Try(Str, [NoFirst([ListWasEmpty]), ..])
wrap = |strs| {
	first = strs.first() ? NoFirst
	Ok(first)
}

#   (c) `.map_err(|e| ...)` — bubble it, transformed by a function.
map_err_chain : List(Str) -> Try(Str, _)
map_err_chain = |strs|
	strs.first().map_err(|e| FirstFailed(e))

# (a) is rare in public APIs because it leaks the inner error type.
# (b) is what platform wrappers use (`Err(ioerr) => Err(StdoutErr(ioerr))`).
# (c) is convenient inside expression-style code that doesn't want a `match`.

# ─────────────────────────────────────────────────────────────────────────────
# 6. The Exit-code escape hatch
# ─────────────────────────────────────────────────────────────────────────────
#
# basic-cli platforms typically include `Exit(I32)` in `main!`'s error union:
#
#   requires {} { main! : List(Str) => Try({}, [Exit(I32), ..]) }
#
# An app that wants to surface a SPECIFIC non-zero exit code can return
# `Err(Exit(2))` instead of crashing. Everything else maps through the
# generic error path in `main_for_host!`.
#
# ─────────────────────────────────────────────────────────────────────────────
# 7. Rules of thumb
# ─────────────────────────────────────────────────────────────────────────────
#
# • Prefer OPEN unions (`[..]`) in public APIs so callers can compose.
# • CLOSE the union at the FFI boundary (`host_*!` declarations). The Roc
#   compiler extends open unions with caller context, which would change
#   the memory layout the host writes to. See the `platforms` topic.
# • Use a record payload as soon as an error needs more than ~1 field.
# • Wrap shared error types (`IOErr`) per subsystem so callers can match
#   either specifically or generically.
# • Use `_` in the err position of a function's signature when you want the
#   compiler to infer the full union from the body. Annotate explicitly
#   only when you want to NARROW the union (i.e. force handling of stray
#   tags before they reach the caller).
