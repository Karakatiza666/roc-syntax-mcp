# Arithmetic, comparison, boolean, range, and error-defaulting operators.

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
		div_trunc: a // b, # integer (truncating) division
		rem: a % b, # remainder
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

# `and` and `or` short-circuit. `a() or b()` is `if a() True else b()`, and
# `a() and b()` is `if a() b() else False`.
#
# Roc has no `&&` or `||`. `|` introduces a function, so `||` already means a
# function that takes no arguments.

# Every operator below is syntax for a well-known static-dispatch method,
# selected at compile time from the operand types:
#
#   +    plus                 ==   is_eq
#   -    minus                !=   is_eq, then Bool.not
#   *    times                <    is_lt
#   /    div_by               <=   is_lte
#   //   div_trunc_by         >    is_gt
#   %    rem_by               >=   is_gte
#   ..<  range_exclusive_to   -x   negate
#   ..=  range_inclusive_to   !x   not
#
# Arithmetic dispatches on the left operand and returns its type. The right
# operand may differ if the method signature allows it. Comparison and range
# operators require both operands to have the same type.
# Defining these methods is how a custom type opts into the operators. See the
# `static_dispatch` topic.

# `..<` and `..=` build a reusable `Range(num)`. `..<` excludes the upper bound,
# `..=` includes it. `for` loops call the range's `iter` method automatically.
sum_to : U64 -> U64
sum_to = |n| {
	var $total = 0

	for i in 0..<n {
		$total = $total + i
	}

	$total
}

# Range operators bind more loosely than the other binary operators, so
# `1..<n + 1` parses as `1..<(n + 1)`. They cannot be chained: `1..<5..<10`
# is an error.
#
# A range starts with a step of 1. `range.step_by(s)` replaces that absolute
# step rather than composing with it, so calling it twice is not multiplicative.
# `range.iter_rev()` walks the same members backwards, and is available for
# integer and `Dec` ranges but deliberately not for `F32` or `F64`, because
# repeated float addition is not exactly reversible.
stepped : List(I64)
stepped = (5.I64..=12).step_by(2).iter_rev().collect()

# `??` supplies a default when the left side evaluates to `Err`. It desugars to
# a `match` returning the default on `Err(_)`.
parse_or_default : Str -> I64
parse_or_default = |text| I64.from_str(text) ?? 0

# `??` handles the error inline. The postfix `?` propagates it by early return.
# Use `??` when a fallback is correct here, `?` when the caller should decide.
# See the `try_operator` topic.

# `list[i]` is planned (it will desugar to `list.subscript(i)`) but does not
# parse yet. Call the `subscript` methods, which return a `Try` rather than
# crashing (`Set.subscript` returns a `Bool`):
#   List.subscript : List(item), U64 -> Try(item, [OutOfBounds])
#   Dict.subscript : Dict(k, v), k -> Try(v, [KeyNotFound])
third : List(I64) -> I64
third = |items| items.subscript(2) ?? 0

# `|>` (the pizza operator) passes a value as the first argument to any function
# in scope. See the `static_dispatch` topic for how it pairs with `.method()`.
piped = "Three" |> Str.concat(" Four")
