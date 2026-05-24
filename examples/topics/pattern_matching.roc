# `match` expressions in Roc.
# Every branch is an expression; the match itself evaluates to a value.
# Patterns can be tags, literals, lists, tuples, records, or `_`.

simple_match : [Red, Green, Blue] -> Str
simple_match = |color| {
	match color {
		Red => "The color is red."
		Green => "The color is green."
		Blue => "The color is blue."
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

# `match` is exhaustive: the compiler warns if you forget a case.
# Avoid overusing `_` so the compiler can tell you when a new variant is added.
