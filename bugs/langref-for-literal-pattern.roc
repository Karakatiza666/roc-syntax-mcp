# The note at langref loops.md:91 is out of date, and the compiler reports a
# second, wrong error.
#
# Run:      roc check langref-for-literal-pattern.roc
# Expected: The note says that a literal pattern in a `for` is not caught at
#           compile time and crashes at runtime. One error, "non exhaustive
#           destructure", is the right result.
# Actual:   "non exhaustive destructure", and also "compile time crash" with
#           the message "hit a runtime error".
#
# Nightly: nightly-2026-10-06-c34079d.

sum_ones = |pairs| {
	var $sum = 0.U64
	for (1, x) in pairs {
		$sum = $sum + x
	}
	$sum
}

main! = |_args| {
	echo!(sum_ones([(1, 1), (2, 2)]).to_str())
	Ok({})
}
