# Tag unions are Roc's sum types. Tags start with a capital letter
# and can carry zero or more payloads.

# `Try(a, b)` is the canonical name for `[Ok(a), Err(b)]` in the new compiler.
# (The old compiler called this `Result`.)
match_tag_union_advanced : Try({}, [StdoutErr(Str), Other]) -> Str
match_tag_union_advanced = |try|
	match try {
		Ok(_) =>
			"Success"

		Err(StdoutErr(err)) =>
			"StdoutErr: ${Str.inspect(err)}"

		Err(_) =>
			"Unknown error"
		}

# Tags can carry multiple payloads.
multi_payload_tag : [Foo(I64, Str), Bar] -> Str
multi_payload_tag = |tag| match tag {
	Foo(num, name) => "Foo with ${num.to_str()} and ${name}"
	Bar => "Just Bar"
}

# Open tag unions use `..` to mean "and possibly other tags".
# This function accepts any tag union that includes at least Red and Green.
color_to_str : [Red, Green, ..] -> Str
color_to_str = |color| match color {
	Red => "red"
	Green => "green"
	_ => "other color"
}

# Type alias for an extensible tag union, using a type variable `others`:
Letters(others) : [A, B, ..others]

# Use the type alias and extend it with [C] in this signature.
letter_to_str : Letters([C]) -> Str
letter_to_str = |letter| match letter {
	A => "A"
	B => "B"
	_ => "other letter"
}

# An or-pattern matches several tags with one branch.
is_warm : [Red, Orange, Blue, Green] -> Bool
is_warm = |color| match color {
	Red | Orange => Bool.True
	Blue | Green => Bool.False
}

# A tag can be written qualified when the union is a nominal type, which
# disambiguates it from a same-named tag elsewhere.
#   Bool.True, Bool.False

# A tag union with exactly one selected direct payload can derive `map` and
# `map!`, so the payload transforms without a `match`. See the
# `derived_methods` topic.
Maybe(a) := [Just(a), Nothing].{
	map : _
	map! : _
}

doubled : Maybe(I64) -> Maybe(I64)
doubled = |m| m.map(|n| n * 2)
