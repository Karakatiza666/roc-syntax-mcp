# An annotated generic empty list in a block, used at two element types,
# crashes compile-time evaluation.
#
# Run:      roc check local-generic-list-crash.roc
# Expected: No errors. langref types.md:31 says `empty : List(a)` in a let-def
#           "is then reusable at any `a`". The same definition at the top
#           level compiles (see top-level-free-type-variable.roc).
# Actual:   "compile time crash" at `[1.U8]`, with the message "invalid
#           numeric literal".
#
# Nightly: nightly-2026-10-06-c34079d.

pair = || {
	empty : List(x)
	empty = []
	(List.concat(empty, [1.U8]), List.concat(empty, ["s"]))
}

main! = |_args| {
	echo!(Str.inspect(pair()))
	Ok({})
}
