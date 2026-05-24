# Strings in Roc.

# Single-line strings use double quotes.
hello = "Hello, world!"

# String interpolation with ${...}. The expression must produce a Str.
# Roc does NOT auto-convert other types — call `.to_str()` yourself.
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

# Common methods (from Builtin.roc) — use `lookup_builtin` for details:
# "ab".concat("cd"), "foo".contains("oo"), "  x  ".trim(),
# "abc".starts_with("a"), "z".repeat(3), "Hello".count_utf8_bytes()
