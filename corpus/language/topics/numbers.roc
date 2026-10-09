# Numeric types, number literals, and custom number types.
#
# Default: a literal without a suffix is `Dec` (128-bit fixed-point decimal).
# So `0.1 + 0.2 == 0.3` is True in Roc.
#
# Integer types: U8, I8, U16, I16, U32, I32, U64, I64, U128, I128.
# Float types: F32, F64.
# Fixed-point decimal: Dec.
#
# Every builtin number type has the same size on every target. A number
# allocates on the heap only when it converts to a heap type such as `Str`.

number_literals = {
	usage_based: 5, # defaults to Dec
	explicit_u8: 5.U8, # type-suffix syntax: `<literal>.<TypeName>`
	explicit_i8: 5.I8,
	explicit_u16: 5.U16,
	explicit_i16: 5.I16,
	explicit_u32: 5.U32,
	explicit_i32: 5.I32,
	explicit_u64: 5.U64,
	explicit_i64: 5.I64,
	explicit_u128: 5.U128,
	explicit_i128: 5.I128,
	explicit_f32: 1.5.F32,
	explicit_f64: 0.1.F64,
	explicit_dec: 0.1.Dec,

	hex: 0x5,
	octal: 0o5,
	binary: 0b0101,
}

# The compiler skips underscores between digits, also hex digits and digits
# after the point. `e` is a base-10 exponent. After `0x`, `e` is a hex digit.
expect 0xFF_FF == 65_535
expect 1_000.000_1 == 1000.0001
expect 1.5e-2 == 0.015
expect 0x1e3 == 483

# The base prefixes `0x`, `0o` and `0b` are lowercase.
# @rejects uppercase base
# bad_hex = 0X5

# A literal with a base prefix has no decimal point, because a letter after the
# point would look like a type suffix such as `.F64`.
# @rejects expected record accessor
# bad_fraction = 0x1.5

# A literal that does not fit its type is a compile error.
# @rejects invalid number
# too_big = 300.U8

# Conversion methods (see Builtin.roc for the full list):
#   I64.from_str("42")        # Try(I64, [BadNumStr])
#   123.to_str()              # "123"
#   I64.to_f64(10)            # 10.0
#   U8.to_u64(5.U8)           # 5.U64

# Literal defaulting. When nothing in the program pins a literal's type, the
# compiler picks the first type in this order that satisfies all of the
# literal's constraints:
#
#   Dec, I64, U64, I128, U128, I32, U32, I16, U16, I8, U8, F64, F32
#
# So a plain `5` becomes `Dec`, but a `5` whose surrounding code demands an
# integer becomes the first integer type that fits. If a default narrows a
# function's inferred type, the compiler emits a `LITERAL DEFAULTED` warning.
# Add an annotation or a suffix (`5.U64`) to pick a type deliberately.

# `Dec` uses 16 bytes and has exactly 18 digits after the point. Its range is
# about -1.7e20 to 1.7e20. It stores base-10 digits, so decimal fractions are
# exact: use it for money. `F32` and `F64` are IEEE 754 binary floats. They are
# faster and have a much wider range: use them for graphics and simulation.
expect 0.1.Dec + 0.2 == 0.3
expect 0.1.F64 + 0.2 != 0.3 # the sum is 0.30000000000000004

# Dividing a `Dec` by zero crashes. Dividing a float by zero gives an infinity,
# and some operations give NaN.
expect (1.F64 / 0).is_infinite()
expect (0.F64 / 0).is_nan()

# Range operators build a `Range(num)` over any numeric type. See the `ranges`
# topic.
first_ten : Range(U64)
first_ten = 0..<10

# A custom numeric type accepts plain literals by defining `from_numeral`.
# `Numeral` carries the literal's exact digits, so the type can accept the
# range its representation supports and reject the rest.
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

# A suffix works with any custom number type in scope: `21.Celsius`.

# `from_numeral` runs at compile time. Operators on a custom number type call
# its methods (`/` calls `div_by`, see the `operators` topic). A top-level
# constant is evaluated at compile time, so `two_thirds` is a finished `Ratio`
# in the program.
Ratio := { num : I64, den : I64 }.{
	from_numeral : Numeral -> Try(Ratio, [InvalidNumeral(Str)])
	from_numeral = |n|
		if n.digits_after_pt_count() > 0 {
			Err(InvalidNumeral("Ratio literals must be whole numbers"))
		} else {
			match I64.from_numeral(n) {
				Ok(num) => Ok(Ratio.{ num, den: 1 })
				Err(err) => Err(err)
			}
		}

	div_by : Ratio, Ratio -> Ratio
	div_by = |a, b|
		if b.num == 0 {
			crash "Ratio division by zero"
		} else {
			Ratio.{ num: a.num * b.den, den: a.den * b.num }
		}

	is_eq : _
}

two_thirds : Ratio
two_thirds = 2 / 3

expect two_thirds == Ratio.{ num: 2, den: 3 }

# `-5` is one literal, so `from_numeral` sees the sign. `-r` calls
# `r.negate()`, which `Ratio` does not define.
expect -5.Ratio == Ratio.{ num: -5, den: 1 }

# @rejects missing method
# flip : Ratio -> Ratio
# flip = |r| -r

# An `Err(InvalidNumeral(msg))` from `from_numeral` is a compile error at the
# literal, and the compiler prints `msg`.
# @rejects invalid number
# half : Ratio
# half = 2.5 / 3

# A `crash` in an operator method during compile-time evaluation is a compile
# error. At runtime, the same crash stops the program.
# @rejects compile time crash
# infinite : Ratio
# infinite = 2 / 0

# The `Numeral` methods. The compiler removes underscores, and applies the base
# prefix and the exponent, before `from_numeral` sees the digits.
#   is_negative           : Numeral -> Bool
#   digits_before_pt      : Numeral -> List(U8)
#   digits_after_pt       : Numeral -> List(U8)
#   digits_after_pt_count : Numeral -> U64
# The digit lists are base 256, most significant first, and zero is `[]`. The
# digits after the point form one whole number, so the base-10 count tells
# `.517` from `.5170`, and `1` (count 0) from `1.0` (count 1). The lists have
# no length limit, so a big-integer type can accept a literal of any size.
Digits := { neg : Bool, before : List(U8), after : List(U8), count : U64 }.{
	from_numeral : Numeral -> Try(Digits, [InvalidNumeral(Str)])
	from_numeral = |n|
		Ok(Digits.{
			neg: n.is_negative(),
			before: n.digits_before_pt(),
			after: n.digits_after_pt(),
			count: n.digits_after_pt_count(),
		})

	is_eq : _
}

expect {
	d : Digits
	d = 356.5170 # 356 is 1 * 256 + 100, and 5170 is 20 * 256 + 50
	d == Digits.{ neg: False, before: [1, 100], after: [20, 50], count: 4 }
}

expect {
	d : Digits
	d = -0.25
	d == Digits.{ neg: True, before: [], after: [25], count: 2 }
}

expect {
	d : Digits
	d = 0xff # the same digits as 255
	d == Digits.{ neg: False, before: [255], after: [], count: 0 }
}

# SIMD vector types are also builtin: U8x16, I8x16, U16x8, I16x8, U32x4, I32x4,
# U64x2, I64x2. Each is a fixed-width vector of the named scalar type.
