# `dbg` and `crash` statements, and the planned `continue`.

# `dbg` is print-line debugging. It prints `[dbg] <value>` to stderr, and
# formats the value with `Str.inspect`, so a `to_inspect` method controls the
# output. It works in pure and effectful functions.
#
# `dbg` and `expect` are the only side effects outside effectful functions. Their
# output is for the programmer, so program behavior must not depend on it. A
# `dbg` in a top-level constant prints during `roc check` and `roc build`, and
# the compiled program does not print it. Other `dbg` output can appear at
# runtime, at compile time only, or never.
dbg_keyword = || {
	foo = 42

	dbg foo
	# `dbg(foo)` also works.

	foo
}

# `crash` halts the program with a message. The platform decides what happens
# next: it can recover, or end the process.
# Use it only for unreachable branches or unrecoverable conditions like OOM.
# For a recoverable error, return a `Try`.
unreachable_branch = |n| {
	if n < 0 {
		crash "n was supposed to be non-negative"
	}

	n * 2
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

# Without a message, write `...`. It desugars to `crash "not implemented"`.
# A `crash` that runs at compile time is a compile error (see `compile_time`).

# `continue` is planned. It will skip to the next iteration of a `for` or
# `while` loop. The compiler reads `continue` as a name that is not defined:
#
# @rejects name not in scope
# skip_all = |xs| {
# 	for _x in xs {
# 		continue
# 	}
# }
