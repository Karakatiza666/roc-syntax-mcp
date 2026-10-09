# `if` is an expression. It behaves exactly like a `match` on a `Bool`:
# `if foo { bar() } else { baz() }` is `match foo { True => bar(), False => baz() }`.
#
# Roc has no truthiness. `if` accepts only `Bool` values.
# @rejects type mismatch
# any_items : List(U64) -> U64
# any_items = |items| if items.len() 1 else 0
#
# `else` is required whenever the `if` produces a value, and optional when the
# body evaluates to `{}`. See `log_if_empty!` below.
# @rejects type mismatch
# size_label : U64 -> Str
# size_label = |n| if n > 9 "big"

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

# An `if` with no `else` is allowed only when its body evaluates to `{}`. It is
# equivalent to writing `{} = if cond { ... } else { {} }`, without the `{} =`
# or the `else`. In practice that means effectful calls, or `return`, `crash`,
# and `expect` statements.
log_if_empty! : Str => {}
log_if_empty! = |name| {
	if name.is_empty() {
		echo!("name was empty\n")
	}
}

# `and` and `or` are short-circuiting, and are themselves defined in terms of
# `if`: `a() or b()` is `if a() True else b()`, and `a() and b()` is
# `if a() b() else False`.
#
# Roc has no `&&` or `||`, because `|` introduces a function and `||` already
# means a function that takes no arguments.
guard : U64 -> Str
guard = |n| if n > 0 and n < 10 "single digit" else "out of range"
