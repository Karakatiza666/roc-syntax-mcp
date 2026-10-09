# Effectful functions in Roc.
#
# A function that calls an effectful function is effectful. Its name ends in
# `!`, and its type uses `=>` (thick arrow) instead of `->` (thin arrow). Every
# effect starts in a function that the platform provides. The platform calls
# the effectful entry point, `main!`.

# `echo!` is available without an `import`. It writes its string to stdout
# unchanged and appends no newline, so every call below writes an explicit `\n`.
effect_demo! : Str => {}
effect_demo! = |msg|
	echo!("${msg}\n")

# The compiler infers purity, so the annotation is optional.
print! = |something| {
	echo!("${Str.inspect(something)}\n")
}

log_each! : List(Str) => {}
log_each! = |items| {
	for item in items {
		echo!("${item}\n")
	}
	{}
}

# Only an effectful function can call an effectful function. A pure function
# and a top-level constant cannot, so the compiler can run them at compile time
# (see `compile_time`).
#
# @rejects effectful top level value
# message = effect_demo!("Sam")
#
# @rejects type mismatch
# shout : Str -> {}
# shout = |name| effect_demo!(name)
#
# A wrong `->` annotation is an error. A warning that lets the program run is
# planned. A missing `!` gives a warning:
#
# @warns effectful function name
# greet = |name| echo!("Hello, ${name}!\n")
#
# A pure function can crash, allocate memory, and use `dbg` and `expect`.

# Roc has no type for "pure or effectful". A higher-order builtin exists twice,
# and the twin with `!` takes an effectful function: `Try.map_ok` and
# `Try.map_ok!`, `List.map_try` and `List.map_try!`. A pure one rejects an
# effectful argument.
#
# @rejects type mismatch
# log_all! : List(Str) => List({})
# log_all! = |names| names.map(|n| effect_demo!(n))
log_ok! : Try(Str, [Empty]) => Try({}, [Empty])
log_ok! = |t| t.map_ok!(|s| echo!("${s}\n"))
