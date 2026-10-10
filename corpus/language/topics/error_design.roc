# Designing error tag unions in Roc.
#
# Roc's `Try(ok, err)` (formerly `Result`) lets you put anything in the
# `err` position. A tag union in a return type is implicitly open, which makes
# it possible to compose errors across modules without coupling them.
# This topic describes the conventions that basic-cli uses.
#
#
# 1. Tag with structured payload (record)
#
#
# A tag's payload need not be a single scalar. Use a record when an
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

#
# 2. Per-subsystem wrapper tags
#
#
# Multiple modules can fail with the same underlying error type (e.g. IOErr),
# but the caller may want to know which module failed. The convention is to
# wrap shared error types in a per-subsystem tag:
#
#   Stdout returns [StdoutErr(IOErr)]
#   Stderr returns [StderrErr(IOErr)]
#   File   returns [FileErr(IOErr)]
#   Path   returns [PathErr(IOErr)]
#
# Callers can write generic handlers (`Err(_)`) or specific ones
# (`Err(FileErr(NotFound))`). Both work, because the wrapper preserves
# the inner IOErr.

handle_io : Try({}, [FileErr([NotFound, Other(Str)]), StdoutErr([Other(Str)])]) -> Str
handle_io = |result| match result {
	Ok({}) => "ok"
	Err(FileErr(NotFound)) => "file not found"
	Err(FileErr(Other(msg))) => "file: ${msg}"
	Err(StdoutErr(Other(msg))) => "stdout: ${msg}"
}

#
# 3. Return-type unions are open implicitly
#
#
# A tag union in an output position, such as a return type, is automatically
# open. It means "these errors and any others the caller adds." This lets `?`
# pass errors up through a function that calls many different platform APIs.
# Writing `..` there is redundant, and the compiler warns ("redundant open tag
# union"). Write `..` only in an input position, where it lets a function
# accept a union wider than the tags it names.

# The return type the compiler infers here will be
# `[StdoutErr(IOErr), FileErr(IOErr)]`: every Try the function bubbled up via
# `?` is unioned in.
pipeline! : Str => Try({}, _)
pipeline! = |_name| {
	# Stdout.line!   returns Try({}, [StdoutErr(IOErr)])
	# File.read_utf8!returns Try(Str, [FileErr(IOErr)])
	# echo!(...)
	# contents = File.read_utf8!(name)?
	# echo!(contents)
	Ok({})
}

# Use `_` in the err position when you want the compiler to infer the full
# union. It is the idiomatic choice in application code, because the error
# message of any unhandled match names exactly which tags need a branch.

#
# 4. Multi-variant tag union (multiple ways to fail)
#
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

#
# 5. Bubbling vs. mapping
#
#
# Three ways to pass on an inner error that you do not handle locally:
#
#   (a) `?` bubbles it as-is.
bubble : List(Str) -> Try(Str, _)
bubble = |strs| {
	first = strs.first()?
	Ok(first)
}

#   (b) `? Tag` bubbles it wrapped in a tag.
wrap : List(Str) -> Try(Str, [NoFirst([ListWasEmpty])])
wrap = |strs| {
	first = strs.first() ? NoFirst
	Ok(first)
}

#   (c) `.map_err(|e| ...)` bubbles it transformed by a function.
map_err_chain : List(Str) -> Try(Str, _)
map_err_chain = |strs|
	strs.first().map_err(|e| FirstFailed(e))

# (a) is rare in public APIs because it leaks the inner error type.
# (b) is what platform wrappers use (`Err(ioerr) => Err(StdoutErr(ioerr))`).
# (c) is convenient inside expression-style code that doesn't want a `match`.

#
# 6. The Exit error for an exit code
#
#
# basic-cli platforms typically include `Exit(I32)` in `main!`'s error union:
#
#   requires { main! : List(Str) => Try({}, [Exit(I32), ..]) }
#
# An app that needs a specific non-zero exit code can return `Err(Exit(2))`
# and not crash. `main_for_host!` maps every other error through its generic
# error path.
#
#
# 7. Rules of thumb
#
#
#   Keep the error type anonymous. Write the tag union inline in the `Try` err
#   position rather than declaring a nominal type to hold it: structural unions
#   with the same shape are already compatible, so no boundary between two
#   modules needs a `map_err` that only converts. Declare a type only to close
#   the union at an FFI boundary, or to attach methods to it. See the `idioms`
#   topic.
#   If you do declare an error type, nest it in the type whose methods return
#   it: `Url.ParseErr`, `CString.NulError`, not a top-level `ParseErr`. The
#   qualified name tells the reader which operation failed. See `modules`.
#   Do not write `..` in a return type: it is already open, and callers compose.
#   Close the union at the FFI boundary (`host_*!` declarations). The Roc
#   compiler extends open unions with caller context, which would change
#   the memory layout the host writes to. See the `platform_abi` topic.
#   Use a record payload as soon as an error needs more than ~1 field.
#   Wrap shared error types (`IOErr`) per subsystem so callers can match
#   either specifically or generically.
#   Use `_` in the err position of a function's signature when you want the
#   compiler to infer the full union from the body. Annotate explicitly
#   only when you want to narrow the union (i.e. force handling of stray
#   tags before they reach the caller).

# 8. The Try method family
#
# In addition to `map_err` and `map_ok`, `Try` has methods for the common
# error-handling patterns that need no `match`:
#
#   on_err   : Try(ok, a), (a -> Try(ok, b)) -> Try(ok, b)
#   catch    : Try(ok, err), (err -> a), (ok -> a) -> a
#   map_both : Try(a, b), (a -> c), (b -> d) -> Try(c, d)
#   map2     : Try(a, err), Try(b, err), (a, b -> c) -> Try(c, err)
#   collapse : Try(a, a) -> a
#   ok_or    : Try(ok, _err), ok -> ok
#   err_or   : Try(_ok, err), err -> err
#
# Each mapping method has an effectful twin taking `=>` and returning `=>`:
# `on_err!`, `catch!`, `map_both!`, `map2!`, `map_ok!`, `map_err!`.
#
# `on_err` is the recovery combinator: it gets the err and returns another
# `Try`, so fallbacks chain. `catch` handles both sides and returns a plain
# value. `collapse` unwraps a `Try` whose ok and err types are the same, which
# is what `catch` leaves behind when both branches produce the same type.
#
# `??` supplies a default inline instead of bubbling. See the `try_operator`
# and `operators` topics.
