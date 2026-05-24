# Tuples group values of different types.

tuple_demo =
	# Tuples can mix types.
	("Roc", 1)

# Destructuring with parentheses.
unpack = || {
	tup = ("Roc", 1)
	(str, num) = tup

	(str, num)
}

# Tuple field access by index: `tup.0`, `tup.1`, etc.
field_access = || {
	pair = ("Roc", 42)
	first = pair.0
	second = pair.1
	(first, second)
}

# Tuple pattern matching in `match`.
classify : (I64, I64) -> Str
classify = |t| match t {
	(0, 0) => "origin"
	(_, 0) => "on x axis"
	(0, _) => "on y axis"
	_ => "elsewhere"
}
