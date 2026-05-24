# Numeric types and literals in the new compiler.
#
# Default: a literal without a suffix is `Dec` (128-bit fixed-point decimal).
# That's why `0.1 + 0.2 == 0.3` is True in Roc.
#
# Integer types: U8, I8, U16, I16, U32, I32, U64, I64, U128, I128.
# Float types: F32, F64.
# Fixed-point decimal: Dec.

number_literals = {
	usage_based: 5,        # defaults to Dec
	explicit_u8: 5.U8,     # type-suffix syntax: `<literal>.<TypeName>`
	explicit_i8: 5.I8,
	explicit_u16: 5.U16,
	explicit_i16: 5.I16,
	explicit_u32: 5.U32,
	explicit_i32: 5.I32,
	explicit_u64: 5.U64,
	explicit_i64: 5.I64,
	explicit_u128: 5.U128,
	explicit_i128: 5.I128,
	# Note: F32, F64, and Dec literals use type inference, which doesn't work
	# with `Str.inspect`, so they're omitted here. Most of the time you'll
	# write the type in the signature instead of suffixing the literal.

	hex: 0x5,
	octal: 0o5,
	binary: 0b0101,
}

# Conversion methods (see Builtin.roc for the full list):
#   I64.from_str("42")        # Try(I64, [BadNumStr])
#   123.to_str()              # "123"
#   I64.to_f64(10)            # 10.0
#   U8.to_u64(5.U8)           # 5.U64
