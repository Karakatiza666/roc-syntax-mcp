# `List.with_capacity(123)` in a top-level constant has capacity 0 when the
# program runs, and 123 under `roc test`.
#
# Run:      roc top-level-capacity.roc, then roc test top-level-capacity.roc
# Expected: Capacity 123 in both. langref compile-time.md:68: the list "will
#           evaluate at runtime to a call to `List.with_capacity(123)`".
# Actual:   The program prints "capacity 0". `roc test` passes `expect
#           reserved.capacity() == 123`.
#
# Nightly: nightly-2026-10-06-c34079d.

reserved : List(U8)
reserved = List.with_capacity(123)

expect reserved.capacity() == 123

main! = |_args| {
	echo!("capacity ${reserved.capacity().to_str()}\n")
	Ok({})
}
