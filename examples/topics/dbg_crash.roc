# `dbg`, `crash`, and `return` statements.

# `dbg` — print-line debugging. Works in both pure and effectful contexts.
# It may run at compile time (constant folding) or at runtime.
dbg_keyword = || {
	foo = 42

	dbg foo
	# `dbg(foo)` also works.

	foo
}

# `crash` halts the program with a message.
# Use it only for unreachable branches or unrecoverable conditions like OOM.
# Don't use it for recoverable errors — use `Try` instead.
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
