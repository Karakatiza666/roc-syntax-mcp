# Testing in Roc with `expect`.
#
# `roc test file.roc` runs every top-level `expect` in that file and the
# files it imports. Tests pass if the expression evaluates to `Bool.True`.

# Top-level `expect` (single expression).
expect Bool.True != Bool.False

# Multi-line `expect` block. The test checks the block's final expression.
## Multi-line expect that confirms basic math works.
expect {
	x = 4
	y = 5
	x + y == 9
}

# An `expect` inside a function body reports a failure and keeps running.
# `roc build` omits it (its default is `--opt=speed`), so it is not a
# production check.
example = |digits| {
	if digits.is_empty() {
		return 0
	}

	# From here on, we assume digits is nonempty.
	expect !digits.is_empty()

	digits.len()
}

# `?` inside a top-level `expect` fails the test on `Err` and the report shows
# which `Err` it was. Inside an inline `expect` (in a function body), `?` is a
# compile error: returning early would make optimized builds, which omit the
# `expect`, behave differently. The same goes for `return`, a `break` out of an
# enclosing loop, and reassigning an outer `var`.
expect {
	n = U64.from_str("42")?
	n == 42
}
