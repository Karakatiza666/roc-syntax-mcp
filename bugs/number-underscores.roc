# Number literals accept underscores that do not have a digit on both sides.
#
# Run:      roc number-underscores.roc
# Expected: Errors for `1__0`, `1_` and `0x_5`. langref numbers.md:13: "each
#           underscore must always have a digit on either side of it".
# Actual:   No errors. The program prints "10.0 1.0 5.0".
#
# Nightly: nightly-2026-10-06-c34079d.

doubled = 1__0
trailing = 1_
after_prefix = 0x_5

main! = |_args| {
	echo!("${doubled.to_str()} ${trailing.to_str()} ${after_prefix.to_str()}\n")
	Ok({})
}
