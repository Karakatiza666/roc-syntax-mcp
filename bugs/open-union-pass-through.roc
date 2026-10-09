# The `add_blue` example of langref tag-unions.md:49 does not type-check.
#
# Run:      roc check open-union-pass-through.roc
# Expected: No errors. The page uses the example to show that `..others`
#           passes unknown tags through.
# Actual:   "type mismatch" at `other => other`. It compiles when the input
#           type also lists `Blue`.
#
# Nightly: nightly-2026-10-06-c34079d.

add_blue : [Red, Green, ..others], Bool -> [Red, Green, Blue, ..others]
add_blue = |color, green_to_blue|
	match color {
		Green if green_to_blue => Blue
		other => other
	}

main! = |_args| Ok({})
