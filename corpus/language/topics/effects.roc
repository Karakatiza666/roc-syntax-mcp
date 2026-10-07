# Effectful functions in Roc.
#
# Convention: any function whose name ends with `!` may perform side effects.
# Its type signature uses `=>` (thick arrow) instead of `->` (thin arrow).
# Pure functions never call effectful functions.

# An effectful function from the platform / standard library.
# `echo!` is available without an `import`.
#
# `echo!` writes its string to stdout unchanged. It appends no newline, so
# every call below interpolates an explicit `\n`.
effect_demo! : Str => {}
effect_demo! = |msg|
	echo!("${msg}\n")

# Only an effectful context can call an effectful function. The type system
# enforces this rule, so a pure function cannot hide a side effect.

print! = |something| {
	echo!("${Str.inspect(something)}\n")
}

# Effectful pipelines compose with pure ones, but the resulting
# function must be effectful (named with `!` and using `=>`).
log_each! : List(Str) => {}
log_each! = |items| {
	for item in items {
		echo!("${item}\n")
	}
	{}
}
