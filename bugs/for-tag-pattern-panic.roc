# A tag pattern in a `for` loop over a list that also holds another tag panics
# the compiler.
#
# Run:      roc check, roc test or roc for-tag-pattern-panic.roc
# Expected: A compile error for the non-exhaustive pattern (langref
#           loops.md:91 says "type mismatch"), or "non exhaustive destructure"
#           as for a literal pattern.
# Actual:   thread ... panic: compiler bug: instantiation widened a closed tag
#           union
#
# Nightly: nightly-2026-10-06-c34079d.

total = |items| {
	var $sum = 0.U64
	for Ok(x) in items {
		$sum = $sum + x
	}
	$sum
}

expect total([Ok(1), Err(2)]) == 1

main! = |_args| {
	echo!(total([Ok(1), Err(2)]).to_str())
	Ok({})
}
