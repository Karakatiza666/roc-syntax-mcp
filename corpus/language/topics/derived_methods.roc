# Compiler-derived methods: the `method : _` opt-in.
#
# Roc can synthesize implementations of six methods: `is_eq`, `to_hash`,
# `parser_for`, `encoder_for`, `map`, and `map!`.
#
# Structural types (records, tuples, tag unions, lists, and so on) receive each
# derived method automatically when their shape supports it. A nominal (`:=`) or
# opaque (`::`) type must opt in to each one it wants, by declaring the method
# with `_` as its annotation and no body.
Model := { value : Str }.{
	is_eq : _
	to_hash : _
	parser_for : _
	encoder_for : _
}

# `_` asks the compiler to infer the method's type and synthesize the body. It
# is recognized only for those six names. Any other declaration without a body
# is an error, except host-provided platform declarations. The opt-in behaves
# the same in application, package, and platform modules.

# A declaration with a body is an ordinary custom implementation and requests
# no derivation, so a type can derive some methods and hand-write others.
Point := { x : I64, y : I64 }.{
	# Custom equality ignores nothing here, but it could.
	is_eq : Point, Point -> Bool
	is_eq = |a, b| a.x == b.x and a.y == b.y

	# Hash is still derived. Keep the two consistent: values that compare equal
	# must feed the same hash data, or `Dict` and `Set` lookups will miss.
	to_hash : _
}

# Derived `map` and `map!` apply to eligible tag unions with one selected direct
# payload. `map` takes a pure transformation, `map!` an effectful one.
Maybe(a) := [Just(a), Nothing].{
	map : _
	map! : _
}

# The full set of well-known methods. The checker resolves each use to one
# concrete implementation, and codegen emits a direct call, so no dispatch
# happens at runtime. The table does not limit method names, because a package
# can define and require its own with a `where` clause.
#
#   to_inspect          Str.inspect(value)
#   is_eq               `==` and `!=` (`!=` calls is_eq then Bool.not)
#   to_hash             Dict, Set, and other hash-based APIs
#   plus minus times    `+` `-` `*`
#   div_by              `/`
#   div_trunc_by        `//`
#   rem_by              `%`
#   is_lt is_lte        `<` `<=`
#   is_gt is_gte        `>` `>=`
#   range_exclusive_to  `..<`
#   range_inclusive_to  `..=`
#   range_exclusive_from, range_inclusive_from   Range.iter_rev
#   range_iter          Range.iter and Range.iter_rev
#   range_len_if_known  numeric range constructors, Range.step_by
#   negate not          unary `-` and unary `!`
#   from_numeral        a number literal whose target type is this type
#   from_quote          a quoted string literal whose target type is this type
#   from_interpolation  an interpolated string literal
#   iter                `for item in value`
#   next                the `for` loop's iteration step, usually from Iter
#   parser_for          generic parsers, such as JSON
#   encoder_for         generic encoders, such as JSON
#   map map!            mapping a selected payload in an eligible tag union

# `to_inspect` customizes how `Str.inspect` renders a value. Without it,
# `Str.inspect` uses Roc's built-in structural representation.
Color := [Red, Green, Blue].{
	to_inspect : Color -> Str
	to_inspect = |color| match color {
		Red => "Color.Red"
		Green => "Color.Green"
		Blue => "Color.Blue"
	}
}

# `Str.inspect` uses `to_inspect` only if its type is exactly `T -> Str`, with
# each type parameter of `T` free and without a `where` clause. A `to_inspect`
# of any other type is an ordinary method, and `Str.inspect` ignores it without
# a warning. Inside `to_inspect`, `Str.inspect` renders a payload of any type.
Wrap(a) := [W(a)].{
	to_inspect : Wrap(a) -> Str
	to_inspect = |Wrap.W(value)| "Wrap(${Str.inspect(value)})"
}

Fixed(a) := [F(a)].{
	to_inspect : Fixed(I64) -> Str
	to_inspect = |_| "custom"
}

expect Str.inspect(Wrap.W("x")) == "Wrap(\"x\")"
expect Str.inspect(Fixed.F(1.I64)) == "F(1)"
expect Fixed.F(1.I64).to_inspect() == "custom"

# Literal conversion hooks. A number literal dispatches `from_numeral` when its
# target type is a nominal type that defines it. `Numeral` carries the
# literal's exact digits, so a type can accept the range its representation
# supports and reject the rest.
Celsius := { degrees : I64 }.{
	from_numeral : Numeral -> Try(Celsius, [InvalidNumeral(Str)])
	from_numeral = |n| match I64.from_numeral(n) {
		# `Celsius.{ ... }` names the nominal type. A bare record also lifts into
		# Celsius here, but a single-field pun needs a comma: `{ degrees }` is a
		# block (the I64), `{ degrees, }` is the record.
		Ok(degrees) => Ok(Celsius.{ degrees })
		Err(err) => Err(err)
	}
}

temp : Celsius
temp = 21 # calls Celsius.from_numeral

# A quoted string literal dispatches `from_quote`. If it returns
# `Err(BadQuotedBytes(message))`, the compiler reports the conversion error
# before the program runs, so an invalid literal is a compile-time failure.
HttpMethod := [Get, Post, Put, Delete].{
	from_quote : Str -> Try(HttpMethod, [BadQuotedBytes(Str)])
	from_quote = |raw| match raw {
		"GET" => Ok(Get)
		"POST" => Ok(Post)
		"PUT" => Ok(Put)
		"DELETE" => Ok(Delete)
		_ => Err(BadQuotedBytes("expected GET, POST, PUT, or DELETE"))
	}
}

method : HttpMethod
method = "POST" # calls HttpMethod.from_quote

# An interpolated string literal dispatches `from_interpolation`. The first
# argument is the literal segment before the first interpolation. The iterator
# yields each interpolated value paired with the literal segment that follows
# it. Plain quoted segments are always `Str`. The interpolated values have the
# `item` type in `Iter((item, Str))`.
#
#   from_interpolation : Str, Iter((item, Str)) -> T

# Arithmetic operators dispatch on the left operand and return its type, but the
# right operand can differ if the signature allows it.
Duration := { millis : I64 }.{
	times : Duration, I64 -> Duration
	times = |duration, scale| { millis: duration.millis * scale }
}

longer : Duration
longer = Duration.{ millis: 10 } * 3
