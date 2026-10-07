# Numeric types and literals.
#
# Default: a literal without a suffix is `Dec` (128-bit fixed-point decimal).
# So `0.1 + 0.2 == 0.3` is True in Roc.
#
# Integer types: U8, I8, U16, I16, U32, I32, U64, I64, U128, I128.
# Float types: F32, F64.
# Fixed-point decimal: Dec.

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

# SIMD vector types are also builtin: U8x16, I8x16, U16x8, I16x8, U32x4, I32x4,
# U64x2, I64x2. Each is a fixed-width vector of the named scalar type.
