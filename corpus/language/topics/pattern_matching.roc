# `match` expressions in Roc.
# Every branch is an expression, and the match itself evaluates to a value.
# Patterns can be tags, literals, lists, tuples, records, or `_`.

simple_match : [Red, Green, Blue, BabyBlue] -> Str
simple_match = |color| {
	match color {
		Red => "The color is red."
		Green => "The color is green."
		# `|` is an or-pattern: one branch for several alternatives.
		Blue | BabyBlue => "The color is blue."
	}
}

# Pattern matching on tuples.
match_tuple : (Bool, Bool) -> Str
match_tuple = |pair| match pair {
	(Bool.True, Bool.True) => "both"
	(Bool.True, _) => "first"
	(_, Bool.True) => "second"
	_ => "neither"
}

# A branch can carry an `if` guard, which runs only when the pattern matches.
classify : [Num(I64), Other] -> Str
classify = |tag| match tag {
	Num(n) if n < 0 => "negative"
	Num(0) => "zero"
	Num(_) => "positive"
	Other => "not a number"
}

# `Type.{ fields }` destructures a nominal type's backing record, in a `match`
# branch or directly in a function parameter.
NominalTypeRecord := { x : U64 }

destructure_nominal_type : NominalTypeRecord -> U64
destructure_nominal_type = |NominalTypeRecord.{ x }| x

# `match` is exhaustive: the compiler rejects a match that misses a case. `_` is the
# catch-all. Use it sparingly, so that the compiler can tell you when someone
# adds a new variant.
#
# Destructuring assignment with `=` must also be exhaustive, which is why
# `{ x, y } = rec` is allowed but `Ok(v) = fallible` is not. See `records` and
# `record_fields` for record patterns, and `list_patterns` for list patterns.

# A string pattern can capture with `${name}` (or discard with `${_}`). Two
# captures cannot be adjacent. A literal must separate them.
route : Str -> Str
route = |path| match path {
	"users/${id}/posts/${post}" => "user ${id}, post ${post}"
	"users/${id}" => "user ${id}"
	_ => "not found"
}

expect route("users/7/posts/42") == "user 7, post 42"
