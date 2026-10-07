# For loops, while loops, break, and reassignable `var`s.
#
# A `var` is a reassignable binding. Its name must start with `$`,
# so every `$name` is a binding that can change.
# Constants (without `$`) can never be reassigned.

# A `for` loop runs over an iterator. Anything with an `iter` method works,
# including lists, dicts, sets, and ranges. The loop body contains only
# statements, has no final expression, and the loop itself evaluates to `{}`.

# `for` loop with a var accumulator.
for_loop = |num_list| {
	var $sum = 0

	for num in num_list {
		$sum = $sum + num
	}

	$sum
}

# Ranges work directly: `1..<5` is exclusive, `1..=5` inclusive. See the
# `ranges` topic.
sum_range = |n| {
	var $sum = 0

	for i in 0..<n {
		$sum = $sum + i
	}

	$sum
}

# `iter_rev` walks a list backwards in place, without building a reversed copy
# the way `List.rev` does. Dicts and sets also provide `iter_rev`, which walks
# their current iteration order backwards. To reverse some other iterator
# source, collect it with `List.from_iter` first, then call `iter_rev`.
reverse_visit = |items| {
	var $visited = []

	for n in items.iter_rev() {
		$visited = $visited.append(n)
	}

	$visited
}

# Whatever sits between `for` and `in` is a pattern, so items destructure
# inline, and `_` discards.
sum_pairs = |pairs| {
	var $total = 0

	for (x, y) in pairs {
		$total = $total + x + y
	}

	$total
}

count_items = |items| {
	var $count = 0

	for _ in items {
		$count = $count + 1
	}

	$count
}

# The `for` pattern must be exhaustive, exactly like a destructuring
# assignment. `for Ok(n) in results { ... }` is not allowed, because the body
# would have no value for `n` if an item were `Err`. Name the whole item and
# `match` inside the body instead.
#
# The compiler rejects such a pattern with "non exhaustive destructure", naming
# the cases the pattern leaves out. A literal pattern such as `for 1 in ...` is
# caught the same way, at compile time.

# `break` exits a `for` or `while` loop early.
break_in_for_loop = |bool_list| {
	var $all_true = Bool.True

	for b in bool_list {
		if b == Bool.False {
			$all_true = Bool.False
			break
		} else {
			{}
		}
	}

	$all_true
}

# `while` loop with a condition.
while_loop = |limit| {
	var $count = 0
	var $sum = 0

	while $count < limit {
		$sum = $sum + $count
		$count = $count + 1
	}

	$sum
}

# `break` exits only the innermost loop. In a nested loop, breaking out of the
# inner one leaves the outer one running.

# Only the function that declares a var can reassign it.
# So `for_each!(|x| { $count = $count + 1 })` is a compile error.
# Use a `for` loop when you need to mutate a var.
