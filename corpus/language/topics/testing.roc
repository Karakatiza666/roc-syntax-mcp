# Testing in Roc with `expect`.
#
# `roc test file.roc` runs every top-level `expect` in that file and the
# files it imports. It also runs the `expect`s of path packages, but not those
# of URL packages. Tests pass if the expression evaluates to `Bool.True`. A
# failure report shows the failing expression and the values of the top-level
# names that it uses. If a test reaches code with a compile error, `roc test`
# counts it as a compiler error, not as a pass or a fail.

# Top-level `expect` (single expression).
expect Bool.True != Bool.False

# Multi-line `expect` block. The test checks the block's final expression.
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
# which `Err` it was.
expect {
	n = U64.from_str("42")?
	n == 42
}

# A program must not depend on an `expect`, so an `expect` cannot change where
# the program goes next. In a top-level or an inline `expect`, these are errors:
# `return`, `break` out of a loop outside the `expect`, and reassigning a `var`
# declared outside it. In an inline `expect`, `?` is an error too.
#
# @rejects return in expect
# expect {
# 	return True
# }
#
# @rejects break in expect
# expect {
# 	break
# 	True
# }
#
# @rejects var reassigned in expect
# withdraw = |balance, amount| {
# 	var $remaining = balance
# 	expect {
# 		$remaining = $remaining - amount
# 		$remaining >= 0
# 	}
# 	$remaining
# }
#
# @rejects try operator in expect
# check_digits = |str| {
# 	expect U64.from_str(str)? > 0
# 	str
# }

# The rules do not apply inside a function or a loop that the `expect` itself
# contains, or to a `var` that it declares.
expect {
	parse = |str| {
		n = U64.from_str(str)?
		Ok(n * 2)
	}

	var $sum = 0
	for n in [1, 2, 3, 4] {
		if n > 2 {
			break
		}
		$sum = $sum + n
	}

	parse("21") == Ok(42) and $sum == 3
}
