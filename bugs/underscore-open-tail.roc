# `.._` in a tag union type does not parse.
#
# Run:      roc check underscore-open-tail.roc
# Expected: No errors. langref tag-unions.md:89 says `..` "is equivalent to
#           writing `.._`". `.._others` parses.
# Actual:   "expected tag union separator", then three more parse errors.
#
# Nightly: nightly-2026-10-06-c34079d.

to_str : [Red, Green, .._] -> Str
to_str = |color|
	match color {
		Red => "red"
		Green => "green"
		_ => "other"
	}

main! = |_args| Ok({})
