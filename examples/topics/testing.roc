# Testing in Roc with `expect`.
#
# `roc test file.roc` runs every top-level `expect` in that file and the
# files it imports. Tests pass if the expression evaluates to `Bool.True`.

# Top-level `expect` (single expression).
expect Bool.True != Bool.False

# Multi-line `expect` block. The block's final expression is what's checked.
## Multi-line expect that confirms basic math works.
expect {
	x = 4
	y = 5
	x + y == 9
}

# `expect` inside a function body acts like an assertion during dev / `roc test`
# but is skipped under `roc --opt=speed`. Don't use it for production checks.
example = |digits| {
	if digits.is_empty() {
		return 0
	}

	# From here on, we assume digits is nonempty.
	expect !digits.is_empty()

	digits.len()
}
