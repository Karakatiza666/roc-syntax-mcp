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

# Single quotes are not strings. `'a'` is syntax for one code point, so it is a
# number literal, and with nothing to pin it the literal is a `Dec`. ASCII-range
# literals like `'a'.U8` are useful when a parser works with UTF-8 bytes.
code_point = 'A' # the number 65

expect '\u(1F469)' == 128105
expect 'a'.U8 == 97

# A single quote needs exactly one code point. `''` is invalid where `""` is
# fine.
# @rejects single quote empty
# no_code_point = ''

# Common methods (use `search_symbols` for details):
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

# Every `Str` is valid UTF-8. So `to_utf8` cannot fail, but `from_utf8` returns
# a `Try`. `from_utf8_lossy` replaces each invalid sequence with U+FFFD.
expect "café".to_utf8() == [99, 97, 102, 195, 169]
expect Str.from_utf8([99, 255]) == Err(BadUtf8({ index: 1, problem: InvalidStartByte }))
expect Str.from_utf8_lossy([99, 255]) == "c\u(FFFD)"

# Surrogate halves are not valid UTF-8, so they are invalid syntax, also in
# single quotes.
# @rejects invalid unicode escape sequence
# lone_surrogate = "\u(D800)"

# A byte count is not a count of code points or of graphemes (user-perceived
# characters). One grapheme can hold many code points: the family emoji
# 👩‍👩‍👦‍👦 has 7. So `Str.len` returns a `LearnAboutStringsInRoc(Str)` tag
# that explains this, and not a number. Use `count_utf8_bytes`, or `is_empty`.
expect "café".count_utf8_bytes() == 5

# @rejects type mismatch
# length : U64
# length = "abc".len()

# `Str` has no grapheme functions. They are in the roc-lang/unicode package.
# Use the `Str` methods for most text. A parser works best on UTF-8 bytes
# (`to_utf8`, `iter_utf8`). Work with code points only in a Unicode library.
# Splitting text into graphemes is almost always slower and more error-prone
# than a design that does not need it.

# `==` compares bytes and does not normalize. `\u(e9)` inserts that exact code
# point, so the first two strings below are equal. The combining form
# `e\u(301)` renders the same but is different. Normalize (NFC or NFD) once,
# when text enters the program, because normalization costs much more CPU time
# than `==`. `Str` does not normalize.
expect "caf\u(e9)" == "café"
expect "caf\u(e9)" != "cafe\u(301)"

# Literal bidirectional control characters (U+061C, U+200E-U+200F,
# U+202A-U+202E, U+2066-U+2069) are rejected anywhere in source, also in
# strings and comments, because they can make code look different from what
# runs. `roc fmt` refuses such a file. Write the escape to put one in a string.
right_to_left_override = "\u(202E)"
