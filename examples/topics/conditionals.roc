# `if` is an expression — every `if` must have an `else` branch.

if_demo : U64 -> Str
if_demo = |num| {
	# One-line if/else.
	one_line_if = if num == 1 "One" else "NotOne"

	# Multi-line if/else (still a single expression).
	two_line_if =
		if num == 2
			"Two"
		else
			"NotTwo"

	# Branches can be blocks (curly braces). The block evaluates to its last expression.
	with_curlies =
		if num == 5 {
			"Five"
		} else {
			"NotFive"
		}

	# `else if` chains for multiple cases.
	if num == 3
		"Three"
	else if num == 4
		"Four"
	else
		one_line_if.concat(two_line_if).concat(with_curlies)
}
