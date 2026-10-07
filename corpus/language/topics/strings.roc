# Strings in Roc.

# Single-line strings use double quotes.
hello = "Hello, world!"

# String interpolation with ${...}. The expression must produce a Str.
# Roc does not auto-convert other types, so call `.to_str()` yourself.
greet : Str -> Str
greet = |name| "Hello, ${name}!"

count_msg : U64 -> Str
count_msg = |n| "Count: ${n.to_str()}"

# Multi-line strings use `\\` at the start of each line (no surrounding quotes).
# Interpolation works inside them too.
multiline_str : U64 -> Str
multiline_str = |number|
	\\Line 1
	\\Line 2
	\\Line ${number.to_str()}

# Unicode escape sequences use \u(HEX).
nbsp = "Unicode escape sequence: \u(00A0)"

# Single quotes are not strings. `'a'` is syntax for a code point, so it is a
# number literal: `'\u(1F469)' == 128105`. It requires exactly one code point,
# so `''` is invalid where `""` is fine. ASCII-range literals like `'a'` are
# useful when a parser works with UTF-8 `U8` bytes.
code_point = 'A' # the number 65

# Common methods (use `lookup_builtin` for details):
#   "ab".concat("cd"), "foo".contains("oo"), "  x  ".trim(),
#   "abc".starts_with("a"), "z".repeat(3), "Hello".count_utf8_bytes()
#
# Searching and splitting return a `Try`, so a miss is a value you handle:
#   Str.split_first : Str, Str -> Try({ before : Str, after : Str }, [NotFound])
#   Str.split_last  : Str, Str -> Try({ before : Str, after : Str }, [NotFound])
key_of : Str -> Str
key_of = |line| match line.split_first("=") {
	Ok({ before, after: _ }) => before.trim()
	Err(NotFound) => line
}

# Replacement comes in three forms:
#   Str.replace_each  : Str, Str, Str -> Str
#   Str.replace_first : Str, Str, Str -> Str
#   Str.replace_last  : Str, Str, Str -> Str

# `Str.iter_utf8 : Str -> Iter(U8)` walks the UTF-8 bytes as an iterator, so it
# composes with the `Iter` adapters and with `for ... in`.
byte_total : Str -> U64
byte_total = |text| text.iter_utf8().map(U8.to_u64).sum()

# A nominal type can be built straight from a string literal by defining
# `from_quote`, or from an interpolated literal by defining
# `from_interpolation`. `Str` itself provides both:
#   Str.from_quote         : Str -> Try(Str, [BadQuotedBytes(Str)])
#   Str.from_interpolation : Str, Iter((Str, Str)) -> Str
# See the `derived_methods` topic for how a custom type opts in.
#
# Roc allows only valid UTF-8, so surrogate halves are not valid syntax, not
# even in single quotes. Equality compares bytes and does not normalize, so
# two strings that render identically can still differ. If you need equal
# results for such strings, normalize them once at the start.
