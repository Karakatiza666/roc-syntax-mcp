# Arithmetic, comparison, and boolean operators.

number_operators : I64, I64 -> _
number_operators = |a, b| {
	a_f64 = I64.to_f64(a)
	b_f64 = I64.to_f64(b)

	{
		# binary operators
		sum: a + b,
		diff: a - b,
		prod: a * b,
		div: a_f64 / b_f64,
		div_trunc: a // b,  # integer (truncating) division
		rem: a % b,         # remainder
		eq: a == b,
		neq: a != b,
		lt: a < b,
		lteq: a <= b,
		gt: a > b,
		gteq: a >= b,

		# unary operators
		neg: -a,
		# the last item can have a comma too
	}
}

boolean_operators : Bool, Bool -> _
boolean_operators = |a, b| {
	bool_and_keyword: a and b,
	bool_or_keyword: a or b,
	not_a: !a,
}

# Note: the old pizza operator `|>` is gone. Use static dispatch (`.method()`) or
# the arrow form (`value->fn(arg)`) instead. See the `static_dispatch` topic.
