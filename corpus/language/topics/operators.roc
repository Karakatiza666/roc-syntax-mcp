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
# `a() and b()` is `if a() b() else False`. They are keywords, not methods, so
# no type can overload them, and both operands must be `Bool`.
# @rejects type mismatch
# both_set : I64, I64 -> Bool
# both_set = |a, b| a and b
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
#   ..=  range_inclusive_to
#
# Arithmetic dispatches on the left operand and returns its type. The right
# operand may differ if the method signature allows it. Comparison and range
# operators require both operands to have the same type.
# Defining these methods is how a custom type opts into the operators. See the
# `static_dispatch` topic.
#
# `-x` calls `x.negate()`, and `negate` must return the operand's type.
# @rejects type mismatch
# Temp := { c : I64 }.{
# 	negate : Temp -> I64
# 	negate = |t| -t.c
# }
# neg_temp : Temp -> I64
# neg_temp = |t| -t
#
# `!x` takes only a `Bool`. A custom `not` method does not make `!` work.
# @rejects type mismatch
# Switch := [On, Off].{
# 	not : Switch -> Switch
# 	not = |s| match s {
# 		On => Off
# 		Off => On
# 	}
# }
# flip : Switch -> Switch
# flip = |s| !s

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
# is a "chained range" error. See the `ranges` topic for `step_by`, `iter_rev`
# and custom ranges.

# `??` supplies a default when the left side evaluates to `Err`. It desugars to
# a `match` returning the default on `Err(_)`.
parse_or_default : Str -> I64
parse_or_default = |text| I64.from_str(text) ?? 0

# `??` handles the error inline. The postfix `?` propagates it by early return.
# Use `??` when a fallback is correct here, `?` when the caller should decide.
# See the `try_operator` topic.

# `list[i]` is planned (it will desugar to `list.subscript(i)`) but does not
# parse yet. Any type that defines `subscript` will get the syntax. Call the
# `subscript` methods, which return a `Try` rather than crashing
# (`Set.subscript` returns a `Bool`):
#   List.subscript : List(item), U64 -> Try(item, [OutOfBounds])
#   Dict.subscript : Dict(k, v), k -> Try(v, [KeyNotFound])
third : List(I64) -> I64
third = |items| items.subscript(2) ?? 0

# `|>` (the pizza operator) passes a value as the first argument to any function
# in scope. See the `static_dispatch` topic for how it pairs with `.method()`.
piped = "Three" |> Str.concat(" Four")
