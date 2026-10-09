# The example of langref types.md:77 does not compile.
#
# Run:      roc check langref-value-where.roc
# Expected: No errors. The page shows it as a value with a `where` clause.
# Actual:   "polymorphic value".
#
# Nightly: nightly-2026-10-06-c34079d.

items : List(a) where [a.to_str : a -> Str]
items = []

main! = |_args| Ok({})
