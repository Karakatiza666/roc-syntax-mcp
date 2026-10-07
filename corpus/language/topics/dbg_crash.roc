# `dbg`, `crash`, and `return` statements.

# `dbg` is print-line debugging. It works in both pure and effectful contexts.
# It may run at compile time (constant folding) or at runtime.
dbg_keyword = || {
	foo = 42

	dbg foo
	# `dbg(foo)` also works.

	foo
}

# `crash` halts the program with a message.
# Use it only for unreachable branches or unrecoverable conditions like OOM.
# For a recoverable error, return a `Try`.
unreachable_branch = |n| {
	if n < 0 {
		crash "n was supposed to be non-negative"
	}

	n * 2
}

# `return` causes the enclosing function to return immediately.
short_circuit = |arg| {
	if !arg {
		return 99
	}

	# rest of the function
	42
}

# `crash` can mark code you have not written yet with a message of your own:
implement_me_later : Str -> Str
implement_me_later = |str| {
	if str == "" {
		str
	} else {
		crash "not implemented"
	}
}

# Without a message, write `...`, upstream's placeholder for "not implemented
# yet". It desugars to `crash "not implemented"`.

# `continue` is specified but not implemented yet. When the compiler implements
# it, `continue` will skip to the next iteration of a `for` or `while` loop.
# Do not use it.
