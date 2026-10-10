# Tag unions are Roc's sum types. Tags start with a capital letter
# and can carry zero or more payloads.

# `Try(ok, err)` is a nominal union, declared as
# `Try(ok, err) := [Ok(ok), Err(err)]`. (The old compiler called this `Result`.)
# The bare tags `Ok` and `Err` become a `Try` where the code expects a `Try`.
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

# A bare tag lifts into a nominal union only if the union has that tag with a
# compatible payload.
#
# @rejects type mismatch
# two_payloads : Try(U64, Str)
# two_payloads = Ok(1, 2)

# Tags can carry multiple payloads. `Foo(I64, Str)` and `Foo((I64, Str))` are
# different types, but a payload has the layout of a tuple, so both compile to
# the same thing.
multi_payload_tag : [Foo(I64, Str), Bar] -> Str
multi_payload_tag = |tag| match tag {
	Foo(num, name) => "Foo with ${num.to_str()} and ${name}"
	Bar => "Just Bar"
}

# One union cannot have two tags with the same name and different payloads.
#
# @rejects type mismatch
# mixed_foo = |flag| if flag Foo("a") else Foo(1.U8, 2.U8)

# A structural union needs no declaration. Two unions with the same tags are the
# same type, and the result of an `if` or `match` has the tags of all branches.
# Open tag unions use `..` to mean "and possibly other tags".
# This function accepts any tag union that includes at least Red and Green.
color_to_str : [Red, Green, ..] -> Str
color_to_str = |color| match color {
	Red => "red"
	Green => "green"
	_ => "other color"
}

# `..others` names the extra tags, so the output type can repeat them.
# `.._others` names them only for the reader. `.._` alone does not parse.
#
# @rejects expected tag union separator
# no_name : [Red, .._] -> Str
#
# A catch-all branch that returns its input gives the output the input's type.
# So the input lists every tag that the output can have, `Blue` included.
green_to_blue : [Red, Green, Blue, ..others] -> [Red, Green, Blue, ..others]
green_to_blue = |color| match color {
	Green => Blue
	other => other
}

pass_purple : [Red, Green, Blue, Purple] -> [Red, Green, Blue, Purple]
pass_purple = |color| green_to_blue(color)

expect pass_purple(Purple) == Purple
expect pass_purple(Green) == Blue

# @rejects type mismatch
# add_blue : [Red, Green, ..others] -> [Red, Green, Blue, ..others]
# add_blue = |color| match color {
# 	Green => Blue
# 	other => other
# }

# Type alias for an extensible tag union, using a type variable `others`:
Letters(others) : [A, B, ..others]

# Use the type alias and extend it with [C] in this signature.
letter_to_str : Letters([C]) -> Str
letter_to_str = |letter| match letter {
	A => "A"
	B => "B"
	_ => "other letter"
}

# A closed structural union, `[Red, Other, ..[]]`, is planned. It does not parse
# in this compiler. Use a nominal type when a union must be closed.
#
# @rejects expected tag union separator
# to_color : Str -> [Red, Other, ..[]]

# An or-pattern matches several tags with one branch.
is_warm : [Red, Orange, Blue, Green] -> Bool
is_warm = |color| match color {
	Red | Orange => Bool.True
	Blue | Green => Bool.False
}

# A nominal union (`:=`) has a fixed set of tags. Use of a tag that the
# declaration does not list is a type error. A nominal union can be recursive.
# `Color.Red` is always a `Color`. A bare `Red` is a structural tag, and
# becomes a `Color` only where the code expects a `Color`.
Color := [Red, Green, Blue].{
	to_hex : Color -> Str
	to_hex = |color| match color {
		Red => "#f00"
		Green => "#0f0"
		Blue => "#00f"
	}
	is_eq : _
}

expected_color : Color
expected_color = Red

# A qualified tag is a value, so a method call on it works. If `Color` had a
# nested type named `Red`, `Color.Red.to_hex` would refer to that type instead.
expect Color.Red.to_hex() == "#f00"
expect expected_color == Color.Red

# @rejects missing method
# bare_red = Red
# bare_hex = bare_red.to_hex()
#
# @rejects type mismatch
# to_purple : Bool -> Color
# to_purple = |flag| if flag Color.Red else Purple

# `[]` is the empty union, and it has no values. A `Try(U64, [])` can never be
# an `Err`, so a match with only `Ok` is exhaustive, and so is `Ok(n) = ...`.
always_ok : U64 -> Try(U64, [])
always_ok = |n| Ok(n)

unwrap_ok : Try(U64, []) -> U64
unwrap_ok = |try| match try {
	Ok(n) => n
}

destructure_ok = || {
	Ok(n) = always_ok(5)
	n
}

expect unwrap_ok(always_ok(3)) + destructure_ok() == 8

# A tag union with one type parameter that is directly a payload can derive
# `map` and `map!`, so the payload transforms without a `match`. See the
# `derived_methods` topic.
Maybe(a) := [Just(a), Nothing].{
	map : _
	map! : _
}

doubled : Maybe(I64) -> Maybe(I64)
doubled = |m| m.map(|n| n * 2)
