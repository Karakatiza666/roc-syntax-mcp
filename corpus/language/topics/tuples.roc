# Tuples group values of different types.

tuple_demo =
# Tuples can mix types.
	("Roc", 1)

# A tuple has at least two elements. `(42)` is only `42` in parentheses.
expect (42) == 42

# Destructuring with parentheses.
unpack = || {
	tup = ("Roc", 1)
	(str, num) = tup

	(str, num)
}

# A tuple has the same layout as a record: its elements are stored inline, with
# no allocation and no reference count of its own. See the `memory` topic.

# Tuple field access by index: `tup.0`, `tup.1`, etc.
field_access = || {
	pair = ("Roc", 42)
	first = pair.0
	second = pair.1
	(first, second)
}

# Access works on any tuple expression, and it chains.
nested = ((1, 2), (3, 4))
get_point = || (100, 200)

expect nested.0.1 == 2
expect get_point().0 == 100

# The index is an integer literal, and the compiler checks it against the
# tuple's size. A name after the dot is a record field access, so a computed
# index is not possible.
#
# @rejects invalid tuple access
# past_end = nested.2

# Tuple pattern matching in `match`.
classify : (I64, I64) -> Str
classify = |t| match t {
	(0, 0) => "origin"
	(_, 0) => "on x axis"
	(0, _) => "on y axis"
	_ => "elsewhere"
}

# A tuple has no optional elements and no update syntax. Use a record when the
# tuple has more than two or three elements, or when the meaning of each
# position is not clear from context.
