# `match` expressions and patterns in Roc.
# Every branch is an expression, and the match itself evaluates to a value.
# Patterns can be tags, literals, lists, tuples, records, or `_`. The first
# branch that matches wins.

simple_match : [Red, Green, Blue, BabyBlue] -> Str
simple_match = |color| {
	match color {
		Red => "The color is red."
		Green => "The color is green."
		# `|` is an or-pattern: one branch for several alternatives.
		Blue | BabyBlue => "The color is blue."
	}
}

# Every alternative must bind the same names, with compatible types.
either_value : Try(U64, U64) -> U64
either_value = |t| match t {
	Ok(n) | Err(n) => n
}

expect either_value(Err(3)) == 3

# @rejects name not bound in every alternative
# only_ok : Try(U64, U64) -> U64
# only_ok = |t| match t {
# 	Ok(n) | Err(_) => n
# }

# Pattern matching on tuples.
match_tuple : (Bool, Bool) -> Str
match_tuple = |pair| match pair {
	(Bool.True, Bool.True) => "both"
	(Bool.True, _) => "first"
	(_, Bool.True) => "second"
	_ => "neither"
}

# A branch can carry an `if` guard, which runs only when the pattern matches.
# If the guard is `False`, matching continues with the next branch.
classify : [Num(I64), Other] -> Str
classify = |tag| match tag {
	Num(n) if n < 0 => "negative"
	Num(0) => "zero"
	Num(_) => "positive"
	Other => "not a number"
}

# A guarded branch never counts for exhaustiveness, even `_ if cond`.
#
# @rejects non exhaustive match
# size : U64 -> Str
# size = |n| match n {
# 	0 => "zero"
# 	_ if n > 5 => "big"
# }

# A number pattern can have a type suffix. A single-quote pattern matches one
# Unicode code point.
is_half : F32 -> Bool
is_half = |number| match number {
	0.5.F32 => True
	_ => False
}

is_letter_a : U8 -> Bool
is_letter_a = |byte| match byte {
	'A'.U8 | 'a'.U8 => True
	_ => False
}

expect is_half(0.5) and is_letter_a(97)

# `pattern as name` binds the whole value and also destructures it.
keep_point : (U64, U64) -> { x : U64, point : (U64, U64) }
keep_point = |value| match value {
	(x, _) as point => { x, point }
}

expect keep_point((1, 2)).point == (1, 2)

# `Type.{ fields }` destructures a nominal type's backing record, in a `match`
# branch or directly in a function parameter.
NominalTypeRecord := { x : U64 }

destructure_nominal_type : NominalTypeRecord -> U64
destructure_nominal_type = |NominalTypeRecord.{ x }| x

# `match` is exhaustive: the compiler rejects a match that misses a case, and
# lists the missing patterns. `_` is the catch-all. Use it sparingly, so that the
# compiler can tell you when someone adds a new variant. A branch after a
# catch-all is redundant:
#
# @warns redundant pattern
# after_catch_all : Try(U64, Str) -> Str
# after_catch_all = |r| match r {
# 	_ => "handled"
# 	Ok(_) => "unreachable"
# }
#
# `_` binds nothing. `_name` binds a name that you intend not to use:
#
# @warns underscore variable used
# double_it = |_n| _n * 2

# A pattern in `=`, in a function argument, or in `for` must also be exhaustive.
# A tag destructure is allowed when the type has only that tag, as in
# `Try(U64, [])` (see `tag_unions`). See `records` and `record_fields` for record
# patterns, and `list_patterns` for list patterns.
#
# @rejects non exhaustive destructure
# first_or_crash : List(U64) -> U64
# first_or_crash = |list| {
# 	Ok(item) = list.first()
# 	item
# }
#
# @rejects non exhaustive destructure
# unwrap_arg : Try(U64, Str) -> U64
# unwrap_arg = |Ok(n)| n

# A string pattern can capture with `${name}` (or discard with `${_}`). A capture
# before literal text takes everything up to the first occurrence of that text.
# Two captures cannot be adjacent. A literal must separate them.
route : Str -> Str
route = |path| match path {
	"users/${id}/posts/${post}" => "user ${id}, post ${post}"
	"users/${id}" => "user ${id}"
	"${key}=${value}" => "key ${key}, value ${value}"
	_ => "not found"
}

expect route("users/7/posts/42") == "user 7, post 42"
expect route("a=b=c") == "key a, value b=c"
