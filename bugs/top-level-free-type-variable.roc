# A top-level value with a free type variable compiles and is generalized.
#
# Run:      roc top-level-free-type-variable.roc
# Expected: An error, by langref types.md:33: "we report an error for top-
#           level values with free vars".
# Actual:   No errors. The program prints "1 1". Only a free variable that
#           keeps a `where` constraint is an error (see langref-value-
#           where.roc).
#
# Nightly: nightly-2026-10-06-c34079d.

empty : List(a)
empty = []

main! = |_args| {
	echo!("${(List.concat(empty, [1.U8])).len().to_str()} ${(List.concat(empty, ["s"])).len().to_str()}\n")
	Ok({})
}
